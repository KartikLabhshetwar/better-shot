import AVFoundation

/// Resolves a concrete microphone so ScreenCaptureKit never silently picks an input device on its own.
nonisolated enum MicrophoneCatalog {
    static func available() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    static func microphone(withID uniqueID: String) -> AVCaptureDevice? {
        guard !uniqueID.isEmpty else { return nil }
        return available().first { $0.uniqueID == uniqueID }
    }

    static func resolveID(availableIDs: [String], savedID: String?, systemDefaultID: String?) -> String? {
        if let savedID, !savedID.isEmpty, availableIDs.contains(savedID) { return savedID }
        if let systemDefaultID, !systemDefaultID.isEmpty, availableIDs.contains(systemDefaultID) { return systemDefaultID }
        return availableIDs.first
    }

    static func preferred(savedID: String?) -> AVCaptureDevice? {
        let devices = available()
        let chosen = resolveID(
            availableIDs: devices.map(\.uniqueID),
            savedID: savedID,
            systemDefaultID: AVCaptureDevice.default(for: .audio)?.uniqueID
        )
        return devices.first { $0.uniqueID == chosen }
    }
}
