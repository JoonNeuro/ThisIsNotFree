import AppKit
import Foundation
import UserNotifications

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]
    init?(_ text: String) {
        let raw = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let components = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }
        var numbers: [Int] = []
        for component in components {
            guard !component.isEmpty, component.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(component) else { return nil }
            numbers.append(number)
        }
        parts = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct GitHubRelease: Decodable {
    let tag_name: String
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    var trustedURL: URL? {
        guard html_url.scheme == "https", html_url.host == "github.com",
              html_url.path.hasPrefix("/JoonNeuro/ThisIsNotFree/releases/") else { return nil }
        return html_url
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var checking = false
    @Published private(set) var release: GitHubRelease?
    @Published private(set) var message = "Updates are checked against GitHub releases."
    @Published private(set) var checkedAt: Date?
    @Published private(set) var notificationsEnabled = false
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var requestID: UUID?
    private let center = UNUserNotificationCenter.current()

    func start() {
        guard timer == nil else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        Task { notificationsEnabled = await center.notificationSettings().authorizationStatus == .authorized }
    }
    func stop() { timer?.invalidate(); timer = nil; requestID = nil; task?.cancel(); task = nil; checking = false }
    deinit { timer?.invalidate(); task?.cancel() }
    func enableNotifications() {
        Task {
            do { notificationsEnabled = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { message = "Notification permission could not be requested." }
        }
    }
    func check() {
        guard !checking else { return }
        checking = true
        let id = UUID()
        requestID = id
        task = Task { [weak self] in
            guard let self else { return }
            defer { if requestID == id { checking = false; task = nil } }
            do {
                let url = URL(string: "https://api.github.com/repos/JoonNeuro/ThisIsNotFree/releases/latest")!
                var request = URLRequest(url: url, timeoutInterval: 15)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("ThisIsNotFree/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                checkedAt = Date()
                if response.statusCode == 404 { release = nil; message = "No published release yet."; return }
                guard response.statusCode == 200 else {
                    message = response.statusCode == 403 || response.statusCode == 429 ? "GitHub's rate limit was reached. Try again later." : "GitHub returned HTTP \(response.statusCode)."
                    return
                }
                let candidate = try JSONDecoder().decode(GitHubRelease.self, from: data)
                guard !candidate.draft, !candidate.prerelease, candidate.trustedURL != nil,
                      let remote = ReleaseVersion(candidate.tag_name), let local = ReleaseVersion(currentVersion) else {
                    message = "The latest release could not be verified."; return
                }
                if remote > local {
                    release = candidate
                    message = "Version \(candidate.tag_name) is available."
                    await notify(candidate)
                } else { release = nil; message = "You're up to date." }
            } catch is CancellationError { }
            catch { if !Task.isCancelled { message = "Could not reach GitHub. You can try again later." } }
        }
    }
    func openRelease() {
        NSWorkspace.shared.open(release?.trustedURL ?? URL(string: "https://github.com/JoonNeuro/ThisIsNotFree/releases")!)
    }
    private func notify(_ release: GitHubRelease) async {
        guard UserDefaults.standard.string(forKey: "updates.lastNotified") != release.tag_name,
              await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "This Is Not Free update"
        content.body = "\(release.tag_name) is available on GitHub. Open Updates to view the release."
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: "ThisIsNotFree.update", content: content, trigger: nil))
            UserDefaults.standard.set(release.tag_name, forKey: "updates.lastNotified")
        } catch { /* The in-app update banner remains available. */ }
    }
}
