import SwiftUI

/// U1: sidebar of filters and categories, table of downloads.
struct MainView: View {
    let manager: DownloadManager
    @State private var filter: Filter? = .all
    @State private var selection = Set<UUID>()
    @State private var removing = Set<UUID>()

    enum Filter: Hashable {
        case all, downloading, queued, completed, failed
        case category(Category)

        func matches(_ d: Download) -> Bool {
            switch self {
            case .all: true
            case .downloading: d.state == .running
            case .queued: d.state == .queued || d.state == .paused
            case .completed: d.state == .completed
            case .failed: if case .failed = d.state { true } else { false }
            case .category(let c): d.category == c
            }
        }
    }

    private var rows: [Download] { manager.downloads.reversed().filter { (filter ?? .all).matches($0) } }
    private var selected: [Download] { manager.downloads.filter { selection.contains($0.id) } }

    var body: some View {
        NavigationSplitView {
            List(selection: $filter) {
                Section {
                    row("All", "tray.full", .all)
                    row("Downloading", "arrow.down.circle", .downloading)
                    row("Queued & Paused", "pause.circle", .queued)
                    row("Completed", "checkmark.circle", .completed)
                    row("Failed", "exclamationmark.triangle", .failed)
                }
                Section("Categories") {
                    ForEach(Category.allCases, id: \.self) { row(LocalizedStringKey($0.rawValue), $0.symbol, .category($0)) }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            table
        }
        .toolbar { toolbar }
        .dropDestination(for: URL.self) { urls, _ in // E1: drop links from a browser
            NewDownloadPanel.show(urls.map { .init(url: $0, headers: [:]) }, manager: manager)
            return true
        }
        .confirmationDialog("Remove \(removing.count) download(s)?", isPresented: .constant(!removing.isEmpty)) {
            Button("Remove from List") { remove(trash: false) }
            if manager.downloads.contains(where: { removing.contains($0.id) && $0.state == .completed }) {
                Button("Move Files to Trash", role: .destructive) { remove(trash: true) }
            }
            Button("Cancel", role: .cancel) { removing = [] }
        } message: {
            Text("Unfinished downloads lose their partial data.")
        }
        .frame(minWidth: 760, minHeight: 420)
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String, _ value: Filter) -> some View {
        Label(title, systemImage: symbol)
            .badge(manager.downloads.filter(value.matches).count)
            .tag(value)
    }

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("Name") { d in
                Label(d.displayName, systemImage: d.category.symbol).lineLimit(1).truncationMode(.middle)
                    .help(d.url.absoluteString)
            }
            .width(min: 180, ideal: 280)
            TableColumn("Size") { d in Text((d.totalBytes ?? (d.stream != nil ? d.received : nil)).map(bytes) ?? "—").monospacedDigit() }
                .width(min: 60, ideal: 80)
            TableColumn("Progress") { d in progress(d) }
                .width(min: 100, ideal: 150)
            TableColumn("Speed") { d in Text(manager.speeds[d.id].map { bytes($0) + "/s" } ?? "").monospacedDigit() }
                .width(min: 70, ideal: 90)
            TableColumn("Time Left") { d in Text(eta(d)).monospacedDigit() }
                .width(min: 60, ideal: 80)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button("Pause") { manager.pause(ids) }
            Button("Resume") { manager.resume(ids) }
            Button("Show in Finder") { reveal(ids) }
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(manager.downloads.filter { ids.contains($0.id) }.map(\.url.absoluteString).joined(separator: "\n"), forType: .string)
            }
            Divider()
            Button("Remove…") { removing = ids }
        } primaryAction: { ids in
            for d in manager.downloads where ids.contains(d.id) {
                if let file = d.fileURL { NSWorkspace.shared.open(file) }
                else if d.state == .running || d.state == .queued { manager.pause([d.id]) }
                else { manager.resume([d.id]) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("New Download", systemImage: "plus") { NewDownloadPanel.show(manager: manager) }
            Button("Resume", systemImage: "play.fill") { manager.resume(selection) }
                .disabled(!selected.contains { $0.state == .paused || $0.state.isFailed })
            Button("Pause", systemImage: "pause.fill") { manager.pause(selection) }
                .disabled(!selected.contains { $0.state == .running || $0.state == .queued })
            Button("Show in Finder", systemImage: "magnifyingglass") { reveal(selection) }
                .disabled(!selected.contains { $0.fileURL != nil })
            Button("Remove", systemImage: "trash") { removing = selection }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selection.isEmpty)
        }
    }

    /// Bar while bytes are flowing, otherwise the state as text.
    @ViewBuilder
    private func progress(_ d: Download) -> some View {
        switch d.state {
        case .running:
            if let fraction = d.fraction {
                ProgressView(value: fraction).accessibilityValue(percent(d))
            } else {
                Text(bytes(d.received))
            }
        case .queued: Text("Queued").foregroundStyle(.secondary)
        case .paused: Text("Paused · \(percent(d))").foregroundStyle(.secondary)
        case .completed: Text("Done").foregroundStyle(.secondary)
        case .failed(let message): Text("Failed").foregroundStyle(.red).help(message)
        }
    }

    private func percent(_ d: Download) -> String {
        d.fraction?.formatted(.percent.precision(.fractionLength(0))) ?? bytes(d.received)
    }

    private func eta(_ d: Download) -> String {
        guard d.state == .running, let fraction = d.fraction, fraction > 0, let speed = manager.speeds[d.id], speed > 0 else { return "" }
        // Streams have no byte total; extrapolate from the share of segments done.
        let remaining = d.totalBytes.map { Double($0 - d.received) } ?? Double(d.received) * (1 - fraction) / fraction
        let seconds = remaining / Double(speed)
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
    }

    private func bytes(_ n: Int64) -> String { n.formatted(.byteCount(style: .file)) }

    private func reveal(_ ids: Set<UUID>) {
        let files = manager.downloads.filter { ids.contains($0.id) }.compactMap(\.fileURL)
        if !files.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(files) }
    }

    private func remove(trash: Bool) {
        manager.remove(removing, trashFiles: trash)
        selection.subtract(removing)
        removing = []
    }
}

extension Download.State {
    var isFailed: Bool { if case .failed = self { true } else { false } }
}
