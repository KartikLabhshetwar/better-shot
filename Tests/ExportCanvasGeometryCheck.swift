import CoreGraphics
import Foundation

@main
enum ExportCanvasGeometryCheck {
    static func expectRenderable(_ canvas: ExportCanvasGeometry.Canvas, _ label: String) {
        precondition(canvas.width == canvas.width.rounded(), "\(label): fractional width \(canvas.width)")
        precondition(canvas.height == canvas.height.rounded(), "\(label): fractional height \(canvas.height)")
        precondition(canvas.width.truncatingRemainder(dividingBy: 2) == 0, "\(label): odd width \(canvas.width)")
        precondition(canvas.height.truncatingRemainder(dividingBy: 2) == 0, "\(label): odd height \(canvas.height)")
        precondition(canvas.width >= 2 && canvas.height >= 2, "\(label): degenerate \(canvas)")
        precondition(canvas.padding >= 0 && canvas.padding == canvas.padding.rounded(), "\(label): bad padding \(canvas.padding)")
        precondition(canvas.videoWidth <= canvas.width, "\(label): video wider than canvas \(canvas)")
        precondition(canvas.videoHeight <= canvas.height, "\(label): video taller than canvas \(canvas)")
        precondition(canvas.offsetX >= canvas.padding, "\(label): offsetX eats the padding \(canvas)")
        precondition(canvas.offsetY >= canvas.padding, "\(label): offsetY eats the padding \(canvas)")
        precondition(
            canvas.offsetX == ((canvas.width - canvas.videoWidth) / 2).rounded(),
            "\(label): video not centred horizontally \(canvas)"
        )
        precondition(
            canvas.offsetY == ((canvas.height - canvas.videoHeight) / 2).rounded(),
            "\(label): video not centred vertically \(canvas)"
        )
    }

    static func expectEncodable(_ canvas: ExportCanvasGeometry.Canvas, _ label: String) {
        expectRenderable(canvas, label)
        precondition(canvas.width == canvas.videoWidth + canvas.padding * 2, "\(label): width does not frame the video")
        precondition(canvas.height == canvas.videoHeight + canvas.padding * 2, "\(label): height does not frame the video")
    }

    static func expectRatio(_ canvas: ExportCanvasGeometry.Canvas, _ ratio: CGFloat, _ label: String) {
        expectRenderable(canvas, label)
        let achieved = canvas.width / canvas.height
        let tolerance = ratio * 4 / min(canvas.width, canvas.height)
        precondition(
            abs(achieved - ratio) <= tolerance,
            "\(label): wanted \(ratio), got \(achieved) from \(canvas)"
        )
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

        let square = ExportCanvasGeometry.canvas(videoWidth: 1920, videoHeight: 1080, paddingFraction: defaultPadding, aspectRatio: 1)
        expectRatio(square, 1, "1080p into square")
        precondition(square.width == 2092 && square.height == 2092, "unexpected square canvas \(square)")
        precondition(square.padding == 86, "square canvas should keep its padding, got \(square.padding)")

        let widened = ExportCanvasGeometry.canvas(videoWidth: 1080, videoHeight: 1920, paddingFraction: 0, aspectRatio: 16.0 / 9)
        expectRatio(widened, 16.0 / 9, "portrait into 16:9")
        precondition(widened.height == 1920, "16:9 fit should grow width only, got \(widened)")

        for ratio: CGFloat in [1, 4.0 / 3, 3.0 / 4, 16.0 / 9, 9.0 / 16, 2.39, 0.5] {
            for width in stride(from: 320.0, through: 3840.0, by: 137.0) {
                for height in stride(from: 240.0, through: 2160.0, by: 331.0) {
                    for fraction in [0.0, 0.08, 0.25, 0.5] {
                        expectRatio(
                            ExportCanvasGeometry.canvas(
                                videoWidth: CGFloat(width),
                                videoHeight: CGFloat(height),
                                paddingFraction: CGFloat(fraction),
                                aspectRatio: ratio
                            ),
                            ratio,
                            "ratio sweep \(width)x\(height)@\(fraction) -> \(ratio)"
                        )
                    }
                }
            }
        }

        for ignored: CGFloat in [0, -1, .nan, .infinity] {
            let canvas = ExportCanvasGeometry.canvas(
                videoWidth: 1920,
                videoHeight: 1080,
                paddingFraction: defaultPadding,
                aspectRatio: ignored
            )
            expectEncodable(canvas, "invalid ratio \(ignored) falls back to padded frame")
            precondition(canvas == hd, "invalid ratio \(ignored) changed the canvas: \(canvas)")
        }

        for degenerate: CGFloat in [0, 1, 1.4, -50, .nan, .infinity, -.infinity] {
            expectRatio(
                ExportCanvasGeometry.canvas(
                    videoWidth: degenerate,
                    videoHeight: degenerate,
                    paddingFraction: defaultPadding,
                    aspectRatio: 16.0 / 9
                ),
                16.0 / 9,
                "degenerate \(degenerate) at 16:9"
            )
        }

        print("ExportCanvasGeometryCheck: all assertions passed")
    }
}
