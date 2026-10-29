import SwiftUI

struct MenuBarToolPreview: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let module: UtilityModule
    let expanded: Bool
    @State private var placement: ToolPlacement = .individual
    @State private var opened = true
    @State private var playing = true
    var body: some View {
        GeometryReader { bounds in
            let toolbar: CGFloat = expanded ? 80 : 35
            let size = popupSize
            let scale = min((bounds.size.width - 22) / size.width, (bounds.size.height - toolbar - 24) / size.height, 1)
            VStack(spacing: 0) {
                if expanded {
                    HStack {
                        Picker("Preview placement", selection: $placement) {
                            Text("Own Icon").tag(ToolPlacement.individual)
                            Text("In the Box").tag(ToolPlacement.box)
                            Text("App Only").tag(ToolPlacement.window)
                        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 330)
                        Spacer(minLength: 8)
                        Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                            .help(playing ? "Pause animation" : "Play animation")
                    }.padding(10)
                }
                HStack(spacing: 9) {
                    Image(systemName: "apple.logo").font(.system(size: 13))
                    if expanded { Text("This Is Not Free").font(.system(size: 11, weight: .semibold)) }
                    Spacer()
                    if placement != .window {
                        Button { playing = false; withAnimation(.easeInOut(duration: 0.25)) { opened.toggle() } } label: {
                            Group {
                                if placement == .box { MenuIdentityMark(icons: hub.icons) }
                                else { Image(systemName: module.symbol).font(.system(size: 16)) }
                            }.frame(width: 28, height: 26)
                                .background(opened ? Color.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain).help("Toggle popup preview")
                    }
                }.padding(.horizontal, 12).frame(height: 30)
                    .background(Color(nsColor: .controlBackgroundColor))
                ZStack(alignment: .topTrailing) {
                    Color.secondary.opacity(0.045)
                    if placement == .window {
                        VStack(spacing: 8) {
                            Image(systemName: "macwindow").font(.title2)
                            Text("App Only").font(.caption.weight(.semibold))
                            if expanded { Text("No menu bar icon or popup.").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if opened {
                        VStack(spacing: 0) {
                            if !showsShelfBar {
                            Image(systemName: "triangle.fill").resizable().frame(width: 12, height: 6)
                                .foregroundStyle(Color(nsColor: .windowBackgroundColor)).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 10)
                            }
                            popup
                                .frame(width: size.width, height: size.height)
                                .allowsHitTesting(false).accessibilityHidden(true)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
                                .scaleEffect(max(0.05, scale), anchor: .topTrailing)
                                .frame(width: size.width * max(0.05, scale), height: size.height * max(0.05, scale), alignment: .topTrailing)
                        }.frame(width: size.width * max(0.05, scale), alignment: .topTrailing)
                            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
                            .padding(.top, 3).padding(.trailing, 10)
                            .transition(.opacity.combined(with: .offset(y: -8)))
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: playing) {
            guard playing, !reduceMotion, !hub.isRenderingExport else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                    withAnimation(.easeInOut(duration: 0.28)) { opened = false }
                    try await Task.sleep(for: .milliseconds(850))
                    withAnimation(.easeInOut(duration: 0.28)) { opened = true }
                } catch { return }
            }
        }
    }
    private var showsShelfBar: Bool { (placement == .individual && module == .shelf) || (placement == .box && preferences.enabled(.shelf) && preferences.externalInBox) }
    private var popupSize: CGSize { showsShelfBar ? CGSize(width: ShelfBarMetrics.width, height: ShelfBarMetrics.height) : CGSize(width: 420, height: 580) }
    @ViewBuilder private var popup: some View {
        if showsShelfBar {
            ShelfPopupView(shelf: hub.shelf, readOnly: true, includeTools: placement == .box)
        } else if placement == .box {
            // Actual current box contents; no fabricated enabled tools or icons.
            BoxPopoverView(shelf: hub.shelf, readOnly: true)
        } else {
            ToolPopupSurface(module: module, readOnly: true)
        }
    }
}

// Both the real per-tool popover and the preview render this exact surface.
struct ToolPopupSurface: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    let module: UtilityModule
    var readOnly = false
    var body: some View {
        Group {
            if module == .shelf { ShelfPopupView(shelf: hub.shelf, readOnly: readOnly) }
            else {
                VStack(spacing: 0) {
                    HStack { Label(module.title, systemImage: module.symbol).font(.headline); Spacer(); Button("Open App") { hub.openWindow?(module.rawValue) }.buttonStyle(.borderless) }.padding(16)
                    Divider()
                    if readOnly { ActualToolPanel(module: module) }
                    else { ToolContentView(module: module) }
                }.frame(width: 420, height: 580).background(Color(nsColor: .windowBackgroundColor))
            }
        }.tint(preferences.accent.color)
            .preferredColorScheme(preferences.appearance == "dark" ? .dark : preferences.appearance == "light" ? .light : nil)
    }
}
