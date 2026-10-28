import SwiftUI

struct ToolCatalogView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    let onlyAdded: Bool
    @State private var search = ""
    @State private var category: ToolCategory?
    private var modules: [UtilityModule] {
        UtilityModule.allCases.filter {
            (!onlyAdded || (preferences.setupComplete && preferences.enabled($0))) &&
            (category == nil || $0.category == category) &&
            (search.isEmpty || ($0.title + " " + $0.detail + " " + $0.category.title).localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(onlyAdded ? "CURATED BY YOU" : "A LITTLE OF EVERYTHING")
                            .font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                        Text(onlyAdded ? "My Toolbox" : "Good things, all in one place.")
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                        Text(onlyAdded ? "The tools you picked. Ready when you are." : "Browse the collection. Preview anything. Keep what you need.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(UtilityModule.allCases.count) TOOLS\nALWAYS FREE")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.3)
                        .multilineTextAlignment(.trailing).foregroundStyle(.secondary).padding(.top, 4)
                }
                HStack(spacing: 14) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a tool", text: $search).textFieldStyle(.plain)
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                    }.padding(10).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                    Text("\(modules.count) available").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        categoryChip("All", nil)
                        ForEach(ToolCategory.allCases) { category in categoryChip(category.title, category) }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 16)], alignment: .leading, spacing: 16) {
                    ForEach(modules) { module in CatalogToolCard(module: module) }
                }
                if modules.isEmpty {
                    ContentUnavailableView(onlyAdded && search.isEmpty ? "Your collection starts here" : "No matching tools", systemImage: "square.grid.2x2", description: Text(onlyAdded ? "Browse All Tools and add the ones you want." : "Try another search or category."))
                    if onlyAdded { Button("Browse All Tools") { hub.tab = "home" } }
                }
                HStack {
                    Image(systemName: "circle.grid.2x2")
                    Text("Every tool has its own preview and controls. Menu bar placement is always optional.")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }.padding(28)
        }
    }
    private func categoryChip(_ title: String, _ value: ToolCategory?) -> some View {
        Button { category = value } label: {
            Text(title).font(.system(size: 10, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 7)
                .foregroundStyle(category == value ? Color.primary : Color.secondary)
                .background(category == value ? Color.primary.opacity(0.09) : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(category == value ? 0 : 0.09)))
        }.buttonStyle(.plain)
    }
}

private struct CatalogToolCard: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    let module: UtilityModule
    private var added: Bool { preferences.setupComplete && preferences.enabled(module) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { hub.tab = module.rawValue } label: {
                VStack(alignment: .leading, spacing: 12) {
                    ToolPreviewCanvas(module: module).frame(height: 104).clipShape(RoundedRectangle(cornerRadius: 10))
                    HStack {
                        Image(systemName: module.symbol).foregroundStyle(module.color)
                        Text(module.title).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    Text(module.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack {
                if added { Label("Added", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Text(module.category.title).foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                Button(added ? "Open" : "+ Add") {
                    if added { hub.tab = module.rawValue }
                    else { preferences.activate(module) }
                }.buttonStyle(.bordered).controlSize(.small)
            }.font(.system(size: 10, weight: .medium)).padding(.top, 13)
        }.padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.primary.opacity(0.065)))
    }
}

struct ModuleWorkspaceView: View {
    @EnvironmentObject var preferences: HubPreferences
    let module: UtilityModule
    @State private var showPreview = false
    private var added: Bool { preferences.setupComplete && preferences.enabled(module) }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(module.category.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                    Spacer()
                    if added {
                        Menu {
                            Button("Remove from My Toolbox") { preferences.set(module, enabled: false) }
                        } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                    }
                }
                HStack(alignment: .center) {
                    HStack(spacing: 12) {
                        Image(systemName: module.symbol).font(.title2).foregroundStyle(module.color)
                            .frame(width: 46, height: 46).background(module.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(module.title).font(.title2.bold())
                            Text(module.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !added { Button("Add Tool") { preferences.activate(module); showPreview = false }.buttonStyle(.borderedProminent) }
                    else { Label("In My Toolbox", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                }
                if added {
                    HStack {
                        Picker("View", selection: $showPreview) { Text("Controls").tag(false); Text("Preview").tag(true) }
                            .pickerStyle(.segmented).frame(width: 190)
                        Spacer()
                        Picker("Menu bar", selection: Binding(get: { preferences.placement(module) }, set: { preferences.setPlacement(module, $0) })) {
                            ForEach(ToolPlacement.allCases) { Text($0.title).tag($0) }
                        }.frame(maxWidth: 230)
                    }
                }
            }.padding(28)
            Divider()
            if !added || showPreview { ModulePreviewDetail(module: module) }
            else { ToolContentView(module: module) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct ModulePreviewDetail: View {
    @EnvironmentObject var preferences: HubPreferences
    let module: UtilityModule
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ToolPreviewCanvas(module: module, expanded: true).frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 15) {
                    Text("A closer look").font(.title3.bold())
                    ForEach(module.features, id: \.self) { feature in
                        Label(feature, systemImage: "checkmark").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if !preferences.setupComplete || !preferences.enabled(module) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Make it part of your toolbox.").font(.headline)
                            Text("Choose its menu bar placement any time.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add Tool") { preferences.activate(module) }.buttonStyle(.borderedProminent)
                    }.padding(18).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
                Text("Illustrative preview. Live values and controls appear after you add this tool.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}

struct ToolPreviewCanvas: View {
    let module: UtilityModule
    var expanded = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                module.color.opacity(0.075)
                drawing.frame(width: min(geometry.size.width - 36, expanded ? 420 : 240))
                    .scaleEffect(expanded ? 1.35 : 1)
                VStack {
                    HStack { Spacer(); Text("PREVIEW").font(.system(size: 7, weight: .medium)).tracking(1.1).foregroundStyle(.tertiary) }
                    Spacer()
                }.padding(10)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityLabel("Illustrative preview of \(module.title)")
    }
    @ViewBuilder private var drawing: some View {
        switch module {
        case .audio:
            VStack(spacing: 10) {
                miniSlider("Browser", symbol: "globe", value: 0.72)
                miniSlider("Music", symbol: "music.note", value: 0.44)
                miniSlider("Call", symbol: "phone", value: 0.86)
            }.padding(.horizontal, 12)
        case .system:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CPU").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    sparkline(values: [0.2, 0.3, 0.22, 0.6, 0.5, 0.85, 0.5, 0.65, 0.4]).frame(height: 30)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("GPU").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(0..<9) { index in RoundedRectangle(cornerRadius: 2).fill(module.color.opacity(0.3 + Double(index % 3) * 0.2)).frame(height: CGFloat([10, 17, 12, 23, 28, 20, 15, 25, 19][index])) }
                    }.frame(height: 30)
                }
            }.padding(16)
        case .storage:
            HStack(spacing: 18) {
                ZStack { Circle().stroke(module.color.opacity(0.15), lineWidth: 8); Circle().trim(from: 0, to: 0.67).stroke(module.color, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90)); Image(systemName: "internaldrive").font(.system(size: 17)).foregroundStyle(.secondary) }.frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Space over time").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                    sparkline(values: [0.85, 0.78, 0.82, 0.55, 0.6, 0.38, 0.4, 0.2]).frame(height: 24)
                }
            }.padding(18)
        case .awake:
            HStack(spacing: 20) {
                Image(systemName: "bolt.shield.fill").font(.system(size: 38, weight: .light)).foregroundStyle(module.color)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Keep Awake").font(.system(size: 11, weight: .semibold))
                    Text("30 min").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    Capsule().fill(module.color.opacity(0.2)).frame(width: 66, height: 4)
                }
            }
        case .displays:
            HStack(alignment: .bottom, spacing: 18) {
                display("laptopcomputer", value: 0.72)
                display("display", value: 0.44)
            }.padding(18)
        case .shelf:
            VStack(spacing: 8) {
                HStack(spacing: 10) { Image(systemName: "wifi"); Image(systemName: "speaker.wave.2"); Image(systemName: "battery.100percent"); Spacer(); Image(systemName: "0.circle.fill").foregroundStyle(module.color) }
                    .font(.system(size: 10)).padding(8).background(Color.primary.opacity(0.055), in: Capsule())
                HStack(spacing: 16) { Image(systemName: "bolt.shield"); Image(systemName: "sun.max"); Image(systemName: "slider.horizontal.3") }
                    .font(.system(size: 16)).foregroundStyle(module.color).padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            }.padding(.horizontal, 12)
        case .updates:
            HStack(spacing: 16) {
                Image(systemName: "arrow.down.circle").font(.system(size: 36, weight: .light)).foregroundStyle(module.color)
                VStack(alignment: .leading, spacing: 8) {
                    Text("GitHub Releases").font(.system(size: 11, weight: .semibold))
                    HStack(spacing: 4) { Image(systemName: "checkmark.shield"); Text("Check for updates") }.font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
    }
    private func miniSlider(_ title: String, symbol: String, value: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 9)).frame(width: 12).foregroundStyle(.secondary)
            Text(title).font(.system(size: 8)).frame(width: 37, alignment: .leading).foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(module.color.opacity(0.13))
                    Capsule().fill(module.color.opacity(0.7)).frame(width: max(0, geometry.size.width * value))
                }
            }.frame(height: 4)
        }
    }
    private func display(_ symbol: String, value: CGFloat) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 33, weight: .light)).foregroundStyle(module.color.opacity(value))
            Capsule().fill(module.color.opacity(0.55)).frame(width: 52 * value, height: 3).frame(width: 52, alignment: .leading)
        }
    }
    private func sparkline(values: [CGFloat]) -> some View {
        GeometryReader { geometry in
            Path { path in
                for (index, value) in values.enumerated() {
                    let point = CGPoint(x: geometry.size.width * CGFloat(index) / CGFloat(values.count - 1), y: geometry.size.height * (1 - value))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }.stroke(module.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct UpdateToolView: View {
    @ObservedObject var updates: UpdateChecker
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("GitHub Releases", systemImage: "arrow.down.circle").font(.title3.bold())
                Text(updates.message).font(.headline)
                Text("Installed version: \(updates.currentVersion)").font(.caption).foregroundStyle(.secondary)
                if let date = updates.checkedAt { Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button(updates.checking ? "Checking…" : "Check Now") { updates.check() }.disabled(updates.checking).buttonStyle(.borderedProminent)
                    Button("View Releases") { updates.openRelease() }
                }
                Divider()
                Button(updates.notificationsEnabled ? "Notifications Enabled" : "Enable Update Notifications") { updates.enableNotifications() }.disabled(updates.notificationsEnabled)
                Text("Checks every six hours while running. Verified releases open on GitHub for you to download.").font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
