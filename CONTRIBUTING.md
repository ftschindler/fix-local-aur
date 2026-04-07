# Contributing

## Testing

This project includes multiple reproducible systemd-based tests that exercise
the user-mode units and the script without touching the real system repo.

### Available Tests

Run all tests:

```bash
make test
```

Or run individual tests:

```bash
make test-systemd        # Basic smoke test
make test-restart-loop   # Restart loop prevention test
```

### test-systemd (Basic Smoke Test)

Overview

- Creates a temporary repo (default `/tmp/test-aur`) with a deterministic dummy package.
- Installs transient user systemd units (prefixed with `test-`) into
  `~/.config/systemd/user/`, points them at the temporary repo.
- Runs the service directly once, then enables the path unit and triggers it
  by adding another package file.
- After the run the test units are disabled and removed; the test repo is
  preserved for inspection.

Override the test directory if you prefer:

```bash
TEST_DIR=/tmp/my-test make test-systemd
```

What it verifies

- The script creates `aur.db.tar.gz` when package files exist.
- The systemd path unit triggers the service when a package is added.
- The script exits quickly if another instance holds the lock (concurrency
  protection).

### test-restart-loop (Restart Loop Prevention)

Overview

- Creates a temporary repo with packages and a pre-existing DB (simulating
  normal state after paru has run).
- Enables the path unit with packages already present.
- Verifies the path unit does NOT enter a restart loop.

What it verifies

- The path unit using `PathModified` does not continuously trigger when
  packages already exist (no `unit-start-limit-hit` or `trigger-limit-hit`).
- The path unit remains in `active (waiting)` state.
- The service starts 0 times (since DB already exists and PathModified only
  triggers on changes, not initial state).

### Common Test Issues

If tests fail

- Check `journalctl --user -u test-fix-aurdb.service` (or the appropriate
  test unit prefix) for logs.
- All tests build deterministic minimal `.pkg.tar.zst` files (no dependence
  on the host pacman cache). Ensure `zstd` is available on the system.

### Notes

- Tests create and leave the test repo directories for inspection. The systemd
  units are removed automatically after each test.
- The `test-systemd` runner will:
  1) create a deterministic dummy package in the test dir,
  2) run the service once directly to verify the script executes correctly,
  3) remove package files and enable the test path unit, and
  4) add a single package to trigger the path unit and confirm a single
     service run.
- The `test-restart-loop` runner will:
  1) create a package and DB in the test dir (simulating normal state),
  2) enable the path unit with packages already present,
  3) wait 5 seconds and verify the service does not restart repeatedly.
