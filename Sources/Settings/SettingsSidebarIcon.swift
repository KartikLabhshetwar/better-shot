import SwiftUI

/// A fixed symbol box keeps wide SF Symbols inside their colored sidebar tile.
struct SettingsSidebarIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .padding(4)
            .background(color, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}
