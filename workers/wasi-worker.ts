// WASI Runner Worker for Deno Deploy
// Executes WASM+WASI modules serverlessly with in-memory virtual FS.
//
// POST /run    - Execute a WASM module
// GET  /health - Health check
//
// Local:  deno run --allow-all workers/wasi-worker.ts
// Deploy: deployctl deploy --project=actrun-wasi workers/wasi-worker.ts

// --- In-Memory Virtual Filesystem ---

class VirtualFs {
  private files = new Map<string, string>();

  write(path: string, content: string, append: boolean) {
    if (append) {
      this.files.set(path, (this.files.get(path) ?? "") + content);
    } else {
      this.files.set(path, content);
    }
  }

  read(path: string): string | undefined {
    return this.files.get(path);
  }

  /** Parse key=value entries (GITHUB_OUTPUT / GITHUB_ENV format) */
  parseKeyValues(path: string): Record<string, string> {
    const content = this.files.get(path) ?? "";
    const result: Record<string, string> = {};
    for (const line of content.split("\n")) {
      if (!line) continue;
      const eq = line.indexOf("=");
      if (eq > 0) {
        result[line.substring(0, eq)] = line.substring(eq + 1);
      }
    }
    return result;
  }
}

// --- Minimal WASI P1 ---

class WasiP1Runner {
  private memory!: WebAssembly.Memory;
  private fds = new Map<
    number,
    { path?: string; isDir: boolean; writeBuf: string[] }
  >();
  private nextFd = 3;
  private env: Record<string, string>;
  private stdoutBuf: Uint8Array[] = [];
  private stderrBuf: Uint8Array[] = [];
  private exitCode = 0;
  private vfs: VirtualFs;
  private preopenDirs: string[];

  constructor(env: Record<string, string>, vfs: VirtualFs, preopenDirs: string[]) {
    this.env = env;
    this.vfs = vfs;
    this.preopenDirs = preopenDirs;
    this.fds.set(0, { isDir: false, writeBuf: [] });
    this.fds.set(1, { isDir: false, writeBuf: [] });
    this.fds.set(2, { isDir: false, writeBuf: [] });
    for (const dir of preopenDirs) {
      this.fds.set(this.nextFd++, { path: dir, isDir: true, writeBuf: [] });
    }
  }

  setMemory(m: WebAssembly.Memory) { this.memory = m; }
  getStdout(): string { return decode(concat(this.stdoutBuf)); }
  getStderr(): string { return decode(concat(this.stderrBuf)); }
  getExitCode(): number { return this.exitCode; }

  private v() { return new DataView(this.memory.buffer); }
  private u8() { return new Uint8Array(this.memory.buffer); }
  private enc = new TextEncoder();

  getImports(): WebAssembly.Imports {
    const self = this;
    return {
      wasi_snapshot_preview1: {
        args_get: () => 0,
        args_sizes_get: (c: number, s: number) => {
          self.v().setUint32(c, 0, true);
          self.v().setUint32(s, 0, true);
          return 0;
        },
        environ_get: (ep: number, bp: number) => {
          const entries = Object.entries(self.env);
          let off = bp;
          for (let i = 0; i < entries.length; i++) {
            self.v().setUint32(ep + i * 4, off, true);
            const s = self.enc.encode(`${entries[i][0]}=${entries[i][1]}\0`);
            self.u8().set(s, off);
            off += s.length;
          }
          return 0;
        },
        environ_sizes_get: (cp: number, sp: number) => {
          const entries = Object.entries(self.env);
          let sz = 0;
          for (const [k, v] of entries) sz += k.length + 1 + v.length + 1;
          self.v().setUint32(cp, entries.length, true);
          self.v().setUint32(sp, sz, true);
          return 0;
        },
        fd_write: (fd: number, iovs: number, iovsLen: number, nw: number) => {
          let written = 0;
          for (let i = 0; i < iovsLen; i++) {
            const ptr = self.v().getUint32(iovs + i * 8, true);
            const len = self.v().getUint32(iovs + i * 8 + 4, true);
            const data = self.u8().subarray(ptr, ptr + len);
            if (fd === 1) self.stdoutBuf.push(data);
            else if (fd === 2) self.stderrBuf.push(data);
            else {
              const entry = self.fds.get(fd);
              if (entry?.path) {
                self.vfs.write(entry.path, decode(data), true);
              }
            }
            written += len;
          }
          self.v().setUint32(nw, written, true);
          return 0;
        },
        fd_read: () => 0,
        fd_close: () => 0,
        fd_seek: () => 0,
        fd_fdstat_get: (fd: number, buf: number) => {
          const e = self.fds.get(fd);
          self.v().setUint8(buf, fd <= 2 ? 2 : e?.isDir ? 3 : 4);
          self.v().setUint16(buf + 2, 0, true);
          self.v().setBigUint64(buf + 8, 0n, true);
          self.v().setBigUint64(buf + 16, 0n, true);
          return 0;
        },
        fd_prestat_get: (fd: number, buf: number) => {
          const e = self.fds.get(fd);
          if (!e?.isDir || !e.path) return 8;
          self.v().setUint8(buf, 0);
          self.v().setUint32(buf + 4, self.enc.encode(e.path).length, true);
          return 0;
        },
        fd_prestat_dir_name: (fd: number, p: number, l: number) => {
          const e = self.fds.get(fd);
          if (!e?.path) return 8;
          self.u8().set(self.enc.encode(e.path).slice(0, l), p);
          return 0;
        },
        path_open: (
          dirfd: number, _: number, pp: number, pl: number,
          __: number, ___: bigint, ____: bigint, _____: number, fdp: number,
        ) => {
          const dir = self.fds.get(dirfd);
          if (!dir?.path) return 8;
          const rel = decode(self.u8().subarray(pp, pp + pl));
          const full = dir.path + "/" + rel;
          const nfd = self.nextFd++;
          self.fds.set(nfd, { path: full, isDir: false, writeBuf: [] });
          // Initialize empty file in vfs
          if (!self.vfs.read(full)) self.vfs.write(full, "", false);
          self.v().setUint32(fdp, nfd, true);
          return 0;
        },
        clock_time_get: (_: number, __: bigint, p: number) => {
          self.v().setBigUint64(p, BigInt(Date.now()) * 1000000n, true);
          return 0;
        },
        proc_exit: (code: number) => {
          self.exitCode = code;
          throw new WasiExit(code);
        },
        sched_yield: () => 0,
        random_get: (buf: number, len: number) => {
          crypto.getRandomValues(self.u8().subarray(buf, buf + len));
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
  }
}

class WasiExit extends Error {
  constructor(public code: number) { super(`exit(${code})`); }
}

function concat(bufs: Uint8Array[]): Uint8Array {
  const total = bufs.reduce((s, b) => s + b.length, 0);
  const r = new Uint8Array(total);
  let o = 0;
  for (const b of bufs) { r.set(b, o); o += b.length; }
  return r;
}
const decode = (b: Uint8Array) => new TextDecoder().decode(b);

// --- HTTP Server ---

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);

  if (url.pathname === "/health") {
    return Response.json({ status: "ok", runtime: "deno", wasi: true });
  }

  if (url.pathname === "/run" && req.method === "POST") {
    try {
      const body = await req.json();
      const { module_url, env = {}, inputs = {} } = body;

      // Build env
      const wasiEnv: Record<string, string> = { ...env };
      for (const [k, v] of Object.entries(inputs)) {
        wasiEnv[`INPUT_${(k as string).toUpperCase()}`] = v as string;
      }

      // Virtual filesystem with file command paths
      const vfs = new VirtualFs();
      const workdir = "/workspace";
      vfs.write(workdir + "/github_output", "", false);
      vfs.write(workdir + "/github_env", "", false);
      wasiEnv["GITHUB_OUTPUT"] = workdir + "/github_output";
      wasiEnv["GITHUB_ENV"] = workdir + "/github_env";
      wasiEnv["GITHUB_WORKSPACE"] = workdir;

      // Fetch module
      if (!module_url) {
        return Response.json({ error: "module_url required" }, { status: 400 });
      }
      const resp = await fetch(module_url);
      if (!resp.ok) {
        return Response.json(
          { error: `fetch ${module_url}: ${resp.status}` },
          { status: 400 },
        );
      }
      const bytes = new Uint8Array(await resp.arrayBuffer());

      // Run
      const runner = new WasiP1Runner(wasiEnv, vfs, [workdir]);
      const mod = await WebAssembly.compile(bytes);
      const inst = await WebAssembly.instantiate(mod, runner.getImports());
      runner.setMemory(inst.exports.memory as WebAssembly.Memory);

      let exitCode = 0;
      try {
        (inst.exports._start as Function)();
      } catch (e) {
        if (e instanceof WasiExit) exitCode = e.code;
        else return Response.json({ error: String(e) }, { status: 500 });
      }

      return Response.json({
        status: exitCode === 0 ? "success" : "failed",
        exit_code: exitCode,
        stdout: runner.getStdout(),
        stderr: runner.getStderr(),
        outputs: vfs.parseKeyValues(workdir + "/github_output"),
        env_updates: vfs.parseKeyValues(workdir + "/github_env"),
      });
    } catch (e) {
      return Response.json({ error: String(e) }, { status: 500 });
    }
  }

  return new Response(
    "actrun wasi-worker\n\nPOST /run  {module_url, env?, inputs?}\nGET /health\n",
  );
});
