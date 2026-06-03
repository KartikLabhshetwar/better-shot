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

    private init() {}

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
                let dmgAsset = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }

                if let assetURLString = dmgAsset?["browser_download_url"] as? String,
                   let assetURL = URL(string: assetURLString) {
                    state = .available(version: latestVersion, url: assetURL)
                } else {
                    state = .failed("No .dmg asset found in latest release")
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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path.path, "-nobrowse", "-readonly", "-plist"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AppUpdater", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to mount DMG (exit code \(process.terminationStatus))"
            ])
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.first(where: { $0["mount-point"] != nil })?["mount-point"] as? String else {
            throw NSError(domain: "AppUpdater", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not find mount point"
            ])
        }

        return mountPoint
    }

    private func relaunchApp(at appURL: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1 && open \"\(appURL.path)\""]
        try? task.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
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
