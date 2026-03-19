# Contributing to actrun

Thank you for your interest in contributing to actrun!

## Getting Started

### Prerequisites

- [MoonBit](https://docs.moonbitlang.com) toolchain
- [just](https://github.com/casey/just) command runner
- Node.js (for action execution)
- Git

### Setup

```bash
git clone https://github.com/mizchi/actrun.git
cd actrun
just        # check + test
```

## Development Workflow

```bash
just            # check + test
just fmt        # format code
just check      # type check (moon check --deny-warn)
just test       # run tests
just e2e        # run E2E scenarios
just run        # run main
```

### Before Submitting

Run the full release check to make sure everything passes:

```bash
just release-check  # fmt + info + check + test + e2e
```

## Project Structure

| Directory/File | Purpose |
|----------------|---------|
| `src/lib.mbt` | Contract types |
| `src/parser.mbt` | Workflow YAML parser |
| `src/trigger.mbt` | Push trigger matcher |
| `src/lowering.mbt` | Bitflow IR lowering |
| `src/executor.mbt` | Native host executor |
| `src/runtime.mbt` | Git workspace materialization |
| `src/main/main.mbt` | CLI entry point |
| `testdata/` | Compatibility fixtures |

## Coding Conventions

- MoonBit code uses `snake_case` for variables/functions, `UpperCamelCase` for types and enums
- Each code block is separated by `///|`
- Use `moon doc '<Type>'` to explore APIs before implementing
- Use `moon test --update` to update snapshot tests

## Submitting Issues

We provide issue templates for:

- **Bug Report** - for unexpected behavior or errors
- **Feature Request** - for new features or enhancements

Please use the appropriate template when creating an issue.

## Submitting Pull Requests

1. Fork the repository and create a branch from `main`
2. Make your changes
3. Ensure `just release-check` passes
4. Fill in the PR template with a summary, changes, and test plan
5. Submit the pull request

### Tips

- Keep PRs focused on a single change
- Include test cases for new functionality
- Update snapshot tests with `just test-update` if needed
- Link related issues in the PR description

## License

By contributing, you agree that your contributions will be licensed under the Apache-2.0 License.
