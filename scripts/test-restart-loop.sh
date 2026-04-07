#!/usr/bin/env bash
set -euo pipefail

# Test that verifies the path unit doesn't enter a restart loop when
# packages already exist and the DB is present.
#
# This reproduces the issue where PathExistsGlob immediately triggers
# when the path unit starts and files matching the glob already exist,
# causing systemd to hit the start-limit.

TEST_DIR="${TEST_DIR:-/tmp/test-aur-restart-loop}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNIT_PREFIX="test-restart-"

echo "=== Testing for restart loop with existing packages ==="
echo "Using TEST_DIR=$TEST_DIR"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Create a deterministic minimal dummy package
TMPPKGDIR="$(mktemp -d)"
PKGNAME="testpkg-1.0-1-any.pkg.tar.zst"

cat >"$TMPPKGDIR/.PKGINFO" <<EOF
pkgbase = testpkg
pkgname = testpkg
pkgver = 1.0
pkgrel = 1
pkgdesc = Dummy package for restart loop test
arch = any
url = https://example.invalid
builddate = 1625097600
packager = Test <test@example.invalid>
EOF

mkdir -p "$TMPPKGDIR/usr/share/testpkg"
echo "dummy" >"$TMPPKGDIR/usr/share/testpkg/README"

(cd "$TMPPKGDIR" && tar -cf - .) | zstd -q -o "$TEST_DIR/$PKGNAME"
rm -rf "$TMPPKGDIR"
echo "✓ Created dummy package $PKGNAME in $TEST_DIR"

# Pre-create the DB so it exists before we enable the path unit
# This simulates the normal state after paru has run
echo "Creating initial DB with repo-add..."
cd "$TEST_DIR"
repo-add -n -R -p aur.db.tar.gz "$PKGNAME" >/dev/null 2>&1
echo "✓ Initial DB created"

ls -la "$TEST_DIR/"
echo ""

# Install test systemd units
mkdir -p ~/.config/systemd/user
service_src="$REPO_ROOT/fix-aurdb.service"
path_src="$REPO_ROOT/fix-aurdb.path"
service_dst="$HOME/.config/systemd/user/${UNIT_PREFIX}fix-aurdb.service"
path_dst="$HOME/.config/systemd/user/${UNIT_PREFIX}fix-aurdb.path"

sed "s|ExecStart=.*|ExecStart=/bin/bash -c 'REPO_DIR=$TEST_DIR /bin/bash \"$REPO_ROOT/fix_local_aur.bash\"'|" "$service_src" >"$service_dst"
sed "s|PathExistsGlob=.*|PathExistsGlob=$TEST_DIR/*.pkg.*|" "$path_src" >"$path_dst"

chmod 0644 "$service_dst" "$path_dst"
chmod +x "$REPO_ROOT/fix_local_aur.bash" || true

echo "✓ Installed test units"

# Reset any prior failed state
systemctl --user reset-failed ${UNIT_PREFIX}fix-aurdb.service ${UNIT_PREFIX}fix-aurdb.path 2>/dev/null || true
systemctl --user daemon-reload

# Record start time
TEST_START_TIME="$(date --iso-8601=seconds)"

echo ""
echo "Enabling path unit with packages and DB already present..."
echo "This should NOT trigger a restart loop."
echo ""

# Enable and start the path unit
systemctl --user enable --now ${UNIT_PREFIX}fix-aurdb.path

# Wait to see if restart loop occurs
echo "Waiting 5 seconds to observe behavior..."
sleep 5

# Count how many times the service started
START_COUNT=$(journalctl --user -u ${UNIT_PREFIX}fix-aurdb.service --no-pager --since "$TEST_START_TIME" 2>/dev/null | grep -c "Starting" || echo "0")
START_COUNT=$(echo "$START_COUNT" | tr -d '\n')

echo ""
echo "=== Results ==="
echo "Service start count: $START_COUNT"
echo ""

# Check unit states
systemctl --user status ${UNIT_PREFIX}fix-aurdb.path --no-pager || true
echo ""
systemctl --user status ${UNIT_PREFIX}fix-aurdb.service --no-pager || true

echo ""
echo "=== Recent journal entries ==="
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
# The service should start 0 times (DB already exists) or at most 1 time
# If it starts 5+ times, we hit the restart loop
if [[ $START_COUNT -ge 5 ]]; then
    echo ""
    echo "❌ FAIL: Restart loop detected! Service started $START_COUNT times."
    exit 1
elif [[ $START_COUNT -le 1 ]]; then
    echo ""
    echo "✓ PASS: No restart loop. Service started $START_COUNT times."
    exit 0
else
    echo ""
    echo "⚠ WARN: Service started $START_COUNT times (unexpected but not a restart loop)"
    exit 0
fi
