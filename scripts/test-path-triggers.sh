#!/usr/bin/env bash
set -euo pipefail

# Test that the path unit correctly triggers when a new package is added

TEST_DIR="${TEST_DIR:-/tmp/test-aur-triggers}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNIT_PREFIX="test-trigger-"

echo "=== Testing path unit triggering on package add ==="
echo "Using TEST_DIR=$TEST_DIR"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Create a dummy package function
create_package() {
    local pkgname="$1"
    local tmppkgdir
    tmppkgdir="$(mktemp -d)"

    cat >"$tmppkgdir/.PKGINFO" <<EOF
pkgbase = ${pkgname}
pkgname = ${pkgname}
pkgver = 1.0
pkgrel = 1
arch = any
EOF

    mkdir -p "$tmppkgdir/usr/share/${pkgname}"
    echo "dummy" >"$tmppkgdir/usr/share/${pkgname}/README"

    (cd "$tmppkgdir" && tar -cf - .) | zstd -q -o "$TEST_DIR/${pkgname}-1.0-1-any.pkg.tar.zst"
    rm -rf "$tmppkgdir"
}

echo "Creating initial package..."
create_package "testpkg1"
echo "✓ Created testpkg1"

# Install test systemd units
mkdir -p ~/.config/systemd/user
service_src="$REPO_ROOT/systemd-user/fix-aurdb.service"
path_src="$REPO_ROOT/systemd-user/fix-aurdb.path"
service_dst="$HOME/.config/systemd/user/${UNIT_PREFIX}fix-aurdb.service"
path_dst="$HOME/.config/systemd/user/${UNIT_PREFIX}fix-aurdb.path"

sed "s|ExecStart=.*|ExecStart=/bin/bash -c 'REPO_DIR=$TEST_DIR /bin/bash \"$REPO_ROOT/fix_local_aur.bash\"'|" "$service_src" >"$service_dst"
sed "s|PathModified=.*|PathModified=$TEST_DIR|" "$path_src" >"$path_dst"

chmod 0644 "$service_dst" "$path_dst"
chmod +x "$REPO_ROOT/fix_local_aur.bash" || true

echo "✓ Installed test units"

# Reset any prior failed state
systemctl --user reset-failed ${UNIT_PREFIX}fix-aurdb.service ${UNIT_PREFIX}fix-aurdb.path 2>/dev/null || true
systemctl --user daemon-reload

# Record start time
TEST_START_TIME="$(date --iso-8601=seconds)"

# Enable the path unit (should not trigger yet since DB doesn't exist)
systemctl --user enable --now ${UNIT_PREFIX}fix-aurdb.path
sleep 1

echo ""
echo "Path unit enabled. Checking if it triggered for existing package (it should)..."
sleep 1

START_COUNT_1=$(journalctl --user -u ${UNIT_PREFIX}fix-aurdb.service --no-pager --since "$TEST_START_TIME" 2>/dev/null | grep -c "Starting\|Started" || echo "0")
START_COUNT_1=$(echo "$START_COUNT_1" | tr -d '\n')

echo "First trigger count: $START_COUNT_1 (expected: 2 for 'Starting' and 'Started')"

# Verify DB was created
if [[ -f "$TEST_DIR/aur.db" ]]; then
    echo "✓ Database was created"
else
    echo "✗ Database was NOT created"
fi

# Now add a second package to trigger the path unit again
echo ""
echo "Adding second package to trigger path unit..."
sleep 2 # Wait to ensure timestamp difference
create_package "testpkg2"
echo "✓ Created testpkg2"

# Wait for systemd to notice and trigger
sleep 3

START_COUNT_2=$(journalctl --user -u ${UNIT_PREFIX}fix-aurdb.service --no-pager --since "$TEST_START_TIME" 2>/dev/null | grep -c "Starting\|Started" || echo "0")
START_COUNT_2=$(echo "$START_COUNT_2" | tr -d '\n')

echo "Second trigger count: $START_COUNT_2 (expected: 4 - two runs total)"

echo ""
echo "=== Unit Status ==="
systemctl --user status ${UNIT_PREFIX}fix-aurdb.path --no-pager || true

echo ""
echo "=== Journal Entries ==="
journalctl --user -u ${UNIT_PREFIX}fix-aurdb.service --no-pager --since "$TEST_START_TIME" -n 50 || true

# Cleanup
echo ""
echo "Cleaning up test units..."
systemctl --user stop ${UNIT_PREFIX}fix-aurdb.path || true
systemctl --user disable ${UNIT_PREFIX}fix-aurdb.path || true
rm -f "$service_dst" "$path_dst"
systemctl --user daemon-reload || true

echo ""
echo "Test directory left at $TEST_DIR for inspection"

# Determine pass/fail
if [[ $START_COUNT_1 -ge 2 && $START_COUNT_2 -ge 4 && -f "$TEST_DIR/aur.db" ]]; then
    echo ""
    echo "✓ PASS: Path unit triggered appropriately"
    exit 0
else
    echo ""
    echo "❌ FAIL: Path unit did not trigger as expected"
    echo "   Expected first count >= 2, got $START_COUNT_1"
    echo "   Expected second count >= 4, got $START_COUNT_2"
    exit 1
fi
