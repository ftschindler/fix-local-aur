.PHONY: test-systemd test-restart-loop test-path-triggers test install

# Install the script and systemd units
install:
	@echo "Installing fix-local-aur-db script..."
	install -m 0755 fix_local_aur.bash ~/.local/bin/fix-local-aur-db
	@echo "Installing systemd user units..."
	install -Dm 0644 fix-aurdb.service ~/.config/systemd/user/fix-aurdb.service
	install -Dm 0644 fix-aurdb.path ~/.config/systemd/user/fix-aurdb.path
	install -Dm 0644 fix-aurdb.timer ~/.config/systemd/user/fix-aurdb.timer
	install -Dm 0644 fix-aurdb-failure-notify.service ~/.config/systemd/user/fix-aurdb-failure-notify.service
	@echo "Reloading systemd user daemon..."
	systemctl --user daemon-reload
	@echo "Enabling and starting units..."
	systemctl --user enable --now fix-aurdb.path
	systemctl --user enable --now fix-aurdb.timer
	@echo ""
	@echo "✓ Installation complete!"
	@echo ""
	@echo "The path unit watches for directory changes while the timer ensures"
	@echo "the DB exists on boot and provides hourly checks as a safety net."
	@echo ""
	@echo "To run the fixer manually: systemctl --user start fix-aurdb.service"
	@echo "To persist across reboots: sudo loginctl enable-linger $$USER"
	@echo "To check status: systemctl --user status fix-aurdb.path fix-aurdb.timer"

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
