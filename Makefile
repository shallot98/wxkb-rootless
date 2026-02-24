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

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatKeyboardSwitch

WeChatKeyboardSwitch_FILES = Tweak.x
WeChatKeyboardSwitch_CFLAGS = -fobjc-arc -IHeaders -fno-modules
WeChatKeyboardSwitch_LDFLAGS = -undefined dynamic_lookup
WeChatKeyboardSwitch_INSTALL_TARGET_PROCESSES = wxkb_plugin WeType

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += WKSPreferences
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp WKSPreferences/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/com.yourname.wechatkeyboardswitch.plist$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/com.yourname.wechatkeyboardswitch$(ECHO_END)
	$(ECHO_NOTHING)cp WKSPreferences/Resources/icon.png $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/com.yourname.wechatkeyboardswitch/icon.png$(ECHO_END)
	$(ECHO_NOTHING)if [ "$(THEOS_PACKAGE_SCHEME)" = "roothide" ]; then ln -sf /usr/lib/DynamicPatches/AutoPatches.dylib "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/WKSPreferences.bundle/WKSPreferences.roothidepatch"; fi$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support/WeChatKeyboardSwitch$(ECHO_END)
	$(ECHO_NOTHING)cp SkinAssets/bda_back_dark.png $(THEOS_STAGING_DIR)/Library/Application\ Support/WeChatKeyboardSwitch/bda_back_dark.png$(ECHO_END)
	$(ECHO_NOTHING)cp SkinAssets/bda_back_light.png $(THEOS_STAGING_DIR)/Library/Application\ Support/WeChatKeyboardSwitch/bda_back_light.png$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support/WeChatKeyboardSwitch/llee_light$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/Application\ Support/WeChatKeyboardSwitch/llee_dark$(ECHO_END)
	$(ECHO_NOTHING)cp SkinAssets/llee_light/*lleeimage_*.png $(THEOS_STAGING_DIR)/Library/Application\ Support/WeChatKeyboardSwitch/llee_light/$(ECHO_END)
	$(ECHO_NOTHING)cp SkinAssets/llee_dark/*lleeimage_*.png $(THEOS_STAGING_DIR)/Library/Application\ Support/WeChatKeyboardSwitch/llee_dark/$(ECHO_END)

after-install::
	install.exec "killall -9 wxkb_plugin WeType || true"
