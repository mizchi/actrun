#!/usr/bin/env node
// WASI Preview1 runner for actrun.
// Compatible with: node >= 20, deno, bun
// Usage: node wasi-runner.mjs run --env K=V --dir /path module.wasm
//
// Accepts the same CLI interface as wasmtime so actrun can use it
// as a drop-in replacement via ACTRUN_WASM_BIN.

const isNode = typeof process !== "undefined" && process.versions?.node;
const isDeno = typeof Deno !== "undefined";
const nodeFs = isNode ? await import("node:fs") : null;
const nodeUrl = isNode ? await import("node:url") : null;

export function parseWasmtimeCli(argv) {
  const envMap = {};
  const preopens = [];
  let modulePath = "";
  let i = 0;
  while (i < argv.length) {
    if (argv[i] === "run") {
      i++;
      continue;
    }
    if (argv[i] === "--env" && i + 1 < argv.length) {
      const eq = argv[i + 1].indexOf("=");
      if (eq > 0) {
        envMap[argv[i + 1].substring(0, eq)] = argv[i + 1].substring(eq + 1);
      }
      i += 2;
      continue;
    }
    if (argv[i] === "--dir" && i + 1 < argv.length) {
      preopens.push(argv[i + 1]);
      i += 2;
      continue;
    }
    modulePath = argv[i];
    i++;
  }
  return { envMap, preopens, modulePath };
}

export function normalizeFsPath(path) {
  const raw = String(path || "").replaceAll("\\", "/");
  const driveMatch = raw.match(/^[A-Za-z]:/);
  const drive = driveMatch ? driveMatch[0] : "";
  const rest = drive ? raw.slice(drive.length) : raw;
  const isAbs = rest.startsWith("/");
  const parts = [];
  for (const part of rest.split("/")) {
    if (!part || part === ".") {
      continue;
    }
    if (part === "..") {
      if (parts.length > 0 && parts[parts.length - 1] !== "..") {
        parts.pop();
      } else if (!isAbs) {
        parts.push("..");
      }
      continue;
    }
    parts.push(part);
  }
  const prefix = drive ? `${drive}${isAbs ? "/" : ""}` : (isAbs ? "/" : "");
  if (prefix.length > 0 || parts.length > 0) {
    return prefix + parts.join("/");
  }
  return ".";
}

export function pathWithinPreopen(basePath, candidatePath) {
  const base = normalizeFsPath(basePath);
  const candidate = normalizeFsPath(candidatePath);
  return candidate === base || candidate.startsWith(base + "/");
}

export function resolvePreopenPath(basePath, relativePath) {
  const base = normalizeFsPath(basePath);
  const candidate = /^[A-Za-z]:[\\/]/.test(relativePath) || relativePath.startsWith("/")
    ? normalizeFsPath(relativePath)
    : normalizeFsPath(base + "/" + relativePath);
  if (!pathWithinPreopen(base, candidate)) {
    return null;
  }
  return candidate;
}

export function writeFileAppend(path, data) {
  if (isDeno) {
    Deno.writeFileSync(path, data, { append: true });
    return;
  }
  nodeFs.appendFileSync(path, data);
}

export function writeFileCreate(path) {
  if (isDeno) {
    Deno.writeFileSync(path, new Uint8Array());
    return;
  }
  nodeFs.writeFileSync(path, "");
}

function writeUsageAndExit() {
  const cmd = isNode ? "node" : "deno run --allow-all";
  const message = `Usage: ${cmd} wasi-runner.mjs run [--env K=V]... [--dir D]... <module.wasm>\n`;
  if (isDeno) {
    Deno.stderr.writeSync(new TextEncoder().encode(message));
    Deno.exit(1);
  }
  process.stderr.write(message);
  process.exit(1);
}

export async function runWasiModule(modulePath, envMap, preopens) {
  let binary;
  if (isDeno) {
    binary = await Deno.readFile(modulePath);
  } else {
    const fsPromises = await import("node:fs/promises");
    binary = await fsPromises.readFile(modulePath);
  }

  let started = false;
  if (isNode) {
    try {
      const { WASI } = await import("node:wasi");
      const wasi = new WASI({
        version: "preview1",
        args: [modulePath],
        env: envMap,
        preopens: Object.fromEntries(preopens.map((dir) => [dir, dir])),
      });
      const mod = await WebAssembly.compile(binary);
      const instance = await WebAssembly.instantiate(mod, wasi.getImportObject());
      wasi.start(instance);
      started = true;
    } catch {
      // node:wasi not available or failed, fall through to pure JS shim
    }
  }

  if (started) {
    return;
  }

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const writeStdout = isDeno
    ? (data) => Deno.stdout.writeSync(data)
    : (data) => process.stdout.write(data);
  const writeStderr = isDeno
    ? (data) => Deno.stderr.writeSync(data)
    : (data) => process.stderr.write(data);
  const exitFn = isDeno ? Deno.exit : process.exit;

  const fds = new Map();
  let nextFd = 3;
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
      args_sizes_get: (argcPtr, argvBufSizePtr) => {
        view().setUint32(argcPtr, 0, true);
        view().setUint32(argvBufSizePtr, 0, true);
        return 0;
      },
      environ_get: (environPtr, environBufPtr) => {
        const entries = Object.entries(envMap);
        let bufOffset = environBufPtr;
        for (let j = 0; j < entries.length; j++) {
          view().setUint32(environPtr + j * 4, bufOffset, true);
          const text = encoder.encode(entries[j][0] + "=" + entries[j][1] + "\0");
          u8().set(text, bufOffset);
          bufOffset += text.length;
        }
        return 0;
      },
      environ_sizes_get: (countPtr, bufSizePtr) => {
        const entries = Object.entries(envMap);
        let size = 0;
        for (const [key, value] of entries) {
          size += key.length + 1 + value.length + 1;
        }
        view().setUint32(countPtr, entries.length, true);
        view().setUint32(bufSizePtr, size, true);
        return 0;
      },
      fd_write: (fd, iovsPtr, iovsLen, nwrittenPtr) => {
        let written = 0;
        for (let j = 0; j < iovsLen; j++) {
          const ptr = view().getUint32(iovsPtr + j * 8, true);
          const len = view().getUint32(iovsPtr + j * 8 + 4, true);
          const data = u8().subarray(ptr, ptr + len);
          if (fd === 1) {
            writeStdout(data);
          } else if (fd === 2) {
            writeStderr(data);
          } else {
            const entry = fds.get(fd);
            if (entry?.path) {
              writeFileAppend(entry.path, data);
            }
          }
          written += len;
        }
        view().setUint32(nwrittenPtr, written, true);
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
        if (!entry?.isDir || !entry.path) {
          return 8;
        }
        view().setUint8(buf, 0);
        view().setUint32(buf + 4, encoder.encode(entry.path).length, true);
        return 0;
      },
      fd_prestat_dir_name: (fd, pathPtr, pathLen) => {
        const entry = fds.get(fd);
        if (!entry?.path) {
          return 8;
        }
        u8().set(encoder.encode(entry.path).slice(0, pathLen), pathPtr);
        return 0;
      },
      path_open: (
        dirfd,
        _dirflags,
        pathPtr,
        pathLen,
        _oflags,
        _rightsBase,
        _rightsInheriting,
        _fdflags,
        fdPtr,
      ) => {
        const dirEntry = fds.get(dirfd);
        if (!dirEntry?.path) {
          return 8;
        }
        const relPath = decoder.decode(u8().subarray(pathPtr, pathPtr + pathLen));
        const fullPath = resolvePreopenPath(dirEntry.path, relPath);
        if (fullPath === null) {
          return 76;
        }
        const newFd = nextFd++;
        fds.set(newFd, { path: fullPath, isDir: false });
        try {
          writeFileCreate(fullPath);
        } catch {
          // Existing files are fine.
        }
        view().setUint32(fdPtr, newFd, true);
        return 0;
      },
      clock_time_get: (_id, _precision, timePtr) => {
        view().setBigUint64(timePtr, BigInt(Date.now()) * 1000000n, true);
        return 0;
      },
      proc_exit: (code) => exitFn(code),
      sched_yield: () => 0,
      random_get: (buf, len) => {
        const arr = u8().subarray(buf, buf + len);
        if (typeof crypto !== "undefined") {
          crypto.getRandomValues(arr);
        }
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

export async function main(argv = isDeno ? Deno.args : process.argv.slice(2)) {
  const { envMap, preopens, modulePath } = parseWasmtimeCli(argv);
  if (!modulePath) {
    writeUsageAndExit();
    return;
  }
  await runWasiModule(modulePath, envMap, preopens);
}

const isMain = (typeof import.meta.main === "boolean" && import.meta.main) ||
  (isNode &&
    process.argv[1] &&
    import.meta.url === nodeUrl.pathToFileURL(process.argv[1]).href);

if (isMain) {
  await main();
}
