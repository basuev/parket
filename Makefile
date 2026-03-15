APP_NAME = tatami
BUNDLE = $(APP_NAME).app
INSTALL_DIR = /Applications/$(BUNDLE)
BUILD_DIR = .build/release

.PHONY: build install clean

build:
	swift build -c release

install: build
	@if [ ! -d "$(INSTALL_DIR)" ]; then \
		mkdir -p $(INSTALL_DIR)/Contents/MacOS; \
		cp Info.plist $(INSTALL_DIR)/Contents/; \
		codesign --force --sign - $(INSTALL_DIR); \
		echo "Fresh install to $(INSTALL_DIR)"; \
		echo "Grant Accessibility permission in System Settings, then: open /Applications/$(APP_NAME).app"; \
	fi
	cp $(BUILD_DIR)/$(APP_NAME) $(INSTALL_DIR)/Contents/MacOS/
	@echo "Updated $(INSTALL_DIR)"

clean:
	swift package clean
	rm -rf $(BUNDLE)

uninstall:
	rm -rf $(INSTALL_DIR)
