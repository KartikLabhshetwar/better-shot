import Foundation

/// Runs `/usr/sbin/screencapture` for one PNG and reports as soon as the PNG is
/// complete. After saving, screencapture tags the file for Spotlight and waits
/// for the reply before exiting; a busy Spotlight holds that exit for up to
/// 10 seconds. The exit status still decides cancellation and failures.
nonisolated enum ScreencaptureRunner {
    enum Outcome: Equatable, Sendable {
        case saved
        case exited(status: Int32, diagnostic: String)
    }

    static func run(_ arguments: [String], output: String,
                    executable: URL = URL(fileURLWithPath: "/usr/sbin/screencapture")) async throws -> Outcome {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let errors = Pipe()
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                var saved = false
                while process.isRunning {
                    if !saved, isCompletePNG(atPath: output) {
                        saved = true
                        continuation.resume(returning: .saved)
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                }
                let data = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard !saved else { return }
                continuation.resume(returning: .exited(
                    status: process.terminationStatus, diagnostic: String(decoding: data, as: UTF8.self)))
            }
        }
    }

    /// A PNG always ends with its IEND chunk, so a file still being written does not.
    static func isCompletePNG(atPath path: String) -> Bool {
        guard let file = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? file.close() }
        guard let size = try? file.seekToEnd(), size >= 12 else { return false }
        try? file.seek(toOffset: size - 12)
        return (try? file.read(upToCount: 12)) == Data([0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82])
    }
}
