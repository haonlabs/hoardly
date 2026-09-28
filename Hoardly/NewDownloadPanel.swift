import AppKit
import SwiftUI

/// U3: a floating window so it can pop over the browser, even when Hoardly's main window is closed.
enum NewDownloadPanel {
    private static var open: [NSWindow] = []

    typealias Item = LocalBridge.IncomingDownload

    static func show(_ items: [Item] = [], manager: DownloadManager) {
        let items = items.isEmpty ? clipboardURLs().map { Item(url: $0, headers: [:]) } : items
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "New Download")
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentViewController = NSHostingController(rootView: NewDownloadView(
            manager: manager, items: items, text: items.map(\.url.absoluteString).joined(separator: "\n"),
            name: items.count == 1 ? items[0].fileName ?? "" : ""
        ) { [weak window] in window?.close() })
        let id = ObjectIdentifier(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { open.removeAll { ObjectIdentifier($0) == id } }
        }
        open.append(window)
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// E1: prefill from the clipboard when it holds links.
    private static func clipboardURLs() -> [URL] {
        parse(NSPasteboard.general.string(forType: .string) ?? "")
    }

    static func parse(_ text: String) -> [URL] {
        text.split(whereSeparator: \.isWhitespace).compactMap { URL(string: String($0)) }
            .filter { ["http", "https"].contains($0.scheme?.lowercased()) && $0.host() != nil }
    }
}

private struct NewDownloadView: View {
    let manager: DownloadManager
    let items: [NewDownloadPanel.Item] // what the browser sent: cookies, referrer, suggested name per URL
    @State var text: String
    @State var name: String
    let close: () -> Void
    @State private var folder: URL? // nil: download folder + category subfolder

    private var urls: [URL] { NewDownloadPanel.parse(text) }
    private var guessedName: String { urls.first?.lastPathComponent ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            form
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                Button("Download Later") { add(start: false) }.disabled(urls.isEmpty)
                Button("Start Download") { add(start: true) }.keyboardShortcut(.defaultAction).disabled(urls.isEmpty)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 520, height: 320) // a grouped Form has no intrinsic height to size the window from
    }

    private var form: some View {
        Form {
            Section("Address") {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .frame(height: 56)
                    .accessibilityLabel("Download addresses, one per line")
            }
            Section {
                if urls.count == 1 {
                    TextField("File name", text: $name, prompt: Text(guessedName))
                } else if urls.count > 1 {
                    LabeledContent("Files", value: "\(urls.count) downloads")
                }
                LabeledContent("Save to") {
                    HStack {
                        Text(folder?.path(percentEncoded: false) ?? DownloadManager.directory(for: name.isEmpty ? guessedName : name).path(percentEncoded: false))
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
    }

    private func add(start: Bool) {
        let custom = urls.count == 1 && !name.isEmpty ? SegmentedDownload.safeName(name) : nil
        for url in urls {
            let sent = items.first { $0.url == url } // URLs typed in by hand carry no browser context
            manager.add(url, headers: sent?.headers ?? [:], fileName: custom ?? sent?.fileName, directory: folder, start: start)
        }
        close()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK { folder = panel.url }
    }
}
