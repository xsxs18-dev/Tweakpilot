TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME ?= roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Tweakpilot

Tweakpilot_FILES = Tweak.x $(wildcard Sources/*.m)
Tweakpilot_CFLAGS = -fobjc-arc -ISources

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
Tweakpilot_CFLAGS += -DTP_ROOTLESS
endif
Tweakpilot_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += tpctl
include $(THEOS_MAKE_PATH)/aggregate.mk

STAGED_ROOT = $(THEOS_STAGING_DIR)

after-stage::
	$(ECHO_NOTHING)chmod 6755 $(STAGED_ROOT)/usr/libexec/tweakpilot/tpctl$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(STAGED_ROOT)/Library/LaunchDaemons$(ECHO_END)
	$(ECHO_NOTHING)sed "s|@PREFIX@|$(THEOS_PACKAGE_INSTALL_PREFIX)|g" daemon/com.xsxs18.tweakpilotd.plist > $(STAGED_ROOT)/Library/LaunchDaemons/com.xsxs18.tweakpilotd.plist$(ECHO_END)
	$(ECHO_NOTHING)chmod 644 $(STAGED_ROOT)/Library/LaunchDaemons/com.xsxs18.tweakpilotd.plist$(ECHO_END)
