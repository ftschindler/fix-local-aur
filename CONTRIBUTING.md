# Contributing

## Testing

This project includes a reproducible systemd-based smoke test that exercises
the user-mode units and the script without touching the real system repo.

Overview

- The test creates a temporary repo (default `/tmp/test-aur`) and copies a
  real package from `/var/cache/pacman/pkg` into it.
- It installs transient user systemd units (prefixed with `test-`) into
  `~/.config/systemd/user/`, points them at the temporary repo, enables the
  path unit, and triggers the path by adding another package file.
- After the run the test units are disabled and removed; the test repo is
  preserved for inspection.

Run the test

1. From the repo root:

   make test-systemd

2. Override the test directory if you prefer:

   TEST_DIR=/tmp/my-test make test-systemd

What the test verifies

- The script creates `aur.db.tar.gz` when package files exist.
- The systemd path unit triggers the service exactly once when a package is
  added (i.e. no self-restart loop). The test runner ensures this by removing
  any packages from the test dir before enabling the path unit, then adding a
  single package to cause an appearance event.
- The script exits quickly if another instance holds the lock (concurrency
  protection). The test runner validates the script is runnable and resets any
  prior systemd failed state before exercising the units.

If the test fails

- Check `journalctl --user -u test-fix-aurdb.service` for logs.
- The test runner now builds a deterministic minimal `.pkg.tar.zst` in the
  test dir (no dependence on the host pacman cache). Ensure `zstd` is
  available on the system so the test can create the compressed package.

Notes

- The test creates and leaves the test repo dir so you can inspect created
  DB artifacts. The systemd units are removed automatically.
- The runner will:
  1) create a deterministic dummy package in the test dir,
  2) run the service once directly to verify the script executes correctly,
  3) remove package files and enable the test path unit, and
  4) add a single package to trigger the path unit and confirm a single
     service run.
