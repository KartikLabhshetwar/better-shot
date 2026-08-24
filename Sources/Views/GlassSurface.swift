import AppKit
import SwiftUI

/// Shadow presets. Liquid Glass carries its own edge shading, so it needs less cast shadow than the pre-Tahoe material, hence two opacities per preset.
struct GlassDepth {
    var materialOpacity: Double
    var glassOpacity: Double
    var radius: CGFloat
    var y: CGFloat

    /// Panels hovering over the desktop: the recording bar, the capture thumbnail.
    static let floating = GlassDepth(materialOpacity: 0.35, glassOpacity: 0.18, radius: 16, y: 5)
    /// Chrome anchored to something on screen: the menu bar tray, toasts.
    static let raised = GlassDepth(materialOpacity: 0.18, glassOpacity: 0.10, radius: 12, y: 4)
    /// Small controls sitting inside another glass surface.
    static let flush = GlassDepth(materialOpacity: 0, glassOpacity: 0, radius: 0, y: 0)
}

enum GlassPalette {
    static let edge = Color(nsColor: .separatorColor).opacity(0.5)
}

/// Pre-Tahoe backing, blended behind the window so it picks up the desktop rather than the app.
struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Liquid Glass on macOS 26, `NSVisualEffectView` below that, opaque fill when transparency is reduced. Exactly one translucent branch runs, so text stays legible.
struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var depth: GlassDepth = .floating
    var isInteractive = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(shape.stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                .shadow(color: .black.opacity(depth.materialOpacity), radius: depth.radius, y: depth.y)
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
                .shadow(color: .black.opacity(depth.glassOpacity), radius: depth.radius, y: depth.y)
        } else {
            content
                .background(VisualEffectBackdrop(material: material, blendingMode: blendingMode).clipShape(shape))
                .overlay(shape.stroke(GlassPalette.edge, lineWidth: 0.5))
                .shadow(color: .black.opacity(depth.materialOpacity), radius: depth.radius, y: depth.y)
        }
    }
}

extension View {
    func glassSurface<S: Shape>(
        in shape: S,
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        depth: GlassDepth = .floating,
        isInteractive: Bool = false
    ) -> some View {
        modifier(GlassSurface(shape: shape, material: material, blendingMode: blendingMode, depth: depth, isInteractive: isInteractive))
    }

    func glassSurface(
        cornerRadius: CGFloat,
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        depth: GlassDepth = .floating,
        isInteractive: Bool = false
    ) -> some View {
        glassSurface(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            material: material,
            blendingMode: blendingMode,
            depth: depth,
            isInteractive: isInteractive
        )
    }
}
