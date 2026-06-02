import SwiftUI

struct MenuBarContentView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // Screenshot capture actions
            Group {
                Button {
                    Task { await CaptureOrchestrator.shared.performCapture(.region) }
                } label: {
                    Label("Capture Region", systemImage: "rectangle.dashed")
                }
                .keyboardShortcut("4", modifiers: [.command, .shift])

                Button {
                    Task { await CaptureOrchestrator.shared.performCapture(.fullscreen) }
                } label: {
                    Label("Capture Screen", systemImage: "desktopcomputer")
                }
                .keyboardShortcut("3", modifiers: [.command, .shift])

                Button {
                    Task { await CaptureOrchestrator.shared.performCapture(.window) }
                } label: {
                    Label("Capture Window", systemImage: "macwindow")
                }
                .keyboardShortcut("5", modifiers: [.command, .shift])

                Button {
                    Task { await CaptureOrchestrator.shared.performCapture(.ocr) }
                } label: {
                    Label("OCR Region", systemImage: "doc.text.viewfinder")
                }
            }

            Divider()

            // Screen recording
            Menu {
                Button {
                    Task { await CaptureOrchestrator.shared.startRecordingFullscreen() }
                } label: {
                    Label("Full Screen", systemImage: "desktopcomputer")
                }

                Button {
                    Task { await CaptureOrchestrator.shared.startRecordingWindow() }
                } label: {
                    Label("Window", systemImage: "macwindow")
                }
            } label: {
                Label("Record Screen", systemImage: "record.circle")
            }

            if ScreenRecorder.shared.isRecording {
                Button {
                    Task { await CaptureOrchestrator.shared.toggleRecording() }
                } label: {
                    Label("Stop Recording", systemImage: "stop.circle.fill")
                }
                .keyboardShortcut("6", modifiers: [.command, .shift])
            }

            Divider()

            // Recent captures
            if !HistoryStore.shared.records.isEmpty {
                Menu("Recent") {
                    ForEach(HistoryStore.shared.records.prefix(5)) { record in
                        Button(record.filename) {
                            let url = HistoryStore.shared.urlForRecord(record)
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                Divider()
            }

            // Settings & Quit
            Button("Preferences...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit BetterShot") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
