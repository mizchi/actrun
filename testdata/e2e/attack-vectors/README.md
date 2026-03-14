# Attack Vector Test Workflows

These workflows test secret exfiltration vectors against the actrun's masking implementation.

## Results

| Vector | Masked | Notes |
|--------|--------|-------|
| Direct stdout | Yes | `${{ secrets.* }}` replaced with `***` |
| env dump | Yes | `ACTRUN_SECRET_*` values masked |
| printenv specific | Yes | Direct env var access masked |
| Base64 encode | **No** | Inherent limitation (same as GitHub Actions) |
| String reverse | **No** | Inherent limitation (same as GitHub Actions) |
| Char-by-char split | **No** | Inherent limitation (same as GitHub Actions) |
| Artifact file content | **No** | Inherent limitation (same as GitHub Actions) |
| GITHUB_STEP_SUMMARY | Yes | Summary content masked |
| GITHUB_OUTPUT | Yes | Output values masked |
| GITHUB_ENV inject+read | Yes | Env propagation masked |
| File command files | Yes | Cleaned up after run |
| run.json / run store | Yes | All persisted data masked |

## Inherent Limitations

Base64/reverse/char-split attacks cannot be prevented by string-based masking.
This matches GitHub Actions' behavior — the responsibility lies with workflow authors
to not transform secrets before outputting them.

Artifact files contain raw data (may include binary) and are not masked.
This also matches GitHub Actions' behavior.
