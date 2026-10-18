import ATRACKit
import AVFoundation
import NetMDKit
import Observation

/// App state: the connected device, its disc, and the files waiting to be burned.
@Observable @MainActor
final class DiscStore {
    struct QueuedFile: Identifiable {
        let id = UUID()
        let url: URL
        var title: String
        var duration: TimeInterval
    }

    enum Phase: Equatable {
        case idle, working(String), uploading(track: Int, of: Int, fraction: Double), saving(track: Int, of: Int)
    }

    private(set) var deviceName: String?
    private(set) var deviceCode: String?
    private(set) var disc: Disc?
    private(set) var phase = Phase.idle
    var queue: [QueuedFile] = []
    var format = UploadFormat.lp2
    var error: String?

    private var client: NetMDClient?

    var isBusy: Bool { phase != .idle }

    /// Queued audio in SP time, which is how the disc reports free space.
    var queuedSPTime: TimeInterval {
        let total = queue.reduce(0) { $0 + $1.duration }
        return switch format { case .sp: total; case .lp2: total / 2; case .lp4: total / 4 }
    }

    func connect() async {
        await run("Looking for a NetMD device…") {
            if client == nil { client = try await NetMDClient() }
            deviceName = try await client!.connect()
            guard deviceName != nil else { return }
            deviceCode = try? await client!.deviceCode()
            disc = try await client!.disc()
        }
    }

    func refresh() async {
        await run("Reading disc…") { disc = try await client?.disc() }
    }

    func renameDisc(_ title: String) async {
        await run("Renaming…") {
            try await client?.renameDisc(title)
            disc = try await client?.disc()
        }
    }

    func renameTrack(_ track: Track, to title: String) async {
        await run("Renaming…") {
            try await client?.renameTrack(track.index, to: title)
            disc = try await client?.disc()
        }
    }

    func erase(_ tracks: [Track]) async {
        let label = tracks.count == 1 ? tracks[0].displayTitle : "\(tracks.count) tracks"
        await run("Erasing \(label)…") {
            // Highest index first, so erasing one doesn't renumber the rest.
            for track in tracks.sorted(by: { $0.index > $1.index }) {
                try await client?.eraseTrack(track.index)
            }
            disc = try await client?.disc()
        }
    }

    func eraseDisc() async {
        await run("Erasing disc…") {
            try await client?.eraseDisc()
            disc = try await client?.disc()
        }
    }

    func add(_ urls: [URL]) async {
        for url in urls {
            let asset = AVURLAsset(url: url)
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            let metadataTitle = try? await AVMetadataItem.metadataItems(from: asset.load(.commonMetadata), filteredByIdentifier: .commonIdentifierTitle)
                .first?.load(.stringValue)
            queue.append(QueuedFile(url: url, title: metadataTitle ?? url.deletingPathExtension().lastPathComponent, duration: duration))
        }
    }

    /// Encodes the queue (LP modes gaplessly, as one album) and uploads it in one session.
    func burn() async {
        guard let client, !queue.isEmpty else { return }
        let files = queue, format = format
        await run("Encoding \(files.count) tracks…") {
            let data = try await Task.detached {
                let urls = files.map(\.url)
                return switch format {
                case .sp: try urls.map(MiniDiscEncoding.spPCM)
                case .lp2: try MiniDiscEncoding.gaplessLP(urls, mode: .lp2)
                case .lp4: try MiniDiscEncoding.gaplessLP(urls, mode: .lp4)
                }
            }.value
            let tracks = zip(files, data).map { UploadTrack(title: $0.title, format: format, data: $1) }
            let count = tracks.count
            try await client.upload(tracks) { n, sent, total in
                // Once a track's data is all sent, the unit spends a while saving it.
                let phase: Phase = sent < total ? .uploading(track: n + 1, of: count, fraction: Double(sent) / Double(total))
                                                : .saving(track: n + 1, of: count)
                // Reported on the client's JS thread; main.async keeps the updates in order.
                DispatchQueue.main.async { [weak self] in self?.phase = phase }
            }
            queue.removeAll()
            disc = try await client.disc()
        }
    }

    func disconnect() async {
        await client?.close()
        deviceName = nil
        deviceCode = nil
        disc = nil
    }

    private func run(_ label: String, _ work: () async throws -> Void) async {
        phase = .working(label)
        defer { phase = .idle }
        do { try await work() } catch { self.error = "\(error)" }
    }
}
