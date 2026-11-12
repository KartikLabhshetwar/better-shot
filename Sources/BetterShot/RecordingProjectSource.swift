import Foundation

nonisolated enum RecordingProjectSourceError: LocalizedError {
    case invalidSource
    case unsafePackage
    case missingMedia
    case alreadyInstalled

    var errorDescription: String? {
        switch self {
        case .invalidSource: "The project contains an invalid recording source."
        case .unsafePackage: "The recording source contains an unsafe file reference."
        case .missingMedia: "A recording source is missing its screen movie. Restore the source package and try again."
        case .alreadyInstalled: "This recording source is already installed in the project."
        }
    }
}

/// A source's immutable package contains its original movies, input, and authored edit document.
/// Clip ranges refer to that document's edited clock, before the outer clip speed is applied.
nonisolated struct RecordingProjectSource: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var displayName: String
    var duration: TimeInterval
    /// Imported project canvases, from the innermost container to the outermost.
    var presentationAspectRatios: [Double]?

    init(id: UUID = UUID(), displayName: String, duration: TimeInterval,
         presentationAspectRatios: [Double]? = nil) {
        self.id = id
        self.displayName = displayName
        self.duration = duration
        self.presentationAspectRatios = presentationAspectRatios
    }

    func sessionDirectory(in projectDirectory: URL) -> URL {
        projectDirectory.appendingPathComponent("sources", isDirectory: true)
            .appendingPathComponent(id.uuidString + ".bettershotrec", isDirectory: true)
    }

    static func validatePresentationAspectRatios(_ aspects: [Double]) throws {
        // Bound imported layout ancestry without retaining recursive package references.
        guard aspects.count <= 16, aspects.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw RecordingProjectSourceError.invalidSource
        }
    }

    func validatePackage(in projectDirectory: URL) throws {
        try Self.validatePresentationAspectRatios(presentationAspectRatios ?? [])
        guard duration.isFinite, duration >= RecordingClipSegment.minimumDuration else {
            throw RecordingProjectSourceError.invalidSource
        }
        let root = projectDirectory.resolvingSymlinksInPath().standardizedFileURL
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try Self.requireDirectory(sources)
        let package = sessionDirectory(in: root)
        try Self.requireDirectory(package)
        try Self.validateTree(package)
    }

    /// Returns a private, unreferenced copy. Callers write their authored snapshot before installing it.
    /// Cancelling or losing the revision check must remove this stage, never touch the original.
    func stageCopy(from sourceDirectory: URL, in projectDirectory: URL, authoredDocument: Data? = nil) throws -> URL {
        try Self.validatePresentationAspectRatios(presentationAspectRatios ?? [])
        guard duration.isFinite, duration >= RecordingClipSegment.minimumDuration else {
            throw RecordingProjectSourceError.invalidSource
        }
        try Self.requireDirectory(sourceDirectory)
        let files = try Self.sourceFiles(in: sourceDirectory, authoredDocument: authoredDocument)
        let sources = try Self.prepareSourcesDirectory(in: projectDirectory)
        let stage = sources.appendingPathComponent(".stage-" + UUID().uuidString + ".bettershotrec", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
            for name in files.names {
                try FileManager.default.copyItem(at: sourceDirectory.appendingPathComponent(name),
                                                to: stage.appendingPathComponent(name))
            }
            if let document = files.document {
                try document.write(to: stage.appendingPathComponent("edit.json"), options: .atomic)
            }
            try Self.validateTree(stage)
            return stage
        } catch {
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
    }

    /// The stage and final package share a directory, so the install is one atomic rename.
    func installStagedCopy(_ stage: URL, in projectDirectory: URL) throws {
        try Self.validatePresentationAspectRatios(presentationAspectRatios ?? [])
        let sources = try Self.prepareSourcesDirectory(in: projectDirectory)
        guard stage.deletingLastPathComponent().standardizedFileURL == sources.standardizedFileURL,
              stage.lastPathComponent.hasPrefix(".stage-"), stage.pathExtension == "bettershotrec" else {
            throw RecordingProjectSourceError.unsafePackage
        }
        try Self.requireDirectory(stage)
        try Self.validateTree(stage)
        let destination = sessionDirectory(in: projectDirectory.resolvingSymlinksInPath().standardizedFileURL)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw RecordingProjectSourceError.alreadyInstalled
        }
        try FileManager.default.moveItem(at: stage, to: destination)
    }

    private static func prepareSourcesDirectory(in projectDirectory: URL) throws -> URL {
        let root = projectDirectory.resolvingSymlinksInPath().standardizedFileURL
        try requireDirectory(root)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        if !FileManager.default.fileExists(atPath: sources.path) {
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: false)
        }
        try requireDirectory(sources)
        return sources
    }

    private static func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw RecordingProjectSourceError.unsafePackage
        }
    }

    private static func sourceFiles(in directory: URL, authoredDocument: Data? = nil) throws -> (names: [String], document: Data?) {
        var names = ["screen.mov"]
        for name in ["camera.mov", "input.json", "capture.json"]
            where FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            names.append(name)
        }
        let draft = directory.appendingPathComponent("edit.draft.json")
        let committed = directory.appendingPathComponent("edit.json")
        let documentURL = FileManager.default.fileExists(atPath: draft.path) ? draft : committed
        var document: Data?
        if authoredDocument != nil || FileManager.default.fileExists(atPath: documentURL.path) {
            if authoredDocument == nil { try requireRegularFile(documentURL) }
            let data = try authoredDocument ?? Data(contentsOf: documentURL)
            document = data
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["sources"] == nil || json["sources"] is NSNull),
                  (json["sourceDocuments"] == nil || json["sourceDocuments"] is NSNull) else {
                throw RecordingProjectSourceError.invalidSource
            }
            if let audio = json["replacementAudioFileName"], !(audio is NSNull) {
                guard let name = audio as? String, !name.isEmpty, name != ".", name != "..",
                      !name.contains("/"), !name.contains("\\"),
                      URL(fileURLWithPath: name).lastPathComponent == name else {
                    throw RecordingProjectSourceError.unsafePackage
                }
                names.append(name)
            }
        }
        for name in names { try requireRegularFile(directory.appendingPathComponent(name)) }
        return (Array(Set(names)).sorted(), document)
    }

    private static func requireRegularFile(_ file: URL) throws {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw RecordingProjectSourceError.unsafePackage
        }
    }

    private static func validateTree(_ directory: URL) throws {
        let screen = directory.appendingPathComponent("screen.mov")
        guard FileManager.default.isReadableFile(atPath: screen.path),
              let size = try? screen.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw RecordingProjectSourceError.missingMedia
        }
        _ = try sourceFiles(in: directory)
        var enumerationError: Error?
        guard let files = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw RecordingProjectSourceError.unsafePackage
        }
        for case let file as URL in files {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            guard values.isSymbolicLink != true,
                  values.isRegularFile == true || values.isDirectory == true else {
                throw RecordingProjectSourceError.unsafePackage
            }
        }
        if let enumerationError { throw enumerationError }
    }
}
