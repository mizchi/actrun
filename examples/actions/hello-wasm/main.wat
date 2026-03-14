;; A minimal WASI wasm action that prints "Hello from WASM!"
;; Compile: this file IS the module (wasmtime can run .wat directly)
;; Place as: _build/actrun/wasm_actions/<name>/<version>/main.wasm
(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "Hello from WASM!\n")
  (func (export "_start")
    (i32.store (i32.const 20) (i32.const 0))
    (i32.store (i32.const 24) (i32.const 17))
    (drop (call $fd_write
      (i32.const 1)
      (i32.const 20)
      (i32.const 1)
      (i32.const 28)))
  )
)
