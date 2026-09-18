name = "mizchi/actrun"

version = "0.32.0"

import {
  "moonbitlang/async@0.22.1",
  "mizchi/bitflow@0.4.1",
  "mizchi/bit_core@0.47.0",
  "mizchi/bit_diff@0.47.0",
  "mizchi/bit_lib@0.47.0",
  "mizchi/bit_osfs@0.47.0",
  "moonbitlang/x@0.5.5",
  "moonbitlang/quickcheck@0.14.0",
  "moonbit-community/yaml@0.0.6",
  "bobzhang/toml@0.4.3",
  "mizchi/jq@0.2.2",
  "mizchi/wite@0.11.3",
  "mizchi/wit@0.3.3",
}

readme = "src/README.mbt.md"

repository = "https://github.com/mizchi/actrun"

license = "Apache-2.0"

keywords = [ "github-actions", "workflow", "runner", "ci" ]

description = "MVP GitHub Actions-compatible push CI runner with bitflow lowering, native execution, and bit workspace materialization."

preferred_target = "native"

source = "src"
