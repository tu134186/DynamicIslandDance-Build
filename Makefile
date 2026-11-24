ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.5
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk
SUBPROJECTS += DynamicIslandDancePrefs

TWEAK_NAME = DynamicIslandDance
DynamicIslandDance_FILES = Tweak.xm
DynamicIslandDance_CFLAGS = -fobjc-arc
DynamicIslandDance_FRAMEWORKS = UIKit QuartzCore CoreFoundation CoreImage

include $(THEOS_MAKE_PATH)/tweak.mk

include $(THEOS_MAKE_PATH)/aggregate.mk