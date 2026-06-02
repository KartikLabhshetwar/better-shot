import Foundation

/// Bridges to the Go `videokit` CLI for FFmpeg-based video processing.
@MainActor
@Observable
final class VideoProcessor {
    static let shared = VideoProcessor()

    private(set) var isProcessing = false
    private(set) var ffmpegAvailable = false

    private init() {
        Task { await checkFFmpeg() }
    }

    // MARK: - FFmpeg Check

    func checkFFmpeg() async {
        let result = await run(command: "check")
        ffmpegAvailable = result?.success ?? false
    }

    // MARK: - Compress

    struct CompressOptions: Codable {
        var input_path: String
        var output_path: String
        var quality: String = "medium"
        var speed: String = "medium"
        var codec: String = "h264"
        var resolution: String = "original"
        var remove_audio: Bool = false
    }

    func compress(_ options: CompressOptions) async -> ProcessResult? {
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }

        guard let json = encodeJSON(options) else { return nil }
        return await run(command: "compress", arg: json)
    }

    // MARK: - Trim

    struct TrimOptions: Codable {
        var input_path: String
        var output_path: String
        var start_time: Double
        var end_time: Double
    }

    func trim(_ options: TrimOptions) async -> ProcessResult? {
        guard !isProcessing else { return nil }
        isProcessing = true
        defer { isProcessing = false }

        guard let json = encodeJSON(options) else { return nil }
        return await run(command: "trim", arg: json)
    }

    // MARK: - Probe

    func probe(filePath: String) async -> String? {
        let process = Process()
        process.executableURL = videokitURL
        process.arguments = ["probe", filePath]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    // MARK: - Internal

    struct ProcessResult: Codable {
        let success: Bool
        let output_path: String?
        let input_size: Int64?
        let output_size: Int64?
        let error: String?
    }

    private var videokitURL: URL {
        // 1. Inside the app bundle's MacOS directory (bundled by post-compile script)
        if let execURL = Bundle.main.executableURL {
            let bundled = execURL.deletingLastPathComponent().appendingPathComponent("videokit")
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }

        // 2. Next to the .app bundle (common for dev builds via Xcode)
        let sibling = URL(fileURLWithPath: Bundle.main.bundlePath)
            .deletingLastPathComponent()
            .appendingPathComponent("videokit")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        // 3. Project root videokit/ directory (dev: when running from Xcode with SRCROOT set)
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            let projectBinary = URL(fileURLWithPath: srcRoot)
                .appendingPathComponent("videokit/videokit")
            if FileManager.default.isExecutableFile(atPath: projectBinary.path) {
                return projectBinary
            }
        }

        // 4. Workspace-relative fallback using the bundle path heuristic
        //    DerivedData/.../Build/Products/Debug/BetterShot.app -> walk up to find project root
        var search = URL(fileURLWithPath: Bundle.main.bundlePath)
        for _ in 0..<8 {
            search = search.deletingLastPathComponent()
            let candidate = search.appendingPathComponent("videokit/videokit")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        // 5. Homebrew / system PATH fallback
        for path in ["/opt/homebrew/bin/videokit", "/usr/local/bin/videokit"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // Last resort — will fail gracefully at call site
        return URL(fileURLWithPath: "/usr/local/bin/videokit")
    }

    private func run(command: String, arg: String? = nil) async -> ProcessResult? {
        let process = Process()
        process.executableURL = videokitURL
        process.arguments = arg != nil ? [command, arg!] : [command]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return try JSONDecoder().decode(ProcessResult.self, from: data)
        } catch {
            return ProcessResult(success: false, output_path: nil, input_size: nil, output_size: nil, error: error.localizedDescription)
        }
    }

    private func encodeJSON<T: Codable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
