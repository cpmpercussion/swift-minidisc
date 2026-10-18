// netmd-js decodes Shift-JIS titles with jconv, which uses Node's global Buffer
// (webpack 4 polyfilled it for Web MiniDisc). esbuild injects this wherever `Buffer` is free.
export { Buffer } from 'buffer';
