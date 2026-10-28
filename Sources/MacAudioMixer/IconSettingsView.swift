import SwiftUI

struct AppIdentityMark: View {
    @ObservedObject var icons: IconAppearance
    var size: CGFloat
    var body: some View { Image(nsImage: icons.appImage).resizable().scaledToFit().frame(width: size, height: size).accessibilityLabel("App icon") }
}

struct MenuIdentityMark: View {
    @ObservedObject var icons: IconAppearance
    var body: some View {
        Image(nsImage: icons.menuImage).renderingMode(icons.menuImage.isTemplate ? .template : .original)
            .frame(width: 20, height: 20).accessibilityLabel("Menu bar icon")
    }
}

struct IconSettingsView: View {
    @ObservedObject var icons: IconAppearance
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Icons").font(.headline)
            HStack(spacing: 16) {
                AppIdentityMark(icons: icons, size: 84)
                VStack(alignment: .leading, spacing: 8) {
                    Text("App & Dock").font(.subheadline.bold())
                    Text(icons.hasCustomApp ? "Custom image" : "The zero-value banknote").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Choose Image…") { icons.choose(.app) }
                        Button("Restore Default") { icons.reset(.app) }.disabled(!icons.hasCustomApp)
                    }
                }
            }
            Divider()
            HStack(spacing: 16) {
                MenuIdentityMark(icons: icons).frame(width: 56, height: 48)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shared Menu Bar Icon").font(.subheadline.bold())
                    Picker("Design", selection: $icons.style) {
                        ForEach(MenuIconStyle.allCases.filter { $0 != .custom || icons.hasCustomMenu }) { Text($0.title).tag($0) }
                    }.frame(maxWidth: 260)
                    HStack {
                        Button("Choose Image…") { icons.choose(.menuBar) }
                        Button("Restore Default") { icons.reset(.menuBar) }.disabled(!icons.hasCustomMenu && icons.style == .zero && icons.monochrome)
                    }
                }
            }
            if icons.style == .custom {
                Toggle("Adapt custom menu icon to light and dark bars", isOn: $icons.monochrome)
                Text("Use a transparent PNG for a clean silhouette. Turn this off to keep the image's original colors.").font(.caption).foregroundStyle(.secondary)
            }
            if icons.importing { ProgressView("Preparing icon…").font(.caption) }
            if let error = icons.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("App images update the Dock and branding inside this app. The Finder icon remains the installed default. Imported images are copied locally and restored after relaunch. Each icon can be reset independently.")
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(icons.importing)
    }
}
