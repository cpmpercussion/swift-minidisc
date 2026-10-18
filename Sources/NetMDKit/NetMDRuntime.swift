import Foundation
import JavaScriptCore

/// Hosts the bundled netmd-js + netmd-exploits in a JSContext.
///
/// All JavaScript runs on the thread that creates the runtime, which must run its run loop
/// (JSC finishes WebAssembly loading through it). USB I/O runs on `usbQueue` and settles its
/// Promise back on that thread, so netmd-js sees an ordinary async WebUSB. The app gives the
/// runtime a thread of its own, so UI work can't stall a transfer (FIELD-NOTES).
public final class NetMDRuntime {
    public let context: JSContext
    private let runLoop: CFRunLoop
    private let usbQueue = DispatchQueue(label: "NetMDKit.usb")
    private var handles: [UInt64: USBDeviceHandle] = [:] // touched only on usbQueue
    private var timers: [Int: Timer] = [:]
    private var nextTimerID = 1
    public var log: (String) -> Void = { print($0) }

    public init() throws {
        runLoop = CFRunLoopGetCurrent()
        context = JSContext()!
        context.name = "netmd-js"
        context.exceptionHandler = { [weak self] _, exception in
            let stack = exception?.forProperty("stack")?.toString() ?? ""
            self?.log("JS exception: \(exception?.toString() ?? "?")\n\(stack)")
        }

        installConsole()
        installTimers()
        installCrypto()
        installUSBHost()

        try evaluateResource("netmd-bundle", "js")
        try evaluateResource("webusb-shim", "js")
        try evaluateResource("netmd-host", "js")

        // netmd-exploits assembles ARM payloads with keystone compiled to WebAssembly.
        let wasm = try Data(contentsOf: try resourceURL("assembler", "wasm"))
        let buffer = makeUint8Array(wasm).forProperty("buffer")!
        context.evaluateScript("NetMDBundle.exploits.Assembler").invokeMethod("setWASMArrayBuffer", withArguments: [buffer])
    }

    @discardableResult
    public func evaluate(_ script: String, sourceName: String = "host.js") -> JSValue? {
        context.evaluateScript(script, withSourceURL: URL(string: sourceName))
    }

    // MARK: - Resources

    private func resourceURL(_ name: String, _ ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).\(ext) (run `npm run build`)"])
        }
        return url
    }

    private func evaluateResource(_ name: String, _ ext: String) throws {
        let url = try resourceURL(name, ext)
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8), withSourceURL: url)
        if let exception = context.exception {
            context.exception = nil
            throw NSError(domain: "NetMDKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Loading \(name).\(ext): \(exception)"])
        }
    }

    // MARK: - Web API polyfills that need the host

    private func installConsole() {
        let console = JSValue(newObjectIn: context)!
        for level in ["log", "info", "warn", "error", "debug", "trace"] {
            let fn: @convention(block) () -> Void = { [weak self] in
                guard let self else { return }
                let args = (JSContext.currentArguments() as? [JSValue]) ?? []
                self.log((level == "log" ? "" : "[\(level)] ") + args.map(self.describe).joined(separator: " "))
            }
            console.setObject(fn, forKeyedSubscript: level as NSString)
        }
        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private func describe(_ value: JSValue) -> String {
        if value.isObject, !value.isInstance(of: context.objectForKeyedSubscript("Error")),
           let json = context.objectForKeyedSubscript("JSON").invokeMethod("stringify", withArguments: [value]), json.isString {
            return json.toString()
        }
        return value.toString()
    }

    private func installTimers() {
        let setTimeout: @convention(block) (JSValue, JSValue) -> Int = { [weak self] callback, delay in
            guard let self else { return 0 }
            let extra = Array(((JSContext.currentArguments() as? [JSValue]) ?? []).dropFirst(2))
            let id = self.nextTimerID
            self.nextTimerID += 1
            let ms = delay.isNumber ? max(0, delay.toDouble()) : 0
            let timer = Timer(timeInterval: ms / 1000, repeats: false) { [weak self] _ in
                self?.timers.removeValue(forKey: id)
                callback.call(withArguments: extra)
            }
            self.timers[id] = timer
            CFRunLoopAddTimer(self.runLoop, timer, .commonModes)
            return id
        }
        let clearTimeout: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timers.removeValue(forKey: id)?.invalidate()
        }
        context.setObject(setTimeout, forKeyedSubscript: "setTimeout" as NSString)
        context.setObject(clearTimeout, forKeyedSubscript: "clearTimeout" as NSString)
    }

    private func installCrypto() {
        let getRandomValues: @convention(block) (JSValue) -> JSValue = { [weak self] array in
            guard let self else { return array }
            let ctx = self.context.jsGlobalContextRef
            if let object = JSValueToObject(ctx, array.jsValueRef, nil),
               let bytes = JSObjectGetTypedArrayBytesPtr(ctx, object, nil) {
                arc4random_buf(bytes, JSObjectGetTypedArrayByteLength(ctx, object, nil))
            }
            return array
        }
        let crypto = JSValue(newObjectIn: context)!
        crypto.setObject(getRandomValues, forKeyedSubscript: "getRandomValues" as NSString)
        context.setObject(crypto, forKeyedSubscript: "crypto" as NSString)
    }

    // MARK: - USB host object (used by webusb-shim.js)

    private func installUSBHost() {
        let host = JSValue(newObjectIn: context)!

        let list: @convention(block) () -> [[String: Any]] = {
            USBBackend.enumerate().map { d in
                [
                    "id": NSNumber(value: d.id).stringValue, // > 2^53, so pass as a string
                    "vendorId": d.vendorId,
                    "productId": d.productId,
                    "manufacturerName": d.manufacturerName ?? "",
                    "productName": d.productName ?? "",
                    "serialNumber": d.serialNumber ?? "",
                ]
            }
        }
        host.setObject(list, forKeyedSubscript: "list" as NSString)

        func define(_ name: String, _ body: @escaping ([JSValue]) -> (USBDeviceHandle?) throws -> Any?) {
            let fn: @convention(block) () -> JSValue = { [unowned self] in
                let args = (JSContext.currentArguments() as? [JSValue]) ?? []
                return self.promise(deviceID: args.first?.toString() ?? "", work: body(Array(args.dropFirst())))
            }
            host.setObject(fn, forKeyedSubscript: name as NSString)
        }

        // `open` is special: it creates the handle.
        let open: @convention(block) (String) -> JSValue = { [unowned self] id in
            self.promise(deviceID: id) { [unowned self] existing in
                if existing != nil { return nil }
                guard let numericID = UInt64(id), let info = USBBackend.enumerate().first(where: { $0.id == numericID }) else {
                    throw USBError.notFound(UInt64(id) ?? 0)
                }
                self.handles[numericID] = try USBDeviceHandle(info: info)
                return nil
            }
        }
        host.setObject(open, forKeyedSubscript: "open" as NSString)

        define("close") { _ in { [unowned self] handle in
            handle?.close()
            if let handle { self.handles.removeValue(forKey: handle.info.id) }
            return nil
        } }
        define("reset") { _ in { try Self.require($0).reset(); return nil } }
        define("selectConfiguration") { args in
            let value = Int(args[0].toInt32())
            return { try Self.require($0).selectConfiguration(value); return nil }
        }
        define("claimInterface") { args in
            let number = Int(args[0].toInt32())
            return { try Self.require($0).claimInterface(number); return nil }
        }
        define("releaseInterface") { args in
            let number = Int(args[0].toInt32())
            return { try Self.require($0).releaseInterface(number); return nil }
        }
        define("controlTransferIn") { args in
            let (type, request, value, index, length) = (UInt8(args[0].toUInt32()), UInt8(args[1].toUInt32()), UInt16(args[2].toUInt32()), UInt16(args[3].toUInt32()), Int(args[4].toUInt32()))
            return { try Self.require($0).controlTransferIn(requestType: type, request: request, value: value, index: index, length: length) }
        }
        define("controlTransferOut") { [unowned self] args in
            let (type, request, value, index) = (UInt8(args[0].toUInt32()), UInt8(args[1].toUInt32()), UInt16(args[2].toUInt32()), UInt16(args[3].toUInt32()))
            let data = self.bytes(of: args[4])
            return { try Self.require($0).controlTransferOut(requestType: type, request: request, value: value, index: index, data: data) }
        }
        define("transferIn") { args in
            let (endpoint, length) = (Int(args[0].toUInt32()), Int(args[1].toUInt32()))
            return { try Self.require($0).transferIn(endpointAddress: endpoint, length: length) }
        }
        define("transferOut") { [unowned self] args in
            let endpoint = Int(args[0].toUInt32())
            let data = self.bytes(of: args[1])
            return { try Self.require($0).transferOut(endpointAddress: endpoint, data: data) }
        }

        context.setObject(host, forKeyedSubscript: "__usbHost" as NSString)
    }

    private static func require(_ handle: USBDeviceHandle?) throws -> USBDeviceHandle {
        guard let handle else { throw USBError.notOpen }
        return handle
    }

    /// Runs `block` on the runtime's thread, the only one that may touch `context`.
    public func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    /// Runs `work` on the USB queue against the device's handle, then settles a JS Promise
    /// on the runtime's thread.
    private func promise(deviceID: String, work: @escaping (USBDeviceHandle?) throws -> Any?) -> JSValue {
        JSValue(newPromiseIn: context) { [unowned self] resolve, reject in
            self.usbQueue.async { [unowned self] in
                let outcome = Result { try work(UInt64(deviceID).flatMap { self.handles[$0] }) }
                self.perform { [unowned self] in
                    switch outcome {
                    case .success(let value as Data):
                        resolve?.call(withArguments: [self.makeUint8Array(value)])
                    case .success(let value):
                        resolve?.call(withArguments: value.map { [$0] } ?? [])
                    case .failure(let error):
                        let jsError = JSValue(newErrorFromMessage: "\(error)", in: self.context)!
                        jsError.setObject("NetworkError", forKeyedSubscript: "name" as NSString)
                        reject?.call(withArguments: [jsError])
                    }
                }
            }
        }
    }

    // MARK: - Typed array bridging (JSC C API, avoids per-byte conversion)

    public func makeUint8Array(_ data: Data) -> JSValue {
        let ctx = context.jsGlobalContextRef
        let object = JSObjectMakeTypedArray(ctx, kJSTypedArrayTypeUint8Array, data.count, nil)!
        if !data.isEmpty, let bytes = JSObjectGetTypedArrayBytesPtr(ctx, object, nil) {
            data.copyBytes(to: bytes.assumingMemoryBound(to: UInt8.self), count: data.count)
        }
        return JSValue(jsValueRef: object, in: context)
    }

    /// Expects a zero-offset Uint8Array (webusb-shim.js copies BufferSources into one).
    func bytes(of value: JSValue) -> Data {
        let ctx = context.jsGlobalContextRef
        guard let object = JSValueToObject(ctx, value.jsValueRef, nil),
              let pointer = JSObjectGetTypedArrayBytesPtr(ctx, object, nil) else { return Data() }
        return Data(bytes: pointer, count: JSObjectGetTypedArrayByteLength(ctx, object, nil))
    }
}
