import Foundation

@main
enum DefaultLookMappingCheck {
    static func main() {
        var config = BeautifierConfig()
        config.padding = 0.18
        config.cornerRadius = 0.18
        config.shadowStrength = 0.5
        config.style = .solid(SolidColor(id: "cobalt", name: "Cobalt", red: 0.16, green: 0.50, blue: 0.88))
        config.alignment = .bottomLeading
        config.aspectRatio = .sixteenNine

        let settings = config.annotationBackgroundSettings
        assert(settings.padding == 0.18, "padding must carry over")
        assert(settings.cornerRadius == 0.18, "corner radius must carry over")
        assert(settings.shadow == 0.5, "shadow must map from shadowStrength")
        assert(settings.alignment == .bottomLeading, "alignment must carry over")
        assert(settings.aspectRatio == .sixteenNine, "aspect ratio must carry over")
        guard case .solid(let color) = settings.style else { fatalError("expected solid style") }
        assert(color.id == "cobalt" && abs(color.red - 0.16) < 0.0001, "solid color must carry over")

        let preset = GradientPreset.presets[0]
        var gradientConfig = BeautifierConfig()
        gradientConfig.style = .gradient(preset)
        guard case .gradient(let gradient) = gradientConfig.annotationBackgroundSettings.style else {
            fatalError("expected gradient style")
        }
        assert(gradient.id == preset.id, "gradient id must carry over")
        assert(gradient.colors.count == preset.stops.count, "every gradient stop must map")
        assert(gradient.startPoint == preset.startPoint.unitPoint, "gradient start point must carry over")
        assert(gradient.endPoint == preset.endPoint.unitPoint, "gradient end point must carry over")

        var wallpaperConfig = BeautifierConfig()
        wallpaperConfig.style = .wallpaper(WallpaperSource(path: "/tmp/wall.jpg"))
        let wallpaperSettings = wallpaperConfig.annotationBackgroundSettings
        guard case .customWallpaper(let wallpaper) = wallpaperSettings.style else {
            fatalError("expected custom wallpaper style")
        }
        assert(wallpaper.url.path == "/tmp/wall.jpg", "wallpaper path must carry over")
        assert(wallpaperSettings.customWallpaper == wallpaper, "customWallpaper must mirror the style")

        var bundledConfig = BeautifierConfig()
        bundledConfig.style = .bundledImage("not-a-real-asset")
        assert(bundledConfig.annotationBackgroundSettings.style == .none, "missing bundled asset must fall back to none")

        var portraitConfig = BeautifierConfig()
        portraitConfig.aspectRatio = .nineSixteen
        assert(portraitConfig.annotationBackgroundSettings.aspectRatio == .auto, "9:16 has no editor twin, must fall back to auto")

        assert(BeautifierConfig().annotationBackgroundSettings.style == .none, "default config must map to no background")

        print("Default look mapping carries style, padding, corner radius, shadow, alignment, and aspect ratio")
    }
}
