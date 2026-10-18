// Everything the Swift host needs, on one global.
import * as netmd from 'netmd-js';
import * as exploits from 'netmd-exploits';
// Title encoding helpers (Shift-JIS via jconv), for self-tests.
import * as netmdUtils from 'netmd-js/dist/utils';
// The same module instance netmd-js uses; exposed so the host can self-test its WebAssembly.
import Crypto from '@originjs/crypto-js-wasm';

globalThis.NetMDBundle = { netmd, netmdUtils, exploits, Crypto };
