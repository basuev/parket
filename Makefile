APP_NAME = parket
BUNDLE = $(APP_NAME).app
INSTALL_DIR = /Applications/$(BUNDLE)
BUILD_DIR = .build/release
BUNDLE_ID = com.parket.app
CODESIGN_IDENTITY ?= -
CODESIGN_REQUIREMENTS ?= =designated => identifier "$(BUNDLE_ID)"

.PHONY: build test fmt lint policy check install clean dist verify-dist notarize fixture-app smoke-local focus-local perf-local latency-local coverage perf benchmark

build:
	swift build --product parket -c release

test:
	swift test --enable-swift-testing

fmt:
	swift format --recursive --in-place Sources Entry Tests Benchmarks scripts/ax-smoke-check.swift scripts/ax-focus-check.swift scripts/ax-perf-check.swift scripts/send-hotkeys.swift scripts/workspace-latency-check.swift Package.swift

lint:
	swift format lint --recursive --strict Sources Entry Tests Benchmarks scripts/ax-smoke-check.swift scripts/ax-focus-check.swift scripts/ax-perf-check.swift scripts/send-hotkeys.swift scripts/workspace-latency-check.swift Package.swift

policy:
	bash scripts/policy-check.sh

check: lint policy test build

install: build
	@if [ ! -d "$(INSTALL_DIR)" ]; then \
		mkdir -p $(INSTALL_DIR)/Contents/MacOS; \
		cp Info.plist $(INSTALL_DIR)/Contents/; \
		echo "fresh install to $(INSTALL_DIR)"; \
		echo "grant accessibility permission in system settings, then: open /Applications/$(APP_NAME).app"; \
	fi
	cp $(BUILD_DIR)/$(APP_NAME) $(INSTALL_DIR)/Contents/MacOS/
	codesign --force --sign "$(CODESIGN_IDENTITY)" --requirements '$(CODESIGN_REQUIREMENTS)' $(INSTALL_DIR)
	@echo "updated $(INSTALL_DIR)"

dist: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp Info.plist $(BUNDLE)/Contents/
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	codesign --force --sign "$(CODESIGN_IDENTITY)" --requirements '$(CODESIGN_REQUIREMENTS)' $(BUNDLE)
	rm -f $(APP_NAME).zip
	ditto -c -k --sequesterRsrc --keepParent $(BUNDLE) $(APP_NAME).zip
	@shasum -a 256 $(APP_NAME).zip

verify-dist:
	bash scripts/verify-dist.sh

notarize:
	bash scripts/notarize.sh

fixture-app:
	bash scripts/build-fixture-app.sh

smoke-local:
	bash scripts/smoke-local.sh

focus-local:
	bash scripts/focus-local.sh

perf-local:
	bash scripts/perf-local.sh workspace-switch

latency-local:
	bash scripts/latency-compare.sh parket

clean:
	swift package clean
	rm -rf $(BUNDLE) $(APP_NAME).zip

coverage:
	swift test --enable-swift-testing --enable-code-coverage

perf:
	swift build --product parket-perf -c release
	.build/release/parket-perf

benchmark:
	bash scripts/benchmark.sh run

uninstall:
	rm -rf $(INSTALL_DIR)
