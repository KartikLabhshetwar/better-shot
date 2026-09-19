import CoreImage

/// Shared GPU focus blur for the displayed preview and the export compositor.
/// Kernels compile once; strength is specified at 1080p and scales with the canvas.
nonisolated enum Recording3DBlurRenderer {
    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "The GPU could not prepare the 3D focus effect. Try reopening the editor or switch Depth Blur to None." }
    }
    private static let kernels: [CIKernel] = (try? CIKernel.kernels(withMetalString: source)) ?? []

    static func apply(_ settings: Recording3DBlur, to image: CIImage, canvas: CGRect) throws -> CIImage {
        guard settings.isActive else { return image }
        let blur = settings.sanitized
        guard blur.isActive else { return image }
        let mode: Double = switch blur.mode { case .none: 0; case .radial: 1; case .directional: 2; case .tiltShift: 3 }
        let radius = blur.strength * canvas.height / 1080
        let frame = CIVector(x: canvas.width, y: canvas.height, z: mode, w: radius)
        let focus = CIVector(x: blur.focusX, y: blur.focusY, z: blur.focusSize, w: blur.angle * .pi / 180)
        let name = blur.bokeh ? "bettershotBokeh" : "bettershotFocusBlur"
        guard let kernel = kernels.first(where: { $0.name == name }) else { throw Failure.unavailable }
        var result = image.cropped(to: canvas)
        for pass in 0..<(blur.bokeh ? 1 : 2) {
            let style = CIVector(x: blur.falloff, y: blur.position, z: Double(pass), w: 0)
            guard let next = kernel.apply(extent: canvas, roiCallback: { _, rect in
                rect.insetBy(dx: -ceil(radius) - 1, dy: -ceil(radius) - 1)
            }, arguments: [result.clampedToExtent(), frame, focus, style]) else { throw Failure.unavailable }
            result = next
        }
        return result.cropped(to: canvas)
    }

    private static let source = #"""
    #include <metal_stdlib>
    #include <CoreImage/CoreImage.h>
    using namespace metal;
    using namespace coreimage;

    float focusRadius(float2 pixel, float4 frame, float4 focus, float4 style) {
        float2 uv = pixel / frame.xy;
        float aspect = frame.x / frame.y;
        float distance;
        float edge = focus.z * 0.5;
        float spread = (edge + 0.35) * (1.0 + 3.0 * style.x);
        if (frame.z == 2.0) {
            float2 delta = (uv - 0.5) * float2(aspect, 1.0);
            float extent = (aspect + 1.0) * 0.5;
            distance = dot(delta, float2(cos(focus.w), sin(focus.w))) - mix(-extent, extent, style.y);
            spread = 0.7 * (1.0 + 3.0 * style.x);
        } else {
            float2 delta = (uv - focus.xy) * float2(aspect, 1.0);
            distance = frame.z == 3.0 ? max(abs(dot(delta, float2(sin(focus.w), cos(focus.w)))) - edge, 0.0) : length(delta);
            distance -= edge;
        }
        float fade = smoothstep(0.0, max(spread, 0.0001), distance);
        return frame.w * pow(fade, mix(2.0, 0.7, style.x));
    }

    [[stitchable]] float4 bettershotFocusBlur(coreimage::sampler image, float4 frame, float4 focus, float4 style, destination dest) {
        float2 p = dest.coord();
        float radius = focusRadius(p, frame, focus, style);
        if (radius < 0.5) return image.sample(image.transform(p));
        radius = min(radius, frame.y * (40.0 / 1080.0));
        float2 axis = style.z < 0.5 ? float2(1, 0) : float2(0, 1);
        float4 sum = float4(0);
        float total = 0;
        // Fixed sample budget: changing resolution or strength never increases GPU taps.
        for (int i = -8; i <= 8; ++i) {
            float fraction = float(i) / 8.0;
            float weight = exp(-2.0 * fraction * fraction);
            sum += image.sample(image.transform(p + axis * fraction * radius)) * weight;
            total += weight;
        }
        return sum / total;
    }

    [[stitchable]] float4 bettershotBokeh(coreimage::sampler image, float4 frame, float4 focus, float4 style, destination dest) {
        float2 p = dest.coord();
        float radius = focusRadius(p, frame, focus, style);
        float4 sum = image.sample(image.transform(p));
        if (radius < 0.5) return sum;
        float total = 1;
        // Uniform disc sampling with a golden-angle spiral avoids directional streaks.
        for (int i = 0; i < 32; ++i) {
            float angle = float(i) * 2.39996323;
            float r = radius * sqrt((float(i) + 0.5) / 32.0);
            float4 color = image.sample(image.transform(p + float2(cos(angle), sin(angle)) * r));
            float light = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
            float weight = 1.0 + 1.5 * smoothstep(0.7, 1.0, light);
            sum += color * weight;
            total += weight;
        }
        return sum / total;
    }
    """#
}
