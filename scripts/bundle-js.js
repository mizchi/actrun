#!/usr/bin/env node
// Bundle the MoonBit JS build output into npm-ready artifacts:
//   dist/actrun.js  - standalone Node.js CLI (bin entry), minified
//   lib/actrun.js   - ESM library exposing the plan API (planWorkflow, ...)
//
// Usage:
//   moon build --release src/cmd/actrun --target js
//   moon build --release src --target js
//   node scripts/bundle-js.js [--no-minify]
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');
const require = createRequire(import.meta.url);
const minify = !process.argv.includes('--no-minify');

// MoonBit emits ESM, but our FFI shims use `require('child_process')`.
// Provide a CommonJS-style `require` inside the ESM bundle.
const ESM_REQUIRE_PRELUDE = [
  "import { createRequire as __actrunCreateRequire } from 'node:module';",
  'const require = __actrunCreateRequire(import.meta.url);',
  '',
].join('\n');

function firstExisting(paths) {
  return paths.find((p) => fs.existsSync(p));
}

function minifyCode(name, code) {
  if (!minify) return code;
  try {
    const { minifySync } = require('oxc-minify');
    return minifySync(name, code, { mangle: true, compress: true }).code;
  } catch {
    console.warn('oxc-minify not available, skipping minification');
    return code;
  }
}

function bundle({ label, inputs, output, prelude, shebang, executable, minify: doMinify }) {
  const input = firstExisting(inputs);
  if (!input) {
    console.error(`${label}: build output not found. Run: ${inputs.hint}`);
    return false;
  }
  const source = fs.readFileSync(input, 'utf8');
  const code = (doMinify ? minifyCode(path.basename(output), source) : source).trimEnd();
  const body = `${prelude}${code}\n`;
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, `${shebang}${body}`);
  if (executable) fs.chmodSync(output, 0o755);
  const before = (Buffer.byteLength(source) / 1024).toFixed(0);
  const after = (fs.statSync(output).size / 1024).toFixed(0);
  console.log(`${label}: ${path.relative(root, output)} (${before}KB -> ${after}KB)`);
  return true;
}

const cliInputs = [
  path.join(root, '_build', 'js', 'release', 'build', 'cmd', 'actrun', 'actrun.js'),
  path.join(root, '_build', 'js', 'debug', 'build', 'cmd', 'actrun', 'actrun.js'),
];
cliInputs.hint = 'moon build --release src/cmd/actrun --target js';

const libInputs = [
  path.join(root, '_build', 'js', 'release', 'build', 'actrun.js'),
  path.join(root, '_build', 'js', 'debug', 'build', 'actrun.js'),
];
libInputs.hint = 'moon build --release src --target js';

const okCli = bundle({
  label: 'cli',
  inputs: cliInputs,
  output: path.join(root, 'dist', 'actrun.js'),
  prelude: ESM_REQUIRE_PRELUDE,
  shebang: '#!/usr/bin/env node\n',
  executable: true,
  minify: true,
});

const okLib = bundle({
  label: 'lib',
  inputs: libInputs,
  output: path.join(root, 'lib', 'actrun.js'),
  prelude: '',
  shebang: '',
  executable: false,
  // Keep the library readable; consumers bundle it themselves.
  minify: false,
});

if (!okCli || !okLib) process.exit(1);
