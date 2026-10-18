// The JS half of NetMDClient: one async function per operation, over unmodified netmd-js.
// Swift calls these by name and awaits the returned Promise.
(function () {
    'use strict';
    const { netmd, netmdUtils } = NetMDBundle;
    const formats = { sp: netmd.Wireformat.pcm, lp2: netmd.Wireformat.lp2, lp4: netmd.Wireformat.lp4 };
    let iface = null;

    function device() {
        if (!iface) throw new Error('No NetMD device connected');
        return iface;
    }

    globalThis.netmdHost = {
        async connect() {
            iface = await netmd.openNewDevice(navigator.usb);
            return iface ? iface.netMd.getDeviceName() : null;
        },

        // null when the unit has no disc (reading the TOC would be rejected).
        async disc() {
            if (!(await netmd.getDeviceStatus(device())).discPresent) return null;
            const d = await netmd.listContent(iface);
            const tracks = d.groups.flatMap((g) =>
                g.tracks.map((t) => ({
                    index: t.index,
                    title: t.title || '',
                    fullWidthTitle: t.fullWidthTitle || '',
                    encoding: netmd.EncodingName[t.encoding],
                    frames: t.duration,
                    group: g.title || '',
                }))
            );
            tracks.sort((a, b) => a.index - b.index);
            const hasGroups = d.groups.some((g) => g.title !== null);
            return { title: d.title || '', fullWidthTitle: d.fullWidthTitle || '', left: d.left, total: d.total, writable: d.writable, hasGroups, tracks };
        },

        async deviceCode() {
            return netmd.getDescriptiveDeviceCode(await device().factory());
        },

        async renameDisc(title) {
            await netmd.renameDisc(device(), title);
        },

        async renameTrack(index, title) {
            await device().setTrackTitle(index, netmdUtils.sanitizeHalfWidthTitle(title));
        },

        // Swift only allows this on discs without groups: erasing shifts indexes, and the
        // group ranges in the disc title would need rewriting (Web MiniDisc does that).
        async eraseTrack(index) {
            await device().eraseTrack(index);
        },

        // One session for every track: the device takes ~40 s per track otherwise (FIELD-NOTES).
        // progress(trackNumber, writtenBytes, totalBytes) is called as data goes out.
        async upload(tracks, progress) {
            await netmd.prepareDownload(device());
            const session = new netmd.MDSession(iface);
            await session.init();
            try {
                for (const [n, t] of tracks.entries()) {
                    const title = netmdUtils.sanitizeHalfWidthTitle(t.title);
                    const track = new netmd.MDTrack(title, formats[t.format], t.data.buffer, 0x400, '', netmd.getAsyncPacketIterator);
                    await session.downloadTrack(track, ({ writtenBytes, totalBytes }) => progress(n, writtenBytes, totalBytes));
                }
            } finally {
                await session.close();
                await iface.release();
            }
        },

        // Release and close, but never netMd.finalize(): its USB reset discards the TOC the
        // unit hasn't written to disc yet (FIELD-NOTES).
        async close() {
            if (!iface) return;
            const { netMd } = iface;
            iface = null;
            await netMd.device.releaseInterface(netMd.iface);
            await netMd.device.close();
        },
    };
})();
