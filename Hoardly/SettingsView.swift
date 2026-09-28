import SwiftUI

/// U6. Keys and defaults live in `DownloadManager.defaults`.
struct SettingsView: View {
    let bridge: LocalBridge

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            BrowserSettings(bridge: bridge).tabItem { Label("Browsers", systemImage: "globe") }
        }
        .frame(width: 500)
    }
}

private struct GeneralSettings: View {
    @AppStorage("downloadDirectory") private var directory = URL.downloadsDirectory.path
    @AppStorage("organizeByCategory") private var organize = true
    @AppStorage("maxConcurrent") private var maxConcurrent = 3
    @AppStorage("connections") private var connections = 8

    var body: some View {
        Form {
            LabeledContent("Download folder") {
                HStack {
                    Text(directory).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url { directory = url.path }
                    }
                }
            }
            Toggle("Sort into category folders (Video, Music, Archives…)", isOn: $organize)
            Stepper("Simultaneous downloads: \(maxConcurrent)", value: $maxConcurrent, in: 1...10)
            Stepper("Connections per download: \(connections)", value: $connections, in: 1...32)
        }
        .formStyle(.grouped)
    }
}

private struct BrowserSettings: View {
    let bridge: LocalBridge
    @AppStorage("confirmBrowserDownloads") private var confirm = true

    var body: some View {
        Form {
            Toggle("Ask before starting downloads sent from the browser", isOn: $confirm)
            LabeledContent("Pairing token") {
                HStack {
                    Text(bridge.token).monospaced().textSelection(.enabled)
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bridge.token, forType: .string)
                    }
                }
            }
            LabeledContent("Status", value: bridge.status)
            Text("Paste the token into the Hoardly extension's settings in Safari, Chrome, Helium or Firefox.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
