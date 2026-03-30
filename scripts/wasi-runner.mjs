#!/usr/bin/env node
// WASI Preview1 runner for actrun.
// Compatible with: node >= 20, deno, bun
// Usage: node wasi-runner.mjs run --env K=V --dir /path module.wasm
//
// Accepts the same CLI interface as wasmtime so actrun can use it
// as a drop-in replacement via ACTRUN_WASM_BIN.

const isNode = typeof process !== "undefined" && process.versions?.node;
const isDeno = typeof Deno !== "undefined";

// --- Argument parsing (wasmtime-compatible) ---
const argv = isDeno ? Deno.args : process.argv.slice(2);
const envMap = {};
const preopens = [];
let modulePath = "";

let i = 0;
while (i < argv.length) {
  if (argv[i] === "run") { i++; continue; }
  if (argv[i] === "--env" && i + 1 < argv.length) {
    const eq = argv[i + 1].indexOf("=");
    if (eq > 0) {
      envMap[argv[i + 1].substring(0, eq)] = argv[i + 1].substring(eq + 1);
    }
    i += 2; continue;
  }
  if (argv[i] === "--dir" && i + 1 < argv.length) {
    preopens.push(argv[i + 1]);
    i += 2; continue;
  }
  modulePath = argv[i];
  i++;
}

if (!modulePath) {
  const cmd = isNode ? "node" : "deno run --allow-all";
  process.stderr?.write?.(`Usage: ${cmd} wasi-runner.mjs run [--env K=V]... [--dir D]... <module.wasm>\n`)
    ?? Deno?.stderr?.writeSync?.(new TextEncoder().encode(`Usage: ${cmd} wasi-runner.mjs run [--env K=V]... [--dir D]... <module.wasm>\n`));
  (isDeno ? Deno.exit(1) : process.exit(1));
}

// --- Read module binary ---
let binary;
if (isDeno) {
  binary = await Deno.readFile(modulePath);
} else {
  const fs = await import("node:fs/promises");
  binary = await fs.readFile(modulePath);
}

// --- Try node:wasi first (Node.js >= 20) ---
let started = false;
if (isNode) {
  try {
    const { WASI } = await import("node:wasi");
    const wasi = new WASI({
      version: "preview1",
      args: [modulePath],
      env: envMap,
      preopens: Object.fromEntries(preopens.map(d => [d, d])),
    });
    const mod = await WebAssembly.compile(binary);
    const instance = await WebAssembly.instantiate(mod, wasi.getImportObject());
    wasi.start(instance);
    started = true;
  } catch {
    // node:wasi not available or failed, fall through to pure JS shim
  }
}

// --- Pure JS WASI P1 shim (Deno, Bun, or Node.js fallback) ---
if (!started) {
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  const writeStdout = isDeno
    ? (d) => Deno.stdout.writeSync(d)
    : (d) => process.stdout.write(d);
  const writeStderr = isDeno
    ? (d) => Deno.stderr.writeSync(d)
    : (d) => process.stderr.write(d);
  const writeFileSync = isDeno
    ? (p, d) => Deno.writeFileSync(p, d, { append: true })
    : (p, d) => { const fs = require("node:fs"); fs.appendFileSync(p, d); };
  const writeFileCreate = isDeno
    ? (p) => Deno.writeFileSync(p, new Uint8Array())
    : (p) => { const fs = require("node:fs"); fs.writeFileSync(p, ""); };
  const exitFn = isDeno ? Deno.exit : process.exit;

  const fds = new Map();
  let nextFd = 3;
  // stdin=0, stdout=1, stderr=2
  fds.set(0, { isDir: false });
  fds.set(1, { isDir: false });
  fds.set(2, { isDir: false });
  for (const dir of preopens) {
    fds.set(nextFd++, { path: dir, isDir: true });
  }

  let memory;
  const view = () => new DataView(memory.buffer);
  const u8 = () => new Uint8Array(memory.buffer);

  const imports = {
    wasi_snapshot_preview1: {
      args_get: () => 0,
      args_sizes_get: (argc_ptr, argv_buf_size_ptr) => {
        view().setUint32(argc_ptr, 0, true);
        view().setUint32(argv_buf_size_ptr, 0, true);
        return 0;
      },
      environ_get: (environ_ptr, environ_buf_ptr) => {
        const entries = Object.entries(envMap);
        let bufOffset = environ_buf_ptr;
        for (let j = 0; j < entries.length; j++) {
          view().setUint32(environ_ptr + j * 4, bufOffset, true);
          const s = encoder.encode(entries[j][0] + "=" + entries[j][1] + "\0");
          u8().set(s, bufOffset);
          bufOffset += s.length;
        }
        return 0;
      },
      environ_sizes_get: (count_ptr, buf_size_ptr) => {
        const entries = Object.entries(envMap);
        let size = 0;
        for (const [k, v] of entries) size += k.length + 1 + v.length + 1;
        view().setUint32(count_ptr, entries.length, true);
        view().setUint32(buf_size_ptr, size, true);
        return 0;
      },
      fd_write: (fd, iovs_ptr, iovs_len, nwritten_ptr) => {
        let written = 0;
        for (let j = 0; j < iovs_len; j++) {
          const ptr = view().getUint32(iovs_ptr + j * 8, true);
          const len = view().getUint32(iovs_ptr + j * 8 + 4, true);
          const data = u8().subarray(ptr, ptr + len);
          if (fd === 1) writeStdout(data);
          else if (fd === 2) writeStderr(data);
          else {
            const entry = fds.get(fd);
            if (entry?.path) writeFileSync(entry.path, data);
          }
          written += len;
        }
        view().setUint32(nwritten_ptr, written, true);
        return 0;
      },
      fd_read: () => 0,
      fd_close: () => 0,
      fd_seek: () => 0,
      fd_fdstat_get: (fd, buf) => {
        const entry = fds.get(fd);
        const filetype = fd <= 2 ? 2 : (entry?.isDir ? 3 : 4);
        view().setUint8(buf, filetype);
        view().setUint16(buf + 2, 0, true);
        view().setBigUint64(buf + 8, 0n, true);
        view().setBigUint64(buf + 16, 0n, true);
        return 0;
      },
      fd_prestat_get: (fd, buf) => {
        const entry = fds.get(fd);
        if (!entry?.isDir || !entry.path) return 8;
        view().setUint8(buf, 0);
        view().setUint32(buf + 4, encoder.encode(entry.path).length, true);
        return 0;
      },
      fd_prestat_dir_name: (fd, path_ptr, path_len) => {
        const entry = fds.get(fd);
        if (!entry?.path) return 8;
        u8().set(encoder.encode(entry.path).slice(0, path_len), path_ptr);
        return 0;
      },
      path_open: (dirfd, _dirflags, path_ptr, path_len, _oflags,
                   _rights_base, _rights_inheriting, _fdflags, fd_ptr) => {
        const dirEntry = fds.get(dirfd);
        if (!dirEntry?.path) return 8;
        const relPath = decoder.decode(u8().slice(path_ptr, path_ptr + path_len));
        const fullPath = dirEntry.path + "/" + relPath;
        if (!preopens.some(d => fullPath.startsWith(d))) return 76;
        const newFd = nextFd++;
        fds.set(newFd, { path: fullPath, isDir: false });
        try { writeFileCreate(fullPath); } catch { /* may exist */ }
        view().setUint32(fd_ptr, newFd, true);
        return 0;
      },
      clock_time_get: (_id, _precision, time_ptr) => {
        view().setBigUint64(time_ptr, BigInt(Date.now()) * 1000000n, true);
        return 0;
      },
      proc_exit: (code) => exitFn(code),
      sched_yield: () => 0,
      random_get: (buf, len) => {
        const arr = u8().subarray(buf, buf + len);
        if (typeof crypto !== "undefined") crypto.getRandomValues(arr);
        return 0;
      },
      poll_oneoff: () => 0,
      path_filestat_get: () => 8,
      path_create_directory: () => 0,
      path_remove_directory: () => 0,
      path_unlink_file: () => 0,
      path_rename: () => 0,
      fd_readdir: () => 0,
      fd_filestat_get: () => 0,
    },
  };

  const mod = await WebAssembly.compile(binary);
  const instance = await WebAssembly.instantiate(mod, imports);
  memory = instance.exports.memory;
  instance.exports._start();
}
