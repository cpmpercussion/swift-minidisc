import ATRACKit
import Foundation
import NetMDJSC

// Spike driver: load netmd-js into JavaScriptCore, self-test its WebAssembly
// dependencies, then try to open a NetMD device and list the disc.
//   --list-usb      also print every attached USB device seen by the Swift backend
//   --fake-device   pretend an MZ-N707 is attached (its registry ID doesn't exist), to check
//                   that Swift USB errors reach netmd-js as rejected Promises
//   --upload-lp2 FILE [--title T] [--chunk BYTES]   (chunk: bytes per encrypted packet, default 0x400 as Web MiniDisc)
//                   decode FILE with Core Audio, encode LP2 with ATRACKit, upload it as a new track
//   --poll-cap-ms MS  poll for replies every MS ms instead of netmd-js's uncapped doubling
//   --erase-track N --expect-title T
//                   erase track N (1-based), only if its title is exactly T

setlinebuf(stdout)

if CommandLine.arguments.contains("--list-usb") {
    let devices = USBBackend.enumerate()
    print("USB devices (\(devices.count)):")
    for d in devices {
        print(String(format: "  %04x:%04x  %@ %@", d.vendorId, d.productId, d.manufacturerName ?? "", d.productName ?? ""))
    }
}

func option(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

var lp2Frames: Data?
if let path = option("--upload-lp2") {
    let t0 = Date()
    let pcm = try AudioFileDecoder.decode(url: URL(fileURLWithPath: path))
    let encoder = try ATRAC3Encoder(mode: .lp2)
    lp2Frames = encoder.write(pcm) + encoder.finish()
    print(String(format: "Encoded %@ to LP2: %.1f s of audio, %d bytes, in %.0f ms",
                 (path as NSString).lastPathComponent, Double(pcm.count / 2) / 44_100, lp2Frames!.count,
                 Date().timeIntervalSince(t0) * 1000))
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

if let lp2Frames {
    runtime.context.setObject(runtime.makeUint8Array(lp2Frames), forKeyedSubscript: "__uploadLP2" as NSString)
    runtime.context.setObject(option("--title") ?? "swift-minidisc test", forKeyedSubscript: "__uploadTitle" as NSString)
    runtime.context.setObject(Int(option("--chunk") ?? "") ?? 0x400, forKeyedSubscript: "__uploadChunk" as NSString)
}
if let cap = option("--poll-cap-ms").flatMap(Int.init) {
    runtime.context.setObject(cap, forKeyedSubscript: "__pollCapMs" as NSString)
}
if let n = option("--erase-track").flatMap(Int.init), let title = option("--expect-title") {
    runtime.context.setObject(n, forKeyedSubscript: "__eraseTrack" as NSString)
    runtime.context.setObject(title, forKeyedSubscript: "__eraseTitle" as NSString)
}

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
    {
        // Web MiniDisc's packet size (1 KB) has a fixed cost per packet; show it.
        const data = new Uint8Array(256 * 1024);
        const t0 = Date.now();
        let n = 0;
        for await (const packet of netmd.getAsyncPacketIterator({ data: data.buffer, frameSize: 192, kek: new Uint8Array(8), chunkSize: 0x400 })) n++;
        console.log(`Encrypted 256 KB as ${n} 1 KB packets in ${Date.now() - t0} ms`);
    }

    if (typeof __pollCapMs !== 'undefined') {
        // Experiment: netmd-js polls for replies at 10 ms * 2^i with no cap, which can overshoot
        // a slow reply by as long as the reply took. Cap the interval to measure the real wait.
        const original = netmd.NetMD.prototype.getReplyLength;
        netmd.NetMD.prototype.getReplyLength = async function () {
            const reply = await original.call(this);
            if (reply.len === 0) await new Promise((r) => setTimeout(r, __pollCapMs));
            return reply;
        };
        netmd.NetMD.readReplyRetryIntervalInMsec = 0;
        console.log(`Reply polling capped at ${__pollCapMs} ms`);
    }
    const iface = await netmd.openNewDevice(navigator.usb);
    if (!iface) {
        console.log('No NetMD device found.');
        return __finish(0);
    }
    console.log('Opened:', iface.netMd.getDeviceName());
    const showDisc = async () => {
        const disc = await netmd.listContent(iface);
        console.log('Disc title:', disc.title, '| tracks:', disc.trackCount, '| left:', disc.left, '| total:', disc.total);
        for (const group of disc.groups) {
            for (const t of group.tracks) console.log(`  ${t.index + 1}. ${t.title} (${netmd.EncodingName[t.encoding]}, ${t.duration})`);
        }
        return disc;
    };
    const disc = await showDisc();
    // Read-only factory query: the SoC + firmware code netmd-exploits keys compatibility on.
    const factory = await iface.factory();
    console.log('Device code:', await netmd.getDescriptiveDeviceCode(factory));

    if (typeof __uploadLP2 !== 'undefined') {
        // Raw ATRAC3 frames, no .at3 header (see netmd-js README: LP2 uploads take raw data).
        const track = new netmd.MDTrack(__uploadTitle, netmd.Wireformat.lp2, __uploadLP2.buffer, __uploadChunk, '', netmd.getAsyncPacketIterator);
        const t0 = Date.now();
        let lastPct = -1;
        const [trackIndex] = await netmd.download(iface, track, ({ writtenBytes, totalBytes }) => {
            const pct = Math.floor((writtenBytes / totalBytes) * 10) * 10;
            if (pct !== lastPct) { lastPct = pct; console.log(`  upload ${pct}% (${writtenBytes}/${totalBytes} bytes)`); }
        });
        console.log(`Uploaded as track ${trackIndex + 1} in ${Date.now() - t0} ms`);
        await showDisc();
    }

    if (typeof __eraseTrack !== 'undefined') {
        const all = disc.groups.flatMap((g) => g.tracks);
        const target = all.find((t) => t.index === __eraseTrack - 1);
        const current = await iface.getTrackTitle(__eraseTrack - 1);
        if (!target || current !== __eraseTitle) {
            console.log(`Not erasing: track ${__eraseTrack} is titled ${JSON.stringify(current)}, expected ${JSON.stringify(__eraseTitle)}`);
            return __finish(1);
        }
        await iface.eraseTrack(__eraseTrack - 1);
        console.log(`Erased track ${__eraseTrack} (${__eraseTitle})`);
        await showDisc();
    }

    // Don't call netMd.finalize(): its USB reset makes the unit drop TOC changes it hasn't
    // written to disc yet. Web MiniDisc never calls it either; release and close only.
    await iface.netMd.device.releaseInterface(iface.netMd.iface);
    await iface.netMd.device.close();
    __finish(0);
})().catch((e) => {
    console.error('Failed:', e && e.stack ? e.message + '\\n' + e.stack : String(e));
    __finish(1);
});
""", sourceName: "spike.js")

// JSC finishes async work (e.g. WebAssembly.instantiate) via the main CFRunLoop,
// so spin that rather than dispatchMain().
RunLoop.main.run()
