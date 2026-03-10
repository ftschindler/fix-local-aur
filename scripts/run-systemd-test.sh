#!/usr/bin/env bash
set -euo pipefail

# Runs a smoke test using systemd user units copied from the repo.
# It creates a temporary test repo (default /tmp/test-aur), copies
# the packaged units into ~/.config/systemd/user/ using the prefix
# "test-" to avoid colliding with installed units, enables the path
# unit, triggers it by adding a package, then collects logs and
# cleans up.

TEST_DIR="${TEST_DIR:-/tmp/test-aur}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNIT_PREFIX="test-"

echo "Using TEST_DIR=$TEST_DIR"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

## Create a deterministic minimal dummy package for testing. This avoids
## relying on host pacman cache state and keeps the test self-contained.
TMPPKGDIR="$(mktemp -d)"
PKGNAME="testpkg-1.0-1-any.pkg.tar.zst"

# Minimal PKGINFO metadata
cat >"$TMPPKGDIR/.PKGINFO" <<EOF
pkgbase = testpkg
pkgname = testpkg
pkgver = 1.0
pkgrel = 1
pkgdesc = Dummy package for repo-add smoke tests
arch = any
url = https://example.invalid
builddate = 1625097600
packager = Test <test@example.invalid>
EOF

# Put a small file in the package so repo-add can create 'files' entries
mkdir -p "$TMPPKGDIR/usr/share/testpkg"
echo "dummy" >"$TMPPKGDIR/usr/share/testpkg/README"

# Create a tarball and compress it with zstd
(cd "$TMPPKGDIR" && tar -cf - .) | zstd -q -o "$TEST_DIR/$PKGNAME"
rm -rf "$TMPPKGDIR"
PKG_SAMPLE="$PKGNAME"
echo "Created deterministic dummy package $PKG_SAMPLE in $TEST_DIR"

# Keep a backup copy outside the test dir so we can remove files to
# simulate an appearance event and still trigger by copying this backup
SAMPLE_BACKUP_DIR="$(mktemp -d -p /tmp fix-local-aur-sample-XXXX)"
cp "$TEST_DIR/$PKG_SAMPLE" "$SAMPLE_BACKUP_DIR/"
SAMPLE_BACKUP="$SAMPLE_BACKUP_DIR/$PKG_SAMPLE"
echo "Backed up sample package to $SAMPLE_BACKUP"

# Copy and rename units into user systemd config
mkdir -p ~/.config/systemd/user
service_src="$REPO_ROOT/systemd-user/fix-aurdb.service"
path_src="$REPO_ROOT/systemd-user/fix-aurdb.path"
service_dst="$HOME/.config/systemd/user/${UNIT_PREFIX}fix-aurdb.service"
path_dst="$HOME/.config/systemd/user/${UNIT_PREFIX}fix-aurdb.path"

## Use an explicit bash invocation to avoid relying on the script being
## directly executable (handles noexec mounts). Bash will read the file.
sed "s|ExecStart=.*|ExecStart=/bin/bash -c 'REPO_DIR=$TEST_DIR /bin/bash \"$REPO_ROOT/fix_local_aur.bash\"'|" "$service_src" >"$service_dst"
sed "s|PathExistsGlob=.*|PathExistsGlob=$TEST_DIR/*.pkg.*|" "$path_src" >"$path_dst"

chmod 0644 "$service_dst" "$path_dst"

echo "Installed test units:"
ls -l "$service_dst" "$path_dst"

## Ensure the main script is executable so systemd can run it
chmod +x "$REPO_ROOT/fix_local_aur.bash" || true

## Reset any prior failed state for the test units (avoids start-limit issues)
systemctl --user reset-failed ${UNIT_PREFIX}fix-aurdb.service ${UNIT_PREFIX}fix-aurdb.path || true

systemctl --user daemon-reload

echo "Running the service directly once to verify the script executes"

# Record start time so we only show logs produced during this test run.
TEST_START_TIME="$(date --iso-8601=seconds)"

# Reset prior failed state, start service, and show only logs since TEST_START_TIME
systemctl --user reset-failed ${UNIT_PREFIX}fix-aurdb.service 2>/dev/null || true
systemctl --user start ${UNIT_PREFIX}fix-aurdb.service 2>/dev/null || true
sleep 1
echo "--- Journal (direct service run, since $TEST_START_TIME) ---"
journalctl --user -u ${UNIT_PREFIX}fix-aurdb.service --no-pager --since "$TEST_START_TIME" -n 200 || true

echo "Now testing the path unit behavior"

systemctl --user reset-failed ${UNIT_PREFIX}fix-aurdb.service ${UNIT_PREFIX}fix-aurdb.path 2>/dev/null || true

# Clean out package files so we can test a fresh appearance event. Removing
# the initial package ensures the path activation is caused by a new file
# appearing after the path unit is enabled.
rm -f "$TEST_DIR"/*.pkg.* || true
systemctl --user enable --now ${UNIT_PREFIX}fix-aurdb.path || true

echo "Triggering path by adding a package (appearance event)"
# Copy from the backup created earlier so the appearance event is reliable
cp "$SAMPLE_BACKUP" "$TEST_DIR/new-$PKG_SAMPLE"
sleep 2

echo "--- Journal (path-triggered service, since $TEST_START_TIME) ---"
journalctl --user -u ${UNIT_PREFIX}fix-aurdb.service --no-pager --since "$TEST_START_TIME" -n 200 || true

echo "--- Start count (since test start) ---"
journalctl --user -u ${UNIT_PREFIX}fix-aurdb.service --no-pager --since "$TEST_START_TIME" | grep -c "Starting" || true

echo "Cleaning up test units"
systemctl --user stop --now ${UNIT_PREFIX}fix-aurdb.path || true
systemctl --user disable --now ${UNIT_PREFIX}fix-aurdb.path || true
rm -f "$service_dst" "$path_dst"
systemctl --user daemon-reload || true

echo "Test directory left at $TEST_DIR for inspection"

exit 0
