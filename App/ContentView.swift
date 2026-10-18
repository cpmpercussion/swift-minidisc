import NetMDKit
import SwiftUI

// The store is passed explicitly rather than through @Environment: views SwiftUI hosts
// outside the window tree (toolbar items, table cells) can be built without it (FIELD-NOTES).
struct ContentView: View {
    let store: DiscStore

    var body: some View {
        VStack(spacing: 0) {
            if let disc = store.disc {
                DiscHeader(store: store, disc: disc)
                Divider()
                TrackTable(store: store, disc: disc)
                Divider()
                BurnQueue(store: store, disc: disc)
            } else {
                ContentUnavailableView {
                    Label {
                        Text(store.isBusy ? "Connecting…" : store.deviceName.map { "No disc in \($0)" } ?? "No NetMD device")
                    } icon: {
                        // The icon's cartridge without its waveform (Design/icon/build.py).
                        Image("Cartridge")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 112)
                    }
                } description: {
                    Text(store.deviceName == nil ? "Connect a NetMD MiniDisc unit over USB." : "Insert a disc, then reload.")
                } actions: {
                    Button(store.deviceName == nil ? "Connect" : "Reload") {
                        Task { store.deviceName == nil ? await store.connect() : await store.refresh() }
                    }
                    .disabled(store.isBusy)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .toolbar {
            ToolbarItem { StatusView(store: store) }
            ToolbarItem {
                Button("Reload", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                    .disabled(store.disc == nil || store.isBusy)
            }
        }
        .alert("Something went wrong", isPresented: .constant(store.error != nil)) {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }
}

private struct DiscHeader: View {
    let store: DiscStore
    let disc: Disc
    @State private var title = ""
    @State private var confirmingErase = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TextField("Untitled disc", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.bold())
                .onSubmit { Task { await store.renameDisc(title) } }
            Spacer()
            VStack(alignment: .trailing) {
                Text(store.deviceName ?? "")
                Text(store.deviceCode ?? "").monospaced()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Button("Erase Disc…", systemImage: "trash", role: .destructive) { confirmingErase = true }
                .disabled(!disc.isWritable || disc.tracks.isEmpty || store.isBusy)
        }
        .padding()
        .confirmationDialog("Erase “\(disc.displayTitle.isEmpty ? "Untitled disc" : disc.displayTitle)”?", isPresented: $confirmingErase) {
            Button("Erase All \(disc.tracks.count) Tracks", role: .destructive) { Task { await store.eraseDisc() } }
        } message: {
            Text("Every track, the disc title and any groups will be erased. This can’t be undone.")
        }
        .onAppear { title = disc.displayTitle }
        .onChange(of: disc.displayTitle) { title = $1 }
    }
}

private struct TrackTable: View {
    let store: DiscStore
    let disc: Disc
    @State private var selection = Set<Track.ID>()
    @State private var pendingErase: [Track] = []

    var body: some View {
        Table(disc.tracks, selection: $selection) {
            TableColumn("#") { Text("\($0.index + 1)").monospacedDigit() }.width(28)
            TableColumn("Title") { track in
                TrackTitleField(store: store, track: track)
            }
            TableColumn("Mode") { Text($0.encoding.uppercased()) }.width(44)
            TableColumn("Time") { Text(Duration.seconds($0.duration).formatted(.time(pattern: .minuteSecond))).monospacedDigit() }.width(52)
        }
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            let tracks = disc.tracks.filter { ids.contains($0.id) }
            if !tracks.isEmpty {
                Button(tracks.count == 1 ? "Erase “\(tracks[0].displayTitle)”…" : "Erase \(tracks.count) Tracks…", role: .destructive) {
                    pendingErase = tracks
                }
                .disabled(!canErase)
            }
        }
        .onDeleteCommand {
            if canErase { pendingErase = disc.tracks.filter { selection.contains($0.id) } }
        }
        .confirmationDialog(eraseTitle, isPresented: Binding(get: { !pendingErase.isEmpty }, set: { if !$0 { pendingErase = [] } })) {
            Button("Erase", role: .destructive) {
                let tracks = pendingErase
                selection.subtract(tracks.map(\.id))
                Task { await store.erase(tracks) }
            }
        } message: {
            Text("This can’t be undone.")
        }
    }

    // Erasing shifts track indexes, and group ranges would need rewriting.
    private var canErase: Bool { disc.isWritable && !disc.hasGroups && !store.isBusy }

    private var eraseTitle: String {
        pendingErase.count == 1 ? "Erase “\(pendingErase[0].displayTitle)”?" : "Erase \(pendingErase.count) tracks?"
    }
}

private struct TrackTitleField: View {
    let store: DiscStore
    let track: Track
    @State private var title = ""

    var body: some View {
        TextField("", text: $title)
            .onSubmit { Task { await store.renameTrack(track, to: title) } }
            .onAppear { title = track.displayTitle }
            .onChange(of: track.displayTitle) { title = $1 }
    }
}

private struct BurnQueue: View {
    let store: DiscStore
    let disc: Disc

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 8) {
            if store.queue.isEmpty {
                Text("Drop audio files here to burn them")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                List {
                    ForEach($store.queue) { $file in
                        HStack {
                            TextField("Title", text: $file.title)
                            Spacer()
                            Text(Duration.seconds(file.duration).formatted(.time(pattern: .minuteSecond))).monospacedDigit()
                        }
                    }
                    .onMove { store.queue.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { store.queue.remove(atOffsets: $0) }
                }
                .frame(minHeight: 100, maxHeight: 180)
            }
            HStack {
                Picker("Mode", selection: $store.format) {
                    ForEach(UploadFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(store.isBusy)
                Text(capacity).font(.caption).foregroundStyle(fits ? Color.secondary : Color.red)
                Spacer()
                Button("Clear") { store.queue.removeAll() }.disabled(store.queue.isEmpty || store.isBusy)
                Button("Burn") { Task { await store.burn() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.queue.isEmpty || !fits || !disc.isWritable || store.isBusy)
            }
        }
        .padding()
        .dropDestination(for: URL.self) { urls, _ in
            Task { await store.add(urls) }
            return true
        }
    }

    private var fits: Bool { store.queuedSPTime <= disc.remaining }

    private var capacity: String {
        let free = Duration.seconds(disc.remaining).formatted(.time(pattern: .minuteSecond))
        let needed = Duration.seconds(store.queuedSPTime).formatted(.time(pattern: .minuteSecond))
        return "\(needed) of \(free) SP time free"
    }
}

private struct StatusView: View {
    let store: DiscStore

    var body: some View {
        // No indeterminate spinners: animating one in the toolbar re-lays-out the whole
        // window every frame (FIELD-NOTES).
        switch store.phase {
        case .idle: EmptyView()
        case .working(let label): Label(label, systemImage: "hourglass").labelStyle(.titleAndIcon)
        case let .uploading(n, count, fraction): ProgressView("Sending track \(n) of \(count)", value: fraction).frame(width: 180)
        case let .saving(n, count): Label("Unit is saving track \(n) of \(count)…", systemImage: "opticaldisc").labelStyle(.titleAndIcon)
        }
    }
}
