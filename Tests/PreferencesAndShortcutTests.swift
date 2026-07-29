import XCTest
import Carbon
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class PreferencesAndShortcutTests: XCTestCase {
    func testResolveExportQualityDefaultsWhenMissing() {
        XCTAssertEqual(ExportQualityResolver.resolve(nil), 0.9)
    }

    func testResolveExportQualityPreservesZero() {
        XCTAssertEqual(ExportQualityResolver.resolve(0.0), 0.0)
    }

    func testResolveExportQualityPreservesNormalValue() {
        XCTAssertEqual(ExportQualityResolver.resolve(0.65), 0.65)
    }

    func testResolveExportQualityClampsStoredValuesToSliderRange() {
        XCTAssertEqual(ExportQualityResolver.resolve(-0.1), 0.0)
        XCTAssertEqual(ExportQualityResolver.resolve(1.1), 1.0)
    }

    func testExportQualitySliderRangeCoversZeroToOne() {
        XCTAssertEqual(ExportQualityResolver.sliderRange.lowerBound, 0.0)
        XCTAssertEqual(ExportQualityResolver.sliderRange.upperBound, 1.0)
    }

    func testExportFormatWebPContract() {
        XCTAssertTrue(ExportFormat.allCases.contains(.webp))
        XCTAssertEqual(ExportFormat.webp.rawValue, "webp")
        XCTAssertEqual(ExportFormat.webp.fileExtension, "webp")
        XCTAssertEqual(ExportFormat.webp.utType, UTType.webp.identifier)
    }

    func testResolveShortcutBindingsCoverAllActionsWithDefaultsWithoutUserDefaultsMutation() {
        let bindings = ShortcutBindings.resolveBindings { _ in nil }
        XCTAssertEqual(Set(bindings.map { $0.0 }), Set(ShortcutAction.allCases))

        let byAction: [ShortcutAction: ShortcutDefinition] = Dictionary(uniqueKeysWithValues: bindings)
        XCTAssertEqual(byAction[.region], .defaultRegion)
        XCTAssertEqual(byAction[.fullscreen], .defaultFullscreen)
        XCTAssertEqual(byAction[.window], .defaultWindow)
        XCTAssertEqual(byAction[.recording], .defaultRecording)
        XCTAssertEqual(byAction[.ocr], .defaultOCR)
        XCTAssertEqual(byAction[.colorPicker], .defaultColorPicker)
    }

    func testWindowDefaultShortcutMatchesDocumentedCombo() {
        XCTAssertEqual(ShortcutDefinition.defaultWindow.keyCode, UInt32(kVK_ANSI_5))
        XCTAssertEqual(ShortcutDefinition.defaultWindow.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertTrue(ShortcutDefinition.defaultWindow.enabled)
    }

    func testWebPEncodeRequirementProducesValidBytesAndMandatoryReadback() throws {
        XCTAssertTrue(ExportFormat.webp.supportsLossyCompressionQuality)

        let image = try XCTUnwrap(makeTinyTestImage())
        let data = try ImageExporter.encodeWebPData(from: image, quality: 0.35)

        XCTAssertGreaterThan(data.count, 12)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self), "WEBP")

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("webp")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try data.write(to: tempURL, options: .atomic)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(tempURL as CFURL, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(decoded.width, image.width)
        XCTAssertEqual(decoded.height, image.height)
    }

    func testWebPPremultipliedAlphaRoundTripPreventsDarkFringe() throws {
        let image = try XCTUnwrap(makePremultipliedAlphaRegressionImage())
        let data = try ImageExporter.encodeWebPData(from: image, quality: 1.0)
        let decoded = try decodeCGImage(from: data, ext: "webp")
        let pixels = try rgbaPixels(from: decoded)

        XCTAssertEqual(pixels[3], 0)
        XCTAssertEqual(Int(pixels[7]), 128, accuracy: 2)
        XCTAssertGreaterThanOrEqual(Int(pixels[4]), 120)
        XCTAssertLessThanOrEqual(Int(pixels[4]), 136)
    }

    func testWebPQualityClampsAndProducesValidOutput() throws {
        let image = try XCTUnwrap(makeTinyTestImage())

        let belowZero = try ImageExporter.encodeWebPData(from: image, quality: -1.0)
        XCTAssertEqual(String(decoding: belowZero.prefix(4), as: UTF8.self), "RIFF")

        let aboveOne = try ImageExporter.encodeWebPData(from: image, quality: 2.0)
        XCTAssertEqual(String(decoding: aboveOne.dropFirst(8).prefix(4), as: UTF8.self), "WEBP")

        let decodedLossy = try decodeCGImage(from: belowZero, ext: "webp")
        let decodedLossless = try decodeCGImage(from: aboveOne, ext: "webp")
        XCTAssertEqual(decodedLossy.width, image.width)
        XCTAssertEqual(decodedLossless.height, image.height)
    }

    func testSharedExportCreatesValidPNGAndJPEG() throws {
        let image = try XCTUnwrap(makeTinyTestImage())
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let pngURL = tempDir.appendingPathComponent("sample.png")
        try ImageExporter.export(image, format: .png, quality: 2.0, to: pngURL)
        let pngData = try Data(contentsOf: pngURL)
        XCTAssertEqual(Array(pngData.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(try decodeCGImage(from: pngData, ext: "png").width, image.width)

        let jpegURL = tempDir.appendingPathComponent("sample.jpeg")
        try ImageExporter.export(image, format: .jpeg, quality: -1.0, to: jpegURL)
        let jpegData = try Data(contentsOf: jpegURL)
        XCTAssertEqual(Array(jpegData.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(try decodeCGImage(from: jpegData, ext: "jpeg").height, image.height)
    }

    func testWebPExportFailsForDirectoryURL() throws {
        let image = try XCTUnwrap(makeTinyTestImage())
        let dirURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }

        XCTAssertThrowsError(try ImageExporter.export(image, format: .webp, quality: 0.5, to: dirURL)) { error in
            XCTAssertEqual(error as? ImageExportError, .dataWriteFailed)
        }
    }

    func testImageExportErrorDescriptionsAreNonEmptyForAllCases() {
        let errors: [ImageExportError] = [
            .invalidDimensions,
            .pixelBufferOverflow,
            .bitmapContextCreationFailed,
            .webPEncodeFailed,
            .imageDestinationCreationFailed,
            .imageFinalizeFailed,
            .dataWriteFailed,
        ]

        for error in errors {
            let description = error.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertNotNil(description)
            XCTAssertFalse(description?.isEmpty ?? true)
        }
    }

    private func makeTinyTestImage() -> CGImage? {
        makeImage(
            width: 2,
            height: 2,
            pixels: [
                255, 0, 0, 255,
                0, 255, 0, 255,
                0, 0, 255, 255,
                255, 255, 0, 255,
            ]
        )
    }

    private func makePremultipliedAlphaRegressionImage() -> CGImage? {
        makeImage(
            width: 2,
            height: 1,
            pixels: [
                0, 0, 0, 0,
                128, 0, 0, 128,
            ]
        )
    }

    private func makeImage(width: Int, height: Int, pixels: [UInt8]) -> CGImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerComponent * bytesPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func decodeCGImage(from data: Data, ext: String) throws -> CGImage {
        let hint = UTType(filenameExtension: ext)?.identifier
        let options: CFDictionary? = hint.map { [kCGImageSourceTypeIdentifierHint: $0] as CFDictionary }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, options))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let drew = pixels.withUnsafeMutableBytes { rawBytes -> Bool in
            guard let base = rawBytes.baseAddress else { return false }
            guard let ctx = CGContext(
                data: base,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }

        XCTAssertTrue(drew)
        return pixels
    }
}
