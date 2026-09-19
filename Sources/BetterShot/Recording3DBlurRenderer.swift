// SPDX-License-Identifier: AGPL-3.0-only
// Adapts Cap 3D rendering, Copyright (c) 2023-present Cap Software, Inc.
// Swift/Metal adaptation Copyright (c) 2026 Kartik Labhshetwar.
// See Resources/Licenses/NOTICE.md for upstream source and full license.

import CoreImage
import QuartzCore
import simd

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

    /// Inverse mapping keeps the camera fixed even when part of a steeply tilted plane
    /// crosses its horizon. Source and destination coordinates here use Core Image's y-up axis.
    static func warp(_ image: CIImage, projection m: CATransform3D, canvas: CGRect) throws -> CIImage {
        let forward = simd_double3x3(columns: (SIMD3(m.m11, m.m12, m.m14),
            SIMD3(m.m21, m.m22, m.m24), SIMD3(m.m41, m.m42, m.m44)))
        guard forward.determinant.isFinite, abs(forward.determinant) > 1e-12 else {
            return CIImage.empty().cropped(to: canvas)
        }
        let inverse = forward.inverse.transpose
        func row(_ i: Int) -> CIVector {
            let r = inverse[i]; return CIVector(x: r.x, y: r.y, z: r.z)
        }
        guard let kernel = kernels.first(where: { $0.name == "bettershotPerspective" }),
              let result = kernel.apply(extent: canvas, roiCallback: { _, _ in canvas },
                arguments: [image.composited(over: CIImage(color: .clear).cropped(to: canvas)).clampedToExtent(), row(0), row(1), row(2), CIVector(x: canvas.width, y: canvas.height)]) else {
            throw Failure.unavailable
        }
        return result
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

    [[stitchable]] float4 bettershotPerspective(coreimage::sampler image, float3 row0, float3 row1, float3 row2, float2 size, destination dest) {
        float3 p = float3(dest.coord().x, size.y - dest.coord().y, 1.0);
        float3 q = float3(dot(row0, p), dot(row1, p), dot(row2, p));
        if (q.z <= 1e-6) return float4(0);
        float2 source = q.xy / q.z;
        float2 uv = source / size;
        float2 dx = (float2(row0.x, row1.x) * q.z - q.xy * row2.x) / (q.z * q.z) / size;
        float2 dy = (float2(row0.y, row1.y) * q.z - q.xy * row2.y) / (q.z * q.z) / size;
        float2 width = max(abs(dx) + abs(dy), float2(1e-6));
        float2 edge = smoothstep(float2(0), width, uv) * smoothstep(float2(0), width, 1.0 - uv);
        float2 sample = clamp(source, float2(0), size);
        return image.sample(image.transform(float2(sample.x, size.y - sample.y))) * edge.x * edge.y;
    }

    [[stitchable]] float4 bettershotFocusBlur(coreimage::sampler image, float4 frame, float4 focus, float4 style, destination dest) {
        float2 p = dest.coord();
        float radius = focusRadius(p, frame, focus, style);
        if (radius < 0.5) return image.sample(image.transform(p));
        int extent = int(min(radius, min(frame.y * (40.0 / 1080.0), 160.0)));
        float sigma = radius * 0.5;
        float2 axis = style.z < 0.5 ? float2(1, 0) : float2(0, 1);
        float4 sum = image.sample(image.transform(p));
        float total = 1;
        // Pair adjacent Gaussian taps with linear filtering. The normalized weights
        // are unchanged; texture reads are halved even at the reference's 8K cap.
        for (int i = 1; i <= extent; i += 2) {
            float a = exp(-float(i * i) / (2.0 * sigma * sigma));
            float b = i + 1 <= extent ? exp(-float((i + 1) * (i + 1)) / (2.0 * sigma * sigma)) : 0.0;
            float weight = a + b;
            float offset = float(i) + b / weight;
            sum += (image.sample(image.transform(p + axis * offset))
                  + image.sample(image.transform(p - axis * offset))) * weight;
            total += 2.0 * weight;
        }
        return sum / total;
    }

    [[stitchable]] float4 bettershotBokeh(coreimage::sampler image, float4 frame, float4 focus, float4 style, destination dest) {
        float2 p = dest.coord();
        float radius = focusRadius(p, frame, focus, style);
        float4 sum = image.sample(image.transform(p));
        if (radius < 0.5) return sum;
        float total = 1;
        for (int ring = 1; ring <= 3; ++ring) {
            int count = ring * 5;
            float ringWeight = mix(1.0, float(ring) / 3.0, 0.3);
            for (int j = 0; j < count; ++j) {
                float angle = 6.28318530718 * float(j) / float(count);
                float r = radius * float(ring) / 3.0;
                float4 color = image.sample(image.transform(p + float2(cos(angle), sin(angle)) * r));
                float light = dot(color.rgb, float3(0.299, 0.587, 0.114));
                float weight = ringWeight * (1.0 + 1.5 * smoothstep(0.7, 1.0, light));
                sum += color * weight;
                total += weight;
            }
        }
        return sum / total;
    }
    """#
}
