import CoreGraphics
import Foundation

@main
enum ExportCanvasGeometryCheck {
    static func expectEncodable(_ canvas: ExportCanvasGeometry.Canvas, _ label: String) {
        precondition(canvas.width == canvas.width.rounded(), "\(label): fractional width \(canvas.width)")
        precondition(canvas.height == canvas.height.rounded(), "\(label): fractional height \(canvas.height)")
        precondition(canvas.width.truncatingRemainder(dividingBy: 2) == 0, "\(label): odd width \(canvas.width)")
        precondition(canvas.height.truncatingRemainder(dividingBy: 2) == 0, "\(label): odd height \(canvas.height)")
        precondition(canvas.width >= 2 && canvas.height >= 2, "\(label): degenerate \(canvas)")
        precondition(canvas.padding >= 0 && canvas.padding == canvas.padding.rounded(), "\(label): bad padding \(canvas.padding)")
        precondition(canvas.width == canvas.videoWidth + canvas.padding * 2, "\(label): width does not frame the video")
        precondition(canvas.height == canvas.videoHeight + canvas.padding * 2, "\(label): height does not frame the video")
    }

    static func main() {
        let defaultPadding: CGFloat = 0.08

        let hd = ExportCanvasGeometry.canvas(videoWidth: 1920, videoHeight: 1080, paddingFraction: defaultPadding)
        expectEncodable(hd, "1080p default padding")
        precondition(hd.padding == 86, "expected rounded padding, got \(hd.padding)")
        precondition(hd.width == 2092 && hd.height == 1252, "unexpected 1080p canvas \(hd)")

        expectEncodable(
            ExportCanvasGeometry.canvas(videoWidth: 3024, videoHeight: 1964, paddingFraction: defaultPadding),
            "retina default padding"
        )

        for width in stride(from: 320.0, through: 3840.0, by: 7.0) {
            for height in stride(from: 240.0, through: 2160.0, by: 331.0) {
                for fraction in [0.0, 0.011, 0.06, 0.08, 0.137, 0.25, 0.5] {
                    let canvas = ExportCanvasGeometry.canvas(
                        videoWidth: CGFloat(width),
                        videoHeight: CGFloat(height),
                        paddingFraction: CGFloat(fraction)
                    )
                    expectEncodable(canvas, "sweep \(width)x\(height)@\(fraction)")
                }
            }
        }

        expectEncodable(
            ExportCanvasGeometry.canvas(videoWidth: 1920 * 0.4237, videoHeight: 1080 * 0.6111, paddingFraction: defaultPadding),
            "fractional crop"
        )

        let zeroPad = ExportCanvasGeometry.canvas(videoWidth: 1921, videoHeight: 1081, paddingFraction: 0)
        expectEncodable(zeroPad, "odd source, no padding")
        precondition(zeroPad.width == 1920 && zeroPad.height == 1080, "odd source not snapped down: \(zeroPad)")

        for degenerate: CGFloat in [0, 1, 1.4, -50, .nan, .infinity, -.infinity] {
            expectEncodable(
                ExportCanvasGeometry.canvas(videoWidth: degenerate, videoHeight: degenerate, paddingFraction: defaultPadding),
                "degenerate \(degenerate)"
            )
        }

        let nanPadding = ExportCanvasGeometry.canvas(videoWidth: 1920, videoHeight: 1080, paddingFraction: .nan)
        expectEncodable(nanPadding, "nan padding")
        precondition(nanPadding.padding == 0, "nan padding should collapse to zero")

        let negativePadding = ExportCanvasGeometry.canvas(videoWidth: 1920, videoHeight: 1080, paddingFraction: -0.3)
        expectEncodable(negativePadding, "negative padding")
        precondition(negativePadding.padding == 0, "negative padding should clamp to zero")

        print("ExportCanvasGeometryCheck: all assertions passed")
    }
}
