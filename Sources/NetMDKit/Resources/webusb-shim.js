// A WebUSB-shaped `navigator.usb` over the Swift host object `__usbHost`.
// Only the surface netmd-js / netmd-exploits use is implemented.
// Every __usbHost method that touches hardware returns a Promise settled by Swift.
(function () {
    'use strict';
    const host = globalThis.__usbHost;

    const REQUEST_TYPES = { standard: 0, class: 1, vendor: 2 };
    const RECIPIENTS = { device: 0, interface: 1, endpoint: 2, other: 3 };

    function bmRequestType(setup, directionIn) {
        const type = REQUEST_TYPES[setup.requestType];
        const recipient = RECIPIENTS[setup.recipient];
        if (type === undefined || recipient === undefined) {
            throw new TypeError(`Unsupported control setup ${setup.requestType}/${setup.recipient}`);
        }
        return (directionIn ? 0x80 : 0x00) | (type << 5) | recipient;
    }

    // Copy any BufferSource into a fresh, zero-offset Uint8Array so Swift can read it directly.
    function toBytes(data) {
        if (data === undefined || data === null) return new Uint8Array(0);
        if (data instanceof ArrayBuffer) return new Uint8Array(data.slice(0));
        if (ArrayBuffer.isView(data)) return new Uint8Array(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
        throw new TypeError('Expected a BufferSource');
    }

    function inResult(bytes) {
        return { status: 'ok', data: new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength) };
    }

    class USBDevice {
        constructor(info) {
            this._id = info.id;
            this.vendorId = info.vendorId;
            this.productId = info.productId;
            this.manufacturerName = info.manufacturerName || undefined;
            this.productName = info.productName || undefined;
            this.serialNumber = info.serialNumber || undefined;
            this.opened = false;
        }

        async open() {
            await host.open(this._id);
            this.opened = true;
        }

        async close() {
            await host.close(this._id);
            this.opened = false;
        }

        async reset() {
            await host.reset(this._id);
        }

        async selectConfiguration(value) {
            await host.selectConfiguration(this._id, value);
        }

        async claimInterface(number) {
            await host.claimInterface(this._id, number);
        }

        async releaseInterface(number) {
            await host.releaseInterface(this._id, number);
        }

        async controlTransferIn(setup, length) {
            const bytes = await host.controlTransferIn(this._id, bmRequestType(setup, true), setup.request, setup.value, setup.index, length);
            return inResult(bytes);
        }

        async controlTransferOut(setup, data) {
            const bytesWritten = await host.controlTransferOut(this._id, bmRequestType(setup, false), setup.request, setup.value, setup.index, toBytes(data));
            return { status: 'ok', bytesWritten };
        }

        // WebUSB takes an endpoint *number*; the direction is implied by the method.
        async transferIn(endpointNumber, length) {
            const bytes = await host.transferIn(this._id, 0x80 | endpointNumber, length);
            return inResult(bytes);
        }

        async transferOut(endpointNumber, data) {
            const bytesWritten = await host.transferOut(this._id, endpointNumber & 0x7f, toBytes(data));
            return { status: 'ok', bytesWritten };
        }
    }

    const devices = new Map(); // id -> USBDevice, so identity is stable across calls

    function wrap(info) {
        let device = devices.get(info.id);
        if (!device) {
            device = new USBDevice(info);
            devices.set(info.id, device);
        }
        return device;
    }

    function matches(info, filter) {
        if (filter.vendorId !== undefined && filter.vendorId !== info.vendorId) return false;
        if (filter.productId !== undefined && filter.productId !== info.productId) return false;
        return true;
    }

    const usb = {
        // There is no permission prompt in a native app: every attached device counts as "paired".
        async getDevices() {
            return host.list().map(wrap);
        },

        // No chooser UI either: pick the first attached device that matches a filter.
        async requestDevice(options) {
            const filters = (options && options.filters) || [];
            const info = host.list().find((d) => filters.length === 0 || filters.some((f) => matches(d, f)));
            if (!info) {
                const err = new Error('No device selected.');
                err.name = 'NotFoundError';
                throw err;
            }
            return wrap(info);
        },

        addEventListener() {},
        removeEventListener() {},
    };

    globalThis.USBDevice = USBDevice;
    globalThis.navigator = globalThis.navigator || {};
    globalThis.navigator.usb = usb;
})();
