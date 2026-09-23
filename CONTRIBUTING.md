# Contributing

Thank you for your interest in contributing to claude-usage-on-icon!

## Core principle

**No credentials, no network, no undocumented APIs.**

This project reads stdin from Claude Code (the official status line input) and displays usage data in a tray icon. Any pull request that:
- Reads `.credentials.json` or OAuth tokens
- Makes HTTP calls (including update checks)
- Uses undocumented APIs
- Accesses keychains or password managers

...is out of scope and will be rejected.

If a feature seems to need any of these, please open an issue to discuss before implementing.

## Style and quality

- **No dependencies beyond stdlib** (Python 3.8+, PowerShell 5.1, shell builtins for scripts)
- **Fast:** target < 150 ms per status line execution
- **Testable:** keep logic pure and testable where possible; use fixtures for integration tests
- **Comments:** only when the WHY is non-obvious (hidden constraints, workarounds, subtle invariants)

## Regression tests

Before submitting a PR, ensure that:
1. Your changes don't introduce any of the bugs from §8 of `PROJECT_PLAN.md`
2. All existing tests pass
3. New features include test coverage in `tests/`

Run tests locally:
```bash
# Python tests
pytest tests/test_statusline_py.py tests/test_tray_logic.py -v

# PowerShell tests (Windows)
pwsh -File tests/statusline.Tests.ps1
pwsh -File tests/tray.Tests.ps1
```

## Security

This project contains no credentials, makes no network calls, and accesses only:
- stdin from Claude Code
- `~/.claude/` and Windows equivalents
- Temporary files for atomic writes
- (Linux/macOS tray only) `$XDG_RUNTIME_DIR` for temporary icons

See `SECURITY.md` for the threat model.

## Development flow

1. Branch from `main` for your feature or fix
2. Write tests alongside your code
3. Run the test suite and linters:
   ```bash
   ruff check . --fix
   ruff format .
   shellcheck writer/*.sh tray/*.sh install/*.sh 2>/dev/null || true
   ```
4. Commit with a clear message explaining the WHY
5. Push and open a PR with a summary of changes

## Versioning

This project uses **SemVer**. All version stamps are in:
- Script headers: `# Version: x.y.z`
- Tray menu and diagnostic log
- `CHANGELOG.md`

A CI check verifies all stamps match the Git tag before release.

## Questions?

Open an issue or discussion. Thank you for helping keep Claude Code usage visible!
