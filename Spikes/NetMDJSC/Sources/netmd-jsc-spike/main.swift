import Foundation
import NetMDJSC

// Spike driver: load netmd-js into JavaScriptCore, self-test its WebAssembly
// dependencies, then try to open a NetMD device and list the disc.
//   --list-usb      also print every attached USB device seen by the Swift backend
//   --fake-device   pretend an MZ-N707 is attached (its registry ID doesn't exist), to check
//                   that Swift USB errors reach netmd-js as rejected Promises

setlinebuf(stdout)

if CommandLine.arguments.contains("--list-usb") {
    let devices = USBBackend.enumerate()
    print("USB devices (\(devices.count)):")
    for d in devices {
        print(String(format: "  %04x:%04x  %@ %@", d.vendorId, d.productId, d.manufacturerName ?? "", d.productName ?? ""))
    }
}

let started = Date()
let runtime: NetMDRuntime
do {
    runtime = try NetMDRuntime()
} catch {
    print("Failed to start runtime: \(error)")
    exit(1)
}
print(String(format: "Runtime loaded in %.0f ms", Date().timeIntervalSince(started) * 1000))

let finish: @convention(block) (Int32) -> Void = { code in exit(code) }
runtime.context.setObject(finish, forKeyedSubscript: "__finish" as NSString)

if CommandLine.arguments.contains("--fake-device") {
    runtime.evaluate("""
    __usbHost.list = () => [{ id: '1', vendorId: 0x054c, productId: 0x0086, manufacturerName: 'Sony', productName: 'Fake MZ-N707', serialNumber: '' }];
    """)
}

runtime.evaluate("""
(async () => {
    const { netmd, exploits, Crypto } = NetMDBundle;
    console.log(`netmd-js: ${netmd.DevicesIds.length} known device IDs; netmd-exploits: ${Object.keys(exploits).length} exports`);

    // netmd-js's secure session uses crypto-js-wasm DES/3DES.
    await Crypto.algo.DES.loadWasm();
    await Crypto.algo.TripleDES.loadWasm();
    const key = Crypto.enc.Hex.parse('0123456789abcdef');
    const ct = Crypto.DES.encrypt(Crypto.enc.Hex.parse('4e6f772069732074'), key, { mode: Crypto.mode.ECB, padding: Crypto.pad.NoPadding });
    console.log('DES (wasm) known-answer test:', ct.ciphertext.toString() === '3fa40e8a984d4815' ? 'ok' : 'FAILED ' + ct.ciphertext.toString());

    // netmd-exploits assembles ARM payloads with keystone (wasm).
    const asm = await exploits.Assembler.create({});
    console.log('Keystone assembler (wasm): loaded', typeof asm.processCode === 'function' ? 'ok' : 'FAILED');

    // Upload path cost: netmd-js DES-CBC encrypts every byte before sending (~4 MB per LP2 track).
    {
        const data = new Uint8Array(4 * 1024 * 1024);
        const t0 = Date.now();
        let sent = 0;
        for await (const packet of netmd.getAsyncPacketIterator({ data: data.buffer, frameSize: 192, kek: new Uint8Array(8), chunkSize: 0x00100000 })) {
            sent += packet.data.byteLength;
        }
        console.log(`Encrypted ${(sent / 1048576).toFixed(1)} MB for upload in ${Date.now() - t0} ms`);
    }

    const iface = await netmd.openNewDevice(navigator.usb);
    if (!iface) {
        console.log('No NetMD device found.');
        return __finish(0);
    }
    console.log('Opened:', iface.netMd.getDeviceName());
    const disc = await netmd.listContent(iface);
    console.log('Disc title:', disc.title, '| tracks:', disc.trackCount, '| left:', disc.left, '| total:', disc.total);
    for (const group of disc.groups) {
        for (const t of group.tracks) console.log(`  ${t.index + 1}. ${t.title} (${netmd.EncodingName[t.encoding]}, ${t.duration})`);
    }
    // Read-only factory query: the SoC + firmware code netmd-exploits keys compatibility on.
    const factory = await iface.factory();
    console.log('Device code:', await netmd.getDescriptiveDeviceCode(factory));
    await iface.netMd.finalize();
    __finish(0);
})().catch((e) => {
    console.error('Failed:', e && e.stack ? e.message + '\\n' + e.stack : String(e));
    __finish(1);
});
""", sourceName: "spike.js")

// JSC finishes async work (e.g. WebAssembly.instantiate) via the main CFRunLoop,
// so spin that rather than dispatchMain().
RunLoop.main.run()
