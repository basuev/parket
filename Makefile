APP_NAME = tatami
BUNDLE = $(APP_NAME).app
INSTALL_DIR = /Applications/$(BUNDLE)
BUILD_DIR = .build/release

.PHONY: build test check install clean dist benchmark

build:
	swift build --product tatami -c release

test:
	swift build --product tatami-tests
	.build/debug/tatami-tests

check: test build

install: build
	@if [ ! -d "$(INSTALL_DIR)" ]; then \
		mkdir -p $(INSTALL_DIR)/Contents/MacOS; \
		cp Info.plist $(INSTALL_DIR)/Contents/; \
		echo "fresh install to $(INSTALL_DIR)"; \
		echo "grant accessibility permission in system settings, then: open /Applications/$(APP_NAME).app"; \
	fi
	cp $(BUILD_DIR)/$(APP_NAME) $(INSTALL_DIR)/Contents/MacOS/
	codesign --force --sign - $(INSTALL_DIR)
	@echo "updated $(INSTALL_DIR)"

dist: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp Info.plist $(BUNDLE)/Contents/
	cp $(BUILD_DIR)/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	codesign --force --sign - $(BUNDLE)
	zip -r $(APP_NAME).zip $(BUNDLE)
	@shasum -a 256 $(APP_NAME).zip

clean:
	swift package clean
	rm -rf $(BUNDLE) $(APP_NAME).zip

benchmark:
	bash scripts/benchmark.sh run

uninstall:
	rm -rf $(INSTALL_DIR)
