TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TOOL_NAME = tpctl

tpctl_FILES = main.c
tpctl_CFLAGS = -Wall -Werror
tpctl_CODESIGN_FLAGS = -Sentitlements.plist
tpctl_INSTALL_PATH = /usr/libexec/tweakpilot

include $(THEOS_MAKE_PATH)/tool.mk
