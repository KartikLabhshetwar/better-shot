//
//  AnnotationEditorChrome.swift
//  BetterShot
//

import SwiftUI

extension Animation {
    /// Animation used for discrete zoom changes (menu, shortcuts, zoom in/out).
    static var canvasZoom: Animation { .smooth(duration: 0.24) }
}

struct AnnotationZoomControl: View {
    @Bindable var model: AnnotationEditorModel

    private func zoom(_ change: () -> Void) {
        withAnimation(.canvasZoom, change)
    }

    var body: some View {
        Menu {
            Button("Zoom In") { zoom { model.zoomIn() } }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { zoom { model.zoomOut() } }
                .keyboardShortcut("-", modifiers: .command)

            Divider()

            Button("Fit Canvas") { zoom { model.fitCanvas() } }
                .keyboardShortcut("1", modifiers: .command)

            Divider()

            Button("50%") { zoom { model.setZoomPercent(50) } }
            Button("100%") { zoom { model.setZoomPercent(100) } }
                .keyboardShortcut("0", modifiers: .command)
            Button("200%") { zoom { model.setZoomPercent(200) } }
        } label: {
            Text("\(model.zoomPercent)%")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .frame(minWidth: 38)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Capsule())
                .glassEffect(.regular.interactive())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Zoom")
    }
}

/// Live pixel dimensions of the current crop selection, shown in the bottom
/// trailing corner of the canvas while cropping. Styled to match the zoom
/// control capsule on the opposite side.
struct CropResolutionBadge: View {
    let size: CGSize

    var body: some View {
        Text("\(Int(size.width)) × \(Int(size.height)) px")
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .fixedSize()
            .glassEffect()
            .help("Crop size")
    }
}

/// A small badge shown beside the zoom control when the editing preview is
/// downscaled to save memory. Collapsed it's just an "i" button; tapping it
/// expands an explanation that the reduction is preview-only and points users
/// to Settings to disable it.
struct LowResolutionPreviewNotice: View {
    @State private var isExpanded = false

    private let diameter: CGFloat = 28

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: diameter, height: diameter)

                if isExpanded {
                    Text("Low-res preview to save memory - exports stay full quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.trailing, 12)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .frame(height: diameter)
            .fixedSize()
            .glassEffect()
        }
        .buttonStyle(.plain)
        .help("Why is this preview low resolution?")
    }
}

struct AnnotationEditorWorkspaceBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}
