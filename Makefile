.PHONY: test-systemd test-restart-loop test-path-triggers test

# Run all tests
test: test-systemd test-restart-loop

# Run the systemd-based smoke test. You can override TEST_DIR on the
# command line: `make test-systemd TEST_DIR=/tmp/my-test`
test-systemd:
	./scripts/run-systemd-test.sh

# Test for restart loop when packages already exist
test-restart-loop:
	./scripts/test-restart-loop.sh

# Test that path unit triggers on package changes (currently fails - PathModified doesn't trigger on initial state)
test-path-triggers:
	./scripts/test-path-triggers.sh
