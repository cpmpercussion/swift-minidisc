// Web APIs that JSContext lacks and that can be written in plain JS.
// setTimeout/clearTimeout, crypto.getRandomValues and navigator.usb come from Swift.

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

if (typeof globalThis.atob !== 'function') {
    globalThis.atob = (input) => {
        const str = String(input).replace(/[\s=]+/g, '');
        let out = '';
        let bits = 0;
        let acc = 0;
        for (const ch of str) {
            const v = B64.indexOf(ch);
            if (v < 0) throw new Error('atob: invalid character');
            acc = (acc << 6) | v;
            bits += 6;
            if (bits >= 8) {
                bits -= 8;
                out += String.fromCharCode((acc >> bits) & 0xff);
            }
        }
        return out;
    };
}

if (typeof globalThis.btoa !== 'function') {
    globalThis.btoa = (input) => {
        const str = String(input);
        let out = '';
        for (let i = 0; i < str.length; i += 3) {
            const a = str.charCodeAt(i), b = str.charCodeAt(i + 1), c = str.charCodeAt(i + 2);
            const n = (a << 16) | ((b || 0) << 8) | (c || 0);
            out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63];
            out += i + 1 < str.length ? B64[(n >> 6) & 63] : '=';
            out += i + 2 < str.length ? B64[n & 63] : '=';
        }
        return out;
    };
}

if (typeof globalThis.TextEncoder !== 'function') {
    globalThis.TextEncoder = class TextEncoder {
        get encoding() { return 'utf-8'; }
        encode(str = '') {
            const s = unescape(encodeURIComponent(String(str)));
            const out = new Uint8Array(s.length);
            for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
            return out;
        }
    };
}

if (typeof globalThis.TextDecoder !== 'function') {
    globalThis.TextDecoder = class TextDecoder {
        constructor(label = 'utf-8') {
            if (!/^utf-?8$/i.test(label)) throw new Error(`TextDecoder: unsupported encoding ${label}`);
        }
        get encoding() { return 'utf-8'; }
        decode(buf) {
            if (!buf) return '';
            const bytes = ArrayBuffer.isView(buf) ? new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength) : new Uint8Array(buf);
            let s = '';
            for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
            return decodeURIComponent(escape(s));
        }
    };
}

if (typeof globalThis.queueMicrotask !== 'function') {
    globalThis.queueMicrotask = (fn) => Promise.resolve().then(fn);
}

if (typeof globalThis.self === 'undefined') globalThis.self = globalThis;
if (typeof globalThis.window === 'undefined') globalThis.window = globalThis;
