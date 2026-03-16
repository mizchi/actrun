#!/usr/bin/env node
// Bundle MoonBit JS output into a standalone Node.js CLI script with minification
const fs = require('fs');
const path = require('path');

const src = path.join(__dirname, '..', '_build', 'js', 'release', 'build', 'cmd', 'actrun', 'actrun.js');
const srcDebug = path.join(__dirname, '..', '_build', 'js', 'debug', 'build', 'cmd', 'actrun', 'actrun.js');
const dist = path.join(__dirname, '..', 'dist', 'actrun.js');

const input = fs.existsSync(src) ? src : srcDebug;
if (!fs.existsSync(input)) {
  console.error('Build output not found. Run: moon build --release src/cmd/actrun --target js');
  process.exit(1);
}

fs.mkdirSync(path.dirname(dist), { recursive: true });

const content = fs.readFileSync(input, 'utf8');
const originalSize = Buffer.byteLength(content);

let output;
try {
  const { minifySync } = require('oxc-minify');
  const result = minifySync(input, content, { mangle: true, compress: true });
  output = result.code;
} catch {
  console.warn('oxc-minify not available, skipping minification');
  output = content;
}

fs.writeFileSync(dist, '#!/usr/bin/env node\n' + output);
fs.chmodSync(dist, 0o755);

const finalSize = Buffer.byteLength(fs.readFileSync(dist));
console.log(`Bundled: ${dist} (${(originalSize / 1024).toFixed(0)}KB -> ${(finalSize / 1024).toFixed(0)}KB)`);
