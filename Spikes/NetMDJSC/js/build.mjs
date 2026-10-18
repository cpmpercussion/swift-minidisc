// Bundles netmd-js + netmd-exploits into one classic script for JavaScriptCore.
// Output: Sources/NetMDJSC/Resources/{netmd-bundle.js,assembler.wasm}; the bundle exposes globalThis.NetMDBundle.
import { build } from 'esbuild';
import { copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const shim = (name) => join(root, 'js', 'shims', name);

await build({
    entryPoints: [join(root, 'js', 'entry.js')],
    outfile: join(root, 'Sources', 'NetMDJSC', 'Resources', 'netmd-bundle.js'),
    bundle: true,
    format: 'iife',
    platform: 'browser',
    target: 'es2020',
    inject: [shim('prelude.js'), shim('buffer.js')],
    alias: {
        util: shim('util.js'),
        fs: shim('empty.js'),
        path: shim('path.js'),
        'browser-or-node': shim('browser-or-node.js'),
    },
    // netmd-js pulls in a Node-only worker helper and the CLI only via index re-exports we don't use.
    external: ['worker_threads', 'usb'],
    logLevel: 'info',
});

copyFileSync(join(root, 'node_modules', 'netmd-exploits', 'assembler.wasm'), join(root, 'Sources', 'NetMDJSC', 'Resources', 'assembler.wasm'));
