import Foundation

/// The naming template is free text that reaches the file system, so the two
/// things worth pinning are that every token resolves and that nothing a person
/// can type produces an illegal, hidden, or over-long name.
@main @MainActor
enum FileNamingCheck {
    static func main() {
        let date = Date(timeIntervalSince1970: 1_758_115_802)
        let context = ScreenshotFileNaming.Context(date: date, kind: .screenshot, counter: 7)

        checkDefaultIsUnchanged(date: date)
        checkStaticTextAndTokens(context: context)
        checkExtensionHandling(context: context)
        checkUnknownTokensSurvive(context: context)
        checkIllegalCharactersAreStripped(context: context)
        checkEmptyTemplateFallsBack(date: date)
        checkCounter(context: context)
        checkKind(date: date)
        checkCounterSpending()
        checkScratchNames()

        print("file naming: 10 groups checked")
    }

    /// Working files must be recognisable so Save never ships a UUID name,
    /// including captures stored by builds that used `bettershot_<UUID>`.
    private static func checkScratchNames() {
        let directory = FileManager.default.temporaryDirectory
        let fresh = ScreenshotFileNaming.scratchURL("Capture", extension: "png", in: directory)
        assert(ScreenshotFileNaming.isScratch(fresh), "a generated working file is scratch: \(fresh.lastPathComponent)")
        assert(fresh.pathExtension == "png" && fresh.deletingLastPathComponent() == directory)
        assert(ScreenshotFileNaming.isScratch(URL(fileURLWithPath: "/x/bettershot_6F1C2B8E-3C1D-4E55-9A0B-1D2E3F4A5B6C.png")),
               "legacy capture names are scratch")
        assert(ScreenshotFileNaming.isScratch(URL(fileURLWithPath: "/x/BetterShot_Annotated_6F1C2B8E-3C1D-4E55-9A0B-1D2E3F4A5B6C.png")),
               "legacy working names are scratch")
        for suffix in ["preview.png", "raw.png", "base.png"] {
            let companion = fresh.deletingPathExtension().appendingPathExtension(suffix)
            assert(ScreenshotFileNaming.isScratch(companion), "\(companion.lastPathComponent) is scratch")
        }
        for name in ["BetterShot_2026-09-23-10-00-00.png", "vacation.png", "BetterShot-hello.png", "hello-a3f9c2.png"] {
            assert(!ScreenshotFileNaming.isScratch(URL(fileURLWithPath: "/x/\(name)")), "\(name) is a real name")
        }
        let taken = directory.appendingPathComponent("FileNamingCheck-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: taken, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: taken) }
        FileManager.default.createFile(atPath: taken.appendingPathComponent("a.png").path, contents: Data())
        assert(ScreenshotFileNaming.uniqueURL(for: "b.png", in: taken).lastPathComponent == "b.png")
        assert(ScreenshotFileNaming.uniqueURL(for: "a.png", in: taken).lastPathComponent == "a 1.png")
        assert(ScreenshotFileNaming.uniqueURL(for: "a.png", in: taken, separator: "-").lastPathComponent == "a-1.png")
    }

    /// `currentFileName` has a side effect, which is why it is a function and
    /// not a property. Pin the contract: one call spends exactly one number,
    /// and a template without `{counter}` spends none.
    private static func checkCounterSpending() {
        let suite = "FileNamingCheck-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("could not open a scratch defaults suite")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        assert(ScreenshotFileNaming.counter(in: defaults) == 1, "an untouched counter starts at 1")
        assert(
            ScreenshotFileNaming.template(in: defaults) == ScreenshotFileNaming.defaultTemplate,
            "an untouched template is the default"
        )

        defaults.set("shot-{counter:3}", forKey: ScreenshotFileNaming.templateKey)
        let first = ScreenshotFileNaming.currentFileName(extension: "png", in: defaults)
        assert(first == "shot-001.png", "the first file takes number 1, got \(first)")
        assert(ScreenshotFileNaming.counter(in: defaults) == 2, "one call must spend exactly one number")

        let second = ScreenshotFileNaming.currentFileName(extension: "png", in: defaults)
        assert(second == "shot-002.png", "the next file takes the next number, got \(second)")
        assert(ScreenshotFileNaming.counter(in: defaults) == 3, "a second call spends a second number")

        // Settings previews through `fileName`, which reads a counter it is
        // handed and stores nothing.
        _ = ScreenshotFileNaming.fileName(
            template: "shot-{counter:3}",
            extension: "png",
            context: ScreenshotFileNaming.Context(counter: ScreenshotFileNaming.counter(in: defaults))
        )
        assert(ScreenshotFileNaming.counter(in: defaults) == 3, "previewing must not spend a number")

        // Clipboard copies name their file from the template without spending.
        let peeked = ScreenshotFileNaming.peekFileName(extension: "png", in: defaults)
        assert(peeked == "shot-003.png", "a clipboard copy renders the next number, got \(peeked)")
        assert(ScreenshotFileNaming.counter(in: defaults) == 3, "a clipboard copy must not spend a number")

        defaults.set("shot-{hex:8}", forKey: ScreenshotFileNaming.templateKey)
        _ = ScreenshotFileNaming.currentFileName(extension: "png", in: defaults)
        assert(ScreenshotFileNaming.counter(in: defaults) == 3, "a template without {counter} spends nothing")

        defaults.set(0, forKey: ScreenshotFileNaming.counterKey)
        assert(ScreenshotFileNaming.counter(in: defaults) == 1, "a stored 0 or negative reads as 1")
    }

    /// Upgrading must not rename anything. The default template has to render
    /// byte-for-byte what the hardcoded 0.4.x formatter produced.
    private static func checkDefaultIsUnchanged(date: Date) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let legacy = "BetterShot_\(formatter.string(from: date)).png"

        let rendered = ScreenshotFileNaming.fileName(
            template: ScreenshotFileNaming.defaultTemplate,
            extension: "png",
            context: ScreenshotFileNaming.Context(date: date)
        )
        assert(rendered == legacy, "default template must match the pre-0.5.0 name, got \(rendered)")
    }

    private static func checkStaticTextAndTokens(context: ScreenshotFileNaming.Context) {
        let name = ScreenshotFileNaming.fileName(template: "hello-{hex:8}", extension: "png", context: context)
        assert(name.hasPrefix("hello-"), "static text must survive verbatim, got \(name)")
        assert(name.hasSuffix(".png"), "extension must be appended, got \(name)")

        let random = name.dropFirst("hello-".count).dropLast(".png".count)
        assert(random.count == 8, "{hex:8} must render 8 characters, got \(random.count)")
        assert(random.allSatisfy { $0.isHexDigit && !$0.isUppercase }, "{hex:8} must be lowercase hex, got \(random)")

        let base62 = ScreenshotFileNaming.render("{base62:6}", context: context)
        assert(base62.count == 6, "{base62:6} must render 6 characters")
        assert(base62.allSatisfy { $0.isLetter || $0.isNumber }, "{base62} must stay alphanumeric, got \(base62)")

        let digits = ScreenshotFileNaming.render("{digits:4}", context: context)
        assert(digits.count == 4 && digits.allSatisfy(\.isNumber), "{digits:4} must render 4 digits, got \(digits)")

        // An out-of-range length is clamped rather than rejected: a template is
        // typed by hand and must never fail to produce a name.
        assert(ScreenshotFileNaming.render("{hex:0}", context: context).count == 1, "{hex:0} must clamp to 1")
        assert(ScreenshotFileNaming.render("{hex:999}", context: context).count == 32, "{hex:999} must clamp to 32")
        assert(ScreenshotFileNaming.render("{hex:abc}", context: context).count == 8, "a non-numeric length falls back to 8")

        let custom = ScreenshotFileNaming.render("{date:yyyy}", context: context)
        assert(custom.count == 4 && custom.allSatisfy(\.isNumber), "{date:yyyy} must render a year, got \(custom)")

        let uuid = ScreenshotFileNaming.render("{uuid}", context: context)
        assert(uuid.count == 36 && uuid == uuid.lowercased(), "{uuid} must be a lowercase UUID, got \(uuid)")
    }

    private static func checkExtensionHandling(context: ScreenshotFileNaming.Context) {
        let explicit = ScreenshotFileNaming.fileName(template: "shot.{ext}", extension: "png", context: context)
        assert(explicit == "shot.png", "{ext} must render the extension once, got \(explicit)")

        let implicit = ScreenshotFileNaming.fileName(template: "shot", extension: "png", context: context)
        assert(implicit == "shot.png", "a template without {ext} still gets one, got \(implicit)")

        let video = ScreenshotFileNaming.fileName(template: "clip", extension: "mp4", context: context)
        assert(video == "clip.mp4", "the extension comes from the caller, got \(video)")

        let already = ScreenshotFileNaming.fileName(template: "shot.png", extension: "png", context: context)
        assert(already == "shot.png", "a matching extension must not be doubled, got \(already)")
    }

    /// A brace that means nothing to BetterShot is far likelier to be a typo
    /// than an instruction, so it stays visible instead of vanishing.
    private static func checkUnknownTokensSurvive(context: ScreenshotFileNaming.Context) {
        let name = ScreenshotFileNaming.fileName(template: "a{nope}b", extension: "png", context: context)
        assert(name == "a{nope}b.png", "an unknown token must be left alone, got \(name)")

        let unclosed = ScreenshotFileNaming.fileName(template: "a{date", extension: "png", context: context)
        assert(unclosed == "a{date.png", "an unclosed brace must be left alone, got \(unclosed)")

        let nested = ScreenshotFileNaming.render("{x{kind}", context: context)
        assert(nested == "{xScreenshot", "a real token after a bad one must still render, got \(nested)")

        assert(ScreenshotFileNaming.tokenNames(in: "a{nope}{kind}") == ["kind"], "only known tokens are counted")
    }

    private static func checkIllegalCharactersAreStripped(context: ScreenshotFileNaming.Context) {
        let slashes = ScreenshotFileNaming.fileName(template: "a/b:c", extension: "png", context: context)
        assert(slashes == "abc.png", "separators must never reach the file system, got \(slashes)")

        let hidden = ScreenshotFileNaming.fileName(template: "...secret", extension: "png", context: context)
        assert(hidden == "secret.png", "a template must not be able to write a hidden file, got \(hidden)")

        let padded = ScreenshotFileNaming.fileName(template: "  spaced  ", extension: "png", context: context)
        assert(padded == "spaced.png", "surrounding whitespace must be trimmed, got \(padded)")

        let long = ScreenshotFileNaming.fileName(
            template: String(repeating: "x", count: 500),
            extension: "png",
            context: context
        )
        assert(long.count == 204, "a long name must be truncated with room for the extension, got \(long.count)")
    }

    private static func checkEmptyTemplateFallsBack(date: Date) {
        let context = ScreenshotFileNaming.Context(date: date)
        for template in ["", "   ", "///", "..."] {
            let name = ScreenshotFileNaming.fileName(template: template, extension: "png", context: context)
            assert(name.hasPrefix("BetterShot_"), "\"\(template)\" must fall back to the default, got \(name)")
            assert(name != ".png", "a template can never produce an extension-only name")
        }
    }

    private static func checkCounter(context: ScreenshotFileNaming.Context) {
        assert(ScreenshotFileNaming.render("{counter}", context: context) == "7", "{counter} renders the current number")
        assert(ScreenshotFileNaming.render("{counter:3}", context: context) == "007", "{counter:3} zero-pads")
        assert(ScreenshotFileNaming.render("{counter:1}", context: context) == "7", "a narrow width does not truncate")

        assert(ScreenshotFileNaming.usesCounter("shot-{counter}"), "a counter template must be detected")
        assert(!ScreenshotFileNaming.usesCounter("shot-{hex:8}"), "random tokens are not a counter")
        assert(!ScreenshotFileNaming.usesCounter("shot-{uuid}"), "a UUID is not a counter")
        assert(!ScreenshotFileNaming.usesCounter(ScreenshotFileNaming.defaultTemplate), "the default spends no numbers")
    }

    private static func checkKind(date: Date) {
        let shot = ScreenshotFileNaming.Context(date: date, kind: .screenshot)
        let clip = ScreenshotFileNaming.Context(date: date, kind: .recording)
        assert(ScreenshotFileNaming.render("{kind}", context: shot) == "Screenshot", "{kind} names a screenshot")
        assert(ScreenshotFileNaming.render("{kind}", context: clip) == "Recording", "{kind} names a recording")
    }
}
