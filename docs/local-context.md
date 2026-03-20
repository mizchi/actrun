# Local GitHub Context

When `--event` is omitted, `actrun` fills the common GitHub Actions context values from the local repository when possible:

- `github.repository`
- `github.ref_name`
- `github.sha`
- `github.actor`
- matching `GITHUB_*` environment variables

This is usually enough when you run `actrun` inside a normal git checkout. Use `actrun.toml` `[local_context]` only when you need deterministic values or when auto-detection is unavailable.

## When To Use

- You are running from a directory without a usable git remote
- You want stable local values for examples, demos, or screenshots
- Your workflow branches on `github.repository`, `github.ref_name`, or `github.actor`

## Configuration

```toml
[local_context]
repository = "owner/repo"
ref_name = "feature/local-demo"
before_rev = "HEAD^"
after_rev = "HEAD"
actor = "your-name"
```

`before_rev` and `after_rev` accept any revision that `git rev-parse` can resolve, such as `HEAD`, `HEAD^`, `HEAD~3`, tags, or raw SHAs.

## Precedence

Values are resolved in this order:

1. CLI flags such as `--repository`, `--ref`, `--before`, `--after`
2. `--event <path>` payload
3. `actrun.toml` `[local_context]`
4. local git auto-detection

`[local_context]` only fills missing values. It does not replace fields already provided by CLI flags or an event payload.

## Full Event Payloads

`[local_context]` sets the common `github.*` fields above, but it does not provide a full `github.event` payload. If your workflow reads nested event data, keep using:

```bash
actrun workflow run .github/workflows/ci.yml --event event.json
```

## Example Workflow

See [`examples/37-local-context.yml`](../examples/37-local-context.yml) for a minimal workflow that prints the resolved `github.*` values together with their `GITHUB_*` environment variables.
