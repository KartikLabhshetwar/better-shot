import AppKit
import SwiftUI

extension Color {
    static let settingsCardFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.045) : .white
    })
    static let settingsCardStroke = Color.primary.opacity(0.08)
}

/// Scrolling, width-limited column that every Settings page is laid out in.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .toggleStyle(.switch)
    }
}

struct SettingsCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.settingsCardFill, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.settingsCardStroke))
    }
}

struct SettingsHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 4)
    }
}

extension SettingsHeader where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

struct SettingsPageLink: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
            .font(.callout)
            .foregroundStyle(isHovered ? .primary : .secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// A titled card of rows separated by `SettingsDivider`, with optional header accessory and footer text.
struct SettingsGroup<Content: View, Accessory: View, Footer: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let footer: Footer

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.accessory = accessory()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsHeader(title: title) { accessory }
            SettingsCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) { content }
            }
            footer
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }
}

extension SettingsGroup where Accessory == EmptyView, Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, content: content, accessory: { EmptyView() }, footer: { EmptyView() })
    }
}

extension SettingsGroup where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(title, content: content, accessory: { EmptyView() }, footer: footer)
    }
}

extension SettingsGroup where Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.init(title, content: content, accessory: accessory, footer: { EmptyView() })
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder let control: Control

    init(_ title: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption {
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .settingsRowPadding()
        .frame(minHeight: 44)
        .animation(.easeOut(duration: 0.15), value: caption)
    }
}

struct SettingToggle: View {
    let title: String
    var caption: String?
    @Binding var isOn: Bool

    init(_ title: String, caption: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.caption = caption
        self._isOn = isOn
    }

    var body: some View {
        SettingRow(title, caption: caption) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}

/// Destructive reset placed at the foot of a page, confirmed by the page's own alert.
struct SettingsResetRow: View {
    var title = "Restore Defaults\u{2026}"
    let caption: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if let caption {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(title, role: .destructive, action: action)
        }
        .padding(.horizontal, 4)
    }
}

/// Permission status in Settings, sharing the onboarding permission model and its recovery steps.
struct SettingsPermissionRow: View {
    let permission: OnboardingPermission
    let permissions: OnboardingPermissions

    private var status: OnboardingPermissionStatus { permissions.status(permission) }
    private var needsSettings: Bool {
        permission.needsSettings(status: status, attempted: permissions.attempted.contains(permission))
    }

    private var caption: String {
        if status == .restricted {
            return "Restricted by this Mac’s settings or administrator."
        }
        if status != .allowed && needsSettings {
            return "In Privacy & Security \u{203A} \(permission.title), turn on BetterShot, then return here."
        }
        return permission.explanation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(permission.displayTitle, caption: caption) { control }
            if permissions.settingsErrorPermission == permission, let error = permissions.settingsError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 11)
            }
        }
    }

    @ViewBuilder private var control: some View {
        if permissions.requesting == permission {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Waiting for \(permission.displayTitle) permission")
        } else if status == .allowed {
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.multicolor)
                .accessibilityLabel("\(permission.displayTitle) access allowed")
        } else if status == .restricted {
            Label("Restricted", systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Button(needsSettings ? "Open Settings\u{2026}" : "Allow\u{2026}") {
                if needsSettings {
                    permissions.openSettings(permission)
                } else {
                    Task { await permissions.request(permission) }
                }
            }
            .disabled(permissions.requesting != nil)
            .accessibilityLabel(needsSettings ? "Open \(permission.title) settings" : "Allow \(permission.displayTitle) access")
        }
    }
}

extension View {
    func settingsRowPadding() -> some View {
        padding(.horizontal, 16).padding(.vertical, 11)
    }
}
