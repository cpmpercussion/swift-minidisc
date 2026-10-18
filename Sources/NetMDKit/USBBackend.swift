import Foundation
import IOKit
import IOKit.usb
import IOUSBHost

/// A USB device as seen in the IORegistry, before it is opened.
public struct USBDeviceInfo: Sendable {
    /// IORegistry entry ID: stable for as long as the device stays attached.
    public let id: UInt64
    public let vendorId: Int
    public let productId: Int
    public let manufacturerName: String?
    public let productName: String?
    public let serialNumber: String?
}

public enum USBError: Error, CustomStringConvertible {
    case notFound(UInt64)
    case notOpen
    case interfaceNotFound(Int)
    case interfaceNotClaimed(Int)
    case ioKit(String, Error)

    public var description: String {
        switch self {
        case .notFound(let id): "USB device \(id) is no longer attached"
        case .notOpen: "USB device is not open"
        case .interfaceNotFound(let n): "USB interface \(n) not found"
        case .interfaceNotClaimed(let n): "USB interface \(n) is not claimed"
        case .ioKit(let what, let error): "\(what) failed: \(error.localizedDescription)"
        }
    }
}

/// Synchronous IOUSBHost wrappers. Call these off the main thread.
public enum USBBackend {
    public static func enumerate() -> [USBDeviceInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [USBDeviceInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            result.append(USBDeviceInfo(
                id: entryID,
                vendorId: intProperty(service, kUSBVendorID) ?? 0,
                productId: intProperty(service, kUSBProductID) ?? 0,
                manufacturerName: stringProperty(service, kUSBVendorString),
                productName: stringProperty(service, kUSBProductString),
                serialNumber: stringProperty(service, kUSBSerialNumberString)
            ))
        }
        return result
    }

    static func service(for id: UInt64) -> io_service_t? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        return service == 0 ? nil : service
    }

    static func intProperty(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }

    static func stringProperty(_ entry: io_registry_entry_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }
}

/// An opened device. Mirrors the WebUSB USBDevice operations netmd-js calls.
public final class USBDeviceHandle: @unchecked Sendable {
    public let info: USBDeviceInfo
    private let service: io_service_t
    private var device: IOUSBHostDevice?
    private var interfaces: [Int: IOUSBHostInterface] = [:]
    private var pipes: [Int: IOUSBHostPipe] = [:]

    static let timeout: TimeInterval = 5
    /// WebUSB never times out a transfer, and netmd-js relies on that: a unit may hold off
    /// bulk data for well over 5 s before it starts recording (FIELD-NOTES). 0 means no timeout.
    static let bulkOutTimeout: TimeInterval = 0
    static let trace = ProcessInfo.processInfo.environment["NETMD_TRACE"] != nil

    public init(info: USBDeviceInfo) throws {
        guard let service = USBBackend.service(for: info.id) else { throw USBError.notFound(info.id) }
        self.info = info
        self.service = service
        do {
            device = try IOUSBHostDevice(__ioService: service, options: [], queue: nil, interestHandler: nil)
        } catch {
            // macOS's composite driver may already own the device. Interface-level access
            // (all NetMD traffic) can still work, so carry on and fail later if it doesn't.
            device = nil
        }
    }

    deinit {
        close()
        IOObjectRelease(service)
    }

    public func close() {
        pipes.removeAll()
        interfaces.values.forEach { $0.destroy() }
        interfaces.removeAll()
        device?.destroy()
        device = nil
    }

    public func reset() throws {
        guard let device else { throw USBError.notOpen }
        do { try device.reset() } catch { throw USBError.ioKit("reset", error) }
    }

    public func selectConfiguration(_ value: Int) throws {
        // Like Chrome's WebUSB: if it is already in that configuration, do nothing.
        if let device, let current = device.configurationDescriptor, Int(current.pointee.bConfigurationValue) == value {
            return
        }
        guard let device else {
            // Not ours to configure; assume the system driver already set configuration 1.
            return
        }
        do { try device.__configure(withValue: value, matchInterfaces: true) } catch { throw USBError.ioKit("selectConfiguration(\(value))", error) }
    }

    public func claimInterface(_ number: Int) throws {
        if interfaces[number] != nil { return }
        guard let ifaceService = findInterfaceService(number) else { throw USBError.interfaceNotFound(number) }
        defer { IOObjectRelease(ifaceService) }
        do {
            interfaces[number] = try IOUSBHostInterface(__ioService: ifaceService, options: [], queue: nil, interestHandler: nil)
        } catch {
            throw USBError.ioKit("claimInterface(\(number))", error)
        }
    }

    public func releaseInterface(_ number: Int) {
        pipes.removeAll()
        interfaces.removeValue(forKey: number)?.destroy()
    }

    public func controlTransferIn(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, length: Int) throws -> Data {
        let buffer = NSMutableData(length: length)!
        let transferred = try control(requestType: requestType, request: request, value: value, index: index, data: buffer)
        return Data(bytes: buffer.bytes, count: transferred)
    }

    public func controlTransferOut(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, data: Data) throws -> Int {
        try control(requestType: requestType, request: request, value: value, index: index, data: NSMutableData(data: data))
    }

    public func transferIn(endpointAddress: Int, length: Int) throws -> Data {
        let buffer = NSMutableData(length: length)!
        var transferred = 0
        do {
            try pipe(endpointAddress).__sendIORequest(with: buffer, bytesTransferred: &transferred, completionTimeout: Self.timeout)
        } catch {
            throw USBError.ioKit("transferIn(0x\(String(endpointAddress, radix: 16)))", error)
        }
        return Data(bytes: buffer.bytes, count: transferred)
    }

    public func transferOut(endpointAddress: Int, data: Data) throws -> Int {
        var transferred = 0
        let started = Date()
        defer {
            if Self.trace { print(String(format: "[usb] out 0x%02x %d bytes %.1f ms", endpointAddress, data.count, Date().timeIntervalSince(started) * 1000)) }
        }
        do {
            try pipe(endpointAddress).__sendIORequest(with: NSMutableData(data: data), bytesTransferred: &transferred, completionTimeout: Self.bulkOutTimeout)
        } catch {
            throw USBError.ioKit("transferOut(0x\(String(endpointAddress, radix: 16)))", error)
        }
        return transferred
    }

    // MARK: - Private

    private func control(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, data: NSMutableData) throws -> Int {
        // Interface-recipient requests go through the claimed interface, as WebUSB requires;
        // anything else needs the device object.
        let recipientIsInterface = requestType & 0x1f == 1
        let target: IOUSBHostObject
        if recipientIsInterface {
            guard let iface = interfaces[Int(index & 0xff)] else { throw USBError.interfaceNotClaimed(Int(index & 0xff)) }
            target = iface
        } else {
            guard let device else { throw USBError.notOpen }
            target = device
        }
        let setup = IOUSBDeviceRequest(bmRequestType: requestType, bRequest: request, wValue: value, wIndex: index, wLength: UInt16(data.length))
        var transferred = 0
        let started = Date()
        defer {
            if Self.trace {
                print(String(format: "[usb] %.3f ctrl 0x%02x/0x%02x len %d -> %d, %.1f ms", started.timeIntervalSince1970.truncatingRemainder(dividingBy: 1000),
                             requestType, request, data.length, transferred, Date().timeIntervalSince(started) * 1000))
            }
        }
        do {
            try target.__send(setup, data: data, bytesTransferred: &transferred, completionTimeout: Self.timeout)
        } catch {
            throw USBError.ioKit(String(format: "control transfer 0x%02x/0x%02x", requestType, request), error)
        }
        return transferred
    }

    private func pipe(_ address: Int) throws -> IOUSBHostPipe {
        if let pipe = pipes[address] { return pipe }
        // NetMD has a single interface; find whichever claimed interface owns this endpoint.
        for iface in interfaces.values {
            if let pipe = try? iface.copyPipe(withAddress: address) {
                pipes[address] = pipe
                return pipe
            }
        }
        throw USBError.interfaceNotClaimed(-1)
    }

    private func findInterfaceService(_ number: Int) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(service, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if IOObjectConformsTo(entry, "IOUSBHostInterface") != 0,
               USBBackend.intProperty(entry, kUSBInterfaceNumber) == number {
                return entry
            }
            IOObjectRelease(entry)
        }
        return nil
    }
}
