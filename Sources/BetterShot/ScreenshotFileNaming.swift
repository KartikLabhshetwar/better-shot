//
//  ScreenshotFileNaming.swift
//  BetterShot
//

import Foundation

enum ScreenshotFileNaming {
    static func fileName(date: Date = Date(), extension pathExtension: String = "png") -> String {
        "BetterShot_\(timestampFormatter.string(from: date)).\(pathExtension)"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }()
}
