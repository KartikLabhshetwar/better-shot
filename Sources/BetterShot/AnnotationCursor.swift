//
//  AnnotationCursor.swift
//  BetterShot
//

import AppKit

extension NSCursor {
    static let annotationPlus: NSCursor = {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outline = NSBezierPath()
        outline.move(to: CGPoint(x: center.x - 6, y: center.y))
        outline.line(to: CGPoint(x: center.x + 6, y: center.y))
        outline.move(to: CGPoint(x: center.x, y: center.y - 6))
        outline.line(to: CGPoint(x: center.x, y: center.y + 6))
        NSColor.white.setStroke()
        outline.lineWidth = 5
        outline.lineCapStyle = .round
        outline.stroke()

        let plus = NSBezierPath()
        plus.move(to: CGPoint(x: center.x - 6, y: center.y))
        plus.line(to: CGPoint(x: center.x + 6, y: center.y))
        plus.move(to: CGPoint(x: center.x, y: center.y - 6))
        plus.line(to: CGPoint(x: center.x, y: center.y + 6))
        NSColor.black.setStroke()
        plus.lineWidth = 2
        plus.lineCapStyle = .round
        plus.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }()
}
