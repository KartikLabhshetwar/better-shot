import AppKit

@main
enum RedactionCacheKeyCheck {
    static let crop = CGRect(x: 10, y: 20, width: 300, height: 200)

    static func key(
        prefix: String = "ns",
        token: UUID,
        tool: AnnotationTool = .blur,
        density: CGFloat = 0.5,
        scale: CGFloat = 1.0,
        cropRect: CGRect = crop
    ) -> String {
        RedactionImageProcessor.previewCacheKey(
            prefix: prefix,
            sourceToken: token,
            tool: tool,
            density: density,
            scale: scale,
            cropRect: cropRect
        ) as String
    }

    static func main() {
        let token = UUID()

        precondition(key(token: token) == key(token: token), "identical inputs must hit the cache, or every preview re-renders")

        let replacedSource = UUID()
        precondition(
            key(token: token) != key(token: replacedSource),
            "a new source image with the same size, tool, density and crop must not reuse the old redaction bitmap"
        )

        precondition(key(token: token, tool: .blur) != key(token: token, tool: .pixelate), "blur and pixelate must not share a cached bitmap")
        precondition(key(token: token, density: 0.5) != key(token: token, density: 0.9), "changing density must re-render")
        precondition(key(token: token, scale: 1.0) != key(token: token, scale: 2.0), "a Retina preview must not reuse the 1x bitmap")
        precondition(key(prefix: "ns", token: token) != key(prefix: "cg", token: token), "the NSImage and CGImage paths scale differently and must not share entries")

        let moved = CGRect(x: 11, y: 20, width: 300, height: 200)
        let resized = CGRect(x: 10, y: 20, width: 301, height: 200)
        precondition(key(token: token, cropRect: crop) != key(token: token, cropRect: moved), "dragging the redaction one pixel must re-render")
        precondition(key(token: token, cropRect: crop) != key(token: token, cropRect: resized), "resizing the redaction one pixel must re-render")

        let ambiguousA = CGRect(x: 1, y: 23, width: 300, height: 200)
        let ambiguousB = CGRect(x: 12, y: 3, width: 300, height: 200)
        precondition(key(token: token, cropRect: ambiguousA) != key(token: token, cropRect: ambiguousB), "fields must stay separated, or neighbouring crops collide")

        precondition(
            key(token: token, density: 0.5) == key(token: token, density: 0.5001),
            "density is quantized on purpose: a sub-percent slider jitter should reuse the bitmap"
        )

        print("RedactionCacheKeyCheck: previews are keyed by source identity, not by image size")
    }
}
