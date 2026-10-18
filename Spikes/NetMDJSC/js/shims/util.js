// netmd-js only uses util.inspect for debug logging.
export function inspect(value) {
    try {
        return JSON.stringify(value, (_k, v) => (ArrayBuffer.isView(v) ? Array.from(new Uint8Array(v.buffer, v.byteOffset, v.byteLength)) : v));
    } catch {
        return String(value);
    }
}
export default { inspect };
