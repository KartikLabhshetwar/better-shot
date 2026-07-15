import Foundation

// MARK: - Request

/// A parsed HTTP/1.1 request. Only the subset the local API needs: request line, headers, body.
struct LocalAPIRequest {
    let method: String
    let path: String
    /// Header names are lowercased.
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

extension LocalAPIRequest {
    enum ParseError: Error {
        case malformedHead
        case headTooLarge
        case bodyTooLarge
    }

    /// Largest request head we will buffer before giving up on a client.
    static let maxHeadSize = 16 * 1024

    /// Parses a complete request out of `buffer`, or returns nil if more bytes are needed.
    static func parse(_ buffer: Data, maxBodySize: Int) throws -> LocalAPIRequest? {
        guard let headEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > maxHeadSize { throw ParseError.headTooLarge }
            return nil
        }
        // The check above only fires while the terminator is missing. A client that sends an
        // oversized head and its terminator together would otherwise land here on the first
        // parse and skip the cap entirely, so measure the head we actually found.
        guard buffer.distance(from: buffer.startIndex, to: headEnd.lowerBound) <= maxHeadSize else {
            throw ParseError.headTooLarge
        }

        let head = String(decoding: buffer[buffer.startIndex..<headEnd.lowerBound], as: UTF8.self)
        var lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { throw ParseError.malformedHead }

        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { throw ParseError.malformedHead }

        let method = String(requestLine[0]).uppercased()
        let target = String(requestLine[1])
        let path = String(target.prefix(while: { $0 != "?" }))

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { throw ParseError.malformedHead }
            let name = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        // A Content-Length that is negative, non-numeric, or too large for Int is a malformed
        // head. Falling back to zero would accept the request and silently ignore its body.
        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsed = Int(rawLength), parsed >= 0 else { throw ParseError.malformedHead }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        guard contentLength <= maxBodySize else { throw ParseError.bodyTooLarge }

        let bodyStart = headEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= contentLength else { return nil }
        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)

        return LocalAPIRequest(
            method: method,
            path: path,
            headers: headers,
            body: Data(buffer[bodyStart..<bodyEnd])
        )
    }
}

// MARK: - Multipart

/// One `multipart/form-data` part.
struct LocalAPIMultipartPart {
    let name: String
    let filename: String?
    let data: Data
}

extension LocalAPIRequest {
    /// Reads the boundary out of a `multipart/form-data` content type, if present.
    static func multipartBoundary(contentType: String) -> String? {
        guard contentType.lowercased().hasPrefix("multipart/form-data") else { return nil }
        return parameter("boundary", in: contentType)
    }

    /// Splits a `multipart/form-data` body into its parts. Malformed input yields whatever parsed cleanly.
    static func parseMultipart(body: Data, boundary: String) -> [LocalAPIMultipartPart] {
        let delimiter = Data("\r\n--\(boundary)".utf8)
        let headSeparator = Data("\r\n\r\n".utf8)

        // The opening delimiter has no leading CRLF, so scan a prefixed copy and treat every
        // delimiter the same way.
        var scratch = Data("\r\n".utf8)
        scratch.append(body)

        var parts: [LocalAPIMultipartPart] = []
        guard var cursor = scratch.range(of: delimiter)?.upperBound else { return parts }

        while scratch.distance(from: cursor, to: scratch.endIndex) >= 2 {
            // A delimiter is followed by "--" when it closes the body, or CRLF when a part follows.
            let marker = scratch[cursor..<scratch.index(cursor, offsetBy: 2)]
            guard marker == Data("\r\n".utf8) else { return parts }

            let partStart = scratch.index(cursor, offsetBy: 2)
            guard let headEnd = scratch.range(of: headSeparator, in: partStart..<scratch.endIndex),
                  let next = scratch.range(of: delimiter, in: headEnd.upperBound..<scratch.endIndex)
            else { return parts }

            let head = String(decoding: scratch[partStart..<headEnd.lowerBound], as: UTF8.self)
            if let name = disposition("name", in: head) {
                parts.append(LocalAPIMultipartPart(
                    name: name,
                    filename: disposition("filename", in: head),
                    data: Data(scratch[headEnd.upperBound..<next.lowerBound])
                ))
            }
            cursor = next.upperBound
        }

        return parts
    }

    private static func disposition(_ name: String, in head: String) -> String? {
        for line in head.split(separator: "\r\n")
        where line.lowercased().hasPrefix("content-disposition:") {
            return parameter(name, in: String(line))
        }
        return nil
    }

    /// Pulls `name="value"` (or `name=value`) out of a semicolon-separated header value.
    private static func parameter(_ name: String, in value: String) -> String? {
        for component in value.split(separator: ";") {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("\(name.lowercased())=") else { continue }
            let raw = trimmed.dropFirst(name.count + 1)
            return String(raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
        return nil
    }
}

// MARK: - Response

struct LocalAPIResponse {
    let status: Int
    let contentType: String
    let body: Data

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> LocalAPIResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let body = try? encoder.encode(value) else {
            return LocalAPIResponse(
                status: 500,
                contentType: "application/json",
                body: Data(#"{"error":"Could not encode response"}"#.utf8)
            )
        }
        return LocalAPIResponse(status: status, contentType: "application/json", body: body)
    }

    static func error(_ status: Int, _ message: String) -> LocalAPIResponse {
        json(ErrorResponse(error: message), status: status)
    }

    static func png(_ data: Data) -> LocalAPIResponse {
        LocalAPIResponse(status: 200, contentType: "image/png", body: data)
    }

    var serialized: Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"

        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 431: return "Request Header Fields Too Large"
        default: return "Internal Server Error"
        }
    }
}

struct ErrorResponse: Encodable {
    let error: String
}
