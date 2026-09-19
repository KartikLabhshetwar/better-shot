import Foundation
import QuartzCore

@main struct Recording3DCheck {
    struct Reference: Decodable {
        struct Preset: Decodable { let name: String; let start, end: Recording3DCamera; let blur: Recording3DBlur }
        struct Sample: Decodable {
            let camera: Recording3DCamera
            let aspect, zoom, entry, exit, time, activity: Double
            let target: CGPoint
            let inverse: [Double]
        }
        let presets: [Preset]
        let cases: [Sample]
    }
    static func checkCapReference() throws {
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/Cap3DReference.json")))
        precondition(reference.presets.count == Recording3DPreset.allCases.count)
        for expected in reference.presets {
            let preset = Recording3DPreset.allCases.first { $0.rawValue == expected.name }!
            precondition(preset.poses.0.camera == expected.start && preset.poses.1.camera == expected.end, "Cap camera preset changed: \(expected.name)")
            precondition(preset.blur == expected.blur, "Cap blur preset changed: \(expected.name)")
        }
        for sample in reference.cases {
            let size = CGSize(width: 360 * sample.aspect, height: 360)
            let shot = Recording3DShot(start: 0, end: 4, startPose: .init(camera: sample.camera),
                endPose: .init(camera: sample.camera), transitionIn: sample.entry, transitionOut: sample.exit)
            precondition(abs(shot.activity(at: sample.time) - sample.activity) < 0.0001)
            let pose = shot.pose(at: sample.time)
            let m = pose.projection(in: size, zoomAmount: sample.zoom, zoomTarget: sample.target)
            let rows = sample.inverse
            let hx = min(sample.aspect, 1.0), hy = min(1 / sample.aspect, 1.0)
            for x in [-0.8, -0.25, 0, 0.4, 0.9] {
                for y in [-0.8, -0.25, 0, 0.4, 0.9] {
                    let w = rows[6] * x + rows[7] * y + rows[8]
                    guard abs(w) > 0.01 else { continue }
                    let px = ((rows[0] * x + rows[1] * y + rows[2]) / w / hx + 1) * size.width / 2
                    let py = (1 - (rows[3] * x + rows[4] * y + rows[5]) / w / hy) * size.height / 2
                    let depth = m.m14 * px + m.m24 * py + m.m44
                    let actual = CGPoint(x: (m.m11 * px + m.m21 * py + m.m41) / depth,
                                         y: (m.m12 * px + m.m22 * py + m.m42) / depth)
                    let expected = CGPoint(x: (x + 1) * size.width / 2, y: (1 - y) * size.height / 2)
                    precondition(hypot(actual.x - expected.x, actual.y - expected.y) < 0.03,
                                 "Projection disagrees with Cap Rust renderer: \(sample.camera), \(actual), \(expected)")
                }
            }
        }
        print("PASS 13 upstream presets and \(reference.cases.count) actual Cap Rust camera/zoom/transition reference cases")
    }

    static func main() throws {
        try checkCapReference()
        let empty = Recording3DTimeline(shots: [], duration: 10)
        precondition(empty.insertionRange(at: 2, duration: 10) == 2...5)
        precondition(empty.insertionRange(at: 9.8, duration: 10) == 7...10)
        precondition(empty.insertionRange(at: .nan, duration: 10) == nil)
        precondition(empty.insertionRange(at: -1, duration: 10) == nil)
        precondition(empty.insertionRange(at: 11, duration: 10) == nil)
        precondition(empty.insertionRange(at: 0, duration: 0.1) == nil)
        var occupied = Recording3DShot(start: 2, end: 5)
        occupied.isEnabled = false
        let gapped = Recording3DTimeline(shots: [occupied, .init(start: 5.1, end: 8)], duration: 10)
        precondition(gapped.insertionRange(at: 3, duration: 10) == nil, "Disabled shots still occupy the lane")
        precondition(gapped.insertionRange(at: 5.05, duration: 10) == nil, "No misleading ghost in a gap below minimum duration")
        precondition(gapped.insertionRange(at: 1, duration: 10) == 0...2)
        precondition(gapped.insertionRange(at: 8, duration: 10) == 8...10)
        print("PASS 3D insertion ghost placement, occupied ranges, boundaries, short clips, and invalid times")
        let size = CGSize(width: 1920, height: 1080)
        for point in [CGPoint.zero, CGPoint(x: 1920, y: 1080), CGPoint(x: 230, y: 790)] {
            let projected = Recording3DPose.identity.project(point, in: size)
            precondition(hypot(projected.x - point.x, projected.y - point.y) < 1e-8)
        }
        // An independent pinhole calculation catches matrix orientation and perspective mistakes.
        let yaw = Recording3DPose(tiltY: 30, scale: 0.8)
        let d = 1920.0 / (2 * tan(Double.pi / 8))
        let expectedX = 960 + 0.8 * cos(Double.pi / 6) * 960 / (1 + sin(Double.pi / 6) * 960 / d)
        precondition(abs(yaw.project(CGPoint(x: 1920, y: 540), in: size).x - expectedX) < 1e-8)
        for width in [1080.0, 1920, 3840] {
            for height in [1080.0, 1920, 2160] {
                for x in [-65.0, 0, 65] {
                    for y in [-65.0, 0, 65] {
                        let p = Recording3DPose(tiltX: x, tiltY: y, roll: 45, scale: 2.5, perspective: 70)
                        let canvas = CGSize(width: width, height: height)
                        for q in [CGPoint.zero, CGPoint(x: width, y: 0), CGPoint(x: 0, y: height), CGPoint(x: width, y: height)] {
                            let m = p.projection(in: canvas)
                            precondition(m.m14 * q.x + m.m24 * q.y + m.m44 > 0.01, "No corner can cross the camera")
                            let projected = p.project(q, in: canvas)
                            let doubled = p.project(CGPoint(x: q.x * 2, y: q.y * 2), in: CGSize(width: width * 2, height: height * 2))
                            precondition(projected.x.isFinite && projected.y.isFinite)
                            precondition(hypot(doubled.x / 2 - projected.x, doubled.y / 2 - projected.y) < 1e-8,
                                         "Preview/export projection must be resolution independent")
                        }
                    }
                }
            }
        }
        var shot = Recording3DShot(start: 1, end: 4)
        shot.apply(.glide)
        precondition(shot.transition == 0 && shot.easing == .linear)
        shot.transition = 0.25
        precondition(shot.pose(at: 0) == .identity && shot.pose(at: 1) == .identity && shot.pose(at: 4) == .identity)
        let middle = shot.pose(at: 2.5)
        precondition(abs(middle.camera!.panX - (0.673 + 0.054) / 2) < 1e-8)
        let nearEnd = shot.pose(at: 4 - 1e-7)
        precondition(abs(nearEnd.scale - 1) < 1e-8)
        let flatCamera = Recording3DPose(camera: .init(distance: 2))
        let right = flatCamera.project(CGPoint(x: 1920, y: 540), in: size)
        precondition(abs(right.x - (960 + 540 / tan(Double.pi / 8) / 2)) < 1e-8,
                     "Camera distance and vertical FOV must determine apparent size")
        let originalPose = Recording3DPose(tiltX: 12, tiltY: -18, roll: -4, scale: 0.85)
        let legacyJSON = "{\"tiltX\":12,\"tiltY\":-18,\"roll\":-4,\"scale\":0.85,\"panX\":0,\"panY\":0,\"perspective\":45}"
        let legacyPose = try JSONDecoder().decode(Recording3DPose.self, from: Data(legacyJSON.utf8))
        precondition(legacyPose == originalPose)
        let data = try JSONEncoder().encode(shot)
        let restored = try JSONDecoder().decode(Recording3DShot.self, from: data)
        precondition(restored == shot)
        var disabled = shot; disabled.isEnabled = false
        precondition(Recording3DTimeline(shots: [disabled], duration: 5).pose(at: 2) == .identity)
        var invalid = shot; invalid.start = .nan
        var second = shot; second.id = UUID(); second.start = 3; second.end = 10
        let timeline = Recording3DTimeline(shots: [invalid, second, shot, shot], duration: 6)
        precondition(timeline.shots.count == 2)
        precondition(timeline.shots[1].start == 4 && timeline.shots[1].end == 6)
        precondition(timeline.pose(at: .nan) == .identity && timeline.pose(at: 6) == .identity)
        for preset in Recording3DPreset.allCases {
            var sample = shot; sample.apply(preset)
            precondition(sample.title == preset.rawValue)
            precondition(sample.startPose == sample.startPose.sanitized)
            precondition(sample.endPose == sample.endPose.sanitized)
            precondition(sample.startPose != sample.endPose, "Every reference look includes motion")
            for canvas in [size, CGSize(width: 1080, height: 1920)] {
                for time in [1.0, 1.7, 3.9] {
                    let pose = sample.pose(at: time)
                    for point in [CGPoint.zero, CGPoint(x: canvas.width, y: 0), CGPoint(x: 0, y: canvas.height), CGPoint(x: canvas.width, y: canvas.height)] {
                        let p = pose.project(point, in: canvas)
                        let q = pose.project(CGPoint(x: point.x * 2, y: point.y * 2), in: CGSize(width: canvas.width * 2, height: canvas.height * 2))
                        precondition(p.x.isFinite && p.y.isFinite && hypot(p.x - q.x / 2, p.y - q.y / 2) < 1e-8)
                    }
                }
            }
        }
        let scene = Recording3DTimeline.scene(Recording3DScene.showcase.presets, in: 2...8)
        precondition(scene.count == 3 && scene[0].start == 2 && scene[2].end == 8)
        precondition(scene[0].end == scene[1].start && scene[1].end == scene[2].start)
        precondition(Recording3DTimeline.scene([.glide, .center], in: 0...0.1).isEmpty)
        let showcase = Recording3DTimeline.scene(Recording3DScene.showcase.presets, in: 0...10,
                                                weights: Recording3DScene.showcase.weights, showcaseFinish: true)
        precondition(showcase.map { $0.end } == [2.7, 5.2, 10])
        precondition(showcase[2].endPose.camera?.distance == 1.6)
        precondition(Recording3DTimeline.scene([.center], in: 0...1, weights: [.nan]).isEmpty)
        let badCamera = Recording3DCamera(tiltX: .infinity, distance: .nan, panX: 100).sanitized
        precondition(badCamera.tiltX == 0 && badCamera.distance == 2 && badCamera.panX == 3)
        let badPose = Recording3DPose(tiltX: .infinity, scale: .nan, panX: 100).sanitized
        precondition(badPose.tiltX == 0 && badPose.scale == 1 && badPose.panX == 0.5)
        let linear = Recording3DTrack(property: .panX, keyframes: [
            .init(position: 0, value: -0.2, outgoing: .zero),
            .init(position: 1, value: 0.4, incoming: CGPoint(x: 1, y: 1))
        ]).normalized()
        precondition(abs(linear.value(at: 0.25)! + 0.05) < 1e-8)
        precondition(linear.value(at: -1) == -0.2 && linear.value(at: 2) == 0.4)
        let slowStart = Recording3DTrack.ease(0.25, outgoing: CGPoint(x: 0.65, y: 0), incoming: CGPoint(x: 0.35, y: 1))
        precondition(slowStart < 0.15 && slowStart > 0)
        precondition(abs(Recording3DEasing.smooth.value(at: 0.25, camera: true) - slowStart) < 1e-8)
        precondition(Recording3DEasing.smooth.value(at: 0.25) == 0.15625, "Legacy plane motion remains unchanged")
        precondition(abs(Recording3DTrack.ease(0.5, outgoing: CGPoint(x: 1, y: 0), incoming: CGPoint(x: 0, y: 1)) - 0.5) < 0.000_01)
        var invalidKeys = linear
        invalidKeys.keyframes += [.init(position: .nan, value: 1), .init(position: 2, value: .infinity)]
        precondition(invalidKeys.normalized() == linear)
        var animated = Recording3DShot(start: 1, end: 5)
        animated.apply(.center)
        animated.tracks = [linear, .init(property: .strength, keyframes: [
            .init(position: 0, value: 0, outgoing: .zero),
            .init(position: 1, value: 20, incoming: CGPoint(x: 1, y: 1))
        ])]
        precondition(abs(animated.pose(at: 2).camera!.panX + 0.05) < 1e-8)
        precondition(abs(animated.defocus(at: 2).strength - 5) < 1e-8)
        precondition(animated.defocus(at: 5) == .none)
        var faded = animated; faded.transition = 0.5; faded.isEnabled = false
        precondition(abs(faded.keyframeValue(for: .panX, at: 0) + 0.2) < 1e-8)
        precondition(abs(faded.keyframeValue(for: .strength, at: 1) - 20) < 1e-8,
                     "Keyframe authoring must retain authored endpoints even when disabled or fading")
        let animatedData = try JSONEncoder().encode(animated)
        let decodedAnimation = try JSONDecoder().decode(Recording3DShot.self, from: animatedData)
        precondition(decodedAnimation == animated)
        var reversed = animated; reversed.reverse()
        precondition(abs(reversed.pose(at: 4).camera!.panX - animated.pose(at: 2).camera!.panX) < 1e-8)
        precondition(abs(reversed.defocus(at: 4).strength - animated.defocus(at: 2).strength) < 1e-8)
        var mirrored = animated; mirrored.flip(horizontal: true)
        precondition(abs(mirrored.pose(at: 2).camera!.panX + animated.pose(at: 2).camera!.panX) < 1e-8)
        precondition(mirrored.blur?.focusX == 1 - animated.blur!.focusX)
        var held = animated; held.holdCamera()
        precondition(held.pose(at: 2) == held.startPose && held.tracks?.count == 1)
        animated.end = 9
        precondition(abs(animated.pose(at: 3).camera!.panX + 0.05) < 1e-8, "Resize preserves relative keyframe timing")
        var blurOnly = shot; blurOnly.apply(.center)
        blurOnly.tracks = [.init(property: .strength, keyframes: [.init(position: 0, value: 20)])]
        precondition(blurOnly.title == "Center", "Blur curves do not change the selected camera look")
        let boundedBlur = Recording3DBlur(mode: .tiltShift, strength: 100, focusSize: 2, angle: 900, bokeh: true).sanitized
        precondition(boundedBlur.strength == 20 && boundedBlur.focusSize == 0.6 && boundedBlur.angle == 180)
        print("3D projection, scaling, near-plane bounds, presets, timing, transitions, sanitization, and Codable checks passed")
    }
}
