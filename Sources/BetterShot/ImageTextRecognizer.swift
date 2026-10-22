//
//  ImageTextRecognizer.swift
//  BetterShot
//

import Foundation
import Vision
import VisionKit

/// Reads barcode payloads and text from images without blocking the main actor.
nonisolated enum ImageTextRecognizer {
    private static let analyzer = ImageAnalyzer()

    /// Returns barcode payloads first, then the recognized text, joined by newlines.
    static func recognizeContent(at url: URL) async throws -> String {
        async let barcodes = barcodePayloads(at: url)
        let text = try await recognizeText(at: url)
        return (try await barcodes + [text]).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Live Text runs in a system service with precompiled models; Vision's own models compile on first use.
    private static func recognizeText(at url: URL) async throws -> String {
        if ImageAnalyzer.isSupported,
           let analysis = try? await analyzer.analyze(imageAt: url, orientation: .up, configuration: .init(.text)) {
            return analysis.transcript
        }
        return try await perform {
            let request = VNRecognizeTextRequest()
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(url: url).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.joined(separator: "\n")
    }

    private static func barcodePayloads(at url: URL) async throws -> [String] {
        try await perform {
            let request = VNDetectBarcodesRequest()
            try VNImageRequestHandler(url: url).perform([request])
            return (request.results ?? []).compactMap(\.payloadStringValue)
        }
    }

    private static func perform(_ work: @escaping @Sendable () throws -> [String]) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(with: Result(catching: work)) }
        }
    }
}
