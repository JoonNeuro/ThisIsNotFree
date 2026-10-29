import AppKit
import SwiftUI
import Charts

struct StorageView: View {
    @ObservedObject var storage: StorageTracker
    @State private var selectedRoot = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                StorageSummaryView(storage: storage)
                if storage.capacity.count > 1 {
                    Chart(storage.capacity) { sample in
                        LineMark(x: .value("Time", sample.date), y: .value("Free GB", Double(sample.free) / 1_000_000_000))
                            .interpolationMethod(.linear)
                    }
                    .chartYAxisLabel("Free GB").frame(height: 90)
                    Text("Free space · up to 1,440 recent samples").font(.caption2).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Text("Watched Folders").font(.headline)
                    Spacer()
                    Button { storage.addFolder() } label: { Label("Add", systemImage: "plus") }
                        .disabled(storage.loading || storage.roots.count >= 8)
                }
                Text("Choose folders such as Downloads, project outputs, or caches. History begins with the first complete scan.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(storage.roots, id: \.self) { root in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root) } label: {
                                Label(URL(fileURLWithPath: root).lastPathComponent, systemImage: "folder")
                            }.buttonStyle(.borderless).lineLimit(1).help(root)
                            Spacer()
                            if let latest = storage.events.last(where: { $0.root == root }) {
                                Text((latest.issues.isEmpty ? "" : "≥ ") + storageBytes(latest.bytes)).font(.caption.monospacedDigit())
                            }
                            Button { storage.removeRoot(root) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help("Remove watch and its history")
                        }
                        Text(root.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                HStack {
                    Button(storage.scanning ? "Cancel Scan" : "Scan Now") { storage.scanning ? storage.cancel() : storage.scan() }
                        .disabled(storage.roots.isEmpty)
                    if storage.scanning { ProgressView().controlSize(.small) }
                    Spacer()
                }
                if let path = storage.scanningPath { Text("Scanning \(URL(fileURLWithPath: path).lastPathComponent)…").font(.caption).foregroundStyle(.secondary) }
                if storage.loading { ProgressView("Loading local history…").font(.caption) }
                if let message = storage.message { Text(message).font(.caption).foregroundStyle(.orange) }
                Divider()
                HStack {
                    Text("Change History").font(.headline)
                    Spacer()
                    if !storage.roots.isEmpty {
                        Picker("Folder", selection: $selectedRoot) {
                            Text("All folders").tag("")
                            ForEach(storage.roots, id: \.self) { root in Text(URL(fileURLWithPath: root).lastPathComponent).tag(root) }
                        }.labelsHidden().frame(maxWidth: 170)
                    }
                }
                if storage.events.isEmpty {
                    Text("Add a folder to record its baseline. Later scans show what grew or disappeared.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(storage.events.reversed().filter { selectedRoot.isEmpty || $0.root == selectedRoot }) { event in
                    StorageEventView(event: event)
                }
                Divider()
                Toggle("Storage notifications", isOn: Binding(get: { storage.notificationsEnabled }, set: { $0 ? storage.enableNotifications() : storage.disableNotifications() }))
                Text("While running: disk space every minute, folder scans every 30 minutes. Alerts for a 5 GB drop between samples or less than 20 GB free. Up to one notification per hour.").font(.caption2).foregroundStyle(.secondary)
                Text("Read-only metadata scans. Up to 8 folders, 25,000 entries and 2 minutes per folder. Cloud-only directories, links, and other volumes are skipped. Incomplete scans keep the previous baseline. Folder totals estimate allocated bytes; APFS clones and hard links can share blocks. They are not exact reclaimable space.").font(.caption2).foregroundStyle(.secondary)
                Text("History stays on this Mac: up to 120 folder scans and 1,440 disk samples. No file contents are stored. Removed watches also remove their local history.").font(.caption2).foregroundStyle(.secondary)
            }.padding(16)
        }.onChange(of: storage.roots) { _, roots in if !roots.contains(selectedRoot) { selectedRoot = "" } }
    }
}

struct StorageSummaryView: View {
    @ObservedObject var storage: StorageTracker
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Storage Tracker", systemImage: "internaldrive").font(.headline)
                Spacer()
                if let sample = storage.latestCapacity { Text(storageBytes(sample.free) + " free").font(.headline.monospacedDigit()) }
            }
            if let sample = storage.latestCapacity {
                ProgressView(value: Double(sample.total - sample.free), total: Double(sample.total))
                Text("\(storageBytes(sample.total - sample.free)) used of \(storageBytes(sample.total)) · startup disk")
                    .font(.caption2).foregroundStyle(.secondary)
            } else { Text("Waiting for the first disk sample…").font(.caption).foregroundStyle(.secondary) }
            if let alert = storage.alert { Label(alert, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
        }
    }
}

private struct StorageEventView: View {
    let event: StorageEvent
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(event.root).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                if let since = event.since {
                    Text("Compared with \(since.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                    Text("\(event.added) added · \(event.removed) removed · \(event.modified) changed").font(.caption)
                    if !event.folders.isEmpty {
                        Text("Largest folder changes").font(.caption.bold())
                        ForEach(event.folders) { change in changeRow(change, reveal: false) }
                    }
                    if !event.changes.isEmpty {
                        Text("Largest file changes").font(.caption.bold())
                        ForEach(event.changes) { change in changeRow(change, reveal: true) }
                    }
                    if event.changes.isEmpty { Text("No allocated-size changes.").font(.caption).foregroundStyle(.secondary) }
                } else if event.issues.isEmpty {
                    Text("Baseline recorded. Changes appear after the next scan.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(event.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }.padding(.top, 6)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(URL(fileURLWithPath: event.root).lastPathComponent).lineLimit(1)
                    Spacer()
                    Text(event.delta.map(storageDelta) ?? (event.issues.isEmpty ? "Baseline" : "Incomplete"))
                        .foregroundStyle((event.delta ?? 0) > 0 ? Color.orange : Color.secondary).monospacedDigit()
                }.font(.subheadline)
                Text(event.date.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
    private func changeRow(_ change: StorageChange, reveal: Bool) -> some View {
        HStack(alignment: .top) {
            Text(change.path).lineLimit(2).truncationMode(.middle).help(change.path).textSelection(.enabled)
            Spacer()
            Text(storageDelta(change.delta)).monospacedDigit().foregroundStyle(change.delta > 0 ? Color.orange : Color.secondary)
            if reveal && change.delta > 0 {
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: event.root).appendingPathComponent(change.path)]) } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(.borderless).help("Reveal in Finder")
            }
        }.font(.caption2)
    }
}
