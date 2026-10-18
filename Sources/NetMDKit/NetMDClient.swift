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

/// A NetMD device, driven by netmd-js in JavaScriptCore on a thread of its own. The JSContext
/// is only touched there, so a busy main thread can't stall a transfer (FIELD-NOTES).
public final class NetMDClient: @unchecked Sendable {
    private let thread = JSThread()
    private var runtime: NetMDRuntime!   // touched only on `thread`

    public init() async throws {
        runtime = try await withCheckedThrowingContinuation { continuation in
            thread.perform { continuation.resume(with: Result { try NetMDRuntime() }) }
        }
    }

    /// Opens the first attached NetMD device. Returns its name, or nil if none is attached.
    public func connect() async throws -> String? {
        try await call("connect") { $0.isNull ? nil : $0.toString() }
    }

    /// The inserted disc, or nil if the unit is empty.
    public func disc() async throws -> Disc? {
        try await call("disc") { d in
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
    }

    /// SoC and firmware, e.g. "S1.400": what netmd-exploits keys its features on.
    public func deviceCode() async throws -> String { try await call("deviceCode") { $0.toString() } }

    public func renameDisc(_ title: String) async throws { try await send("renameDisc", title) }
    public func renameTrack(_ index: Int, to title: String) async throws { try await send("renameTrack", index, title) }
    public func eraseTrack(_ index: Int) async throws { try await send("eraseTrack", index) }
    public func eraseDisc() async throws { try await send("eraseDisc") }
    public func close() async { try? await send("close") }

    /// Uploads tracks in one session. `progress(track, sent, total)` reports bytes sent; once a
    /// track's bytes are all sent the unit spends a while saving it before the next one starts.
    /// `progress` is called on the client's thread.
    public func upload(_ tracks: [UploadTrack], progress: @escaping @Sendable (Int, Int, Int) -> Void) async throws {
        let report: @convention(block) (Int, Int, Int) -> Void = { progress($0, $1, $2) }
        try await evaluate("upload", makeArgs: { runtime in
            let items = JSValue(newArrayIn: runtime.context)!
            for (n, t) in tracks.enumerated() {
                let item = JSValue(newObjectIn: runtime.context)!
                item.setObject(t.title, forKeyedSubscript: "title" as NSString)
                item.setObject(t.format.rawValue, forKeyedSubscript: "format" as NSString)
                item.setObject(runtime.makeUint8Array(t.data), forKeyedSubscript: "data" as NSString)
                items.setObject(item, atIndexedSubscript: n)
            }
            return [items, JSValue(object: report, in: runtime.context)!]
        }) { _ in () }
    }

    private func send(_ name: String, _ args: Any...) async throws {
        try await evaluate(name, makeArgs: { _ in args }) { _ in () }
    }

    private func call<T>(_ name: String, _ args: Any..., result: @escaping (JSValue) -> T) async throws -> T {
        try await evaluate(name, makeArgs: { _ in args }, result: result)
    }

    /// Calls `netmdHost[name](...args)` on the JS thread, awaits the Promise it returns, and
    /// converts the result there: JSValues never leave that thread.
    private func evaluate<T>(_ name: String, makeArgs: @escaping (NetMDRuntime) -> [Any], result: @escaping (JSValue) -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            thread.perform { [self] in
                let context = runtime.context
                let resolve: @convention(block) (JSValue) -> Void = { continuation.resume(returning: result($0)) }
                let reject: @convention(block) (JSValue) -> Void = { error in
                    continuation.resume(throwing: NetMDError(description: error.forProperty("message")?.toString() ?? error.toString()))
                }
                let host = context.objectForKeyedSubscript("netmdHost")!
                let promise = host.invokeMethod(name, withArguments: makeArgs(runtime))!
                promise.invokeMethod("then", withArguments: [JSValue(object: resolve, in: context)!, JSValue(object: reject, in: context)!])
            }
        }
    }
}

/// A thread that runs its run loop forever, for the JSContext and the timers and USB
/// completions netmd-js waits on.
private final class JSThread: Thread {
    private var runLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)

    override init() {
        super.init()
        name = "NetMDKit.js"
        qualityOfService = .userInitiated
        start()
        ready.wait()
    }

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        // A run loop with no sources returns at once; a port keeps this one alive.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        ready.signal()
        while true { RunLoop.current.run(mode: .default, before: .distantFuture) }
    }

    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}
