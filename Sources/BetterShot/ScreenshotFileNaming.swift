//
//  ScreenshotFileNaming.swift
//  BetterShot
//
//  Builds a deliverable's file name from a template. A template is plain text
//  with `{token}` placeholders, so `hello-{hex:8}` names a file `hello-a3f9c2e1.png`.
//  Anything BetterShot does not recognise is copied through verbatim: a stray
//  brace stays a brace rather than silently eating the rest of the name.
//
//  The renderer is pure. It never reads preferences and never advances the
//  counter, so Settings can preview a template as often as it likes without
//  taking a number out of the sequence. `AppPreferences.captureFileName` is
//  the one path that spends one.
//

import Foundation

nonisolated enum ScreenshotFileNaming {
    /// The pre-0.5.0 name, written as a template. Upgrading changes nothing
    /// about the files that land in the save folder.
    static let defaultTemplate = "BetterShot_{date}-{time}"

    enum Kind: String {
        case screenshot = "Screenshot"
        case recording = "Recording"
    }

    /// Everything a template is allowed to ask about the capture it names.
    struct Context {
        var date: Date
        var kind: Kind
        var counter: Int

        init(date: Date = Date(), kind: Kind = .screenshot, counter: Int = 1) {
            self.date = date
            self.kind = kind
            self.counter = counter
        }
    }

    // MARK: - Stored template

    static let templateKey = "bs_fileNameTemplate"
    static let counterKey = "bs_fileNameCounter"

    /// The template every saved screenshot and recording is named from. The
    /// default renders exactly what pre-0.5.0 builds wrote, so upgrading leaves
    /// an existing save folder's naming alone. Settings writes it through
    /// `@AppStorage(templateKey)`.
    static func template(in defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: templateKey) ?? defaultTemplate
    }

    /// The number `{counter}` renders next.
    static func counter(in defaults: UserDefaults = .standard) -> Int {
        max(defaults.object(forKey: counterKey) as? Int ?? 1, 1)
    }

    /// Names one deliverable from the stored template.
    ///
    /// Calling this SPENDS one `{counter}` number. It is the only path that
    /// does, which is what lets Settings preview a template as often as it
    /// likes. Call it once per file, and hold the result in a local rather
    /// than calling it again for the same save.
    static func currentFileName(
        extension pathExtension: String,
        kind: Kind = .screenshot,
        date: Date = Date(),
        in defaults: UserDefaults = .standard
    ) -> String {
        let template = template(in: defaults)
        let counter = counter(in: defaults)
        let name = fileName(
            template: template,
            extension: pathExtension,
            context: Context(date: date, kind: kind, counter: counter)
        )
        if usesCounter(template) { defaults.set(counter + 1, forKey: counterKey) }
        return name
    }

    // MARK: - Rendering

    /// The finished name, sanitised and carrying `pathExtension`. An empty or
    /// all-punctuation template falls back to `defaultTemplate` rather than
    /// producing a file called `.png`.
    static func fileName(
        template: String,
        extension pathExtension: String,
        context: Context = Context()
    ) -> String {
        let rendered = sanitized(render(template, context: context))
        let base = rendered.isEmpty ? sanitized(render(defaultTemplate, context: context)) : rendered
        let ext = sanitized(pathExtension)
        guard !ext.isEmpty else { return base }
        // `{ext}` is a token, so a template may already end with the extension.
        guard !base.lowercased().hasSuffix(".\(ext.lowercased())") else { return base }
        return "\(base).\(ext)"
    }

    /// Substitutes tokens without sanitising or appending an extension. Settings
    /// uses `fileName` for its preview; this exists for the checks.
    static func render(_ template: String, context: Context = Context(), extension pathExtension: String = "") -> String {
        var output = ""
        var index = template.startIndex

        while index < template.endIndex {
            let character = template[index]
            guard character == "{",
                  let close = template[index...].firstIndex(of: "}"),
                  let value = value(
                      for: String(template[template.index(after: index)..<close]),
                      context: context,
                      extension: pathExtension
                  )
            else {
                output.append(character)
                index = template.index(after: index)
                continue
            }

            output += value
            index = template.index(after: close)
        }

        return output
    }

    /// Whether this template spends a number when it renders. Comparing two
    /// renders would not answer it: `{uuid}` and `{hex:8}` differ every time.
    static func usesCounter(_ template: String) -> Bool {
        tokenNames(in: template).contains("counter")
    }

    static func tokenNames(in template: String) -> [String] {
        var names: [String] = []
        var index = template.startIndex

        while index < template.endIndex {
            guard template[index] == "{",
                  let close = template[index...].firstIndex(of: "}")
            else {
                index = template.index(after: index)
                continue
            }

            let body = String(template[template.index(after: index)..<close])
            let name = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            // Asking the renderer keeps the two from drifting apart.
            guard value(for: body, context: Context(), extension: "png") != nil else {
                index = template.index(after: index)
                continue
            }

            names.append(name)
            index = template.index(after: close)
        }

        return names
    }

    // MARK: - Tokens

    private static func value(for token: String, context: Context, extension pathExtension: String) -> String? {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let argument = parts.count > 1 ? String(parts[1]) : nil

        switch name {
        case "date": return formatted(context.date, pattern: argument ?? "yyyy-MM-dd")
        case "time": return formatted(context.date, pattern: argument ?? "HH-mm-ss")
        case "hex": return randomString(from: hexAlphabet, count: count(argument, fallback: 8))
        case "base62": return randomString(from: base62Alphabet, count: count(argument, fallback: 6))
        case "digits": return randomString(from: digitAlphabet, count: count(argument, fallback: 4))
        case "uuid": return UUID().uuidString.lowercased()
        case "counter": return padded(context.counter, width: count(argument, fallback: 1))
        case "kind": return context.kind.rawValue
        case "ext": return pathExtension
        default: return nil
        }
    }

    private static let hexAlphabet = Array("0123456789abcdef")
    private static let base62Alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let digitAlphabet = Array("0123456789")

    private static func randomString(from alphabet: [Character], count: Int) -> String {
        String((0..<count).map { _ in alphabet.randomElement() ?? "0" })
    }

    private static func count(_ argument: String?, fallback: Int) -> Int {
        guard let argument, let parsed = Int(argument.trimmingCharacters(in: .whitespaces)) else { return fallback }
        return min(max(parsed, 1), 32)
    }

    private static func padded(_ value: Int, width: Int) -> String {
        let digits = String(max(value, 0))
        guard digits.count < width else { return digits }
        return String(repeating: "0", count: width - digits.count) + digits
    }

    private static func formatted(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // MARK: - Sanitising

    /// A template is free text, so it can contain a path separator, a colon that
    /// Finder still shows as a slash, or enough characters to blow past the
    /// 255-byte name limit. None of those may reach the file system.
    private static func sanitized(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.controlCharacters)
            .union(.newlines)
        let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.filter { !illegal.contains($0) }))
        let trimmed = cleaned.drop { $0 == "." || $0 == " " }
        return String(trimmed.prefix(200)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }

    // MARK: - Insert menu

    struct MenuItem: Identifiable {
        let title: String
        let token: String
        var id: String { token }
    }

    struct MenuGroup: Identifiable {
        let title: String
        let items: [MenuItem]
        var id: String { title }
    }

    /// The Insert menu in Settings, so the picker and the renderer cannot drift.
    static let menuGroups: [MenuGroup] = [
        MenuGroup(title: "Date & Time", items: [
            MenuItem(title: "Date", token: "{date}"),
            MenuItem(title: "Date, day first", token: "{date:dd-MM-yyyy}"),
            MenuItem(title: "Date, dotted", token: "{date:yyyy.MM.dd}"),
            MenuItem(title: "Time", token: "{time}"),
            MenuItem(title: "Time, compact", token: "{time:HHmmss}"),
        ]),
        MenuGroup(title: "Random", items: [
            MenuItem(title: "Hex, 8 characters", token: "{hex:8}"),
            MenuItem(title: "Hex, 4 characters", token: "{hex:4}"),
            MenuItem(title: "Base62, 6 characters", token: "{base62:6}"),
            MenuItem(title: "Digits, 4 characters", token: "{digits:4}"),
            MenuItem(title: "UUID", token: "{uuid}"),
        ]),
        MenuGroup(title: "Counter", items: [
            MenuItem(title: "Counter", token: "{counter}"),
            MenuItem(title: "Counter, 3 digits", token: "{counter:3}"),
        ]),
        MenuGroup(title: "Capture", items: [
            MenuItem(title: "Screenshot or Recording", token: "{kind}"),
            MenuItem(title: "File extension", token: "{ext}"),
        ]),
    ]
}
