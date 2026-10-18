// netmd-js decodes Shift-JIS titles with jconv, which uses Node's global Buffer
// (webpack 4 polyfilled it for Web MiniDisc). esbuild injects this wherever `Buffer` is free.
// Keep package.json's buffer version equal to netmd-js's so npm dedupes them: with two copies,
// jconv's `instanceof Buffer` check fails and Shift-JIS titles decode as mojibake.
export { Buffer } from 'buffer';
