NDK_PATH ?= $(ANDROID_HOME)/ndk/29.0.13113456
.DEFAULT_GOAL := all

ARCH ?= $(shell uname -m)
ifeq ($(ARCH), x86_64)
	CCA ?= $(NDK_PATH)/toolchains/llvm/prebuilt/linux-x86_64/bin/clang
else
	CCA ?= clang
endif

BUILD_TYPE ?= debug
ifeq ($(BUILD_TYPE), debug)
	TYPE_CFLAGS = -g -O0 -DDEBUG
else
	TYPE_CFLAGS = -O3 -ffast-math -flto -fvisibility=hidden -Wl,-s -Wl,--gc-sections
endif

CFLAGS = -Wall

# Zygisk related variables
ZYGISK_FILES := src/main.c

VER_NAME ?= v1
VER_CODE ?= $(shell git rev-list HEAD --count)
COMMIT_HASH ?= $(shell git rev-parse --verify --short HEAD)
MODULE_ZIP ?= zygisk_example_module.zip

clean:
	@echo Cleaning build artifacts...
	@rm -rf build

installKsu: all
	su -c "/data/adb/ksud module install $(MODULE_ZIP)"

installMagisk: all
	su -M -c "magisk --install-module $(MODULE_ZIP)"

installAPatch: all
	su -c "/data/adb/apd module install $(MODULE_ZIP)"

all:
	@echo Creating build directory...
	@mkdir -p build/zygisk
	@cp -r module/* build

	@echo Building Zygisk library...
	@$(CCA) $(CFLAGS) $(TYPE_CFLAGS) --target=aarch64-linux-android25 -shared -fPIC $(ZYGISK_FILES) -Isrc/ -o build/zygisk/arm64-v8a.so -llog
	@$(CCA) $(CFLAGS) $(TYPE_CFLAGS) --target=armv7a-linux-androideabi25 -shared -fPIC $(ZYGISK_FILES) -Isrc/ -o build/zygisk/armeabi-v7a.so -llog
	@$(CCA) $(CFLAGS) $(TYPE_CFLAGS) --target=x86_64-linux-android25 -shared -fPIC $(ZYGISK_FILES) -Isrc/ -o build/zygisk/x86_64.so -llog
	@$(CCA) $(CFLAGS) $(TYPE_CFLAGS) --target=i686-linux-android25 -shared -fPIC $(ZYGISK_FILES) -Isrc/ -o build/zygisk/x86.so -llog

	@sed -e 's/$${versionName}/$(VER_NAME) ($(VER_CODE)-$(COMMIT_HASH)-$(BUILD_TYPE))/g' \
             -e 's/$${versionCode}/$(VER_CODE)/g' \
             module/module.prop > build/module.prop

	@echo Creating module zip...
	@cd build && zip -qr9 ../$(MODULE_ZIP) .
