.PHONY: test-systemd

# Run the systemd-based smoke test. You can override TEST_DIR on the
# command line: `make test-systemd TEST_DIR=/tmp/my-test`
test-systemd:
	./scripts/run-systemd-test.sh
