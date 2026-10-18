// Everything the Swift host needs, on one global.
import * as netmd from 'netmd-js';
import * as exploits from 'netmd-exploits';
// The same module instance netmd-js uses; exposed so the host can self-test its WebAssembly.
import Crypto from '@originjs/crypto-js-wasm';

globalThis.NetMDBundle = { netmd, exploits, Crypto };
