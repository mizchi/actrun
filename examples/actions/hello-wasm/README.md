# hello-wasm

A minimal WASI wasm action for actrun.

## How wasm actions work

1. Write your action as a WASI-compatible wasm module
2. Place it in the wasm action root:
   ```
   _build/actrun/wasm_actions/<name>/<version>/main.wasm
   ```
3. Reference it in your workflow:
   ```yaml
   - uses: wasm://name@version
   ```

## Building wasm actions

### From WAT (WebAssembly Text Format)
```bash
# wasmtime can run .wat directly
cp main.wat _build/actrun/wasm_actions/hello/v1/main.wasm
```

### From Rust
```bash
cargo build --target wasm32-wasip1 --release
cp target/wasm32-wasip1/release/my_action.wasm \
   _build/actrun/wasm_actions/my-action/v1/main.wasm
```

### From Go
```bash
GOOS=wasip1 GOARCH=wasm go build -o main.wasm
cp main.wasm _build/actrun/wasm_actions/my-action/v1/main.wasm
```

### From C
```bash
# Requires wasi-sdk
$WASI_SDK/bin/clang -o main.wasm main.c
cp main.wasm _build/actrun/wasm_actions/my-action/v1/main.wasm
```

## Environment

Wasm actions receive the same environment as other actions:
- `INPUT_*` for action inputs
- `GITHUB_OUTPUT` for setting outputs
- `GITHUB_ENV` for setting environment
- `GITHUB_STEP_SUMMARY` for step summary
- All standard `GITHUB_*` variables

## Runtime

Default: `wasmtime`. Override with `ACTRUN_WASM_BIN`.
