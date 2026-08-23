import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct R2UploadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Hand-rolled AWS SigV4 signing for direct-to-R2 uploads. No SDK dependency.
enum R2SigV4 {
    static let algorithm = "AWS4-HMAC-SHA256"
    static let unsignedPayload = "UNSIGNED-PAYLOAD"
    static let region = "auto"
    static let service = "s3"

    struct Signature {
        let amzDate: String
        let contentSHA256: String
        let authorizationHeader: String
    }

    static func sign(
        method: String,
        host: String,
        canonicalURI: String,
        accessKeyID: String,
        secretAccessKey: String,
        contentType: String,
        date: Date = Date()
    ) -> Signature {
        let (dateStamp, amzDate) = formattedDates(from: date)
        let payloadHash = unsignedPayload

        let headerLines = [
            "content-type:\(contentType)",
            "host:\(host)",
            "x-amz-content-sha256:\(payloadHash)",
            "x-amz-date:\(amzDate)",
        ]
        let canonicalHeaders = headerLines.map { $0 + "\n" }.joined()
        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"

        let canonicalRequest = [
            method,
            canonicalURI,
            "",
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            sha256Hex(canonicalRequest),
        ].joined(separator: "\n")

        let signingKey = deriveSigningKey(secretAccessKey: secretAccessKey, dateStamp: dateStamp)
        let signature = hmacHex(key: signingKey, message: stringToSign)

        let authorizationHeader = "\(algorithm) Credential=\(accessKeyID)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"

        return Signature(amzDate: amzDate, contentSHA256: payloadHash, authorizationHeader: authorizationHeader)
    }

    static func deriveSigningKey(secretAccessKey: String, dateStamp: String) -> SymmetricKey {
        let kSecret = SymmetricKey(data: Data("AWS4\(secretAccessKey)".utf8))
        let kDate = hmac(key: kSecret, message: dateStamp)
        let kRegion = hmac(key: SymmetricKey(data: kDate), message: region)
        let kService = hmac(key: SymmetricKey(data: kRegion), message: service)
        return SymmetricKey(data: hmac(key: SymmetricKey(data: kService), message: "aws4_request"))
    }

    static func hmac(key: SymmetricKey, message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key))
    }

    static func hmacHex(key: SymmetricKey, message: String) -> String {
        hmac(key: key, message: message).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static let unreservedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")

    static func uriEncodePath(_ path: String) -> String {
        var encoded = ""
        for scalar in path.unicodeScalars {
            if unreservedCharacters.contains(scalar) {
                encoded.unicodeScalars.append(scalar)
            } else if scalar == "/" {
                encoded += "/"
            } else {
                for byte in String(scalar).utf8 {
                    encoded += String(format: "%%%02X", byte)
                }
            }
        }
        return encoded
    }

    private static func formattedDates(from date: Date) -> (dateStamp: String, amzDate: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: date)
        return (String(amzDate.prefix(8)), amzDate)
    }
}

@MainActor
@Observable
final class R2Uploader {
    static let shared = R2Uploader()

    private(set) var uploadProgress: [UUID: Double] = [:]
    private(set) var uploadingItems: Set<UUID> = []
    private(set) var uploadedURLs: [UUID: String] = [:]
    private(set) var failedItems: [UUID: String] = [:]

    private var activeTasks: [UUID: Task<URL, Error>] = [:]
    private let session = URLSession(configuration: .default)

    private init() {}

    func upload(itemID: UUID, fileURL: URL) async throws -> URL {
        let credentials = R2CredentialStore.shared.snapshot()
        guard credentials.isConfigured else {
            throw R2UploadError(message: "R2 sharing is not configured. Add your credentials in Settings > Sharing.")
        }

        uploadingItems.insert(itemID)
        uploadProgress[itemID] = 0
        failedItems.removeValue(forKey: itemID)

        let session = session
        let task = Task<URL, Error> {
            try await Self.performUpload(itemID: itemID, fileURL: fileURL, credentials: credentials, session: session) { fraction in
                Task { @MainActor in
                    R2Uploader.shared.uploadProgress[itemID] = fraction
                }
            }
        }
        activeTasks[itemID] = task

        do {
            let result = try await task.value
            uploadingItems.remove(itemID)
            uploadProgress.removeValue(forKey: itemID)
            uploadedURLs[itemID] = result.absoluteString
            activeTasks.removeValue(forKey: itemID)
            return result
        } catch {
            uploadingItems.remove(itemID)
            uploadProgress.removeValue(forKey: itemID)
            activeTasks.removeValue(forKey: itemID)
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            failedItems[itemID] = message
            throw error
        }
    }

    func cancel(itemID: UUID) {
        activeTasks[itemID]?.cancel()
        activeTasks.removeValue(forKey: itemID)
        uploadingItems.remove(itemID)
        uploadProgress.removeValue(forKey: itemID)
    }

    nonisolated static func testConnection(credentials: R2Credentials) async throws {
        guard credentials.isConfigured else {
            throw R2UploadError(message: "Fill in all fields before testing.")
        }

        let probeKey = "bettershot-connection-probe"
        let host = "\(credentials.accountID).r2.cloudflarestorage.com"
        let canonicalURI = "/" + uriEncodePath(credentials.bucket) + "/" + uriEncodePath(probeKey)
        guard let url = URL(string: "https://\(host)\(canonicalURI)") else {
            throw R2UploadError(message: "Invalid R2 endpoint URL.")
        }

        let contentType = "application/octet-stream"
        let signature = R2SigV4.sign(
            method: "GET",
            host: host,
            canonicalURI: canonicalURI,
            accessKeyID: credentials.accessKeyID,
            secretAccessKey: credentials.secretAccessKey,
            contentType: contentType
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(signature.amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(signature.contentSHA256, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(signature.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw R2UploadError(message: "No response from R2.")
        }
        if (200..<300).contains(http.statusCode) { return }
        if http.statusCode == 404, errorCode(data: data) != "NoSuchBucket" { return }
        throw R2UploadError(message: parseErrorMessage(data: data, statusCode: http.statusCode))
    }

    nonisolated private static func performUpload(
        itemID: UUID,
        fileURL: URL,
        credentials: R2Credentials,
        session: URLSession,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let key = objectKey(for: itemID, fileURL: fileURL)
        let host = "\(credentials.accountID).r2.cloudflarestorage.com"
        let canonicalURI = "/" + uriEncodePath(credentials.bucket) + "/" + uriEncodePath(key)
        guard let uploadURL = URL(string: "https://\(host)\(canonicalURI)") else {
            throw R2UploadError(message: "Invalid R2 endpoint URL.")
        }

        let contentType = mimeType(for: fileURL)
        let signature = R2SigV4.sign(
            method: "PUT",
            host: host,
            canonicalURI: canonicalURI,
            accessKeyID: credentials.accessKeyID,
            secretAccessKey: credentials.secretAccessKey,
            contentType: contentType
        )

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(signature.amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(signature.contentSHA256, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(signature.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 600

        let delegate = R2UploadProgressDelegate(onProgress: progress)
        let (data, response) = try await session.upload(for: request, fromFile: fileURL, delegate: delegate)

        guard let http = response as? HTTPURLResponse else {
            throw R2UploadError(message: "No response from R2.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw R2UploadError(message: parseErrorMessage(data: data, statusCode: http.statusCode))
        }

        progress(1)

        let base = credentials.publicBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let shareURL = URL(string: "\(base)/\(key)") else {
            throw R2UploadError(message: "Could not build a share URL from the Public Base URL.")
        }
        return shareURL
    }

    nonisolated private static func objectKey(for itemID: UUID, fileURL: URL) -> String {
        "recordings/\(itemID.uuidString)/\(sanitizedFilename(fileURL.lastPathComponent))"
    }

    nonisolated private static let filenameAllowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_")

    nonisolated private static func sanitizedFilename(_ name: String) -> String {
        String(name.unicodeScalars.map { filenameAllowedCharacters.contains($0) ? Character($0) : "-" })
    }

    nonisolated private static func mimeType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension.lowercased()), let mime = type.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }

    nonisolated private static func uriEncodePath(_ path: String) -> String {
        R2SigV4.uriEncodePath(path)
    }

    nonisolated private static func parseErrorMessage(data: Data, statusCode: Int) -> String {
        guard let text = String(data: data, encoding: .utf8), let code = extractXMLValue(tag: "Code", from: text) else {
            return "R2 request failed with status \(statusCode)."
        }
        if let detail = extractXMLValue(tag: "Message", from: text), !detail.isEmpty {
            return "\(code): \(detail)"
        }
        return code
    }

    nonisolated private static func errorCode(data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return extractXMLValue(tag: "Code", from: text)
    }

    nonisolated private static func extractXMLValue(tag: String, from xml: String) -> String? {
        guard let openRange = xml.range(of: "<\(tag)>"), let closeRange = xml.range(of: "</\(tag)>"),
              openRange.upperBound <= closeRange.lowerBound else {
            return nil
        }
        return String(xml[openRange.upperBound..<closeRange.lowerBound])
    }
}

private final class R2UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}
