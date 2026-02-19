# 默认走 rootless；可通过命令行覆盖为 roothide
THEOS_PACKAGE_SCHEME ?= rootless

# rootless / roothide 默认使用 arm64，兼容 wxkb_plugin(arm64-only)
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
ARCHS ?= arm64
TARGET ?= iphone:clang:13.7:14.0
else ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
ARCHS ?= arm64
TARGET ?= iphone:clang:13.7:14.0
else
ARCHS ?= arm64
TARGET ?= iphone:clang:latest:13.0
endif

INSTALL_TARGET_PROCESSES = wxkb_plugin WeType

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatKeyboardSwitch

WeChatKeyboardSwitch_FILES = Tweak.x
WeChatKeyboardSwitch_CFLAGS = -fobjc-arc -IHeaders -fno-modules
WeChatKeyboardSwitch_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += WKSPreferences
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp WKSPreferences/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/com.yourname.wechatkeyboardswitch.plist$(ECHO_END)

after-install::
	install.exec "killall -9 wxkb_plugin WeType || true"
