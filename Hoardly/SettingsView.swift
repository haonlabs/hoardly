import ServiceManagement
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
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            // B6: extensions can only hand downloads to a running app; otherwise the browser keeps them.
            Toggle("Open Hoardly at login", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { _, on in
                    do {
                        try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
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
    @AppStorage("interceptExtensions") private var extensions = ""
    @AppStorage("interceptMinSizeMB") private var minSizeMB = 0

    var body: some View {
        Form {
            Section {
                TextField("Take over files of type", text: $extensions, axis: .vertical)
                    .lineLimit(2...4)
                Stepper(minSizeMB == 0 ? "…and any file: off" : "…and any file over \(minSizeMB) MB",
                        value: $minSizeMB, in: 0...10_000, step: 10)
                Text("Hold ⌥ Option while clicking a link to let the browser download it instead.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Browser downloads")
            }
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
