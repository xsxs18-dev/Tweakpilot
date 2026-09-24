TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Tweakpilot

Tweakpilot_FILES = Tweak.x $(wildcard Sources/*.m)
Tweakpilot_CFLAGS = -fobjc-arc -ISources
Tweakpilot_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += tpctl
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	$(ECHO_NOTHING)chmod 6755 $(THEOS_STAGING_DIR)/usr/libexec/tweakpilot/tpctl$(ECHO_END)
