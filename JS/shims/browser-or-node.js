// JavaScriptCore is neither: report "browser" so netmd-exploits takes the
// setWASMArrayBuffer path instead of reading assembler.wasm through fs.
export const isBrowser = true;
export const isNode = false;
export const isWebWorker = false;
export const isJsDom = false;
export const isDeno = false;
