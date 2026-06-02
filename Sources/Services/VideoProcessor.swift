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
        // Look for videokit binary next to the app bundle, or in the repo
        let bundle = Bundle.main.bundlePath
        let bundleSibling = URL(fileURLWithPath: bundle)
            .deletingLastPathComponent()
            .appendingPathComponent("videokit")

        if FileManager.default.fileExists(atPath: bundleSibling.path) {
            return bundleSibling
        }

        // Dev fallback: look in the videokit/ directory relative to the project
        let devPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("videokit/videokit")

        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath
        }

        // Last resort: check PATH
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
