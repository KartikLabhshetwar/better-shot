import CoreGraphics
import CoreImage
import Foundation

enum ColorPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case cinematic
    case noir
    case vintage
    case frost
    case golden
    case midnight
    case vivid
    case dreamy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .cinematic: return "Cinematic"
        case .noir: return "Noir"
        case .vintage: return "Vintage"
        case .frost: return "Frost"
        case .golden: return "Golden"
        case .midnight: return "Midnight"
        case .vivid: return "Vivid"
        case .dreamy: return "Dreamy"
        }
    }

    var values: ColorCorrection {
        var values = ColorCorrection()
        switch self {
        case .none:
            break
        case .cinematic:
            values.contrast = 0.12
            values.saturation = 0.06
            values.temperature = 0.04
            values.splitTone = 0.45
            values.vignette = 0.18
            values.grain = 0.12
        case .noir:
            values.exposure = 0.04
            values.contrast = 0.3
            values.saturation = -1
            values.fade = 0.06
            values.vignette = 0.32
            values.grain = 0.35
        case .vintage:
            values.contrast = -0.06
            values.saturation = -0.18
            values.temperature = 0.22
            values.tint = 0.08
            values.fade = 0.28
            values.vignette = 0.14
            values.grain = 0.28
        case .frost:
            values.contrast = 0.08
            values.saturation = -0.08
            values.temperature = -0.3
            values.tint = -0.04
            values.fade = 0.06
        case .golden:
            values.exposure = 0.06
            values.contrast = 0.06
            values.saturation = 0.12
            values.temperature = 0.38
            values.fade = 0.04
            values.vignette = 0.1
        case .midnight:
            values.exposure = -0.08
            values.contrast = 0.16
            values.saturation = -0.22
            values.temperature = -0.1
            values.splitTone = 0.3
            values.vignette = 0.28
            values.grain = 0.18
        case .vivid:
            values.exposure = 0.02
            values.contrast = 0.14
            values.saturation = 0.32
        case .dreamy:
            values.exposure = 0.08
            values.contrast = -0.14
            values.saturation = -0.04
            values.temperature = 0.06
            values.tint = 0.05
            values.fade = 0.3
            values.grain = 0.1
        }
        return values
    }
}

struct ColorCorrection: Codable, Equatable, Sendable {
    var intensity: CGFloat = 1
    var exposure: CGFloat = 0
    var contrast: CGFloat = 0
    var saturation: CGFloat = 0
    var temperature: CGFloat = 0
    var tint: CGFloat = 0
    var fade: CGFloat = 0
    var splitTone: CGFloat = 0
    var vignette: CGFloat = 0
    var grain: CGFloat = 0

    static let identity = ColorCorrection()

    /// Parameters after intensity scaling, matching Cap's compositor.
    var resolved: ResolvedColorCorrection {
        let scale = min(max(intensity, 0), 1)
        return ResolvedColorCorrection(
            exposureStops: clampSigned(exposure) * 1.5 * scale,
            contrast: clampSigned(contrast) * scale,
            saturation: clampSigned(saturation) * scale,
            temperature: clampSigned(temperature) * scale,
            tint: clampSigned(tint) * scale,
            fade: clampUnit(fade) * scale,
            splitTone: clampSigned(splitTone) * scale,
            vignette: clampUnit(vignette) * scale,
            grain: clampUnit(grain) * scale
        )
    }

    var isIdentity: Bool { resolved.isIdentity }

    /// The named preset these values came from, or nil once a slider moved them off it.
    var preset: ColorPreset? {
        ColorPreset.allCases.first { $0.values.withIntensity(intensity) == self }
    }

    func withIntensity(_ intensity: CGFloat) -> ColorCorrection {
        var copy = self
        copy.intensity = intensity
        return copy
    }

    mutating func apply(_ preset: ColorPreset) {
        self = preset.values.withIntensity(intensity)
    }

    private func clampSigned(_ value: CGFloat) -> CGFloat { min(max(value, -1), 1) }
    private func clampUnit(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intensity = try container.decodeIfPresent(CGFloat.self, forKey: .intensity) ?? 1
        exposure = try container.decodeIfPresent(CGFloat.self, forKey: .exposure) ?? 0
        contrast = try container.decodeIfPresent(CGFloat.self, forKey: .contrast) ?? 0
        saturation = try container.decodeIfPresent(CGFloat.self, forKey: .saturation) ?? 0
        temperature = try container.decodeIfPresent(CGFloat.self, forKey: .temperature) ?? 0
        tint = try container.decodeIfPresent(CGFloat.self, forKey: .tint) ?? 0
        fade = try container.decodeIfPresent(CGFloat.self, forKey: .fade) ?? 0
        splitTone = try container.decodeIfPresent(CGFloat.self, forKey: .splitTone) ?? 0
        vignette = try container.decodeIfPresent(CGFloat.self, forKey: .vignette) ?? 0
        grain = try container.decodeIfPresent(CGFloat.self, forKey: .grain) ?? 0
    }
}

struct ResolvedColorCorrection: Equatable, Sendable {
    let exposureStops: CGFloat
    let contrast: CGFloat
    let saturation: CGFloat
    let temperature: CGFloat
    let tint: CGFloat
    let fade: CGFloat
    let splitTone: CGFloat
    let vignette: CGFloat
    let grain: CGFloat

    var isIdentity: Bool {
        exposureStops == 0 && contrast == 0 && saturation == 0 && temperature == 0
            && tint == 0 && fade == 0 && splitTone == 0 && vignette == 0 && grain == 0
    }
}

nonisolated enum ColorGrade {
    private static let kernelSource = """
    float bsHash(vec2 p) {
        return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
    }

    kernel vec4 bsGrade(
        sampler src,
        float exposureStops, float contrast, float saturation,
        float temperature, float tint, float fade,
        float splitTone, float vignette, float grain,
        vec4 bounds
    ) {
        vec4 color = sample(src, samplerCoord(src));
        vec3 rgb = color.rgb * exp2(exposureStops);

        rgb = rgb * vec3(
            1.0 + 0.10 * temperature + 0.04 * tint,
            1.0 - 0.07 * tint,
            1.0 - 0.10 * temperature + 0.04 * tint
        );

        rgb = (rgb - vec3(0.5)) * (1.0 + contrast) + vec3(0.5);

        float luma = dot(clamp(rgb, vec3(0.0), vec3(1.0)), vec3(0.2126, 0.7152, 0.0722));
        rgb = mix(vec3(luma), rgb, 1.0 + saturation);

        float shadowWeight = 1.0 - smoothstep(0.2, 0.65, luma);
        float highlightWeight = smoothstep(0.35, 0.8, luma);
        rgb = rgb + splitTone * (
            shadowWeight * vec3(-0.06, 0.02, 0.08) +
            highlightWeight * vec3(0.08, 0.02, -0.06)
        );

        rgb = rgb * (1.0 - 0.18 * fade) + vec3(0.09 * fade);

        vec2 unit = (destCoord() - bounds.xy) / max(bounds.zw, vec2(1.0));

        if (vignette > 0.0) {
            float radius = length((unit - vec2(0.5)) * 2.0);
            rgb = rgb * (1.0 - vignette * 0.65 * smoothstep(0.5, 1.5, radius));
        }

        if (grain > 0.0) {
            float gradedLuma = dot(clamp(rgb, vec3(0.0), vec3(1.0)), vec3(0.2126, 0.7152, 0.0722));
            float response = 0.25 + 0.75 * (1.0 - abs(2.0 * gradedLuma - 1.0));
            float noise = bsHash(destCoord());
            rgb = rgb + vec3((noise - 0.5) * grain * 0.35 * response);
        }

        return vec4(clamp(rgb, vec3(0.0), vec3(1.0)), color.a);
    }
    """

    // ponytail: CIKL is the only runtime-compiled kernel path without a -fcikernel
    // Metal build phase; project.yml defines CI_SILENCE_GL_DEPRECATION for it.
    private static let kernel = CIKernel(source: kernelSource)
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func apply(_ correction: ColorCorrection, to image: CIImage) -> CIImage {
        let values = correction.resolved
        guard !values.isIdentity, let kernel else { return image }
        let bounds = image.extent.isInfinite ? CGRect(x: 0, y: 0, width: 1, height: 1) : image.extent
        let output = kernel.apply(
            extent: bounds,
            roiCallback: { _, rect in rect },
            arguments: [
                image,
                Float(values.exposureStops), Float(values.contrast), Float(values.saturation),
                Float(values.temperature), Float(values.tint), Float(values.fade),
                Float(values.splitTone), Float(values.vignette), Float(values.grain),
                CIVector(cgRect: bounds)
            ]
        )
        return output ?? image
    }

    static func apply(_ correction: ColorCorrection, to image: CGImage) -> CGImage {
        guard !correction.isIdentity else { return image }
        let input = CIImage(cgImage: image)
        let graded = apply(correction, to: input)
        return context.createCGImage(graded, from: input.extent) ?? image
    }
}
