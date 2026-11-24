include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = DynamicIslandDancePrefs
DynamicIslandDancePrefs_FILES = DIDRootListController.m
DynamicIslandDancePrefs_INSTALL_PATH = /Library/PreferenceBundles
DynamicIslandDancePrefs_RESOURCE_DIRS = Resources
DynamicIslandDancePrefs_FRAMEWORKS = UIKit CoreFoundation
DynamicIslandDancePrefs_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/bundle.mk

ADDITIONAL_LDFLAGS += -Wl,-undefined,dynamic_lookup
