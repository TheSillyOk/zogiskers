include common.mk

ifeq ($(BUILD_TYPE), debug)
	TYPE_CFLAGS := -g -O0 -DDEBUG
else
	TYPE_CFLAGS := -O3 -ffast-math -flto
endif

CFLAGS := -fno-unwind-tables -fno-asynchronous-unwind-tables -Wl,--gc-sections          \
		  -Wl,--icf=all -Wl,-z,norelro -Wl,--pack-dyn-relocs=relr -nostartfiles \
		  -Wl,--strip-all -Wl,--exclude-libs,ALL -Wl,-z,lazy           	        \
		  -fvisibility=hidden -Wl,--build-id=none -Wl,--as-needed               \
		  -Wall -Wextra -Wpedantic -Wno-gnu-flexible-array-initializer		\
		  -Wno-variadic-macros -Wno-variadic-macro-arguments-omitted            \
		  -Wno-gnu-zero-variadic-macro-arguments

ZYGISK_FILES := src/main.c

VERSION ?= $(VER_CODE)-$(COMMIT_HASH)-$(BUILD_TYPE)
MODULE_ZIP ?= $(MODULE_NAME)-$(VER_NAME)-$(VERSION).zip
ZIP_OUT ?= $(BUILD_DIR)/out/$(MODULE_ZIP)

ifeq ($(TERMUX_VERSION),)
	ADB_PUSH := adb push $(ZIP_OUT) /data/local/tmp
	ADB_SHELL := adb shell 
	INSTALL_PATH := /data/local/tmp/$(MODULE_ZIP)
else
	INSTALL_PATH := $(ZIP_OUT)
endif

.PHONY: zygisk build

all: debug release

debug:
	$(MAKE) -s build BUILD_TYPE=debug

release:
	$(MAKE) -s build BUILD_TYPE=release

clean:
	@echo Cleaning build artifacts...
	@rm -rf build

build:
	@echo Creating build directory...
	@mkdir -p $(BUILD_DIR)/$(BUILD_TYPE)/zygisk
	@cp -r module/* $(BUILD_DIR)/$(BUILD_TYPE)

	@echo Building Zygisk library...
	@for arch in $(ARCHS); do \
		$(MAKE) -s zygisk BUILD_TYPE=$(BUILD_TYPE) ARCH=$$arch; \
	done
	@sed -e 's/$${versionName}/$(VER_NAME) ($(VERSION))/g' \
             -e 's/$${versionCode}/$(VER_CODE)/g' \
             module/module.prop > build/$(BUILD_TYPE)/module.prop

	@echo Creating module zip...
	@mkdir -p $(BUILD_DIR)/out
	@cd $(BUILD_DIR)/$(BUILD_TYPE) && zip -qr9 ../out/$(MODULE_ZIP) .

zygisk:
	$(CC_ARCH) $(CFLAGS) $(TYPE_CFLAGS) -shared -fPIC $(ZYGISK_FILES) -Isrc/ -o $(BUILD_DIR)/$(BUILD_TYPE)/zygisk/$(ARCH).so -llog

installModule: build
	$(ADB_PUSH)
	@$(ADB_SHELL)su -M -c "magisk --install-module $(INSTALL_PATH) 2&>/dev/null"|| \
	$(ADB_SHELL)su -c "ksud module install $(INSTALL_PATH) 2&>/dev/null"||        \
	$(ADB_SHELL)su -c "apd module install $(INSTALL_PATH) 2&>/dev/null"           \
	|| echo "[X] Could not find valid CLI to install the module"

installModuleAndReboot: installModule
	$(ADB_SHELL)su -c reboot
