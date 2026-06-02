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
        case upToDate
        case failed(String)
    }

    private(set) var state: State = .idle

    private let owner = "KartikLabhshetwar"
    private let repo = "better-shot"

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

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
                    ?? assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }

                let downloadURL: URL
                if let assetURLString = dmgAsset?["browser_download_url"] as? String,
                   let assetURL = URL(string: assetURLString) {
                    downloadURL = assetURL
                } else if let htmlURL = json["html_url"] as? String,
                          let releaseURL = URL(string: htmlURL) {
                    downloadURL = releaseURL
                } else {
                    state = .failed("No download found")
                    return
                }

                state = .available(version: latestVersion, url: downloadURL)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func openDownload(_ url: URL) {
        NSWorkspace.shared.open(url)
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
