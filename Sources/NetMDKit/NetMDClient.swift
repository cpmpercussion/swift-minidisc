import Foundation
import JavaScriptCore

public struct Disc: Sendable, Equatable {
    public var title: String
    public var fullWidthTitle: String
    public var tracks: [Track]
    public var remaining: TimeInterval   // in SP time; LP2 holds twice this, LP4 four times
    public var total: TimeInterval
    public var isWritable: Bool
    public var hasGroups: Bool

    public var displayTitle: String { fullWidthTitle.isEmpty ? title : fullWidthTitle }
}

public struct Track: Sendable, Equatable, Identifiable {
    public var index: Int
    public var title: String
    public var fullWidthTitle: String
    public var encoding: String          // "sp", "lp2", "lp4"
    public var duration: TimeInterval
    public var group: String

    public var id: Int { index }
    public var displayTitle: String { fullWidthTitle.isEmpty ? title : fullWidthTitle }
}

public enum UploadFormat: String, Sendable, CaseIterable {
    case sp, lp2, lp4
}

public struct UploadTrack: Sendable {
    public var title: String
    public var format: UploadFormat
    public var data: Data   // SP: 16-bit big-endian stereo PCM. LP2/LP4: raw ATRAC3 frames.

    public init(title: String, format: UploadFormat, data: Data) {
        self.title = title
        self.format = format
        self.data = data
    }
}

public struct NetMDError: Error, CustomStringConvertible {
    public let description: String
}

/// A NetMD device, driven by netmd-js in JavaScriptCore. Main-actor only, like the JSContext.
@MainActor
public final class NetMDClient {
    private let runtime: NetMDRuntime
    private var host: JSValue { runtime.context.objectForKeyedSubscript("netmdHost") }

    public init() throws {
        runtime = try NetMDRuntime()
    }

    /// Opens the first attached NetMD device. Returns its name, or nil if none is attached.
    public func connect() async throws -> String? {
        let name = try await call("connect")
        return name.isNull ? nil : name.toString()
    }

    /// The inserted disc, or nil if the unit is empty.
    public func disc() async throws -> Disc? {
        let d = try await call("disc")
        if d.isNull { return nil }
        let frames = { (v: JSValue) in v.toDouble() / 512 }   // netmd-js counts 1/512 s frames
        let tracks = (d.forProperty("tracks").toArray() ?? []).indices.map { i in
            let t = d.forProperty("tracks").atIndex(i)!
            return Track(index: Int(t.forProperty("index").toInt32()), title: t.forProperty("title").toString(),
                         fullWidthTitle: t.forProperty("fullWidthTitle").toString(), encoding: t.forProperty("encoding").toString(),
                         duration: frames(t.forProperty("frames")), group: t.forProperty("group").toString())
        }
        return Disc(title: d.forProperty("title").toString(), fullWidthTitle: d.forProperty("fullWidthTitle").toString(),
                    tracks: tracks, remaining: frames(d.forProperty("left")), total: frames(d.forProperty("total")),
                    isWritable: d.forProperty("writable").toBool(), hasGroups: d.forProperty("hasGroups").toBool())
    }

    /// SoC and firmware, e.g. "S1.400": what netmd-exploits keys its features on.
    public func deviceCode() async throws -> String { try await call("deviceCode").toString() }

    public func renameDisc(_ title: String) async throws { _ = try await call("renameDisc", title) }
    public func renameTrack(_ index: Int, to title: String) async throws { _ = try await call("renameTrack", index, title) }
    public func eraseTrack(_ index: Int) async throws { _ = try await call("eraseTrack", index) }
    public func close() async { _ = try? await call("close") }

    /// Uploads tracks in one session. `progress(track, sent, total)` reports bytes sent; once a
    /// track's bytes are all sent the unit spends a while saving it before the next one starts.
    public func upload(_ tracks: [UploadTrack], progress: @escaping (Int, Int, Int) -> Void) async throws {
        let items = JSValue(newArrayIn: runtime.context)!
        for (n, t) in tracks.enumerated() {
            let item = JSValue(newObjectIn: runtime.context)!
            item.setObject(t.title, forKeyedSubscript: "title" as NSString)
            item.setObject(t.format.rawValue, forKeyedSubscript: "format" as NSString)
            item.setObject(runtime.makeUint8Array(t.data), forKeyedSubscript: "data" as NSString)
            items.setObject(item, atIndexedSubscript: n)
        }
        let report: @convention(block) (Int, Int, Int) -> Void = { progress($0, $1, $2) }
        _ = try await call("upload", items, JSValue(object: report, in: runtime.context)!)
    }

    /// Calls `netmdHost[name](...args)` and awaits the Promise it returns.
    private func call(_ name: String, _ args: Any...) async throws -> JSValue {
        let context = runtime.context
        return try await withCheckedThrowingContinuation { continuation in
            let resolve: @convention(block) (JSValue) -> Void = { continuation.resume(returning: $0) }
            let reject: @convention(block) (JSValue) -> Void = { error in
                continuation.resume(throwing: NetMDError(description: error.forProperty("message")?.toString() ?? error.toString()))
            }
            let promise = host.invokeMethod(name, withArguments: args)!
            promise.invokeMethod("then", withArguments: [JSValue(object: resolve, in: context)!, JSValue(object: reject, in: context)!])
        }
    }
}
