.PH: help debug release test clean lint

.DEFAULT_GOAL := help

# Swift compiler configuration
SWIFT ?= swift
WORKER_COUNT ?= 4

help:
	@echo "genestackctl Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  make debug    - Build the CLI in debug mode"
	@echo "  make release  - Build the CLI in release mode"
	@echo "  make test     - Run the test suite"
	@echo "  make clean    - Remove build artifacts"
	@echo "  make lint     - Run linting checks (requires SwiftLint if installed)"
	@echo "  make help     - Show this help message"

debug: src-build debug-build

src-build:
	$(SWIFT) build --target genestackctl

debug-build:
	$(SWIFT) build -c debug -j $(WORKER_COUNT)

release: release-build

release-build:
	$(SWIFT) build -c release -j $(WORKER_COUNT)

test: test-run

test-run:
	$(SWIFT) test -j $(WORKER_COUNT)

clean: clean-build

clean-build:
	$(SWIFT) package clean
	rm -rf .build

lint:
	@echo "Checking for SwiftLint..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint Sources/ Tests/; \
	else \
		echo "SwiftLint is not installed. Skipping linting."; \
	fi
