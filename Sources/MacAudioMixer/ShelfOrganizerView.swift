import SwiftUI
import UniformTypeIdentifiers

struct ShelfIconView: View {
    @ObservedObject var shelf: MenuShelf
    let item: ShelfItem
    var size: CGFloat = 24
    var body: some View {
        Group {
            if let icon = shelf.liveIcons[item.id] {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: size * 1.5, height: size)
            } else if let icon = item.icon {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: size, height: size)
                    .overlay(alignment: .bottomTrailing) { Image(systemName: "app.badge").font(.system(size: 7)).padding(1).background(.regularMaterial, in: Circle()) }
            } else { Image(systemName: "app.dashed").frame(width: size, height: size) }
        }.help(shelf.liveIcons[item.id] == nil ? "App icon fallback · Original snapshot unavailable" : "Original menu bar icon snapshot")
    }
}

struct ShelfOrganizerView: View {
    @EnvironmentObject var hub: UtilityHub
    @EnvironmentObject var preferences: HubPreferences
    @ObservedObject var shelf: MenuShelf
    @State private var dragging: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Arrange your menu bar").font(.title3.bold())
            Text("Drag discovered icons between lanes, or onto another icon to change their order. Shelf contents update immediately. Apply Arrangement moves the original icons into visible or collapsible sections; failed moves remain revealed.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Open Shelf Bar") { hub.openShelfBar?() }.disabled(!preferences.enabled(.shelf) || preferences.layout == .window)
                Button("Refresh Icons") { shelf.refresh() }.disabled(shelf.refreshing || shelf.arranging)
                if !shelf.accessibilityGranted { Button("Allow Accessibility") { shelf.requestAccessibility() } }
                Button(shelf.screenCaptureGranted ? "Refresh Original Images" : "Show Original Icon Images") { shelf.requestIconCapture() }.disabled(shelf.capturing || !shelf.accessibilityGranted)
                if shelf.refreshing || shelf.capturing { ProgressView().controlSize(.small) }
            }
            Text("Original images need Screen Recording. Only visible menu-item rectangles are captured, kept in memory, and never uploaded. Unavailable images carry an app-icon fallback badge. Collapsed originals keep their last captured image.")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(ShelfDestination.allCases) { destination in
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Text(destination.title).font(.headline); Spacer(); Text("\(shelf.items.filter { shelf.arrangement.destination($0.id) == destination }.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    Text(destination.detail).font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(shelf.arrangement.ordered(shelf.items.filter { shelf.arrangement.destination($0.id) == destination })) { item in
                                VStack(spacing: 6) {
                                    ShelfIconView(shelf: shelf, item: item)
                                    Text(item.title).font(.caption2).lineLimit(2).frame(width: 90, height: 28)
                                    if shelf.appliedItems.contains(item.id) { Text("Applied").font(.system(size: 8)).foregroundStyle(.green) }
                                    Menu("Move") {
                                        ForEach(ShelfDestination.allCases) { choice in Button(choice.title) { shelf.assign(item.id, to: choice) } }
                                    }.font(.caption2).menuStyle(.borderlessButton).fixedSize()
                                }.padding(9).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                                    .onDrag { dragging = item.id; return NSItemProvider(object: item.id as NSString) }
                                    .onDrop(of: [.text], isTargeted: nil) { providers in
                                        accept(providers, destination: destination, before: item.id)
                                    }
                            }
                            if shelf.items.filter({ shelf.arrangement.destination($0.id) == destination }).isEmpty {
                                Text("Drop icons here").font(.caption).foregroundStyle(.secondary).frame(width: 210, height: 95)
                            }
                        }.padding(3)
                    }.frame(minHeight: 110)
                }.padding(14).background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                    .onDrop(of: [.text], isTargeted: nil) { providers in accept(providers, destination: destination) }
            }
            HStack {
                Button(shelf.arranging ? "Moving Originals…" : "Apply Arrangement") { shelf.applyArrangement() }
                    .buttonStyle(.borderedProminent)
                    .disabled(shelf.arranging || shelf.items.isEmpty || !shelf.supportsCollapse || !preferences.enabled(.shelf) || preferences.layout == .window)
                Button("Reveal All Originals") { shelf.setCollapsed(false) }.disabled(shelf.arranging)
                Button("Collapse Originals") { shelf.setCollapsed(true) }.disabled(!shelf.organizerEnabled || shelf.arranging)
            }
            Text(shelf.supportsCollapse ? "Add Menu Bar Shelf and use a menu bar layout to apply. macOS may refuse to move protected icons. During Apply, leave the pointer idle; originals are collapsed only after every move is verified." : "This macOS version does not support section collapsing. Dragging still chooses Shelf contents, but originals must be hidden using macOS or the owning app's settings.")
                .font(.caption2).foregroundStyle(.secondary)
            if let message = shelf.message { Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }
    }
    private func accept(_ providers: [NSItemProvider], destination: ShelfDestination, before: String? = nil) -> Bool {
        guard !shelf.arranging, dragging != nil,
              let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let id = value as? String else { return }
            Task { @MainActor in
                guard id == dragging, id != before, !shelf.arranging, shelf.items.contains(where: { $0.id == id }) else { return }
                shelf.assign(id, to: destination, before: before); dragging = nil
            }
        }
        return true
    }
}
