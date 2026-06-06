import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            Button {
                Task { await CaptureOrchestrator.shared.performCapture(.region) }
            } label: {
                Label("Region", systemImage: "rectangle.dashed")
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])

            Button {
                Task { await CaptureOrchestrator.shared.performCapture(.fullscreen) }
            } label: {
                Label("Full Screen", systemImage: "desktopcomputer")
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])

            Button {
                Task { await CaptureOrchestrator.shared.performCapture(.window) }
            } label: {
                Label("Window", systemImage: "macwindow")
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])

            Divider()

            Button {
                Task { await CaptureOrchestrator.shared.performCapture(.ocr) }
            } label: {
                Label("Copy Text (OCR)", systemImage: "doc.text.viewfinder")
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button {
                Task { await CaptureOrchestrator.shared.performCapture(.colorPicker) }
            } label: {
                Label("Pick Color", systemImage: "eyedropper")
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            if PinnedScreenshotController.shared.hasPinnedWindows {
                Divider()

                Button {
                    PinnedScreenshotController.shared.unpinAll()
                } label: {
                    Label("Unpin All", systemImage: "pin.slash")
                }
            }

            Divider()

            Menu("Recent Captures") {
                if HistoryStore.shared.records.isEmpty {
                    Text("No captures yet")
                } else {
                    ForEach(HistoryStore.shared.records.prefix(8)) { record in
                        Button {
                            let url = HistoryStore.shared.urlForRecord(record)
                            EditorWindowController.shared.open(url: url)
                        } label: {
                            Text(record.filename)
                        }
                    }
                }
            }

            Divider()

            Button("Settings") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
