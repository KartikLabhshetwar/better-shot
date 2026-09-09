//
//  AnnotationEditorChrome.swift
//  BetterShot
//

import SwiftUI

struct AnnotationZoomControl: View {
    @Bindable var model: AnnotationEditorModel

    var body: some View {
        Menu {
            Button("Zoom In", action: model.zoomIn)
                .disabled(model.zoomPercent >= AnnotationEditorModel.maxZoomPercent)
            Button("Zoom Out", action: model.zoomOut)
                .disabled(model.zoomPercent <= AnnotationEditorModel.minZoomPercent)
            Divider()
            Button("Fit Canvas", action: model.fitCanvas)
            ForEach([25, 50, 100, 200, 400], id: \.self) { percent in
                Button("\(percent)%") { model.setZoomPercent(percent) }
            }
        } label: {
            Text("\(model.zoomPercent)%")
                .monospacedDigit()
                .frame(width: 64)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(8)
        .background(EditorChrome.panel, in: Capsule())
        .accessibilityLabel("Canvas zoom, \(model.zoomPercent) percent")
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
            .studioGlass()
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
            .studioGlass()
        }
        .buttonStyle(.plain)
        .help("Why is this preview low resolution?")
    }
}

struct AnnotationEditorWorkspaceBackground: View {
    var body: some View {
        EditorChrome.workspace
            .ignoresSafeArea()
    }
}
