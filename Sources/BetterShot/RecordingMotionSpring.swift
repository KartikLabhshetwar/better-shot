//
//  RecordingMotionSpring.swift
//  BetterShot
//
//  One physically integrated spring, shared by the viewport and pointer
//  timelines so both settle with the same semi-implicit Euler step instead of
//  maintaining two parallel integrators.
//

import Foundation

nonisolated struct SpringConstant: Sendable {
    var tension: Double
    var friction: Double
    var inertia: Double
}

nonisolated struct DampedSpring: Sendable {
    var position: Double
    var velocity: Double = 0

    mutating func snap(to value: Double) {
        position = value
        velocity = 0
    }

    mutating func step(toward target: Double, using constant: SpringConstant, dt: Double) {
        guard constant.inertia > 0 else {
            position = target
            velocity = 0
            return
        }
        let acceleration = (
            constant.tension * (target - position) - constant.friction * velocity
        ) / constant.inertia
        velocity += acceleration * dt
        position += velocity * dt
    }
}
