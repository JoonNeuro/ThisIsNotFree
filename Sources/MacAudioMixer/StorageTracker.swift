import AppKit
import Combine
import Darwin
import UserNotifications

struct StorageFile: Codable, Equatable {
    let bytes: Int64
    let modified: Int64
}

struct StorageChange: Codable, Identifiable {
    var id: String { path }
    let path: String
    let delta: Int64
}

struct StorageScan: Codable {
    let path: String
    let date: Date
    var files: [String: StorageFile]
    var issues: [String]
    var complete: Bool { issues.isEmpty }
    var bytes: Int64 { files.values.reduce(0) { $0 + $1.bytes } }
}

struct StorageEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let root: String
    let bytes: Int64
    let delta: Int64?
    let added: Int
    let removed: Int
    let modified: Int
    let changes: [StorageChange]
    let folders: [StorageChange]
    let issues: [String]
    let since: Date?

    static func comparing(_ scan: StorageScan, to previous: StorageScan?) -> StorageEvent {
        // Failed or incomplete scans must never turn inaccessible files into deletions.
        let baseline = scan.complete && previous?.complete == true && previous?.path == scan.path ? previous : nil
        var added = 0, removed = 0, modified = 0
        var changes: [StorageChange] = []
        var folders: [String: Int64] = [:]
        if let baseline {
            for (path, file) in scan.files {
                let old = baseline.files[path]
                if old == nil { added += 1 }
                else if old != file { modified += 1 }
                let delta = file.bytes - (old?.bytes ?? 0)
                if delta != 0 { changes.append(.init(path: path, delta: delta)) }
            }
            for (path, file) in baseline.files where scan.files[path] == nil {
                removed += 1
                changes.append(.init(path: path, delta: -file.bytes))
            }
            for change in changes {
                let parts = change.path.split(separator: "/")
                let parent = parts.count > 1 ? parts.dropLast().prefix(2).joined(separator: "/") : "Files at folder root"
                folders[parent, default: 0] += change.delta
            }
        }
        return .init(id: UUID(), date: scan.date, root: scan.path, bytes: scan.bytes,
                     delta: baseline.map { scan.bytes - $0.bytes }, added: added, removed: removed, modified: modified,
                     changes: Array(changes.sorted { abs($0.delta) > abs($1.delta) }.prefix(8)),
                     folders: Array(folders.map { StorageChange(path: $0.key, delta: $0.value) }.filter { $0.delta != 0 }.sorted { abs($0.delta) > abs($1.delta) }.prefix(5)),
                     issues: scan.issues, since: baseline?.date)
    }
}

// Metadata only: lstat does not read file contents or download cloud placeholders.
enum StorageScanner {
    static func scan(_ root: String, limit: Int = 25_000, cancelled: () -> Bool = { false }) -> StorageScan {
        let root = URL(fileURLWithPath: root, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
        let url = URL(fileURLWithPath: root, isDirectory: true)
        var files: [String: StorageFile] = [:]
        var issues: [String] = []
        func issue(_ text: String) { if issues.count < 4 { issues.append(text) } }
        var rootInfo = stat()
        guard lstat(root, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR else {
            return .init(path: root, date: Date(), files: [:], issues: ["Folder unavailable. Check access or choose it again."])
        }
        guard rootInfo.st_flags & UInt32(SF_DATALESS) == 0 else {
            return .init(path: root, date: Date(), files: [:], issues: ["This folder is cloud-only. Choose a locally downloaded folder."])
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in
            issue("Some folders could not be read. This scan will not replace the baseline.")
            return true
        }) else {
            return .init(path: root, date: Date(), files: [:], issues: ["Folder could not be scanned."])
        }
        var visited = 0
        let deadline = Date().addingTimeInterval(120)
        for case let item as URL in enumerator {
            visited += 1
            if cancelled() { issue("Scan cancelled."); break }
            if visited > limit || Date() > deadline { issue("Scan limit reached. Watch a smaller folder for complete history."); break }
            var info = stat()
            guard lstat(item.path, &info) == 0 else { issue("Some files changed or could not be read during the scan."); continue }
            let type = info.st_mode & S_IFMT
            if info.st_dev != rootInfo.st_dev { if type == S_IFDIR { enumerator.skipDescendants() }; continue }
            // Foundation does not descend symbolic links. skipDescendants on a link
            // can skip the next real directory instead.
            if type == S_IFLNK { continue }
            if info.st_flags & UInt32(SF_DATALESS) != 0 {
                // A cloud-only directory may have descendants; do not ask the provider to enumerate them.
                if type == S_IFDIR { enumerator.skipDescendants(); issue("Cloud-only folders skipped. Choose locally downloaded folders for complete history."); continue }
            }
            guard type == S_IFREG else { continue }
            // Enumeration URLs may use /private/var while the chosen URL uses /var.
            let relative = item.pathComponents.suffix(enumerator.level).joined(separator: "/")
            files[relative] = .init(bytes: max(0, Int64(info.st_blocks) * 512), modified: Int64(info.st_mtimespec.tv_sec) &* 1_000_000_000 &+ Int64(info.st_mtimespec.tv_nsec))
        }
        return .init(path: root, date: Date(), files: files, issues: issues)
    }
}

struct StorageCapacity: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let total: Int64
    let free: Int64
}

private struct StorageArchive: Codable {
    var roots: [String] = []
    var events: [StorageEvent] = []
    var capacity: [StorageCapacity] = []
    var baselines: [String: StorageScan] = [:]
}

@MainActor
final class StorageTracker: ObservableObject {
    @Published private(set) var roots: [String] = []
    @Published private(set) var events: [StorageEvent] = []
    @Published private(set) var capacity: [StorageCapacity] = []
    @Published private(set) var loading = false
    @Published private(set) var scanning = false
    @Published private(set) var scanningPath: String?
    @Published private(set) var message: String?
    @Published private(set) var alert: String?
    @Published private(set) var notificationsEnabled = UserDefaults.standard.bool(forKey: "storage.notifications")
    private var baselines: [String: StorageScan] = [:]
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var lastScan: Date?
    private var lastNotification: Date?
    private var loaded = false
    private var sampling = false
    private let persistence = DispatchQueue(label: "ThisIsNotFree.storage.persistence", qos: .utility)
    private let archiveURL: URL

    init(preview: Bool = false, archiveURL: URL? = nil) {
        self.archiveURL = archiveURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ThisIsNotFree/Storage/history.json")
        if archiveURL != nil { notificationsEnabled = false }
        guard preview else { return }
        let root = "/Example/Project Outputs"
        let now = Date()
        roots = [root]
        capacity = (0..<24).map { index in
            .init(date: now.addingTimeInterval(Double(index - 23) * 3600), total: 1_000_000_000_000,
                  free: 210_000_000_000 - Int64(index) * 4_000_000_000)
        }
        let first = StorageScan(path: root, date: now.addingTimeInterval(-1800), files: ["reviews/old.bin": .init(bytes: 8_000_000_000, modified: 1)], issues: [])
        let second = StorageScan(path: root, date: now, files: ["reviews/latest.bin": .init(bytes: 14_000_000_000, modified: 2)], issues: [])
        events = [.comparing(first, to: nil), .comparing(second, to: first)]
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if loaded { if !loading { tick() }; return }
        loaded = true; loading = true
        let url = archiveURL
        persistence.async { [weak self] in
            var archive = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(StorageArchive.self, from: $0) }
            if let data = try? Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent("baseline.json")),
               let baselines = try? JSONDecoder().decode([String: StorageScan].self, from: data) { archive?.baselines = baselines }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let archive {
                    self.roots = Array(archive.roots.prefix(8))
                    self.events = Array(archive.events.suffix(120))
                    self.capacity = Array(archive.capacity.suffix(1440))
                    self.baselines = archive.baselines.filter { self.roots.contains($0.key) }
                }
                self.loading = false
                if self.timer != nil { self.tick() }
            }
        }
    }
    func stop() { timer?.invalidate(); timer = nil; cancel() }
    deinit { timer?.invalidate(); task?.cancel() }

    private func tick() {
        sampleCapacity()
        if lastScan == nil || Date().timeIntervalSince(lastScan!) >= 1800 { scan() }
    }
    private func sampleCapacity() {
        guard !sampling else { return }
        sampling = true
        Task.detached(priority: .utility) { [weak self] in
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let total = (attributes?[.systemSize] as? NSNumber)?.int64Value ?? 0
            let free = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let sample = StorageCapacity(date: Date(), total: total, free: free)
            await self?.acceptCapacity(sample)
        }
    }
    private func acceptCapacity(_ sample: StorageCapacity) {
        sampling = false
        guard timer != nil, sample.total > 0 else { return }
        if let previous = capacity.last, previous.free - sample.free >= 5_000_000_000 {
            alert = "Free space fell by \(storageBytes(previous.free - sample.free)) since \(previous.date.formatted(date: .abbreviated, time: .shortened)). Scan watched folders to investigate."
            notify(alert!)
        } else if sample.free < 20_000_000_000 {
            alert = "Only \(storageBytes(sample.free)) free on your startup disk."
            notify(alert!)
        } else { alert = nil }
        capacity.append(sample)
        capacity = Array(capacity.suffix(1440))
        persist()
    }
    func scan() {
        guard !loading, !scanning, !roots.isEmpty else { return }
        scanning = true; message = nil; lastScan = Date()
        let token = UUID(); generation = token
        let paths = roots
        task = Task.detached(priority: .utility) { [weak self] in
            for path in paths {
                guard !Task.isCancelled else { break }
                await self?.setScanningPath(path, token: token)
                let scan = StorageScanner.scan(path, cancelled: { Task.isCancelled })
                guard !Task.isCancelled else { break }
                await self?.accept(scan, token: token)
            }
            await self?.finish(token)
        }
    }
    private func setScanningPath(_ path: String, token: UUID) { if generation == token { scanningPath = path } }
    private func accept(_ scan: StorageScan, token: UUID) {
        guard generation == token, roots.contains(scan.path) else { return }
        events.append(.comparing(scan, to: baselines[scan.path]))
        events = Array(events.suffix(120))
        if scan.complete { baselines[scan.path] = scan }
        persist(includeBaselines: scan.complete)
    }
    private func finish(_ token: UUID) {
        guard generation == token else { return }
        scanning = false; scanningPath = nil; task = nil
    }
    func cancel() {
        task?.cancel(); task = nil; generation = UUID(); scanning = false; scanningPath = nil
    }
    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "Watch Folder"
        panel.message = "Track local file size changes. Choose a specific folder; broad scans may hit the scan limit."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addRoot(url.resolvingSymlinksInPath().standardizedFileURL.path)
    }
    func addRoot(_ path: String) {
        guard !loading else { return }
        guard roots.count < 8 else { message = "Watch up to eight folders. Remove one before adding another."; return }
        let path = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        guard !roots.contains(where: { $0 == path || $0 == "/" || path == "/" || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) else {
            message = "This folder overlaps an existing watch. Choose a separate folder."; return
        }
        cancel(); roots.append(path); persist(); scan()
    }
    func removeRoot(_ path: String) {
        cancel(); roots.removeAll { $0 == path }; baselines.removeValue(forKey: path)
        events.removeAll { $0.root == path }; persist(includeBaselines: true)
    }
    func enableNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] allowed, _ in
            Task { @MainActor in
                self?.notificationsEnabled = allowed
                UserDefaults.standard.set(allowed, forKey: "storage.notifications")
                if !allowed { self?.message = "Allow notifications in System Settings → Notifications." }
            }
        }
    }
    func disableNotifications() { notificationsEnabled = false; UserDefaults.standard.set(false, forKey: "storage.notifications") }
    private func notify(_ text: String) {
        guard notificationsEnabled, lastNotification.map({ Date().timeIntervalSince($0) > 3600 }) ?? true else { return }
        lastNotification = Date()
        let content = UNMutableNotificationContent()
        content.title = "Storage space changed"; content.body = text
        UNUserNotificationCenter.current().add(.init(identifier: "storage-space", content: content, trigger: nil))
    }
    func waitForPendingWrites() async {
        await withCheckedContinuation { continuation in persistence.async { continuation.resume() } }
    }
    private func persist(includeBaselines: Bool = false) {
        let archive = StorageArchive(roots: roots, events: events, capacity: capacity)
        let manifests = includeBaselines ? baselines : nil
        let url = archiveURL
        persistence.async { [weak self] in
            do {
                let data = try JSONEncoder().encode(archive)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                if let manifests {
                    let baselineURL = url.deletingLastPathComponent().appendingPathComponent("baseline.json")
                    try JSONEncoder().encode(manifests).write(to: baselineURL, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: baselineURL.path)
                }
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                Task { @MainActor [weak self] in self?.message = "Storage history could not be saved. Check free space and folder access." }
            }
        }
    }
}

func storageBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal) }
func storageDelta(_ bytes: Int64) -> String { (bytes > 0 ? "+" : bytes < 0 ? "−" : "") + storageBytes(abs(bytes)) }
