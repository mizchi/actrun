# Performance

Benchmark on Apple Silicon (M-series, macOS aarch64).
Nix measurements use warm nix store cache. All times are median of 3 runs unless noted.

## Environment

| Mode | Runtime | Shell / Node.js |
|------|---------|-----------------|
| `local` | Host macOS | bash 3.2.57, Node v24.12.0 |
| `nix-packages` | `nix develop` wrapper | bash 5.3.9, Node v24.14.0 |
| `apple-container` | Apple container (Linux VM) | BusyBox ash 1.36.1, Node v20.20.2 (alpine) |

## Startup overhead

Measured with 1 job, 1 step (`echo ok`). This is the minimum time actrun takes before any user code runs.

| Mode | Startup |
|------|--------:|
| `local` | ~0.13s |
| `nix-packages` | ~0.70s |
| `apple-container` | ~0.93s |

- `nix-packages` overhead comes from `nix develop` shell initialization, not package downloads (warm cache)
- `apple-container` overhead comes from container lifecycle: create, start, exec, stop

## Workspace modes

Measured with 2 jobs, 7 steps, light file I/O (`mkdir`, `echo`, `wc`, `sort`, `sha256sum`).

| Mode | Time |
|------|-----:|
| `local` | ~0.27s |
| `worktree` | ~0.26s |
| `tmp` | ~0.60s |

- `local` and `worktree` are effectively the same speed
- `tmp` adds ~0.3s for `git clone` into a temporary directory

## CPU benchmark

Node.js prime sieve to 5,000,000 (trial division). Measures pure V8 compute with no I/O.

| Mode | V8 exec | actrun total | Overhead |
|------|--------:|-------------:|---------:|
| `local` | 644ms | 0.78s | 0.14s |
| `nix-packages` | 629ms | 1.45s | 0.82s |
| `apple-container` | 502ms | 1.43s | 0.93s |

- V8 execution speed is comparable across all modes
- `apple-container` V8 is slightly faster (Linux VM scheduling / memory layout differences)
- The overhead column = actrun total - V8 exec, matches startup overhead

## File I/O benchmark

Node.js `fs` module operations. Measures filesystem metadata and data throughput.

| Operation | local | nix-packages | apple-container |
|-----------|------:|-------------:|----------------:|
| Write 1,000 small files | 52ms | 47ms | **14ms** |
| Read 1,000 small files | 12ms | 10ms | **4ms** |
| Write 10MB sequential | 1ms | 1ms | 3ms |
| Read 10MB sequential | 1ms | 2ms | 3ms |
| Stat 1,000 files | 3ms | 2ms | 2ms |

### Analysis

**Many-file operations (write/read 1k files):**
`apple-container` is **3-4x faster** than macOS native. This is due to ext4 vs APFS metadata performance — creating and opening many small files involves directory entry allocation and inode creation, where ext4 (even inside a VM) significantly outperforms APFS.

**Large sequential I/O (10MB):**
All modes are comparable (~1-3ms). Block-level throughput is not a bottleneck at this scale.

**`local` vs `nix-packages`:**
Identical I/O performance. Nix wraps the shell but does not change the filesystem path — all operations hit the same APFS volume.

## Recommendations

| Use case | Recommended mode |
|----------|-----------------|
| Fast iteration / development | `local` (0.13s startup) |
| Reproducible environment | `nix-packages` (+0.6s startup) |
| CI-like isolation | `worktree` (~0.26s) |
| Heavy file I/O (npm install, etc.) | `apple-container` (3-4x faster metadata ops) |
| Production CI parity | `apple-container` (matches Linux CI environment) |
