.PH: help debug release test clean lint ci-test ci-release install-bin package-rpm package-deb package-all

.DEFAULT_GOAL := help

# Swift compiler configuration
SWIFT ?= swift
WORKER_COUNT ?= 4

help:
	@echo "genestackctl Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Build targets:"
	@echo "  make debug    - Build the CLI in debug mode"
	@echo "  make release  - Build the CLI in release mode"
	@echo "  make test     - Run the test suite"
	@echo "  make clean    - Remove build artifacts"
	@echo "  make lint     - Run linting checks (requires SwiftLint if installed)"
	@echo "  make install-bin - Install binary to /usr/local/bin"
	@echo "  make ci-test   - Run CI test suite (verbose)"
	@echo "  make ci-release - Create release artifacts"
	@echo "  make package-rpm - Build RPM package (Linux)"
	@echo "  make package-deb - Build DEB package (Linux)"
	@echo "  make package-all - Build both RPM and DEB packages"
	@echo ""
	@echo "Help:"
	@echo "  make help     - Show this help message"

ci-test:
	$(SWIFT) test -v -j $(WORKER_COUNT)

test:
	$(SWIFT) test -j $(WORKER_COUNT)

release:
	$(SWIFT) build -c release -j $(WORKER_COUNT)
	strip .build/release/genectl

debug:
	$(SWIFT) build -c release -j $(WORKER_COUNT)
	strip .build/release/genectl
	mkdir -p dist
	cp .build/release/genectl dist/
	@echo "Release binary created in dist/genectl"

install-bin: release
	sudo cp .build/release/genectl /usr/local/bin/
	@echo "Installed genectl to /usr/local/bin/"

package-rpm: release
	@echo "Building RPM package..."
	./packaging/rpm/build.sh

package-deb: release
	@echo "Building DEB package..."
	./packaging/deb/build.sh

package-all: package-rpm package-deb
	@echo "All packages built successfully"
