#!/usr/bin/env swift

import Foundation
import Vision
import AppKit

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: ocr-helper <image-path>\n", stderr)
    exit(1)
}

let imagePath = CommandLine.arguments[1]
let imageURL = URL(fileURLWithPath: imagePath)

guard FileManager.default.fileExists(atPath: imagePath) else {
    fputs("Error: Image file not found: \(imagePath)\n", stderr)
    exit(1)
}

guard let image = NSImage(contentsOf: imageURL),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Error: Could not load image\n", stderr)
    exit(1)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

do {
    try handler.perform([request])
} catch {
    fputs("Error: OCR failed - \(error.localizedDescription)\n", stderr)
    exit(1)
}

guard let observations = request.results else {
    fputs("Error: No results from OCR\n", stderr)
    exit(1)
}

let recognizedText = observations.compactMap { observation in
    observation.topCandidates(1).first?.string
}.joined(separator: "\n")

if recognizedText.isEmpty {
    fputs("No text found in image\n", stderr)
    exit(2)
}

print(recognizedText)
