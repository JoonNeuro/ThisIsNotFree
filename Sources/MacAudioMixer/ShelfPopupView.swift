import SwiftUI

struct ShelfBarMetrics {
    static let width: CGFloat = 820
    static let height: CGFloat = 112
}

// The exact same horizontally scrollable strip is used by the real panel and preview.
struct ShelfPopupView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    @ObservedObject var shelf: MenuShelf
    var readOnly = false
    var showsHeader = true
    var width: CGFloat = ShelfBarMetrics.width
    var includeTools = false
    var openTool: ((UtilityModule) -> Void)?
    private var items: [ShelfItem] { shelf.shelfItems }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Menu Bar Shelf", systemImage: "archivebox").font(.caption.weight(.semibold))
                Spacer()
                if shelf.refreshing || shelf.capturing { ProgressView().controlSize(.mini) }
                Button { shelf.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Refresh icons")
                Button("Arrange") { hub.openWindow?("shelf") }.font(.caption).buttonStyle(.borderless)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    if includeTools {
                        ForEach(preferences.boxModules.filter { $0 != .shelf }) { module in
                            Button { openTool?(module) } label: {
                                Image(systemName: module.symbol).font(.system(size: 20)).frame(width: 42, height: 38)
                                    .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).help(module.title)
                        }
                        if !preferences.boxModules.filter({ $0 != .shelf }).isEmpty && !items.isEmpty { Divider().frame(height: 28) }
                    }
                    ForEach(items) { item in
                        Button { shelf.activate(item) } label: {
                            ShelfIconView(shelf: shelf, item: item, size: 20).frame(minWidth: 38, minHeight: 38)
                                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).help("\(item.title) · Open original menu")
                    }
                    if !shelf.accessibilityGranted {
                        Text("Allow Accessibility to connect your real menu items.").font(.caption).foregroundStyle(.secondary)
                        Button("Connect") { shelf.requestAccessibility() }.controlSize(.small)
                    } else if items.isEmpty {
                        Text("Drag items into In Shelf using Arrange.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 2)
            }
            HStack {
                Text("Scroll sideways · Click an icon to open its menu").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                if !shelf.liveIcons.isEmpty { Text("Icon snapshots").font(.system(size: 9)).foregroundStyle(.secondary) }
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
            .frame(width: width, height: ShelfBarMetrics.height).background(Color(nsColor: .windowBackgroundColor))
            .onAppear { if !readOnly && !hub.isRenderingExport { shelf.refresh() } }
    }
}
