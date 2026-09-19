import Foundation

nonisolated struct Recording3DBlur: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable {
        case none = "None", radial = "Radial", directional = "Directional", tiltShift = "Tilt shift"
    }
    var mode = Mode.none
    var strength: Double = 0
    var falloff: Double = 0.62
    var focusX: Double = 0.37
    var focusY: Double = 0.5
    var focusSize: Double = 0.4
    var angle: Double = 0
    var position: Double = 0.5
    var bokeh = false

    static let none = Self()
    static let showcase = Self(mode: .radial, strength: 19, bokeh: true)
    var sanitized: Self {
        var result = self
        for property in Recording3DProperty.allCases {
            guard let key = property.blurKey else { continue }
            let value = result[keyPath: key], bounds = property.bounds(blur: self)
            result[keyPath: key] = value.isFinite ? min(max(value, bounds.lowerBound), bounds.upperBound) : Self.none[keyPath: key]
        }
        return result
    }
    var isActive: Bool { mode != .none && strength > 0.001 }
}

nonisolated enum Recording3DProperty: String, Codable, CaseIterable, Identifiable, Sendable {
    case tiltX, tiltY, roll, rotateX, rotateY, distance, fieldOfView, panX, panY
    case strength, falloff, focusX, focusY, focusSize, angle, position
    var id: Self { self }
    var title: String {
        switch self {
        case .tiltX: "Camera · Tilt X"
        case .tiltY: "Camera · Tilt Y"
        case .roll: "Camera · Roll"
        case .rotateX: "Screen · Fold X"
        case .rotateY: "Screen · Fold Y"
        case .distance: "Camera · Distance"
        case .fieldOfView: "Camera · Field of view"
        case .panX: "Camera · Horizontal"
        case .panY: "Camera · Vertical"
        case .strength: "Blur · Strength"
        case .falloff: "Blur · Falloff"
        case .focusX: "Blur · Focus X"
        case .focusY: "Blur · Focus Y"
        case .focusSize: "Blur · Focus size"
        case .angle: "Blur · Angle"
        case .position: "Blur · Position"
        }
    }
    var cameraKey: WritableKeyPath<Recording3DCamera, Double>? {
        switch self {
        case .tiltX: \.tiltX
        case .tiltY: \.tiltY
        case .roll: \.roll
        case .rotateX: \.rotateX
        case .rotateY: \.rotateY
        case .distance: \.distance
        case .fieldOfView: \.fieldOfView
        case .panX: \.panX
        case .panY: \.panY
        default: nil
        }
    }
    var blurKey: WritableKeyPath<Recording3DBlur, Double>? {
        switch self {
        case .strength: \.strength
        case .falloff: \.falloff
        case .focusX: \.focusX
        case .focusY: \.focusY
        case .focusSize: \.focusSize
        case .angle: \.angle
        case .position: \.position
        default: nil
        }
    }
    func bounds(blur: Recording3DBlur = .none) -> ClosedRange<Double> {
        switch self {
        case .tiltX: -70...70
        case .tiltY: -60...60
        case .roll: -180...180
        case .rotateX: -90...90
        case .rotateY: -50...50
        case .distance: 0.5...10
        case .fieldOfView: 10...100
        case .panX, .panY: -3...3
        case .strength: 0...(blur.bokeh ? 20 : 60)
        case .angle: 0...(blur.mode == .tiltShift ? 180 : 360)
        case .focusSize: 0...(blur.mode == .tiltShift ? 0.6 : 1)
        default: 0...1
        }
    }
}

/// Positions are fractions of the shot, so moving/resizing it keeps the curve's timing intact.
nonisolated struct Recording3DKeyframe: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var position: Double
    var value: Double
    var incoming = CGPoint(x: 0.35, y: 1)
    var outgoing = CGPoint(x: 0.65, y: 0)
}

nonisolated struct Recording3DTrack: Codable, Equatable, Identifiable, Sendable {
    var property: Recording3DProperty
    var keyframes: [Recording3DKeyframe]
    var id: Recording3DProperty { property }

    func normalized() -> Self {
        var frames: [Recording3DKeyframe] = [], ids = Set<UUID>()
        let bounds = property.bounds()
        for var frame in keyframes.prefix(4096).filter({ $0.position.isFinite && $0.value.isFinite })
            .sorted(by: { $0.position < $1.position }) {
            guard ids.insert(frame.id).inserted else { continue }
            frame.position = min(max(frame.position, 0), 1)
            frame.value = min(max(frame.value, bounds.lowerBound), bounds.upperBound)
            func clamp(_ point: CGPoint, fallback: CGPoint) -> CGPoint {
                CGPoint(x: point.x.isFinite ? min(max(point.x, 0), 1) : fallback.x,
                        y: point.y.isFinite ? min(max(point.y, 0), 1) : fallback.y)
            }
            frame.incoming = clamp(frame.incoming, fallback: CGPoint(x: 0.35, y: 1))
            frame.outgoing = clamp(frame.outgoing, fallback: CGPoint(x: 0.65, y: 0))
            if let last = frames.last, abs(last.position - frame.position) < 0.000_001 { frames.removeLast() }
            frames.append(frame)
        }
        return Self(property: property, keyframes: frames)
    }

    /// Called on tracks normalized once at edit/load time. No frame-time sorting or allocations.
    func value(at position: Double) -> Double? {
        guard let first = keyframes.first, position.isFinite else { return nil }
        if position <= first.position { return first.value }
        var low = 0, high = keyframes.count
        while low < high {
            let mid = (low + high) / 2
            if keyframes[mid].position <= position { low = mid + 1 } else { high = mid }
        }
        guard low < keyframes.count else { return keyframes.last?.value }
        let a = keyframes[low - 1], b = keyframes[low]
        let t = (position - a.position) / (b.position - a.position)
        let progress = Self.ease(t, outgoing: a.outgoing, incoming: b.incoming)
        return a.value + (b.value - a.value) * progress
    }

    static func ease(_ t: Double, outgoing: CGPoint, incoming: CGPoint) -> Double {
        if t <= 0 { return 0 }; if t >= 1 { return 1 }
        if outgoing.x == outgoing.y && incoming.x == incoming.y { return t }
        func cubic(_ a: Double, _ b: Double, _ u: Double) -> Double {
            let v = 1 - u
            return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
        }
        // Bounded bisection stays stable even for vertical tangents and crossed handles.
        var lower = 0.0, upper = 1.0
        for _ in 0..<20 {
            let u = (lower + upper) / 2
            if cubic(outgoing.x, incoming.x, u) < t { lower = u } else { upper = u }
        }
        return cubic(outgoing.y, incoming.y, (lower + upper) / 2)
    }
}
