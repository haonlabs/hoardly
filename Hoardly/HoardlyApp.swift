import SwiftUI

@main
struct HoardlyApp: App {
    @State private var manager = DownloadManager()
    @State private var bridge = LocalBridge()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager, bridge: bridge)
                .task {
                    bridge.onAdd = { manager.add($0, headers: $1) }
                    bridge.start()
                }
        }
    }
}

// ponytail: bare M1 test UI; the real window (sidebar, table, categories) is M2.
struct ContentView: View {
    let manager: DownloadManager
    let bridge: LocalBridge
    @State private var newURL = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Paste a download URL", text: $newURL).onSubmit(add)
                Button("Add", action: add)
            }
            List(manager.downloads.reversed()) { download in
                DownloadRow(download: download, speed: manager.speeds[download.id], manager: manager)
            }
            HStack {
                Text(bridge.status)
                Spacer()
                Text("Pairing token: \(bridge.token)").monospaced().textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bridge.token, forType: .string)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 640, minHeight: 400)
    }

    private func add() {
        guard let url = URL(string: newURL.trimmingCharacters(in: .whitespaces)),
              ["http", "https"].contains(url.scheme?.lowercased()) else { return }
        manager.add(url)
        newURL = ""
    }
}

struct DownloadRow: View {
    let download: Download
    let speed: Int64?
    let manager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(download.displayName).lineLimit(1).truncationMode(.middle)
                Spacer()
                switch download.state {
                case .running, .queued:
                    Button("Pause", systemImage: "pause.fill") { manager.pause(download.id) }
                case .paused, .failed:
                    Button("Resume", systemImage: "play.fill") { manager.resume(download.id) }
                case .completed:
                    Button("Show in Finder", systemImage: "magnifyingglass") {
                        if let url = manager.fileURL(download) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            if let total = download.totalBytes, total > 0 {
                ProgressView(value: Double(download.received), total: Double(total))
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var detail: String {
        let received = download.received.formatted(.byteCount(style: .file))
        let size = download.totalBytes.map { " of " + $0.formatted(.byteCount(style: .file)) } ?? ""
        switch download.state {
        case .running:
            let rate = speed.map { " · " + $0.formatted(.byteCount(style: .file)) + "/s" } ?? ""
            return "\(received)\(size)\(rate)"
        case .queued: return "Queued · \(received)\(size)"
        case .paused: return "Paused · \(received)\(size)"
        case .completed: return "Done · \(received)"
        case .failed(let message): return "Failed · \(message)"
        }
    }
}
