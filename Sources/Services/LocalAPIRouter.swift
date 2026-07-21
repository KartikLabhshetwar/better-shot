import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Maps requests to the local API's endpoints. Runs off the main actor — rendering must not block the UI.
enum LocalAPIRouter {

    static func route(_ request: LocalAPIRequest) -> LocalAPIResponse {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return health()
        case ("GET", "/presets"):
            return presets()
        case ("POST", "/beautify"):
            return beautify(request)
        case (_, "/health"), (_, "/presets"), (_, "/beautify"):
            return .error(405, "\(request.method) is not allowed on \(request.path)")
        default:
            return .error(404, "No endpoint at \(request.path)")
        }
    }

    // MARK: - GET /health

    private struct HealthResponse: Encodable {
        let status: String
        let version: String
    }

    private static func health() -> LocalAPIResponse {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return .json(HealthResponse(status: "ok", version: version))
    }

    // MARK: - GET /presets

    private struct PresetsResponse: Encodable {
        struct Solid: Encodable {
            let id: String
            let name: String
            let hex: String
        }

        struct Gradient: Encodable {
            let id: String
            let name: String
            let stops: [String]
        }

        let solid: [Solid]
        let gradient: [Gradient]
    }

    private static func presets() -> LocalAPIResponse {
        let solid = SolidColor.presets.map {
            PresetsResponse.Solid(id: $0.id, name: $0.name, hex: hex(red: $0.red, green: $0.green, blue: $0.blue))
        }
        let gradient = GradientPreset.presets.map { preset in
            PresetsResponse.Gradient(
                id: preset.id,
                name: preset.name,
                stops: preset.stops.map { hex(red: $0.red, green: $0.green, blue: $0.blue) }
            )
        }
        return .json(PresetsResponse(solid: solid, gradient: gradient))
    }

    // MARK: - POST /beautify

    /// Style parameters, shared by the multipart and JSON encodings.
    private struct BeautifyBody: Decodable {
        var image: String?
        var background: String?
        var padding: Double?
        var cornerRadius: Double?
        var shadowStrength: Double?
        var aspectRatio: String?
        var alignment: String?
    }

    private struct BeautifyError: Error {
        let status: Int
        let message: String

        init(_ message: String, status: Int = 400) {
            self.status = status
            self.message = message
        }
    }

    private static func beautify(_ request: LocalAPIRequest) -> LocalAPIResponse {
        let contentType = request.header("content-type") ?? ""

        let imageData: Data
        let config: BeautifierConfig
        do {
            let body: BeautifyBody
            (imageData, body) = try decodeBeautifyRequest(request, contentType: contentType)
            config = try makeConfig(from: body)
        } catch let error as BeautifyError {
            return .error(error.status, error.message)
        } catch {
            return .error(400, "Could not read request: \(error.localizedDescription)")
        }

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .error(400, "Could not decode the uploaded image")
        }

        guard let rendered = BeautifierRenderer.render(image: image, config: config) else {
            return .error(500, "Renderer failed")
        }

        guard let png = pngData(from: rendered) else {
            return .error(500, "Could not encode the rendered image as PNG")
        }

        return .png(png)
    }

    private static func decodeBeautifyRequest(
        _ request: LocalAPIRequest,
        contentType: String
    ) throws -> (Data, BeautifyBody) {
        if let boundary = LocalAPIRequest.multipartBoundary(contentType: contentType) {
            let parts = LocalAPIRequest.parseMultipart(body: request.body, boundary: boundary)
            guard let image = parts.first(where: { $0.name == "image" })?.data, !image.isEmpty else {
                throw BeautifyError("Missing 'image' file part")
            }

            func field(_ name: String) -> String? {
                guard let part = parts.first(where: { $0.name == name }) else { return nil }
                return String(decoding: part.data, as: UTF8.self)
            }

            func number(_ name: String) throws -> Double? {
                guard let raw = field(name) else { return nil }
                guard let value = Double(raw) else {
                    throw BeautifyError("'\(name)' must be a number, got '\(raw)'")
                }
                return value
            }

            let body = BeautifyBody(
                image: nil,
                background: field("background"),
                padding: try number("padding"),
                cornerRadius: try number("cornerRadius"),
                shadowStrength: try number("shadowStrength"),
                aspectRatio: field("aspectRatio"),
                alignment: field("alignment")
            )
            return (image, body)
        }

        if contentType.lowercased().hasPrefix("application/json") {
            let body: BeautifyBody
            do {
                body = try JSONDecoder().decode(BeautifyBody.self, from: request.body)
            } catch {
                throw BeautifyError("Could not parse JSON body: \(error.localizedDescription)")
            }
            guard let base64 = body.image else {
                throw BeautifyError("Missing 'image' (base64-encoded image data)")
            }
            guard let image = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), !image.isEmpty else {
                throw BeautifyError("'image' is not valid base64")
            }
            return (image, body)
        }

        throw BeautifyError("Content-Type must be multipart/form-data or application/json", status: 415)
    }

    private static func makeConfig(from body: BeautifyBody) throws -> BeautifierConfig {
        var config = BeautifierConfig.default

        if let background = body.background {
            config.style = try backgroundStyle(from: background)
        }
        // Ranges match the editor's sliders, so the API can't ask for a canvas the UI could never produce.
        if let padding = body.padding {
            config.padding = try clamp(padding, to: 0...0.45, name: "padding")
        }
        if let cornerRadius = body.cornerRadius {
            config.cornerRadius = try clamp(cornerRadius, to: 0...0.12, name: "cornerRadius")
        }
        if let shadowStrength = body.shadowStrength {
            config.shadowStrength = try clamp(shadowStrength, to: 0...1, name: "shadowStrength")
        }
        // Enum fields tolerate case and stray whitespace so scripts don't have to
        // reproduce the exact rawValue casing.
        if let raw = body.aspectRatio {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let aspectRatio = CanvasAspectRatio.allCases.first(where: { $0.rawValue.lowercased() == normalized.lowercased() }) else {
                let valid = CanvasAspectRatio.allCases.map(\.rawValue).joined(separator: ", ")
                throw BeautifyError("Unknown aspectRatio '\(raw)'. Valid values: \(valid)")
            }
            config.aspectRatio = aspectRatio
        }
        if let raw = body.alignment {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let alignment = ImageAlignment.allCases.first(where: { $0.rawValue.lowercased() == normalized.lowercased() }) else {
                let valid = ImageAlignment.allCases.map(\.rawValue).joined(separator: ", ")
                throw BeautifyError("Unknown alignment '\(raw)'. Valid values: \(valid)")
            }
            config.alignment = alignment
        }

        return config
    }

    private static func backgroundStyle(from value: String) throws -> BackgroundStyle {
        if value == "none" { return .none }

        if value.hasPrefix("#") {
            guard let color = solidColor(fromHex: value) else {
                throw BeautifyError("Invalid hex color '\(value)'. Expected #RRGGBB")
            }
            return .solid(color)
        }
        if let preset = SolidColor.presets.first(where: { $0.id == value }) {
            return .solid(preset)
        }
        if let preset = GradientPreset.presets.first(where: { $0.id == value }) {
            return .gradient(preset)
        }
        throw BeautifyError("Unknown background '\(value)'. Use 'none', a #RRGGBB hex, or a preset id from GET /presets")
    }

    // MARK: - Helpers

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, name: String) throws -> CGFloat {
        guard value.isFinite else { throw BeautifyError("'\(name)' must be a finite number") }
        return CGFloat(min(max(value, range.lowerBound), range.upperBound))
    }

    private static func solidColor(fromHex value: String) -> SolidColor? {
        let digits = value.dropFirst()
        guard digits.count == 6, let packed = UInt32(digits, radix: 16) else { return nil }
        return SolidColor(
            id: "custom",
            name: value.uppercased(),
            red: Double((packed >> 16) & 0xFF) / 255,
            green: Double((packed >> 8) & 0xFF) / 255,
            blue: Double(packed & 0xFF) / 255
        )
    }

    private static func hex(red: Double, green: Double, blue: Double) -> String {
        func channel(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1, nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
