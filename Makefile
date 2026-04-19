include common.mk

ifeq ($(BUILD_TYPE), debug)
	TYPE_CFLAGS := -g -O0 -DDEBUG
else
	TYPE_CFLAGS := -O3 -ffast-math -flto -fvisibility=hidden -Wl,-s -Wl,--gc-sections
endif

CFLAGS := -Wall -Wextra -nostartfiles

ZYGISK_FILES := src/main.c

VERSION ?= $(VER_CODE)-$(COMMIT_HASH)-$(BUILD_TYPE)
MODULE_ZIP ?= $(MODULE_NAME)-$(VER_NAME)-$(VERSION).zip
ZIP_OUT ?= $(BUILD_DIR)/out/$(MODULE_ZIP)

ifneq ($(TERMUX_BUILD), 1)
	ADB_CMD := adb push $(ZIP_OUT) /data/local/tmp && adb shell 
	INSTALL_PATH := /data/local/tmp/$(MODULE_ZIP)
else
	ADB_CMD := 
	INSTALL_PATH := $(ZIP_OUT)
endif

.PHONY: build debug release installKsu installMagisk installAPatch

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

installKsu: build
	$(ADB_CMD)su -c "/data/adb/ksud module install $(INSTALL_PATH)"

installMagisk: build
	$(ADB_CMD)su -M -c "magisk --install-module $(INSTALL_PATH)"

installAPatch: build
	$(ADB_CMD)su -c "/data/adb/apd module install $(BUILD_DIR)/out/$(INSTALL_PATH)"
