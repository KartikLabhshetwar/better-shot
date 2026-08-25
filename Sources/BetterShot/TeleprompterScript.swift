//
//  TeleprompterScript.swift
//  BetterShot
//
//  The teleprompter's text model: the script split into display words, a
//  greedy fuzzy matcher that tracks how far into the script the speaker
//  has read from live transcription, and the fixed line layout the notch
//  overlay scrolls through. Matching is recomputed from the full spoken
//  history on every recognizer update, so volatile-result revisions can
//  never leave the pointer stranded mid-script.
//

import AppKit
import Foundation

/// Word-level text utilities shared by the matcher (which runs on the
/// speech engine's task) and the layout (main actor).
nonisolated enum TeleprompterScriptText {
    /// Display tokens: whitespace-separated words keeping punctuation.
    static func displayWords(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Canonical form used to compare a spoken word against a script word:
    /// lowercased with everything but letters and digits stripped, so
    /// "Hello," matches "hello" and "it's" matches "its".
    static func normalize(_ word: String) -> String {
        String(word.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }).lowercased()
    }

    static func normalizedWords(_ text: String) -> [String] {
        displayWords(text).map(normalize).filter { !$0.isEmpty }
    }
}

/// Tracks reading progress: given everything the recognizer has heard so
/// far, how many script display words have been spoken. Greedy with a
/// short lookahead, so misrecognized or skipped words don't stall the
/// prompter - the pointer re-anchors on the next word that matches.
nonisolated struct TeleprompterScriptMatcher: Sendable {
    private struct Entry {
        let normalized: String
        let displayIndex: Int
    }

    /// Script words the recognizer could plausibly skip past in one jump.
    private static let lookahead = 8

    private let entries: [Entry]

    init(script: String) {
        entries = TeleprompterScriptText.displayWords(script)
            .enumerated()
            .compactMap { index, word in
                let normalized = TeleprompterScriptText.normalize(word)
                guard !normalized.isEmpty else { return nil }
                return Entry(normalized: normalized, displayIndex: index)
            }
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    /// Number of script display words read so far (the word at index
    /// `count - 1` is the one being spoken).
    func spokenDisplayWordCount(spoken: [String]) -> Int {
        var position = 0
        for word in spoken {
            guard position < entries.count else { break }
            let window = position..<min(entries.count, position + Self.lookahead)
            if let match = window.first(where: { entries[$0].normalized == word }) {
                position = match + 1
            }
        }
        guard position > 0 else { return 0 }
        return entries[position - 1].displayIndex + 1
    }
}

/// The script wrapped into fixed lines for the overlay. Wrapping is done
/// once up front with real AppKit text measurement so the view can scroll
/// line-by-line and know exactly which line holds the active word.
struct TeleprompterScriptLayout {
    struct Word: Identifiable {
        /// Index into the script's display words (the matcher's counting).
        let index: Int
        let text: String

        var id: Int { index }
    }

    let lines: [[Word]]
    /// Line index for each display word.
    private let lineOfWord: [Int]

    static let empty = TeleprompterScriptLayout(lines: [], lineOfWord: [])

    private init(lines: [[Word]], lineOfWord: [Int]) {
        self.lines = lines
        self.lineOfWord = lineOfWord
    }

    init(script: String, maximumLineWidth: CGFloat, font: NSFont) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let spaceWidth = (" " as NSString).size(withAttributes: attributes).width

        var lines: [[Word]] = []
        var lineOfWord: [Int] = []
        var currentLine: [Word] = []
        var currentWidth: CGFloat = 0
        var wordIndex = 0

        func flushLine() {
            guard !currentLine.isEmpty else { return }
            lines.append(currentLine)
            currentLine = []
            currentWidth = 0
        }

        // Paragraph breaks in the script are respected as hard line breaks.
        for paragraph in script.components(separatedBy: .newlines) {
            for word in TeleprompterScriptText.displayWords(paragraph) {
                let width = (word as NSString).size(withAttributes: attributes).width
                let joinedWidth = currentLine.isEmpty ? width : currentWidth + spaceWidth + width
                if !currentLine.isEmpty, joinedWidth > maximumLineWidth {
                    flushLine()
                    currentWidth = width
                } else {
                    currentWidth = joinedWidth
                }
                currentLine.append(Word(index: wordIndex, text: word))
                lineOfWord.append(lines.count)
                wordIndex += 1
            }
            flushLine()
        }

        self.lines = lines
        self.lineOfWord = lineOfWord
    }

    var isEmpty: Bool {
        lines.isEmpty
    }

    func lineIndex(forWord index: Int) -> Int {
        guard !lineOfWord.isEmpty else { return 0 }
        return lineOfWord[min(max(index, 0), lineOfWord.count - 1)]
    }

    /// Whether this word closes its line - the reader's cue that their eyes
    /// need the next line now, not after the recognizer catches up.
    func isLastWord(inLine index: Int) -> Bool {
        guard index >= 0, index < lineOfWord.count else { return false }
        return index + 1 == lineOfWord.count || lineOfWord[index + 1] != lineOfWord[index]
    }
}
