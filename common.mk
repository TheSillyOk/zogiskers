ROOT_DIR ?= .
BUILD_TYPE ?= debug
API_LEVEL ?= 25
ARCHS ?= arm64-v8a armeabi-v7a x86 x86_64
ARCH ?= arm64-v8a

VER_NAME ?= v1
VER_CODE ?= $(shell git -C "$(ROOT_DIR)" rev-list HEAD --count 2>/dev/null || echo 1)
COMMIT_HASH ?= $(shell git -C "$(ROOT_DIR)" rev-parse --verify --short HEAD 2>/dev/null || echo unknown)

MODULE_ID ?= zogisko_one
MODULE_NAME ?= ZogiskOne

NDK_VERSION ?= 29.0.13113456
ANDROID_HOME ?= $(HOME)/Android/Sdk
NDK_PATH ?= $(ANDROID_HOME)/ndk/$(NDK_VERSION)
TOOLCHAIN ?= $(NDK_PATH)/toolchains/llvm/prebuilt/linux-x86_64
SYSROOT ?= $(TOOLCHAIN)/sysroot

ifneq ($(TERMUX_VERSION),)
    TERMUX_BUILD := 1
endif

ifneq ($(TERMUX_BUILD), 1)
	CC = $(TOOLCHAIN)/bin/clang
	AR = $(TOOLCHAIN)/bin/llvm-ar
	STRIP = $(TOOLCHAIN)/bin/llvm-strip
else
	CC = clang
	AR = llvm-ar
	STRIP = llvm-strip
endif

BUILD_DIR ?= $(ROOT_DIR)/build

TARGET_arm64-v8a = aarch64-linux-android$(API_LEVEL)
TARGET_armeabi-v7a = armv7a-linux-androideabi$(API_LEVEL)
TARGET_x86 = i686-linux-android$(API_LEVEL)
TARGET_x86_64 = x86_64-linux-android$(API_LEVEL)

CC_ARCH = $(CC) --target=$(TARGET_$(ARCH)) --sysroot=$(SYSROOT)
