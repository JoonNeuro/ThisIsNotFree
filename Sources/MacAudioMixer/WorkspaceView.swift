import AppKit
import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    var body: some View {
        HSplitView {
            WorkspaceSidebarView().frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
            Group {
                if let module = UtilityModule(rawValue: hub.tab) {
                    ModuleWorkspaceView(module: module).id(module)
                } else {
                    VStack(spacing: 0) {
                        if hub.tab == "home" || hub.tab == "mine" {
                            ToolCatalogView(onlyAdded: hub.tab == "mine")
                        } else {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(hub.tab == "layout" ? "Tools & Layout" : "Settings").font(.title.bold())
                                    Text(hub.tab == "layout" ? "A place for everything you choose." : "Make this toolbox feel like yours.").foregroundStyle(.secondary)
                                }
                                Spacer()
                            }.padding(28)
                            Divider()
                            if hub.tab == "layout" { LayoutEditorView(shelf: hub.shelf) }
                            else { HubSettingsView(updates: hub.updates) }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(preferences.accent.color)
        .preferredColorScheme(preferences.appearance == "dark" ? .dark : preferences.appearance == "light" ? .light : nil)
    }
}

private struct WorkspaceSidebarView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppIdentityMark(icons: hub.icons, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("This Is Not Free").font(.headline)
                    Text("THE COLLECTION").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    row("All Tools", "square.grid.2x2", "home", count: UtilityModule.allCases.count)
                    row("My Toolbox", "tray", "mine", count: preferences.setupComplete ? preferences.modules.count : 0)
                    ForEach(ToolCategory.allCases) { category in
                        Text(category.title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.1)
                            .foregroundStyle(.secondary).padding(.top, 18).padding(.bottom, 7).padding(.leading, 10)
                        ForEach(category.modules) { module in
                            row(module.title, module.symbol, module.rawValue, enabled: preferences.setupComplete && preferences.enabled(module))
                        }
                    }
                }
            }
            Divider()
            row("Menu Bar Layout", "menubar.rectangle", "layout")
            row("Settings", "gearshape", "settings")
        }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
    }
    private func row(_ title: String, _ symbol: String, _ tab: String, count: Int? = nil, enabled: Bool = false) -> some View {
        Button { hub.tab = tab } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).lineLimit(1)
                Spacer(minLength: 2)
                if let count { Text("\(count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                else if enabled { Circle().fill(.green).frame(width: 5, height: 5).accessibilityLabel("Added") }
            }
            .font(.system(size: 12, weight: hub.tab == tab ? .semibold : .regular))
            .foregroundStyle(hub.tab == tab ? preferences.accent.color : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(.horizontal, 10)
            .background(hub.tab == tab ? preferences.accent.color.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
}

struct ToolContentView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    let module: UtilityModule
    var body: some View {
        Group {
            if !preferences.setupComplete || !preferences.enabled(module) {
                ModulePreviewDetail(module: module)
            } else {
                switch module {
                case .audio:
                    if let mixer = hub.mixer { MixerView().environmentObject(mixer) }
                    else { ProgressView("Starting Audio Mixer…") }
                case .storage: StorageView(storage: hub.storage)
                case .shelf: ShelfView(shelf: hub.shelf, groups: hub.groups)
                case .updates: UpdateToolView(updates: hub.updates)
                default: DashboardView(system: hub.system, awake: hub.awake, displays: hub.displays, updates: hub.updates, section: module)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct LayoutChoicesView: View {
    @EnvironmentObject var preferences: HubPreferences
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(LayoutPreset.allCases) { preset in
                Button { preferences.applyLayout(preset); preferences.workspaceConfigured = true; preferences.setupComplete = true } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: preset.symbol).font(.title2).frame(width: 30)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(preset.title).font(.headline); Spacer(); if preferences.layout == preset { Image(systemName: "checkmark.circle.fill") } }
                            Text(preset.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(16).frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
                        .background(preferences.layout == preset ? preferences.accent.color.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(preferences.layout == preset ? preferences.accent.color : .clear, lineWidth: 2))
                }.buttonStyle(.plain)
            }
        }
    }
}

struct LayoutEditorView: View {
    @EnvironmentObject var preferences: HubPreferences
    @ObservedObject var shelf: MenuShelf
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Start with a layout").font(.headline)
                LayoutChoicesView()
                Divider()
                Text("Choose your tools").font(.headline)
                Text("Enable only what you want. Each enabled tool can live in the app, in the shared box, or behind its own menu bar icon.").font(.subheadline).foregroundStyle(.secondary)
                ForEach(UtilityModule.allCases) { module in
                    HStack(spacing: 20) {
                        ModuleToggle(module: module)
                        if preferences.enabled(module) {
                            Picker("Location for \(module.title)", selection: Binding(get: { preferences.placement(module) }, set: { preferences.setPlacement(module, $0) })) {
                                ForEach(ToolPlacement.allCases) { Text($0.title).tag($0) }
                            }.labelsHidden().frame(width: 145)
                        }
                    }
                }
                Divider()
                ExternalIconsEditor(shelf: shelf)
                if preferences.enabled(.shelf) && preferences.layout == .custom {
                    Text("For multiple custom boxes, use Menu Bar Shelf → Menu Bar Groups. Saved groups appear in the menu bar only in Custom Mix.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24)
        }
    }
}

struct ExternalIconsEditor: View {
    @EnvironmentObject var preferences: HubPreferences
    @ObservedObject var shelf: MenuShelf
    @State private var search = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Existing Menu Bar Icons").font(.headline)
            Toggle("Connect other apps' menu bar items", isOn: Binding(get: { preferences.enabled(.shelf) }, set: { if $0 { preferences.activate(.shelf) } else { preferences.set(.shelf, enabled: false) } }))
            if preferences.enabled(.shelf) {
                Toggle("Include existing items in the shared box", isOn: Binding(get: { preferences.externalInBox }, set: { preferences.externalInBox = $0; preferences.layout = .custom }))
                if preferences.externalInBox {
                    Toggle("Include all discovered items, including new ones", isOn: $preferences.includeAllExternal)
                    HStack {
                        Button("Refresh Items") { shelf.refresh() }.disabled(shelf.refreshing)
                        if !shelf.accessibilityGranted { Button("Allow Accessibility") { shelf.requestAccessibility() } }
                        if shelf.refreshing { ProgressView().controlSize(.small) }
                    }
                    TextField("Search existing menu bar items", text: $search).textFieldStyle(.roundedBorder)
                    ForEach(shelf.items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.appName.localizedCaseInsensitiveContains(search) }) { item in
                        HStack {
                            if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                            VStack(alignment: .leading) { Text(item.title).font(.subheadline); Text(item.appName).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if preferences.includeAllExternal { Text("In the Box").font(.caption).foregroundStyle(.secondary) }
                            else { Toggle("In the Box", isOn: Binding(get: { shelf.pinned.contains(item.id) }, set: { value in if value != shelf.pinned.contains(item.id) { shelf.togglePin(item) } })).toggleStyle(.checkbox) }
                        }
                    }
                    if shelf.items.isEmpty { Text("Refresh after granting Accessibility to see available items. Some system and third-party items are not exposed by macOS.").font(.caption).foregroundStyle(.secondary) }
                    Text("Tiles use app icons and open each item's original menu. They do not copy live status graphics or move original icons automatically.").font(.caption).foregroundStyle(.secondary)
                }
                if shelf.supportsCollapse {
                    Toggle("Use a collapsible section for original icons", isOn: Binding(get: { shelf.organizerEnabled }, set: { shelf.enableOrganizer($0) }))
                    if shelf.organizerEnabled {
                        Text("Hold ⌘ and drag originals to the left of the │ divider. Keep this app's box to its right, then collapse the section.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(shelf.collapsed ? "Reveal Originals" : "Collapse Originals") { shelf.setCollapsed(!shelf.collapsed) }
                            Button("Restore Menu Bar") { shelf.restore() }
                        }
                    }
                }
                if let message = shelf.message { Text(message).font(.caption).foregroundStyle(.orange) }
            }
        }.onAppear { if preferences.enabled(.shelf) { shelf.refresh() } }
    }
}

struct BoxPopoverView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    @ObservedObject var shelf: MenuShelf
    @State private var selected: UtilityModule?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if selected != nil { Button { selected = nil } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless) }
                HStack(spacing: 8) {
                    if let selected { Image(systemName: selected.symbol) }
                    else { MenuIdentityMark(icons: hub.icons) }
                    Text(selected?.title ?? "My Toolbox")
                }.font(.headline)
                Spacer()
                Button("Open App") { hub.openWindow?(selected?.rawValue) }.buttonStyle(.borderless)
            }.padding(16)
            Divider()
            if !preferences.setupComplete {
                ContentUnavailableView("Build your toolbox", systemImage: "macwindow", description: Text("Open the app to browse previews and add the tools you want."))
            } else if let selected {
                ToolContentView(module: selected)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !preferences.boxModules.isEmpty {
                            Text("My Tools").font(.caption).foregroundStyle(.secondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                                ForEach(preferences.boxModules) { module in
                                    Button { selected = module } label: {
                                        VStack(spacing: 9) { Image(systemName: module.symbol).font(.title2); Text(module.title).font(.caption).lineLimit(2) }
                                            .frame(maxWidth: .infinity, minHeight: 80).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        if preferences.enabled(.shelf) && preferences.externalInBox {
                            HStack { Text("Menu Bar Items").font(.caption).foregroundStyle(.secondary); Spacer(); Button { shelf.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).disabled(shelf.refreshing) }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                                ForEach(preferences.includeAllExternal ? shelf.items : shelf.pinnedItems) { item in
                                    Button { shelf.activate(item) } label: {
                                        VStack(spacing: 6) {
                                            if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                                            else { Image(systemName: "app").font(.title2) }
                                            Text(item.title).font(.caption2).lineLimit(2)
                                        }.frame(maxWidth: .infinity, minHeight: 66)
                                    }.buttonStyle(.plain).help(item.appName)
                                }
                            }
                            if !shelf.accessibilityGranted { Button("Connect Existing Icons") { hub.openWindow?("layout") } }
                            else if shelf.items.isEmpty { Text("No accessible menu items found. Refresh or customize in the app.").font(.caption).foregroundStyle(.secondary) }
                        }
                        Button("Customize Tools & Layout") { hub.openWindow?("layout") }.buttonStyle(.borderless)
                    }.padding(16)
                }
            }
        }.frame(width: 420, height: 580)
            .background(Color(nsColor: .windowBackgroundColor))
            .tint(preferences.accent.color)
            .preferredColorScheme(preferences.appearance == "dark" ? .dark : preferences.appearance == "light" ? .light : nil)
            .onAppear { if preferences.enabled(.shelf) && preferences.externalInBox { shelf.refresh() } }
    }
}

struct ToolPopoverView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    let module: UtilityModule
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label(module.title, systemImage: module.symbol).font(.headline); Spacer(); Button("Open App") { hub.openWindow?(module.rawValue) }.buttonStyle(.borderless) }.padding(16)
            Divider()
            ToolContentView(module: module)
        }.frame(width: 420, height: 580).background(Color(nsColor: .windowBackgroundColor)).tint(preferences.accent.color)
            .preferredColorScheme(preferences.appearance == "dark" ? .dark : preferences.appearance == "light" ? .light : nil)
    }
}
