import AppKit
import SwiftUI
import UserNotifications

/// U5: "Download complete/failed" banners; clicking one reveals the file (handled in AppDelegate).
enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(_ download: Download) {
        let content = UNMutableNotificationContent()
        switch download.state {
        case .completed:
            content.title = String(localized: "Download complete")
            content.body = download.displayName
        case .failed(let message):
            content.title = String(localized: "Download failed")
            content.body = "\(download.displayName)\n\(message)"
        default:
            return
        }
        content.sound = .default
        if let file = download.fileURL { content.userInfo = ["path": file.path] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: download.id.uuidString, content: content, trigger: nil))
    }
}

/// U4: overall progress bar and active count on the Dock icon.
enum DockProgress {
    static func update(_ downloads: [Download]) {
        let tile = NSApp.dockTile
        let running = downloads.filter { $0.state == .running }
        tile.badgeLabel = running.isEmpty ? nil : "\(running.count)"
        let sized = running.compactMap { d in d.totalBytes.map { (received: d.received, total: $0) } }
        let total = sized.reduce(0) { $0 + $1.total }
        if total > 0 {
            let view = NSHostingView(rootView: DockTileView(progress: Double(sized.reduce(0) { $0 + $1.received }) / Double(total)))
            view.frame = NSRect(origin: .zero, size: tile.size)
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.display()
    }
}

private struct DockTileView: View {
    let progress: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(nsImage: NSApp.applicationIconImage).resizable()
            // Shapes rather than ProgressView: the Dock snapshots this view, and AppKit-backed controls don't draw there.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.55))
                    Capsule().fill(.white).frame(width: max(geo.size.height, geo.size.width * progress))
                        .padding(2)
                }
            }
            .frame(height: 14)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !DownloadManager.isTesting else { return }
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestAuthorization()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo["path"] as? String else { return }
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)]) }
    }
}
