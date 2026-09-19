//
//  HoverButton.swift
//  boringNotch
//
//  Created by Kraigo on 04.09.2024.
//

// Adapted from TheBoredTeam/boring.notch at 99c26e418323d10e48886469fc9bd83900194bec.
// GPL-3.0; see Resources/Licenses/BoringNotch.txt and NOTICE.md.
// BetterShot: accessible names and reduced-motion-aware, shorter hover feedback.

import SwiftUI

struct BoringNotchHoverButton: View {
    var title: String
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)

        Button(action: action) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            Image(systemName: icon)
                                .foregroundColor(iconColor)
                                .font(scale == .large ? .largeTitle : .body)
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(title)
        .help(title)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
