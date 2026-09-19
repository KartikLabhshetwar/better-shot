import Foundation
import QuartzCore

@main struct Recording3DCheck {
    static func main() throws {
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
                    let pose = sample.pose(at: time), matrix = pose.projection(in: canvas)
                    for point in [CGPoint.zero, CGPoint(x: canvas.width, y: 0), CGPoint(x: 0, y: canvas.height), CGPoint(x: canvas.width, y: canvas.height)] {
                        precondition(matrix.m14 * point.x + matrix.m24 * point.y + matrix.m44 > 0)
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
        print("3D projection, scaling, near-plane bounds, presets, timing, transitions, sanitization, and Codable checks passed")
    }
}
