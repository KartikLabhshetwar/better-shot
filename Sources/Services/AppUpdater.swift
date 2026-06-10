import Foundation
import AppKit

@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    enum State: Equatable {
        case idle
        case checking
        case available(version: String, url: URL)
        case downloading(progress: Double)
        case readyToInstall(version: String, dmgPath: URL)
        case installing
        case upToDate
        case failed(String)
    }

    private(set) var state: State = .idle

    private let owner = "KartikLabhshetwar"
    private let repo = "better-shot"

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var downloadTask: URLSessionDownloadTask?

    private(set) var latestAvailableVersion: String?

    private init() {}

    func checkForUpdatesQuietly() async {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if isNewer(latestVersion, than: currentVersion) {
                latestAvailableVersion = latestVersion
                let assets = json["assets"] as? [[String: Any]] ?? []
                let arch = Self.currentArchitecture
                let dmgAsset = assets.first { ($0["name"] as? String)?.contains(arch) == true && ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                    ?? assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }

                if let assetURLString = dmgAsset?["browser_download_url"] as? String,
                   let assetURL = URL(string: assetURLString),
                   isTrustedAssetURL(assetURL) {
                    state = .available(version: latestVersion, url: assetURL)
                    ToastWindow.shared.show(
                        title: "Update Available",
                        message: "Version \(latestVersion) is available",
                        systemIcon: "arrow.down.circle"
                    )
                }
            }
        } catch {}
    }

    func checkForUpdates() async {
        state = .checking

        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            state = .failed("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                state = .failed("Invalid response")
                return
            }

            if httpResponse.statusCode == 404 {
                state = .upToDate
                return
            }

            guard httpResponse.statusCode == 200 else {
                state = .failed("Server returned \(httpResponse.statusCode)")
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                state = .failed("Could not parse response")
                return
            }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            if isNewer(latestVersion, than: currentVersion) {
                let assets = json["assets"] as? [[String: Any]] ?? []
                let arch = Self.currentArchitecture
                let dmgAsset = assets.first { ($0["name"] as? String)?.contains(arch) == true && ($0["name"] as? String)?.hasSuffix(".dmg") == true }
                    ?? assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }

                if let assetURLString = dmgAsset?["browser_download_url"] as? String,
                   let assetURL = URL(string: assetURLString),
                   isTrustedAssetURL(assetURL) {
                    state = .available(version: latestVersion, url: assetURL)
                } else {
                    state = .failed("No trusted .dmg asset found in latest release")
                }
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func downloadAndInstall(version: String, url: URL) async {
        state = .downloading(progress: 0)

        let delegate = DownloadProgressDelegate { [weak self] progress in
            Task { @MainActor in
                self?.state = .downloading(progress: progress)
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let downloadTask = session.downloadTask(with: url)
        self.downloadTask = downloadTask

        do {
            let localURL: URL = try await withCheckedThrowingContinuation { continuation in
                delegate.completion = { result in
                    continuation.resume(with: result)
                }
                downloadTask.resume()
            }

            let dmgDir = FileManager.default.temporaryDirectory.appendingPathComponent("BetterShotUpdate")
            try? FileManager.default.removeItem(at: dmgDir)
            try FileManager.default.createDirectory(at: dmgDir, withIntermediateDirectories: true)

            let dmgPath = dmgDir.appendingPathComponent("BetterShot-\(version).dmg")
            if FileManager.default.fileExists(atPath: dmgPath.path) {
                try FileManager.default.removeItem(at: dmgPath)
            }
            try FileManager.default.moveItem(at: localURL, to: dmgPath)

            state = .readyToInstall(version: version, dmgPath: dmgPath)
        } catch {
            state = .failed("Download failed: \(error.localizedDescription)")
        }
    }

    func installUpdate(dmgPath: URL) async {
        state = .installing

        do {
            let mountPoint = try await mountDMG(at: dmgPath)
            defer {
                Task.detached {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                    process.arguments = ["detach", mountPoint, "-quiet"]
                    try? process.run()
                    process.waitUntilExit()
                    try? FileManager.default.removeItem(at: dmgPath.deletingLastPathComponent())
                }
            }

            let mountURL = URL(fileURLWithPath: mountPoint)
            let contents = try FileManager.default.contentsOfDirectory(at: mountURL, includingPropertiesForKeys: nil)
            guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                state = .failed("No .app found in DMG")
                return
            }

            guard let currentAppURL = Bundle.main.bundleURL as URL? else {
                state = .failed("Cannot determine current app location")
                return
            }

            // Security: refuse to install anything that isn't validly signed by the
            // same team as the running app. Without this, a compromised release asset
            // is silent arbitrary code execution.
            if let verifyError = await Self.verifyUpdateBundle(appBundle, against: currentAppURL) {
                state = .failed("Update rejected: \(verifyError)")
                return
            }

            let backupURL = currentAppURL.deletingLastPathComponent()
                .appendingPathComponent(currentAppURL.lastPathComponent + ".backup")

            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.moveItem(at: currentAppURL, to: backupURL)

            do {
                try FileManager.default.copyItem(at: appBundle, to: currentAppURL)
            } catch {
                try? FileManager.default.removeItem(at: currentAppURL)
                try? FileManager.default.moveItem(at: backupURL, to: currentAppURL)
                state = .failed("Install failed: \(error.localizedDescription)")
                return
            }

            try? FileManager.default.removeItem(at: backupURL)

            relaunchApp(at: currentAppURL)
        } catch {
            state = .failed("Install failed: \(error.localizedDescription)")
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .idle
    }

    private func mountDMG(at path: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                process.arguments = ["attach", path.path, "-nobrowse", "-readonly", "-plist"]

                let pipe = Pipe()
                process.standardOutput = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: NSError(domain: "AppUpdater", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to mount DMG (exit code \(process.terminationStatus))"
                    ]))
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                do {
                    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                          let entities = plist["system-entities"] as? [[String: Any]],
                          let mountPoint = entities.first(where: { $0["mount-point"] != nil })?["mount-point"] as? String else {
                        continuation.resume(throwing: NSError(domain: "AppUpdater", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: "Could not find mount point"
                        ]))
                        return
                    }
                    continuation.resume(returning: mountPoint)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Only accept release assets hosted on this repo's GitHub releases page.
    private func isTrustedAssetURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host == "github.com"
            && url.path.hasPrefix("/\(owner)/\(repo)/releases/download/")
    }

    /// Verifies the candidate bundle has a valid code signature and the same
    /// Team ID as the running app. Returns an error message, or nil if OK.
    private static func verifyUpdateBundle(_ candidate: URL, against currentApp: URL) async -> String? {
        guard let currentTeam = await teamIdentifier(of: currentApp) else {
            return "current app is unsigned; cannot establish a trust anchor for updates"
        }
        let verify = await runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", candidate.path])
        guard verify == 0 else {
            return "downloaded app failed code signature verification"
        }
        guard let candidateTeam = await teamIdentifier(of: candidate) else {
            return "downloaded app has no Team ID"
        }
        guard candidateTeam == currentTeam else {
            return "downloaded app is signed by a different team (\(candidateTeam))"
        }
        return nil
    }

    /// Parses `TeamIdentifier=` from `codesign -dv` output; nil if unsigned or "not set".
    private static func teamIdentifier(of bundle: URL) async -> String? {
        let output = await runProcessCapturingOutput("/usr/bin/codesign", ["-dv", bundle.path])
        guard let line = output?.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) else {
            return nil
        }
        let team = String(line.dropFirst("TeamIdentifier=".count)).trimmingCharacters(in: .whitespaces)
        return (team.isEmpty || team == "not set") ? nil : team
    }

    private static func runProcess(_ path: String, _ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(returning: -1)
                }
            }
        }
    }

    private static func runProcessCapturingOutput(_ path: String, _ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                // codesign -dv writes details to stderr
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    private func relaunchApp(at appURL: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Path passed as $0, not interpolated — immune to shell metacharacters.
        task.arguments = ["-c", "sleep 1 && open \"$0\"", appURL.path]
        try? task.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = candidate.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(candidateParts.count, currentParts.count) {
            let c = i < candidateParts.count ? candidateParts[i] : 0
            let o = i < currentParts.count ? currentParts[i] : 0
            if c > o { return true }
            if c < o { return false }
        }
        return false
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    var completion: ((Result<URL, Error>) -> Void)?

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dmg")
        do {
            try FileManager.default.copyItem(at: location, to: tempCopy)
            completion?(.success(tempCopy))
        } catch {
            completion?(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error = error {
            completion?(.failure(error))
        }
    }
}
