#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <limits.h>
#import <math.h>
#import <stdint.h>
#import <CoreFoundation/CoreFoundation.h>

static BOOL gWKSSwipeEnabled = YES;
static BOOL gWKSInSwitch = NO;
static BOOL gWKSSwitchScheduled = NO;
static CFAbsoluteTime gWKSLastSwitchTs = 0;
__attribute__((unused)) static int gWKSSwipeCallbackDepth = 0;
static __weak id gWKSTextUpPanel = nil;
static uintptr_t gWKSTextUpTouchAddr = 0;
static CGPoint gWKSTextUpStartPoint = {0.0, 0.0};
static BOOL gWKSTextUpHasStartPoint = NO;
static CFAbsoluteTime gWKSTextUpArmedTs = 0;
static __weak id gWKSRecentMoveTriggerPanel = nil;
static uintptr_t gWKSRecentMoveTriggerTouchAddr = 0;
static CFAbsoluteTime gWKSRecentMoveTriggerTs = 0;
static CFAbsoluteTime gWKSLastNonNativeKeyTouchBeganTs = 0;

static const NSTimeInterval kWKSDebounceSeconds = 0.10;
static const NSTimeInterval kWKSScheduleDelaySeconds = 0.06;
static const NSTimeInterval kWKSSwitchCooldownSeconds = 0.12;
static const NSTimeInterval kWKSAdjustingRetryDelaySeconds = 0.06;
static const NSTimeInterval kWKSSwitchApplyDelaySeconds = 0.08;
static const int kWKSAdjustingMaxRetries = 10;
static const CGFloat kWKSTextUpMoveTriggerDistance = 14.0;
static const CGFloat kWKSTextUpMoveMaxHorizontal = 24.0;
static const CGFloat kWKSTextUpCancelTriggerDistance = 18.0;
static const CGFloat kWKSTextUpVerticalRatio = 1.25;
static const CGFloat kWKSTextUpKeyTopMargin = -6.0;
static const NSTimeInterval kWKSTextUpMinGestureAgeSeconds = 0.015;
static const CGFloat kWKSTextUpMinVelocity = 110.0; // pt/s，放宽速度门槛，优先保证触发稳定性
static const NSTimeInterval kWKSTextUpStateTTLSeconds = 0.65;
static const NSTimeInterval kWKSRecentMoveTriggerTTLSeconds = 0.35;
static const CGFloat kWKSHorizontalBlockMinDistance = 14.0;
static const CGFloat kWKSHorizontalBlockRatio = 1.60;
static const CGFloat kWKSSwipeEndTriggerDistance = 12.0;
static const NSTimeInterval kWKSSwipeEndMinGestureAgeSeconds = 0.01;
static const NSTimeInterval kWKSSwipeEndMaxGestureAgeSeconds = 1.50;
static const NSTimeInterval kWKSRecognizerTypingGuardSeconds = 0.02;

static void (*gOrigPanelSwipeUp)(id, SEL, id) = NULL;
static void (*gOrigPanelSwipeDown)(id, SEL, id) = NULL;
static void (*gOrigPanelSwipeEnded)(id, SEL, id, id) = NULL;
static void (*gOrigPanelAnySwipeBegan)(id, SEL, id, id) = NULL;
static void (*gOrigPanelAnySwipeMoved)(id, SEL, id, id) = NULL;
static void (*gOrigPanelTouchesCancelled)(id, SEL, id, id) = NULL;
static void (*gOrigPanelProcessTouchBegan)(id, SEL, id, id) = NULL;
static void (*gOrigPanelProcessTouchMoved)(id, SEL, id, id) = NULL;
static void (*gOrigPanelProcessTouchCancel)(id, SEL, id, id) = NULL;
static void (*gOrigPanelProcessTouchEnd)(id, SEL, id, id) = NULL;
static void (*gOrigPanelProcessTouchEndWithInterrupter)(id, SEL, id, id, id) = NULL;
static void (*gOrigPanelSwipeUpBegan)(id, SEL, id, id, BOOL) = NULL;
static void (*gOrigPanelSwipeUpMoved)(id, SEL, id, id) = NULL;
static void (*gOrigT9SwipeUp)(id, SEL, id) = NULL;
static void (*gOrigT9SwipeDown)(id, SEL, id) = NULL;
static void (*gOrigT9SwipeUpBegan)(id, SEL, id, id, BOOL) = NULL;
static void (*gOrigT9SwipeUpMoved)(id, SEL, id, id) = NULL;
static void (*gOrigT26SwipeUp)(id, SEL, id) = NULL;
static void (*gOrigT26SwipeDown)(id, SEL, id) = NULL;
static void (*gOrigT26SwipeUpBegan)(id, SEL, id, id, BOOL) = NULL;
static void (*gOrigT26SwipeUpMoved)(id, SEL, id, id) = NULL;
static long long (*gOrigPanelTryRecognizeSwipeTouch)(id, SEL, id, id, unsigned long long *, BOOL) = NULL;

static void (*gOrigPanelDidAttachHosting)(id, SEL) = NULL;
static void (*gOrigT9DidAttachHosting)(id, SEL) = NULL;
static void (*gOrigT26DidAttachHosting)(id, SEL) = NULL;

static void (*gOrigAppButtonLayoutSubviews)(id, SEL) = NULL;
static void (*gOrigButtonLayoutSubviews)(id, SEL) = NULL;
static void (*gOrigKeyViewLayoutSubviews)(id, SEL) = NULL;
static void (*gOrigTopBarLayoutSubviews)(id, SEL) = NULL;
static void (*gOrigToolBarAuxLayoutSubviews)(id, SEL) = NULL;

static void (*gOrigSymbolListDidAttachHosting)(id, SEL) = NULL;
static void (*gOrigGridBoderFillLayerFill)(id, SEL, CGSize, CGRect, CGSize) = NULL;
static void (*gOrigBorderLayerLayoutSublayers)(id, SEL) = NULL;
static void (*gOrigSymbolCellSetBorderPosition)(id, SEL, unsigned long long) = NULL;

static void WKSHandleSwipe(id context);
static void WKSAttemptToggleWhenReady(id context, int retries);
static void WKSResetSwipeRecognitionState(id panel);
static void WKSSwizzleClassMethod(Class cls, SEL sel, IMP newImp, IMP *oldStore);
static void WKSLoadPreferences(void);
static void WKSPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                  const void *object, CFDictionaryRef userInfo);
static BOOL WKSTouchHorizontalBlocked(id touch);
static BOOL WKSUseGestureRecognizerMode(void);
static BOOL WKSShouldAllowPanelSwipeTouch(id panel, UITouch *touch);
static void WKSHandlePanelSwipeGesture(id panel, UISwipeGestureRecognizer *gesture);
static void WKSEnsurePanelSwipeRecognizers(id panelObj);

@interface WKSPanelSwipeGestureBridge : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handlePanelSwipe:(UISwipeGestureRecognizer *)gesture;
@end

@implementation WKSPanelSwipeGestureBridge
+ (instancetype)shared {
    static WKSPanelSwipeGestureBridge *bridge = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bridge = [[WKSPanelSwipeGestureBridge alloc] init];
    });
    return bridge;
}

- (void)handlePanelSwipe:(UISwipeGestureRecognizer *)gesture {
    WKSHandlePanelSwipeGesture(gesture.view, gesture);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return WKSShouldAllowPanelSwipeTouch(gestureRecognizer.view, touch);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    (void)otherGestureRecognizer;
    return NO;
}
@end

static void WKSLoadPreferences(void) {
    CFPreferencesAppSynchronize(CFSTR("com.yourname.wechatkeyboardswitch"));
    CFTypeRef val = CFPreferencesCopyAppValue(CFSTR("swipeEnabled"),
                                              CFSTR("com.yourname.wechatkeyboardswitch"));
    if (val) {
        if (CFGetTypeID(val) == CFBooleanGetTypeID()) {
            gWKSSwipeEnabled = CFBooleanGetValue((CFBooleanRef)val);
        }
        CFRelease(val);
    } else {
        gWKSSwipeEnabled = YES; // 默认开启
    }
}

static void WKSPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                  const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    WKSLoadPreferences();
}

static const void *kWKSTouchStartPointAssocKey = &kWKSTouchStartPointAssocKey;
static const void *kWKSTouchKeepNativeSwipeAssocKey = &kWKSTouchKeepNativeSwipeAssocKey;
static const void *kWKSTouchSwitchTriggeredAssocKey = &kWKSTouchSwitchTriggeredAssocKey;
static const void *kWKSTouchHorizontalBlockedAssocKey = &kWKSTouchHorizontalBlockedAssocKey;
static const void *kWKSTouchBeganTsAssocKey = &kWKSTouchBeganTsAssocKey;
static const void *kWKSTouchSwitchHandledAssocKey = &kWKSTouchSwitchHandledAssocKey;
static const void *kWKSPanelSwipeUpRecognizerAssocKey = &kWKSPanelSwipeUpRecognizerAssocKey;
static const void *kWKSPanelSwipeDownRecognizerAssocKey = &kWKSPanelSwipeDownRecognizerAssocKey;

static BOOL WKSInvokeLongLongGetter(id obj, SEL sel, long long *outValue) {
    if (!obj || !sel || !outValue || ![obj respondsToSelector:sel]) {
        return NO;
    }

    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments < 2) {
        return NO;
    }

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:obj];
    [inv setSelector:sel];

    @try {
        [inv invoke];
        long long value = 0;
        [inv getReturnValue:&value];
        *outValue = value;
        return YES;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static long long WKSGetLongLongProperty(id obj, SEL sel, long long fallback) {
    long long value = fallback;
    if (WKSInvokeLongLongGetter(obj, sel, &value)) {
        return value;
    }
    return fallback;
}

static BOOL WKSInvokeVoidNoArg(id obj, SEL sel) {
    if (!obj || !sel || ![obj respondsToSelector:sel]) {
        return NO;
    }

    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments < 2) {
        return NO;
    }

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:obj];
    [inv setSelector:sel];

    @try {
        [inv invoke];
        return YES;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static BOOL WKSInvokeBoolNoArg(id obj, SEL sel, BOOL fallback) {
    if (!obj || !sel || ![obj respondsToSelector:sel]) {
        return fallback;
    }

    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments < 2) {
        return fallback;
    }

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:obj];
    [inv setSelector:sel];

    @try {
        [inv invoke];
        BOOL value = fallback;
        [inv getReturnValue:&value];
        return value;
    } @catch (__unused NSException *e) {
        return fallback;
    }
}

static BOOL WKSInvokeBoolWithObject(id obj, SEL sel, id arg, BOOL fallback) {
    if (!obj || !sel || ![obj respondsToSelector:sel]) {
        return fallback;
    }

    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments < 3) {
        return fallback;
    }

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:obj];
    [inv setSelector:sel];
    id argObj = arg;
    [inv setArgument:&argObj atIndex:2];

    @try {
        [inv invoke];
        BOOL value = fallback;
        [inv getReturnValue:&value];
        return value;
    } @catch (__unused NSException *e) {
        return fallback;
    }
}

static BOOL WKSInvokeSwitchEngineSession(id obj, long long panelType) {
    SEL sel = @selector(switchEngineSessionWithPanelViewType:force:complection:);
    if (!obj || ![obj respondsToSelector:sel]) {
        return NO;
    }

    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments < 5) {
        return NO;
    }

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:obj];
    [inv setSelector:sel];

    BOOL force = NO;
    id completion = nil;
    [inv setArgument:&panelType atIndex:2];
    [inv setArgument:&force atIndex:3];
    [inv setArgument:&completion atIndex:4];

    @try {
        [inv invoke];
        return YES;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static id WKSGetPanelHosting(id panel) {
    if (!panel) {
        return nil;
    }

    @try {
        id host = [panel valueForKey:@"hosting"];
        if (host) {
            return host;
        }
    } @catch (__unused NSException *e) {
    }

    Class cls = [panel class];
    while (cls) {
        Ivar ivar = class_getInstanceVariable(cls, "_hosting");
        if (!ivar) {
            cls = class_getSuperclass(cls);
            continue;
        }
        id host = object_getIvar(panel, ivar);
        if (host) {
            return host;
        }
        break;
    }
    return nil;
}

static BOOL WKSStringLooksSpaceKey(NSString *value) {
    if (value.length == 0) {
        return NO;
    }
    if ([value isEqualToString:@" "]) {
        return YES;
    }
    NSString *text = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        return NO;
    }
    NSString *lower = text.lowercaseString;
    return [lower isEqualToString:@"space"] ||
           [lower isEqualToString:@"blank"] ||
           [text isEqualToString:@"空格"] ||
           [lower containsString:@"space"] ||
           [lower containsString:@"blank"] ||
           [text containsString:@"空格"];
}

static BOOL WKSStringLooksDeleteKey(NSString *value) {
    if (value.length == 0) {
        return NO;
    }
    NSString *text = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        return NO;
    }
    NSString *lower = text.lowercaseString;
    return [lower isEqualToString:@"delete"] ||
           [lower isEqualToString:@"backspace"] ||
           [text isEqualToString:@"删除"] ||
           [text isEqualToString:@"退格"] ||
           [lower containsString:@"delete"] ||
           [lower containsString:@"backspace"] ||
           [text containsString:@"删除"] ||
           [text containsString:@"退格"] ||
           [text containsString:@"⌫"] ||
           [text containsString:@"←"];
}

static NSString *WKSStringForKVC(id obj, NSString *key) {
    if (!obj || key.length == 0) {
        return nil;
    }
    @try {
        id value = [obj valueForKey:key];
        if ([value isKindOfClass:[NSString class]]) {
            return (NSString *)value;
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
}

static id WKSFindKeyViewFromView(id viewObj) {
    Class keyViewClass = objc_getClass("WBKeyView");
    UIView *cursor = [viewObj isKindOfClass:[UIView class]] ? (UIView *)viewObj : nil;
    for (int i = 0; cursor && i < 8; i++) {
        if ((keyViewClass && [cursor isKindOfClass:keyViewClass]) ||
            [NSStringFromClass([cursor class]) containsString:@"WBKeyView"]) {
            return cursor;
        }
        cursor = cursor.superview;
    }
    return nil;
}

static id WKSExtractTouchLikeObject(id arg) {
    if (!arg) {
        return nil;
    }
    if ([arg isKindOfClass:[NSSet class]]) {
        return [(NSSet *)arg anyObject];
    }
    if ([arg isKindOfClass:[UIEvent class]]) {
        return [[(UIEvent *)arg allTouches] anyObject];
    }
    return arg;
}

static uintptr_t WKSAddressForTouchArg(id arg) {
    id touchLike = WKSExtractTouchLikeObject(arg);
    return touchLike ? (uintptr_t)(__bridge void *)touchLike : (uintptr_t)0;
}

static BOOL WKSGetTouchLocationInPanel(id touchArg, id panel, CGPoint *outPoint) {
    if (!panel || ![panel isKindOfClass:[UIView class]]) {
        return NO;
    }
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike || ![touchLike respondsToSelector:@selector(locationInView:)]) {
        return NO;
    }
    @try {
        CGPoint p = [(UITouch *)touchLike locationInView:(UIView *)panel];
        if (outPoint) {
            *outPoint = p;
        }
        return YES;
    } @catch (__unused NSException *e) {
        return NO;
    }
}

static void WKSSetTouchStartPoint(id touchArg, CGPoint point) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return;
    }
    @try {
        objc_setAssociatedObject(touchLike, kWKSTouchStartPointAssocKey,
                                 [NSValue valueWithCGPoint:point],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {
    }
}

static BOOL WKSGetTouchStartPoint(id touchArg, CGPoint *outPoint) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return NO;
    }
    @try {
        id value = objc_getAssociatedObject(touchLike, kWKSTouchStartPointAssocKey);
        if ([value isKindOfClass:[NSValue class]]) {
            if (outPoint) {
                *outPoint = [(NSValue *)value CGPointValue];
            }
            return YES;
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static void WKSSetTouchKeepNativeSwipe(id touchArg, BOOL keepNative) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return;
    }
    @try {
        objc_setAssociatedObject(touchLike, kWKSTouchKeepNativeSwipeAssocKey,
                                 @(keepNative), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {
    }
}

static BOOL WKSGetTouchKeepNativeSwipe(id touchArg, BOOL *outKeepNative) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return NO;
    }
    @try {
        id value = objc_getAssociatedObject(touchLike, kWKSTouchKeepNativeSwipeAssocKey);
        if ([value isKindOfClass:[NSNumber class]]) {
            if (outKeepNative) {
                *outKeepNative = [(NSNumber *)value boolValue];
            }
            return YES;
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static void WKSSetTouchSwitchTriggered(id touchArg, BOOL triggered) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return;
    }
    @try {
        objc_setAssociatedObject(touchLike, kWKSTouchSwitchTriggeredAssocKey,
                                 @(triggered), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {
    }
}

static BOOL WKSGetTouchSwitchTriggered(id touchArg, BOOL *outTriggered) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return NO;
    }
    @try {
        id value = objc_getAssociatedObject(touchLike, kWKSTouchSwitchTriggeredAssocKey);
        if ([value isKindOfClass:[NSNumber class]]) {
            if (outTriggered) {
                *outTriggered = [(NSNumber *)value boolValue];
            }
            return YES;
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static void WKSSetTouchHorizontalBlocked(id touchArg, BOOL blocked) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return;
    }
    @try {
        objc_setAssociatedObject(touchLike, kWKSTouchHorizontalBlockedAssocKey,
                                 @(blocked), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {
    }
}

static BOOL WKSGetTouchHorizontalBlocked(id touchArg, BOOL *outBlocked) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return NO;
    }
    @try {
        id value = objc_getAssociatedObject(touchLike, kWKSTouchHorizontalBlockedAssocKey);
        if ([value isKindOfClass:[NSNumber class]]) {
            if (outBlocked) {
                *outBlocked = [(NSNumber *)value boolValue];
            }
            return YES;
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static void WKSSetTouchBeganTimestamp(id touchArg, CFAbsoluteTime ts) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return;
    }
    @try {
        objc_setAssociatedObject(touchLike, kWKSTouchBeganTsAssocKey,
                                 @(ts), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {
    }
}

static BOOL WKSGetTouchBeganTimestamp(id touchArg, CFAbsoluteTime *outTs) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return NO;
    }
    @try {
        id value = objc_getAssociatedObject(touchLike, kWKSTouchBeganTsAssocKey);
        if ([value isKindOfClass:[NSNumber class]]) {
            if (outTs) {
                *outTs = [(NSNumber *)value doubleValue];
            }
            return YES;
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static void WKSSetTouchSwitchHandled(id touchArg, BOOL handled) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return;
    }
    @try {
        objc_setAssociatedObject(touchLike, kWKSTouchSwitchHandledAssocKey,
                                 @(handled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {
    }
}

__attribute__((unused)) static BOOL WKSTouchSwitchHandled(id touchArg) {
    id touchLike = WKSExtractTouchLikeObject(touchArg);
    if (!touchLike) {
        return NO;
    }
    @try {
        id value = objc_getAssociatedObject(touchLike, kWKSTouchSwitchHandledAssocKey);
        if ([value isKindOfClass:[NSNumber class]]) {
            return [(NSNumber *)value boolValue];
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static id WKSGetSwipeKeyView(id panel, id swipeArg) {
    id obj = WKSExtractTouchLikeObject(swipeArg);
    id keyView = WKSFindKeyViewFromView(obj);
    if (!keyView && [obj respondsToSelector:@selector(view)]) {
        @try {
            keyView = WKSFindKeyViewFromView([obj view]);
        } @catch (__unused NSException *e) {
        }
    }
    if (keyView) {
        return keyView;
    }

    // 兜底：从面板私有字段提取当前识别中的 keyView。
    NSArray<NSString *> *keys = @[
        @"_recognizingSwipeView",
        @"_recognizingSwipeUpView",
        @"_recognizingSwipeDownView",
        @"_currentTouchView"
    ];
    for (NSString *key in keys) {
        @try {
            id value = [panel valueForKey:key];
            id fromView = WKSFindKeyViewFromView(value);
            if (fromView) {
                return fromView;
            }
        } @catch (__unused NSException *e) {
        }
    }
    return nil;
}

static BOOL WKSIsSpaceKeyView(id keyView) {
    if (!keyView) {
        return NO;
    }

    NSArray<NSString *> *directKeys = @[@"defaultTitle", @"defaultInputForNormalState"];
    for (NSString *key in directKeys) {
        if (WKSStringLooksSpaceKey(WKSStringForKVC(keyView, key))) {
            return YES;
        }
    }

    id item = nil;
    @try {
        item = [keyView valueForKey:@"item"];
    } @catch (__unused NSException *e) {
    }
    NSArray<NSString *> *itemKeys = @[@"identifier", @"title", @"input", @"upInput"];
    for (NSString *key in itemKeys) {
        if (WKSStringLooksSpaceKey(WKSStringForKVC(item, key))) {
            return YES;
        }
    }
    return NO;
}

static BOOL WKSIsDeleteKeyView(id keyView) {
    if (!keyView) {
        return NO;
    }

    NSArray<NSString *> *directKeys = @[@"defaultTitle", @"defaultInputForNormalState"];
    for (NSString *key in directKeys) {
        if (WKSStringLooksDeleteKey(WKSStringForKVC(keyView, key))) {
            return YES;
        }
    }

    id item = nil;
    @try {
        item = [keyView valueForKey:@"item"];
    } @catch (__unused NSException *e) {
    }
    NSArray<NSString *> *itemKeys = @[@"identifier", @"title", @"input", @"upInput"];
    for (NSString *key in itemKeys) {
        if (WKSStringLooksDeleteKey(WKSStringForKVC(item, key))) {
            return YES;
        }
    }
    return NO;
}

static BOOL WKSPanelIsDeleteKeyView(id panel, id keyView) {
    if (WKSIsDeleteKeyView(keyView)) {
        return YES;
    }
    if (!panel || !keyView) {
        return NO;
    }

    id deleteManager = nil;
    @try {
        deleteManager = [panel valueForKey:@"_deleteManager"];
    } @catch (__unused NSException *e) {
    }
    if (!deleteManager) {
        @try {
            deleteManager = [panel valueForKey:@"deleteManager"];
        } @catch (__unused NSException *e) {
        }
    }
    if (!deleteManager) {
        return NO;
    }

    if (WKSInvokeBoolWithObject(deleteManager, @selector(checkDetectSwipeDelete:), keyView, NO)) {
        return YES;
    }

    @try {
        id detectingKeyView = [deleteManager valueForKey:@"detectingSwipeKeyView"];
        if (detectingKeyView == keyView) {
            return YES;
        }
    } @catch (__unused NSException *e) {
    }
    @try {
        id managerKeyView = [deleteManager valueForKey:@"keyView"];
        if (managerKeyView == keyView) {
            return YES;
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

static void WKSPrimeTouchKeepNativeSwipeFromArg(id panel, id swipeArg) {
    if (!panel || !swipeArg) {
        return;
    }
    id keyView = WKSGetSwipeKeyView(panel, swipeArg);
    if (!keyView) {
        return;
    }
    BOOL keepNative = WKSIsSpaceKeyView(keyView) || WKSPanelIsDeleteKeyView(panel, keyView);
    WKSSetTouchKeepNativeSwipe(swipeArg, keepNative);
}

static BOOL WKSShouldKeepNativeSpaceSwipe(id panel, id swipeArg) {
    WKSPrimeTouchKeepNativeSwipeFromArg(panel, swipeArg);
    BOOL keepNative = NO;
    if (WKSGetTouchKeepNativeSwipe(swipeArg, &keepNative)) {
        return keepNative;
    }
    id keyView = WKSGetSwipeKeyView(panel, swipeArg);
    return WKSIsSpaceKeyView(keyView) || WKSPanelIsDeleteKeyView(panel, keyView);
}

static BOOL WKSShouldIgnoreDeleteSwipe(id panel, id swipeArg) {
    (void)panel;
    (void)swipeArg;
    return NO;
}

static BOOL WKSUseGestureRecognizerMode(void) {
    // 方案 C：使用键盘级 UISwipeGestureRecognizer，弱化按键级 touch 兜底判定。
    return YES;
}

static id WKSGetKeyViewAtPanelPoint(id panel, CGPoint point) {
    if (!panel || ![panel isKindOfClass:[UIView class]]) {
        return nil;
    }
    UIView *panelView = (UIView *)panel;
    UIView *hitView = [panelView hitTest:point withEvent:nil];
    id keyView = WKSFindKeyViewFromView(hitView);
    if (keyView) {
        return keyView;
    }
    @try {
        return WKSFindKeyViewFromView([panel valueForKey:@"_currentTouchView"]);
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static id WKSGetKeyViewFromTouch(id panel, UITouch *touch) {
    if (!panel || !touch || ![panel isKindOfClass:[UIView class]]) {
        return nil;
    }
    id keyFromTouchView = WKSFindKeyViewFromView(touch.view);
    if (keyFromTouchView) {
        return keyFromTouchView;
    }
    UIView *panelView = (UIView *)panel;
    CGPoint point = [touch locationInView:panelView];
    return WKSGetKeyViewAtPanelPoint(panel, point);
}

static BOOL WKSGesturePointShouldKeepNative(id panel, CGPoint point) {
    id keyView = WKSGetKeyViewAtPanelPoint(panel, point);
    if (!keyView) {
        return NO;
    }
    (void)panel;
    return WKSIsSpaceKeyView(keyView) || WKSIsDeleteKeyView(keyView);
}

static BOOL WKSShouldAllowPanelSwipeTouch(id panel, UITouch *touch) {
    if (!WKSUseGestureRecognizerMode() || !gWKSSwipeEnabled) {
        return NO;
    }
    if (!panel || !touch || ![panel isKindOfClass:[UIView class]]) {
        return NO;
    }
    id keyView = WKSGetKeyViewFromTouch(panel, touch);
    if (keyView && (WKSIsSpaceKeyView(keyView) || WKSIsDeleteKeyView(keyView))) {
        return NO;
    }
    return YES;
}

static void WKSHandlePanelSwipeGesture(id panel, UISwipeGestureRecognizer *gesture) {
    if (!WKSUseGestureRecognizerMode() || !gWKSSwipeEnabled) {
        return;
    }
    if (!panel || !gesture || ![panel isKindOfClass:[UIView class]]) {
        return;
    }
    if (gesture.state != UIGestureRecognizerStateRecognized &&
        gesture.state != UIGestureRecognizerStateEnded) {
        return;
    }

    UIView *panelView = (UIView *)panel;
    CGPoint point = [gesture locationInView:panelView];
    if (WKSGesturePointShouldKeepNative(panel, point)) {
        return;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if ((now - gWKSLastNonNativeKeyTouchBeganTs) < kWKSRecognizerTypingGuardSeconds) {
        return;
    }

    WKSResetSwipeRecognitionState(panel);
    WKSHandleSwipe(panel);
}

static void WKSEnsurePanelSwipeRecognizers(id panelObj) {
    if (!WKSUseGestureRecognizerMode() || !panelObj || ![panelObj isKindOfClass:[UIView class]]) {
        return;
    }
    UIView *panel = (UIView *)panelObj;
    WKSPanelSwipeGestureBridge *bridge = [WKSPanelSwipeGestureBridge shared];

    UISwipeGestureRecognizer *swipeUp = objc_getAssociatedObject(panel, kWKSPanelSwipeUpRecognizerAssocKey);
    if (!swipeUp) {
        swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:bridge
                                                            action:@selector(handlePanelSwipe:)];
        swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
        swipeUp.numberOfTouchesRequired = 1;
        swipeUp.cancelsTouchesInView = NO;
        swipeUp.delaysTouchesBegan = NO;
        swipeUp.delaysTouchesEnded = NO;
        swipeUp.delegate = bridge;
        [panel addGestureRecognizer:swipeUp];
        objc_setAssociatedObject(panel, kWKSPanelSwipeUpRecognizerAssocKey,
                                 swipeUp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UISwipeGestureRecognizer *swipeDown = objc_getAssociatedObject(panel, kWKSPanelSwipeDownRecognizerAssocKey);
    if (!swipeDown) {
        swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:bridge
                                                              action:@selector(handlePanelSwipe:)];
        swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
        swipeDown.numberOfTouchesRequired = 1;
        swipeDown.cancelsTouchesInView = NO;
        swipeDown.delaysTouchesBegan = NO;
        swipeDown.delaysTouchesEnded = NO;
        swipeDown.delegate = bridge;
        [panel addGestureRecognizer:swipeDown];
        objc_setAssociatedObject(panel, kWKSPanelSwipeDownRecognizerAssocKey,
                                 swipeDown, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    swipeUp.enabled = gWKSSwipeEnabled;
    swipeDown.enabled = gWKSSwipeEnabled;

    for (UIGestureRecognizer *recognizer in panel.gestureRecognizers) {
        if (recognizer == swipeUp || recognizer == swipeDown) {
            continue;
        }
        [recognizer requireGestureRecognizerToFail:swipeUp];
        [recognizer requireGestureRecognizerToFail:swipeDown];
    }
}

static BOOL WKSPanelShouldUseTextUpMoveMode(id panel, id swipeArg) {
    if (WKSUseGestureRecognizerMode()) {
        // 识别器模式下关闭 move 备用链路，避免快打时按键轨迹被误判为切换手势。
        return NO;
    }
    return (panel && !WKSShouldKeepNativeSpaceSwipe(panel, swipeArg));
}

static BOOL WKSIsPredominantlyHorizontalSwipe(id panel, id swipeArg) {
    if (!panel) {
        return NO;
    }
    CGPoint startPoint = CGPointZero;
    CGPoint currentPoint = CGPointZero;
    if (!WKSGetTouchStartPoint(swipeArg, &startPoint) ||
        !WKSGetTouchLocationInPanel(swipeArg, panel, &currentPoint)) {
        return NO;
    }
    CGFloat dx = currentPoint.x - startPoint.x;
    CGFloat dy = currentPoint.y - startPoint.y;
    CGFloat absDx = (CGFloat)fabs(dx);
    CGFloat absDy = (CGFloat)fabs(dy);
    return (absDx >= kWKSHorizontalBlockMinDistance &&
            absDx > (absDy * kWKSHorizontalBlockRatio));
}

static void WKSClearTextUpMoveState(void) {
    gWKSTextUpPanel = nil;
    gWKSTextUpTouchAddr = 0;
    gWKSTextUpStartPoint = CGPointZero;
    gWKSTextUpHasStartPoint = NO;
    gWKSTextUpArmedTs = 0;
}

static void WKSClearTextUpMoveStateForPanel(id panel) {
    if (panel && gWKSTextUpPanel == panel) {
        WKSClearTextUpMoveState();
    }
}

static void WKSArmTextUpMoveState(id panel, id swipeArg) {
    if (!panel) {
        return;
    }
    gWKSTextUpPanel = panel;
    gWKSTextUpTouchAddr = WKSAddressForTouchArg(swipeArg);
    gWKSTextUpArmedTs = CFAbsoluteTimeGetCurrent();
    gWKSTextUpHasStartPoint = WKSGetTouchLocationInPanel(swipeArg, panel, &gWKSTextUpStartPoint);
    if (gWKSTextUpHasStartPoint) {
        WKSSetTouchStartPoint(swipeArg, gWKSTextUpStartPoint);
    }
}

static BOOL WKSTextUpMoveTouchMatches(id swipeArg) {
    if (gWKSTextUpTouchAddr == 0) {
        return YES;
    }
    uintptr_t touchAddr = WKSAddressForTouchArg(swipeArg);
    return (touchAddr == 0 || touchAddr == gWKSTextUpTouchAddr);
}

static void WKSClearRecentMoveTrigger(void) {
    gWKSRecentMoveTriggerPanel = nil;
    gWKSRecentMoveTriggerTouchAddr = 0;
    gWKSRecentMoveTriggerTs = 0;
}

static void WKSMarkRecentMoveTrigger(id panel, id swipeArg) {
    gWKSRecentMoveTriggerPanel = panel;
    gWKSRecentMoveTriggerTouchAddr = WKSAddressForTouchArg(swipeArg);
    gWKSRecentMoveTriggerTs = CFAbsoluteTimeGetCurrent();
}

static BOOL WKSHasRecentMoveTrigger(id panel, id swipeArg) {
    if (!panel || panel != gWKSRecentMoveTriggerPanel) {
        return NO;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if ((now - gWKSRecentMoveTriggerTs) > kWKSRecentMoveTriggerTTLSeconds) {
        WKSClearRecentMoveTrigger();
        return NO;
    }
    uintptr_t touchAddr = WKSAddressForTouchArg(swipeArg);
    if (gWKSRecentMoveTriggerTouchAddr != 0 && touchAddr != 0 &&
        gWKSRecentMoveTriggerTouchAddr != touchAddr) {
        return NO;
    }
    return YES;
}

__attribute__((unused)) static BOOL WKSConsumeRecentMoveTrigger(id panel, id swipeArg) {
    if (!WKSHasRecentMoveTrigger(panel, swipeArg)) {
        return NO;
    }
    WKSClearRecentMoveTrigger();
    return YES;
}

static void WKSHandleTextUpSwipeBegan(id panel, id swipeArg) {
    if (WKSPanelShouldUseTextUpMoveMode(panel, swipeArg)) {
        WKSArmTextUpMoveState(panel, swipeArg);
    } else {
        WKSClearTextUpMoveStateForPanel(panel);
    }
}

static BOOL WKSIsValidUpSwipeDelta(CGFloat dy, CGFloat dx, CGFloat minDistance, CGFloat maxHorizontal) {
    if (dy > -minDistance) {
        return NO;
    }
    CGFloat absDx = (CGFloat)fabs(dx);
    if (absDx > maxHorizontal) {
        return NO;
    }
    CGFloat absDy = (CGFloat)fabs(dy);
    return (absDy >= absDx * kWKSTextUpVerticalRatio);
}

__attribute__((unused)) static BOOL WKSIsValidDownSwipeDelta(CGFloat dy, CGFloat dx, CGFloat minDistance, CGFloat maxHorizontal) {
    if (dy < minDistance) {
        return NO;
    }
    CGFloat absDx = (CGFloat)fabs(dx);
    if (absDx > maxHorizontal) {
        return NO;
    }
    CGFloat absDy = (CGFloat)fabs(dy);
    return (absDy >= absDx * kWKSTextUpVerticalRatio);
}

static BOOL WKSIsValidUpSwipeKeyPosition(id panel, id swipeArg, CGPoint startPoint, CGPoint currentPoint) {
    if (!panel || ![panel isKindOfClass:[UIView class]]) {
        return YES;
    }
    id keyView = WKSGetSwipeKeyView(panel, swipeArg);
    if (!keyView || ![keyView isKindOfClass:[UIView class]]) {
        return YES;
    }
    UIView *keyViewObj = (UIView *)keyView;
    CGRect keyFrame = [keyViewObj convertRect:keyViewObj.bounds toView:(UIView *)panel];
    if (CGRectIsEmpty(keyFrame)) {
        return YES;
    }
    if (!CGRectContainsPoint(keyFrame, startPoint)) {
        return NO;
    }
    // 中短划也放宽出界要求，减少“必须滑很远”才触发的问题
    CGFloat absDy = (CGFloat)fabs(currentPoint.y - startPoint.y);
    if (absDy >= 14.0) {
        return YES;
    }
    return (currentPoint.y <= (CGRectGetMinY(keyFrame) - kWKSTextUpKeyTopMargin));
}

__attribute__((unused)) static BOOL WKSIsValidDownSwipeKeyPosition(id panel, id swipeArg, CGPoint startPoint, CGPoint currentPoint) {
    if (!panel || ![panel isKindOfClass:[UIView class]]) {
        return YES;
    }
    id keyView = WKSGetSwipeKeyView(panel, swipeArg);
    if (!keyView || ![keyView isKindOfClass:[UIView class]]) {
        return YES;
    }
    UIView *keyViewObj = (UIView *)keyView;
    CGRect keyFrame = [keyViewObj convertRect:keyViewObj.bounds toView:(UIView *)panel];
    if (CGRectIsEmpty(keyFrame)) {
        return YES;
    }
    if (!CGRectContainsPoint(keyFrame, startPoint)) {
        return NO;
    }
    CGFloat absDy = (CGFloat)fabs(currentPoint.y - startPoint.y);
    if (absDy >= 14.0) {
        return YES;
    }
    return (currentPoint.y >= (CGRectGetMaxY(keyFrame) + kWKSTextUpKeyTopMargin));
}

__attribute__((unused)) static BOOL WKSGetSwipeMetrics(id panel, id swipeArg,
                                                       CGPoint *outStartPoint, CGPoint *outCurrentPoint,
                                                       CGFloat *outDx, CGFloat *outDy, CFAbsoluteTime *outAge) {
    if (!panel) {
        return NO;
    }
    CGPoint startPoint = CGPointZero;
    CGPoint currentPoint = CGPointZero;
    BOOL hasStartPoint = WKSGetTouchStartPoint(swipeArg, &startPoint);
    if (!hasStartPoint && panel == gWKSTextUpPanel && gWKSTextUpHasStartPoint &&
        WKSTextUpMoveTouchMatches(swipeArg)) {
        startPoint = gWKSTextUpStartPoint;
        hasStartPoint = YES;
    }
    if (!hasStartPoint || !WKSGetTouchLocationInPanel(swipeArg, panel, &currentPoint)) {
        return NO;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime beganTs = 0;
    if (!WKSGetTouchBeganTimestamp(swipeArg, &beganTs)) {
        if (panel == gWKSTextUpPanel && gWKSTextUpArmedTs > 0.0 && WKSTextUpMoveTouchMatches(swipeArg)) {
            beganTs = gWKSTextUpArmedTs;
        } else {
            beganTs = now - kWKSSwipeEndMinGestureAgeSeconds;
        }
    }
    CFAbsoluteTime age = now - beganTs;

    if (outStartPoint) {
        *outStartPoint = startPoint;
    }
    if (outCurrentPoint) {
        *outCurrentPoint = currentPoint;
    }
    if (outDx) {
        *outDx = currentPoint.x - startPoint.x;
    }
    if (outDy) {
        *outDy = currentPoint.y - startPoint.y;
    }
    if (outAge) {
        *outAge = age;
    }
    return YES;
}

__attribute__((unused)) static BOOL WKSShouldTriggerSwitchForDirection(id panel, id swipeArg, BOOL upward, BOOL allowMissingMetrics) {
    CGPoint startPoint = CGPointZero;
    CGPoint currentPoint = CGPointZero;
    CGFloat dx = 0.0;
    CGFloat dy = 0.0;
    CFAbsoluteTime age = 0.0;
    if (!WKSGetSwipeMetrics(panel, swipeArg,
                            &startPoint, &currentPoint,
                            &dx, &dy, &age)) {
        return allowMissingMetrics;
    }

    if (age < kWKSSwipeEndMinGestureAgeSeconds || age > kWKSSwipeEndMaxGestureAgeSeconds) {
        return NO;
    }

    if (upward) {
        return WKSIsValidUpSwipeDelta(dy, dx, kWKSSwipeEndTriggerDistance, kWKSTextUpMoveMaxHorizontal) &&
               WKSIsValidUpSwipeKeyPosition(panel, swipeArg, startPoint, currentPoint);
    }
    return WKSIsValidDownSwipeDelta(dy, dx, kWKSSwipeEndTriggerDistance, kWKSTextUpMoveMaxHorizontal) &&
           WKSIsValidDownSwipeKeyPosition(panel, swipeArg, startPoint, currentPoint);
}

static void WKSTryHandleTextUpSwipeMoved(id panel, id swipeArg) {
    if (!panel) {
        return;
    }
    if (WKSHasRecentMoveTrigger(panel, swipeArg)) {
        return;
    }
    if (gWKSTextUpPanel != panel) {
        if (WKSPanelShouldUseTextUpMoveMode(panel, swipeArg)) {
            WKSArmTextUpMoveState(panel, swipeArg);
        }
        return;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if ((now - gWKSTextUpArmedTs) > kWKSTextUpStateTTLSeconds) {
        WKSClearTextUpMoveState();
        return;
    }
    if ((now - gWKSTextUpArmedTs) < kWKSTextUpMinGestureAgeSeconds) {
        return;
    }
    if (!WKSTextUpMoveTouchMatches(swipeArg)) {
        return;
    }

    CGPoint currentPoint = CGPointZero;
    if (!WKSGetTouchLocationInPanel(swipeArg, panel, &currentPoint)) {
        return;
    }
    CGPoint startPoint = gWKSTextUpStartPoint;
    BOOL hasStartPoint = gWKSTextUpHasStartPoint;
    if (WKSGetTouchStartPoint(swipeArg, &startPoint)) {
        hasStartPoint = YES;
        gWKSTextUpStartPoint = startPoint;
        gWKSTextUpHasStartPoint = YES;
    }
    if (!hasStartPoint) {
        gWKSTextUpStartPoint = currentPoint;
        gWKSTextUpHasStartPoint = YES;
        WKSSetTouchStartPoint(swipeArg, currentPoint);
        return;
    }

    CGFloat dy = currentPoint.y - startPoint.y;
    CGFloat dx = currentPoint.x - startPoint.x;
    CFAbsoluteTime elapsed = now - gWKSTextUpArmedTs;
    CGFloat velocity = (elapsed > 0.001) ? (CGFloat)(fabs(dy) / elapsed) : 0.0;
    if (WKSIsValidUpSwipeDelta(dy, dx, kWKSTextUpMoveTriggerDistance, kWKSTextUpMoveMaxHorizontal) &&
        WKSIsValidUpSwipeKeyPosition(panel, swipeArg, startPoint, currentPoint) &&
        velocity >= kWKSTextUpMinVelocity) {
        WKSSetTouchSwitchHandled(swipeArg, YES);
        WKSSetTouchSwitchTriggered(swipeArg, YES);
        WKSMarkRecentMoveTrigger(panel, swipeArg);
        WKSClearTextUpMoveState();
        WKSResetSwipeRecognitionState(panel);
        WKSHandleSwipe(panel);
    }
}

static void WKSTryHandleTextUpSwipeCancelled(id panel, id swipeArg) {
    if (!panel || gWKSTextUpPanel != panel || WKSHasRecentMoveTrigger(panel, swipeArg)) {
        WKSClearTextUpMoveStateForPanel(panel);
        return;
    }
    CGPoint startPoint = gWKSTextUpStartPoint;
    BOOL hasStartPoint = gWKSTextUpHasStartPoint;
    if (WKSGetTouchStartPoint(swipeArg, &startPoint)) {
        hasStartPoint = YES;
    }
    if (!WKSTextUpMoveTouchMatches(swipeArg) || !hasStartPoint) {
        WKSClearTextUpMoveStateForPanel(panel);
        return;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if ((now - gWKSTextUpArmedTs) > kWKSTextUpStateTTLSeconds) {
        WKSClearTextUpMoveStateForPanel(panel);
        return;
    }
    if ((now - gWKSTextUpArmedTs) < kWKSTextUpMinGestureAgeSeconds) {
        WKSClearTextUpMoveStateForPanel(panel);
        return;
    }

    CGPoint currentPoint = CGPointZero;
    if (!WKSGetTouchLocationInPanel(swipeArg, panel, &currentPoint)) {
        WKSClearTextUpMoveStateForPanel(panel);
        return;
    }

    CGFloat dy = currentPoint.y - startPoint.y;
    CGFloat dx = currentPoint.x - startPoint.x;
    if (WKSIsValidUpSwipeDelta(dy, dx, kWKSTextUpCancelTriggerDistance, kWKSTextUpMoveMaxHorizontal) &&
        WKSIsValidUpSwipeKeyPosition(panel, swipeArg, startPoint, currentPoint)) {
        WKSSetTouchSwitchHandled(swipeArg, YES);
        WKSSetTouchSwitchTriggered(swipeArg, YES);
        WKSMarkRecentMoveTrigger(panel, swipeArg);
        WKSClearTextUpMoveStateForPanel(panel);
        WKSHandleSwipe(panel);
        return;
    }
    WKSClearTextUpMoveStateForPanel(panel);
}

static void WKSForceDisableCursorMoveState(id panel) {
    if (!panel) {
        return;
    }
    @try {
        [panel setValue:@0 forKey:@"_supportsMoveCursorDirection"];
    } @catch (__unused NSException *e) {
    }
    @try {
        [panel setValue:@NO forKey:@"moveCursorStyle"];
    } @catch (__unused NSException *e) {
    }
}

static void WKSResetSwipeRecognitionState(id panel) {
    if (!panel) {
        return;
    }
    @try {
        [panel setValue:@0 forKey:@"_adjustingTextPositionCount"];
    } @catch (__unused NSException *e) {
    }
    @try {
        [panel setValue:@0 forKey:@"_horSwipeGestureRespType"];
    } @catch (__unused NSException *e) {
    }
    @try {
        [panel setValue:nil forKey:@"_lastSwipeTouch"];
    } @catch (__unused NSException *e) {
    }
    @try {
        [panel setValue:nil forKey:@"_recognizingSwipeView"];
    } @catch (__unused NSException *e) {
    }
    @try {
        [panel setValue:nil forKey:@"_recognizingSwipeUpView"];
    } @catch (__unused NSException *e) {
    }
    @try {
        [panel setValue:nil forKey:@"_recognizingSwipeDownView"];
    } @catch (__unused NSException *e) {
    }
    id keyView = nil;
    @try {
        keyView = [panel valueForKey:@"_currentTouchView"];
    } @catch (__unused NSException *e) {
    }
    if (keyView) {
        @try {
            [keyView setValue:@NO forKey:@"moveCursorStyle"];
        } @catch (__unused NSException *e) {
        }
    }
}

__attribute__((unused)) static void WKSHandleHorizontalBlockedReturn(id panel, id swipeArg, BOOL clearFlags) {
    if (!panel) {
        return;
    }
    if (clearFlags) {
        WKSSetTouchHorizontalBlocked(swipeArg, NO);
        WKSSetTouchSwitchTriggered(swipeArg, NO);
    }
    WKSForceDisableCursorMoveState(panel);
    WKSResetSwipeRecognitionState(panel);
    WKSClearTextUpMoveStateForPanel(panel);
}

static long long WKSPanelTryRecognizeSwipeTouch(id self, SEL _cmd, id touch, id keyView,
                                                 unsigned long long *supportsMoveCursorDirection,
                                                 BOOL force) {
    BOOL keepNativeSpaceSwipe = WKSIsSpaceKeyView(keyView) || WKSPanelIsDeleteKeyView(self, keyView);
    WKSSetTouchKeepNativeSwipe(touch, keepNativeSpaceSwipe);

    if (supportsMoveCursorDirection && !keepNativeSpaceSwipe) {
        *supportsMoveCursorDirection = 0;
    }
    if (!keepNativeSpaceSwipe) {
        WKSForceDisableCursorMoveState(self);
    }

    long long result = 0;
    if (gOrigPanelTryRecognizeSwipeTouch) {
        result = gOrigPanelTryRecognizeSwipeTouch(self, _cmd, touch, keyView,
                                                  supportsMoveCursorDirection, force);
    }
    // 对所有面板的非空格键阻止进入“全键盘光标移动”方向；
    // 只有空格键保留原生光标移动。
    if (supportsMoveCursorDirection && !keepNativeSpaceSwipe) {
        *supportsMoveCursorDirection = 0;
    }
    if (!keepNativeSpaceSwipe) {
        WKSForceDisableCursorMoveState(self);
    }
    return result;
}

static BOOL WKSInvokeHandleLangSwitch(UIView *panel, id host,
                                      long long *beforeHostTypeOut,
                                      long long *beforePanelTypeOut) {
    if (!panel || !host) {
        return NO;
    }
    if (![host respondsToSelector:@selector(handleLangSwitch)] ||
        ![host respondsToSelector:@selector(currentPanelType)]) {
        return NO;
    }

    long long beforeHostType = WKSGetLongLongProperty(host, @selector(currentPanelType), LLONG_MIN);
    long long beforePanelType = WKSGetLongLongProperty(panel, @selector(panelType), LLONG_MIN);

    if (beforeHostTypeOut) {
        *beforeHostTypeOut = beforeHostType;
    }
    if (beforePanelTypeOut) {
        *beforePanelTypeOut = beforePanelType;
    }

    if (!WKSInvokeVoidNoArg(host, @selector(handleLangSwitch))) {
        return NO;
    }
    return YES;
}

static BOOL WKSDidPanelTypeChange(UIView *panel, id host,
                                  long long beforeHostType,
                                  long long beforePanelType,
                                  long long *afterHostTypeOut) {
    long long afterHostType = WKSGetLongLongProperty(host, @selector(currentPanelType), LLONG_MIN);
    long long afterPanelType = WKSGetLongLongProperty(panel, @selector(panelType), LLONG_MIN);

    if (afterHostTypeOut) {
        *afterHostTypeOut = afterHostType;
    }

    if (beforeHostType != LLONG_MIN && afterHostType != LLONG_MIN && beforeHostType != afterHostType) {
        return YES;
    }
    if (beforePanelType != LLONG_MIN && afterPanelType != LLONG_MIN && beforePanelType != afterPanelType) {
        return YES;
    }
    return NO;
}

static BOOL WKSClassNameLooksToolbar(NSString *className) {
    if (className.length == 0) {
        return NO;
    }
    NSString *name = className.lowercaseString;
    return [name containsString:@"topbar"] ||
           [name containsString:@"toolbar"] ||
           [name containsString:@"tool_bar"] ||
           [name containsString:@"logo"] ||
           [name containsString:@"controlcenter"] ||
           [name containsString:@"auxiliary"] ||
           [name containsString:@"funcbar"];
}

static BOOL WKSIsTopSmallView(UIView *view) {
    if (!view || CGRectIsEmpty(view.bounds) || !view.window) {
        return NO;
    }
    CGRect r = [view convertRect:view.bounds toView:nil];
    if (CGRectIsEmpty(r)) {
        return NO;
    }
    return (r.origin.y < 180.0 && r.size.width <= 96.0 && r.size.height <= 96.0);
}

static BOOL WKSIsToolbarCandidateView(UIView *view) {
    if (!view) {
        return NO;
    }

    if (WKSClassNameLooksToolbar(NSStringFromClass([view class]))) {
        return YES;
    }

    UIView *sup = view.superview;
    for (int i = 0; sup && i < 6; i++) {
        if (WKSClassNameLooksToolbar(NSStringFromClass([sup class]))) {
            return YES;
        }
        sup = sup.superview;
    }
    return WKSIsTopSmallView(view);
}

static void WKSClearViewBackground(UIView *view) {
    if (!view) {
        return;
    }

    view.opaque = NO;
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;

    @try {
        if ([view respondsToSelector:@selector(setHighlightedBackgroundColor:)]) {
            [view setValue:UIColor.clearColor forKey:@"highlightedBackgroundColor"];
        }
        if ([view respondsToSelector:@selector(setHighlightedBorderColor:)]) {
            [view setValue:UIColor.clearColor forKey:@"highlightedBorderColor"];
        }
        if ([view respondsToSelector:@selector(setOriginBorderColor:)]) {
            [view setValue:UIColor.clearColor forKey:@"originBorderColor"];
        }
        id mask = [view valueForKey:@"highlightMask"];
        if ([mask isKindOfClass:[UIView class]]) {
            UIView *maskView = (UIView *)mask;
            maskView.hidden = YES;
            maskView.alpha = 0.0;
            maskView.backgroundColor = UIColor.clearColor;
            maskView.layer.backgroundColor = UIColor.clearColor.CGColor;
        }
    } @catch (__unused NSException *e) {
    }
}

static void WKSApplyToolbarTransparencyRecursive(UIView *view, BOOL force, int depth) {
    if (!view || depth > 3) {
        return;
    }

    BOOL matched = force || WKSClassNameLooksToolbar(NSStringFromClass([view class]));
    BOOL shouldClear = matched || WKSIsToolbarCandidateView(view);
    if (shouldClear) {
        WKSClearViewBackground(view);
    }

    BOOL nextForce = force || matched;
    for (UIView *sub in view.subviews) {
        WKSApplyToolbarTransparencyRecursive(sub, nextForce, depth + 1);
    }
}

static void WKSApplyToolbarTransparency(id obj) {
    if (!obj || ![obj isKindOfClass:[UIView class]]) {
        return;
    }
    UIView *view = (UIView *)obj;
    if (!WKSIsToolbarCandidateView(view) &&
        !WKSClassNameLooksToolbar(NSStringFromClass([view class]))) {
        return;
    }
    WKSApplyToolbarTransparencyRecursive(view, NO, 0);
}

static BOOL WKSClassNameContainsSymbolList(NSString *className) {
    if (className.length == 0) {
        return NO;
    }
    NSString *name = className.lowercaseString;
    return [name containsString:@"symbollist"] ||
           [name containsString:@"symbolcell"] ||
           [name containsString:@"wbt9panel"] ||
           [name containsString:@"arrangeview"];
}

static BOOL WKSViewBelongsToSymbolList(UIView *view) {
    UIView *cursor = view;
    for (int i = 0; cursor && i < 8; i++) {
        if (WKSClassNameContainsSymbolList(NSStringFromClass([cursor class]))) {
            return YES;
        }
        cursor = cursor.superview;
    }
    return NO;
}

static BOOL WKSLayerBelongsToSymbolList(CALayer *layer) {
    CALayer *cursor = layer;
    for (int i = 0; cursor && i < 8; i++) {
        id delegate = cursor.delegate;
        if ([delegate isKindOfClass:[UIView class]]) {
            if (WKSViewBelongsToSymbolList((UIView *)delegate)) {
                return YES;
            }
        } else if (delegate && WKSClassNameContainsSymbolList(NSStringFromClass([delegate class]))) {
            return YES;
        }
        cursor = cursor.superlayer;
    }
    return NO;
}

static void WKSClearShapeLayerVisuals(CALayer *layer) {
    if (!layer) {
        return;
    }

    layer.hidden = YES;
    layer.opacity = 0.0f;
    layer.borderWidth = 0.0;
    layer.backgroundColor = UIColor.clearColor.CGColor;
    @try {
        [layer setValue:(id)UIColor.clearColor.CGColor forKey:@"strokeColor"];
        [layer setValue:(id)UIColor.clearColor.CGColor forKey:@"fillColor"];
        [layer setValue:nil forKey:@"path"];
    } @catch (__unused NSException *e) {
    }
}

static void WKSDisableArrangeGridFillInView(UIView *arrangeView) {
    if (!arrangeView) {
        return;
    }

    @try {
        if ([arrangeView respondsToSelector:@selector(setFillGirdBoderAutomatically:)]) {
            [arrangeView setValue:@NO forKey:@"fillGirdBoderAutomatically"];
        }
    } @catch (__unused NSException *e) {
    }

    @try {
        id grid = [arrangeView valueForKey:@"_gridFillView"];
        if ([grid isKindOfClass:[CALayer class]]) {
            WKSClearShapeLayerVisuals((CALayer *)grid);
        }
    } @catch (__unused NSException *e) {
    }
}

static void WKSDisableSymbolListGridFill(id symbolListObj) {
    if (!symbolListObj || ![symbolListObj isKindOfClass:[UIView class]]) {
        return;
    }
    UIView *symbolList = (UIView *)symbolListObj;

    id arrangeView = nil;
    @try {
        arrangeView = [symbolList valueForKey:@"arrangeView"];
    } @catch (__unused NSException *e) {
    }
    if (!arrangeView) {
        @try {
            arrangeView = [symbolList valueForKey:@"_arrangeView"];
        } @catch (__unused NSException *e) {
        }
    }

    if ([arrangeView isKindOfClass:[UIView class]]) {
        WKSDisableArrangeGridFillInView((UIView *)arrangeView);
    }
}

static id WKSGetSymbolListViewFromPanel(id panel) {
    if (!panel) {
        return nil;
    }
    @try {
        id list = [panel valueForKey:@"_symbolListView"];
        if (list) {
            return list;
        }
    } @catch (__unused NSException *e) {
    }
    @try {
        id list = [panel valueForKey:@"symbolListView"];
        if (list) {
            return list;
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
}

static BOOL WKSHostIsAdjustingTextPosition(id host) {
    if (!host) {
        return NO;
    }
    return WKSInvokeBoolNoArg(host, @selector(isAdjustingTextPosition), NO);
}

static void WKSReleaseSwitchLockDeferred(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kWKSDebounceSeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        gWKSInSwitch = NO;
    });
}

static void WKSAttemptToggleWhenReady(id context, int retries) {
    UIView *panel = [context isKindOfClass:[UIView class]] ? (UIView *)context : nil;
    id host = WKSGetPanelHosting(panel);
    if (!panel || !host) {
        gWKSInSwitch = NO;
        return;
    }

    BOOL adjusting = WKSHostIsAdjustingTextPosition(host);
    if (adjusting) {
        if (retries > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(kWKSAdjustingRetryDelaySeconds * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WKSAttemptToggleWhenReady(context, retries - 1);
            });
            return;
        }
        // retries 耗尽：强制重置 adjusting 状态，继续执行切换
        WKSResetSwipeRecognitionState(panel);
    }

    long long beforeHostType = LLONG_MIN;
    long long beforePanelType = LLONG_MIN;
    if (!WKSInvokeHandleLangSwitch(panel, host, &beforeHostType, &beforePanelType)) {
        if (retries > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(kWKSAdjustingRetryDelaySeconds * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WKSAttemptToggleWhenReady(context, retries - 1);
            });
            return;
        }
        WKSReleaseSwitchLockDeferred();
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kWKSSwitchApplyDelaySeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIView *checkPanel = [context isKindOfClass:[UIView class]] ? (UIView *)context : nil;
        id checkHost = WKSGetPanelHosting(checkPanel);
        if (!checkPanel || !checkHost) {
            gWKSInSwitch = NO;
            return;
        }

        long long afterHostType = LLONG_MIN;
        BOOL switched = WKSDidPanelTypeChange(checkPanel, checkHost,
                                              beforeHostType, beforePanelType,
                                              &afterHostType);
        if (switched) {
            if (afterHostType != LLONG_MIN) {
                WKSInvokeSwitchEngineSession(checkHost, afterHostType);
            }
            gWKSLastSwitchTs = CFAbsoluteTimeGetCurrent();
            WKSReleaseSwitchLockDeferred();
            return;
        }

        if (retries > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                         (int64_t)(kWKSAdjustingRetryDelaySeconds * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                WKSAttemptToggleWhenReady(context, retries - 1);
            });
            return;
        }

        WKSReleaseSwitchLockDeferred();
    });
}

static void WKSHandleSwipe(id context) {
    if (!gWKSSwipeEnabled) {
        return;
    }
    if (gWKSInSwitch || gWKSSwitchScheduled) {
        return;
    }

    gWKSSwitchScheduled = YES;
    __weak id weakContext = context;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kWKSScheduleDelaySeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        gWKSSwitchScheduled = NO;

        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (gWKSInSwitch || (now - gWKSLastSwitchTs) < kWKSSwitchCooldownSeconds) {
            return;
        }

        id strongContext = weakContext;
        if (!strongContext) {
            return;
        }

        gWKSInSwitch = YES;
        // 兜底：500ms 后强制释放锁，防止重试链路意外卡死
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (gWKSInSwitch) {
                gWKSInSwitch = NO;
            }
        });
        WKSAttemptToggleWhenReady(strongContext, kWKSAdjustingMaxRetries);
    });
}

static void WKSEnsureDisableCursorAdjustForHost(id host) {
    (void)host;
}

static void WKSPanelAnySwipeBegan(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    WKSSetTouchBeganTimestamp(swipeRef, CFAbsoluteTimeGetCurrent());
    WKSSetTouchSwitchHandled(swipeRef, NO);
    CGPoint startPoint = CGPointZero;
    if (WKSGetTouchLocationInPanel(swipeRef, self, &startPoint)) {
        WKSSetTouchStartPoint(swipeRef, startPoint);
    }
    if (WKSShouldIgnoreDeleteSwipe(self, swipeRef)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    if (!shouldKeepNative) {
        gWKSLastNonNativeKeyTouchBeganTs = CFAbsoluteTimeGetCurrent();
        WKSSetTouchHorizontalBlocked(swipeRef, NO);
        WKSForceDisableCursorMoveState(self);
        WKSHandleTextUpSwipeBegan(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
    if (shouldKeepNative && gOrigPanelAnySwipeBegan) {
        gOrigPanelAnySwipeBegan(self, _cmd, arg, touch);
    }
}

static void WKSPanelAnySwipeMoved(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    if (WKSShouldIgnoreDeleteSwipe(self, swipeRef)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    if (!shouldKeepNative) {
        WKSForceDisableCursorMoveState(self);
        if (WKSIsPredominantlyHorizontalSwipe(self, swipeRef)) {
            WKSSetTouchHorizontalBlocked(swipeRef, YES);
        }
    }
    if (shouldKeepNative && gOrigPanelAnySwipeMoved) {
        gOrigPanelAnySwipeMoved(self, _cmd, arg, touch);
    }
    if (!shouldKeepNative) {
        WKSForceDisableCursorMoveState(self);
        WKSTryHandleTextUpSwipeMoved(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
}

static void WKSPanelTouchesCancelled(id self, SEL _cmd, id touches, id event) {
    id swipeRef = touches ?: event;
    if (WKSShouldIgnoreDeleteSwipe(self, swipeRef)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    if (!WKSShouldKeepNativeSpaceSwipe(self, swipeRef)) {
        WKSTryHandleTextUpSwipeCancelled(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
    if (gOrigPanelTouchesCancelled) {
        gOrigPanelTouchesCancelled(self, _cmd, touches, event);
    }
}

static void WKSPanelProcessTouchBegan(id self, SEL _cmd, id touch, id keyView) {
    BOOL keepNativeSwipe = (WKSIsSpaceKeyView(keyView) || WKSPanelIsDeleteKeyView(self, keyView));
    WKSSetTouchBeganTimestamp(touch, CFAbsoluteTimeGetCurrent());
    WKSSetTouchSwitchHandled(touch, NO);
    WKSSetTouchKeepNativeSwipe(touch, keepNativeSwipe);
    WKSSetTouchSwitchTriggered(touch, NO);
    WKSSetTouchHorizontalBlocked(touch, NO);
    if (!keepNativeSwipe) {
        gWKSLastNonNativeKeyTouchBeganTs = CFAbsoluteTimeGetCurrent();
        CGPoint startPoint = CGPointZero;
        if (WKSGetTouchLocationInPanel(touch, self, &startPoint)) {
            WKSSetTouchStartPoint(touch, startPoint);
        }
        WKSForceDisableCursorMoveState(self);
        WKSHandleTextUpSwipeBegan(self, touch);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
    if (gOrigPanelProcessTouchBegan) {
        gOrigPanelProcessTouchBegan(self, _cmd, touch, keyView);
    }
}

static void WKSPanelProcessTouchMoved(id self, SEL _cmd, id touch, id keyView) {
    BOOL keepNativeSwipe = (WKSIsSpaceKeyView(keyView) || WKSPanelIsDeleteKeyView(self, keyView));
    WKSSetTouchKeepNativeSwipe(touch, keepNativeSwipe);
    if (!keepNativeSwipe) {
        if (WKSIsPredominantlyHorizontalSwipe(self, touch)) {
            WKSSetTouchHorizontalBlocked(touch, YES);
        }
    }
    if (gOrigPanelProcessTouchMoved) {
        gOrigPanelProcessTouchMoved(self, _cmd, touch, keyView);
    }
    if (!keepNativeSwipe) {
        WKSForceDisableCursorMoveState(self);
        WKSTryHandleTextUpSwipeMoved(self, touch);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
}

static void WKSPanelProcessTouchCancel(id self, SEL _cmd, id touch, id keyView) {
    WKSSetTouchSwitchTriggered(touch, NO);
    WKSSetTouchHorizontalBlocked(touch, NO);
    WKSClearTextUpMoveStateForPanel(self);
    if (gOrigPanelProcessTouchCancel) {
        gOrigPanelProcessTouchCancel(self, _cmd, touch, keyView);
    }
}

static BOOL WKSPanelShouldCancelTouchEndForSwitch(id self, id touch) {
    (void)self;
    (void)touch;
    // 避免通过 touchCancel 干预系统触摸收尾，防止手势识别链路被卡死导致仅首次生效。
    return NO;
}

static BOOL WKSShouldTriggerSwitchOnTouchEndFallback(id panel, id touch) {
    if (WKSUseGestureRecognizerMode()) {
        return NO;
    }
    if (!panel || !touch) {
        return NO;
    }
    if (WKSShouldIgnoreDeleteSwipe(panel, touch)) {
        return NO;
    }
    if (WKSShouldKeepNativeSpaceSwipe(panel, touch)) {
        return NO;
    }
    if (WKSTouchSwitchHandled(touch) || WKSTouchHorizontalBlocked(touch)) {
        return NO;
    }
    BOOL shouldTriggerUp = WKSShouldTriggerSwitchForDirection(panel, touch, YES, NO);
    BOOL shouldTriggerDown = WKSShouldTriggerSwitchForDirection(panel, touch, NO, NO);
    return (shouldTriggerUp || shouldTriggerDown);
}

__attribute__((unused)) static BOOL WKSTouchSwitchTriggered(id touch) {
    BOOL triggered = NO;
    WKSGetTouchSwitchTriggered(touch, &triggered);
    return triggered;
}

static BOOL WKSTouchHorizontalBlocked(id touch) {
    BOOL blocked = NO;
    WKSGetTouchHorizontalBlocked(touch, &blocked);
    return blocked;
}

static void WKSPanelProcessTouchEnd(id self, SEL _cmd, id touch, id keyView) {
    if (WKSPanelShouldCancelTouchEndForSwitch(self, touch) && gOrigPanelProcessTouchCancel) {
        gOrigPanelProcessTouchCancel(self, @selector(processTouchCancel:keyView:), touch, keyView);
        WKSSetTouchSwitchTriggered(touch, NO);
        WKSSetTouchHorizontalBlocked(touch, NO);
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldTriggerFallback = WKSShouldTriggerSwitchOnTouchEndFallback(self, touch);
    if (gOrigPanelProcessTouchEnd) {
        gOrigPanelProcessTouchEnd(self, _cmd, touch, keyView);
    }
    if (shouldTriggerFallback) {
        WKSSetTouchSwitchHandled(touch, YES);
        WKSSetTouchSwitchTriggered(touch, YES);
        WKSHandleSwipe(self);
    }
    WKSSetTouchSwitchTriggered(touch, NO);
    WKSSetTouchHorizontalBlocked(touch, NO);
    WKSClearTextUpMoveStateForPanel(self);
}

static void WKSPanelProcessTouchEndWithInterrupter(id self, SEL _cmd, id touch, id keyView, id interrupterKeyView) {
    if (WKSPanelShouldCancelTouchEndForSwitch(self, touch) && gOrigPanelProcessTouchCancel) {
        gOrigPanelProcessTouchCancel(self, @selector(processTouchCancel:keyView:), touch, keyView);
        WKSSetTouchSwitchTriggered(touch, NO);
        WKSSetTouchHorizontalBlocked(touch, NO);
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldTriggerFallback = WKSShouldTriggerSwitchOnTouchEndFallback(self, touch);
    if (gOrigPanelProcessTouchEndWithInterrupter) {
        gOrigPanelProcessTouchEndWithInterrupter(self, _cmd, touch, keyView, interrupterKeyView);
    }
    if (shouldTriggerFallback) {
        WKSSetTouchSwitchHandled(touch, YES);
        WKSSetTouchSwitchTriggered(touch, YES);
        WKSHandleSwipe(self);
    }
    WKSSetTouchSwitchTriggered(touch, NO);
    WKSSetTouchHorizontalBlocked(touch, NO);
    WKSClearTextUpMoveStateForPanel(self);
}

static void WKSPanelSwipeUpBegan(id self, SEL _cmd, id arg, id touch, BOOL isOpenUpTips) {
    id swipeRef = touch ?: arg;
    WKSSetTouchBeganTimestamp(swipeRef, CFAbsoluteTimeGetCurrent());
    WKSSetTouchSwitchHandled(swipeRef, NO);
    CGPoint startPoint = CGPointZero;
    if (WKSGetTouchLocationInPanel(swipeRef, self, &startPoint)) {
        WKSSetTouchStartPoint(swipeRef, startPoint);
    }
    if (WKSShouldIgnoreDeleteSwipe(self, swipeRef)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    if (!shouldKeepNative) {
        WKSHandleTextUpSwipeBegan(self, swipeRef);
        return;
    }
    WKSClearTextUpMoveStateForPanel(self);
    if (gOrigPanelSwipeUpBegan) {
        gOrigPanelSwipeUpBegan(self, _cmd, arg, touch, isOpenUpTips);
    }
}

static void WKSPanelSwipeUpMoved(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    if (WKSShouldIgnoreDeleteSwipe(self, swipeRef)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    if (shouldKeepNative) {
        if (gOrigPanelSwipeUpMoved) {
            gOrigPanelSwipeUpMoved(self, _cmd, arg, touch);
        }
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    if (WKSTouchHorizontalBlocked(swipeRef)) {
        WKSSetTouchHorizontalBlocked(swipeRef, YES);
    }
    WKSTryHandleTextUpSwipeMoved(self, swipeRef);
}

static void WKSPanelSwipeUp(id self, SEL _cmd, id touch) {
    if (WKSShouldIgnoreDeleteSwipe(self, touch)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    if (shouldKeepNative && gOrigPanelSwipeUp) {
        gOrigPanelSwipeUp(self, _cmd, touch);
    }
    WKSSetTouchSwitchTriggered(touch, NO);
    WKSSetTouchHorizontalBlocked(touch, NO);
    WKSClearTextUpMoveStateForPanel(self);
}

static void WKSPanelSwipeDown(id self, SEL _cmd, id touch) {
    if (WKSShouldIgnoreDeleteSwipe(self, touch)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    if (shouldKeepNative && gOrigPanelSwipeDown) {
        gOrigPanelSwipeDown(self, _cmd, touch);
    }
    WKSSetTouchSwitchTriggered(touch, NO);
    WKSSetTouchHorizontalBlocked(touch, NO);
    WKSClearTextUpMoveStateForPanel(self);
}

static void WKSPanelSwipeEnded(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    if (WKSShouldIgnoreDeleteSwipe(self, swipeRef)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    if (shouldKeepNative && gOrigPanelSwipeEnded) {
        gOrigPanelSwipeEnded(self, _cmd, arg, touch);
    }
    WKSSetTouchSwitchTriggered(swipeRef, NO);
    WKSSetTouchHorizontalBlocked(swipeRef, NO);
    WKSClearTextUpMoveStateForPanel(self);
}

static void WKST9SwipeUpBegan(id self, SEL _cmd, id arg, id touch, BOOL isOpenUpTips) {
    id swipeRef = touch ?: arg;
    WKSSetTouchBeganTimestamp(swipeRef, CFAbsoluteTimeGetCurrent());
    WKSSetTouchSwitchHandled(swipeRef, NO);
    CGPoint startPoint = CGPointZero;
    if (WKSGetTouchLocationInPanel(swipeRef, self, &startPoint)) {
        WKSSetTouchStartPoint(swipeRef, startPoint);
    }
    if (WKSShouldIgnoreDeleteSwipe(self, swipeRef)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    if (!shouldKeepNative) {
        WKSHandleTextUpSwipeBegan(self, swipeRef);
        return;
    }
    WKSClearTextUpMoveStateForPanel(self);
    if (gOrigT9SwipeUpBegan) {
        gOrigT9SwipeUpBegan(self, _cmd, arg, touch, isOpenUpTips);
    }
}

static void WKST9SwipeUpMoved(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    if (WKSShouldIgnoreDeleteSwipe(self, swipeRef)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    if (shouldKeepNative) {
        if (gOrigT9SwipeUpMoved) {
            gOrigT9SwipeUpMoved(self, _cmd, arg, touch);
        }
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    if (WKSTouchHorizontalBlocked(swipeRef)) {
        WKSSetTouchHorizontalBlocked(swipeRef, YES);
    }
    WKSTryHandleTextUpSwipeMoved(self, swipeRef);
}

static void WKST9SwipeUp(id self, SEL _cmd, id touch) {
    if (WKSShouldIgnoreDeleteSwipe(self, touch)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    if (shouldKeepNative && gOrigT9SwipeUp) {
        gOrigT9SwipeUp(self, _cmd, touch);
    }
    WKSSetTouchSwitchTriggered(touch, NO);
    WKSSetTouchHorizontalBlocked(touch, NO);
    WKSClearTextUpMoveStateForPanel(self);
}

static void WKST9SwipeDown(id self, SEL _cmd, id touch) {
    if (WKSShouldIgnoreDeleteSwipe(self, touch)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    if (shouldKeepNative && gOrigT9SwipeDown) {
        gOrigT9SwipeDown(self, _cmd, touch);
    }
    WKSSetTouchSwitchTriggered(touch, NO);
    WKSSetTouchHorizontalBlocked(touch, NO);
    WKSClearTextUpMoveStateForPanel(self);
}

static void WKST26SwipeUpBegan(id self, SEL _cmd, id arg, id touch, BOOL isOpenUpTips) {
    id swipeRef = touch ?: arg;
    WKSSetTouchBeganTimestamp(swipeRef, CFAbsoluteTimeGetCurrent());
    WKSSetTouchSwitchHandled(swipeRef, NO);
    CGPoint startPoint = CGPointZero;
    if (WKSGetTouchLocationInPanel(swipeRef, self, &startPoint)) {
        WKSSetTouchStartPoint(swipeRef, startPoint);
    }
    if (WKSShouldIgnoreDeleteSwipe(self, swipeRef)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    if (!shouldKeepNative) {
        WKSHandleTextUpSwipeBegan(self, swipeRef);
        return;
    }
    WKSClearTextUpMoveStateForPanel(self);
    if (gOrigT26SwipeUpBegan) {
        gOrigT26SwipeUpBegan(self, _cmd, arg, touch, isOpenUpTips);
    }
}

static void WKST26SwipeUpMoved(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    if (WKSShouldIgnoreDeleteSwipe(self, swipeRef)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    if (shouldKeepNative) {
        if (gOrigT26SwipeUpMoved) {
            gOrigT26SwipeUpMoved(self, _cmd, arg, touch);
        }
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    if (WKSTouchHorizontalBlocked(swipeRef)) {
        WKSSetTouchHorizontalBlocked(swipeRef, YES);
    }
    WKSTryHandleTextUpSwipeMoved(self, swipeRef);
}

static void WKST26SwipeUp(id self, SEL _cmd, id touch) {
    if (WKSShouldIgnoreDeleteSwipe(self, touch)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    if (shouldKeepNative && gOrigT26SwipeUp) {
        gOrigT26SwipeUp(self, _cmd, touch);
    }
    WKSSetTouchSwitchTriggered(touch, NO);
    WKSSetTouchHorizontalBlocked(touch, NO);
    WKSClearTextUpMoveStateForPanel(self);
}

static void WKST26SwipeDown(id self, SEL _cmd, id touch) {
    if (WKSShouldIgnoreDeleteSwipe(self, touch)) {
        WKSClearTextUpMoveStateForPanel(self);
        return;
    }
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    if (shouldKeepNative && gOrigT26SwipeDown) {
        gOrigT26SwipeDown(self, _cmd, touch);
    }
    WKSSetTouchSwitchTriggered(touch, NO);
    WKSSetTouchHorizontalBlocked(touch, NO);
    WKSClearTextUpMoveStateForPanel(self);
}

static void WKSPanelDidAttachHosting(id self, SEL _cmd) {
    if (gOrigPanelDidAttachHosting) {
        gOrigPanelDidAttachHosting(self, _cmd);
    }
    WKSEnsureDisableCursorAdjustForHost(WKSGetPanelHosting(self));
    WKSApplyToolbarTransparency(self);
    WKSEnsurePanelSwipeRecognizers(self);
}

static void WKST9DidAttachHosting(id self, SEL _cmd) {
    if (gOrigT9DidAttachHosting) {
        gOrigT9DidAttachHosting(self, _cmd);
    }
    WKSEnsureDisableCursorAdjustForHost(WKSGetPanelHosting(self));
    WKSApplyToolbarTransparency(self);
    WKSDisableSymbolListGridFill(WKSGetSymbolListViewFromPanel(self));
    WKSEnsurePanelSwipeRecognizers(self);
}

static void WKST26DidAttachHosting(id self, SEL _cmd) {
    if (gOrigT26DidAttachHosting) {
        gOrigT26DidAttachHosting(self, _cmd);
    }
    WKSEnsureDisableCursorAdjustForHost(WKSGetPanelHosting(self));
    WKSApplyToolbarTransparency(self);
    WKSEnsurePanelSwipeRecognizers(self);
}

static void WKSApplyButtonBorderExcludingToolbar(UIView *view) {
    if (!view) {
        return;
    }

    // 工具栏按钮保持透明，其他按钮统一增加边框。
    BOOL isToolbarButton =
        WKSIsToolbarCandidateView(view) ||
        WKSClassNameLooksToolbar(NSStringFromClass([view class]));
    UIColor *borderColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    CALayer *backgroundLayer = nil;
    @try {
        id layerObj = [view valueForKey:@"backgroundLayer"];
        if ([layerObj isKindOfClass:[CALayer class]]) {
            backgroundLayer = (CALayer *)layerObj;
        }
    } @catch (__unused NSException *e) {
    }

    if (isToolbarButton) {
        view.layer.borderWidth = 0.0;
        view.layer.borderColor = nil;
        view.layer.cornerRadius = 0.0;
        view.layer.masksToBounds = NO;
        if (backgroundLayer) {
            backgroundLayer.borderWidth = 0.0;
            backgroundLayer.borderColor = nil;
        }
    } else {
        view.layer.borderWidth = 1.0;
        view.layer.borderColor = borderColor.CGColor;
        view.layer.cornerRadius = 6.0;
        view.layer.masksToBounds = YES;
        if (backgroundLayer) {
            backgroundLayer.borderWidth = 1.0;
            backgroundLayer.borderColor = borderColor.CGColor;
            if (backgroundLayer.cornerRadius < 0.5) {
                backgroundLayer.cornerRadius = 6.0;
            }
            backgroundLayer.masksToBounds = YES;
        }

        @try {
            if ([view respondsToSelector:@selector(setOriginBorderColor:)]) {
                [view setValue:borderColor forKey:@"originBorderColor"];
            }
            if ([view respondsToSelector:@selector(setHighlightedBorderColor:)]) {
                [view setValue:borderColor forKey:@"highlightedBorderColor"];
            }
        } @catch (__unused NSException *e) {
        }
    }
}

static void WKSAppButtonLayoutSubviews(id self, SEL _cmd) {
    if (gOrigAppButtonLayoutSubviews) {
        gOrigAppButtonLayoutSubviews(self, _cmd);
    }
    UIView *view = (UIView *)self;
    WKSClearViewBackground(view);
    WKSApplyButtonBorderExcludingToolbar(view);
}

static void WKSButtonLayoutSubviews(id self, SEL _cmd) {
    if (gOrigButtonLayoutSubviews) {
        gOrigButtonLayoutSubviews(self, _cmd);
    }
    UIView *view = (UIView *)self;
    WKSClearViewBackground(view);
    WKSApplyButtonBorderExcludingToolbar(view);
}

static void WKSKeyViewLayoutSubviews(id self, SEL _cmd) {
    if (gOrigKeyViewLayoutSubviews) {
        gOrigKeyViewLayoutSubviews(self, _cmd);
    }
    WKSApplyButtonBorderExcludingToolbar((UIView *)self);
}

static void WKSTopBarLayoutSubviews(id self, SEL _cmd) {
    if (gOrigTopBarLayoutSubviews) {
        gOrigTopBarLayoutSubviews(self, _cmd);
    }
    WKSApplyToolbarTransparency(self);
}

static void WKSToolBarAuxLayoutSubviews(id self, SEL _cmd) {
    if (gOrigToolBarAuxLayoutSubviews) {
        gOrigToolBarAuxLayoutSubviews(self, _cmd);
    }
    WKSApplyToolbarTransparency(self);
}

static void WKSSymbolListDidAttachHosting(id self, SEL _cmd) {
    if (gOrigSymbolListDidAttachHosting) {
        gOrigSymbolListDidAttachHosting(self, _cmd);
    }
    WKSDisableSymbolListGridFill(self);
}

static void WKSGridBoderFillLayerFill(id self, SEL _cmd, CGSize contentSize, CGRect lastCellFrame, CGSize cellSize) {
    if (WKSLayerBelongsToSymbolList((CALayer *)self)) {
        WKSClearShapeLayerVisuals((CALayer *)self);
        return;
    }
    if (gOrigGridBoderFillLayerFill) {
        gOrigGridBoderFillLayerFill(self, _cmd, contentSize, lastCellFrame, cellSize);
    }
}

static void WKSBorderLayerLayoutSublayers(id self, SEL _cmd) {
    if (gOrigBorderLayerLayoutSublayers) {
        gOrigBorderLayerLayoutSublayers(self, _cmd);
    }

    BOOL shouldHide = WKSLayerBelongsToSymbolList((CALayer *)self);
    if (!shouldHide) {
        @try {
            id targetView = [self valueForKey:@"_qmuibd_targetBorderView"];
            if ([targetView isKindOfClass:[UIView class]]) {
                shouldHide = WKSViewBelongsToSymbolList((UIView *)targetView);
            }
        } @catch (__unused NSException *e) {
        }
    }

    if (shouldHide) {
        WKSClearShapeLayerVisuals((CALayer *)self);
    }
}

static void WKSSymbolCellSetBorderPosition(id self, SEL _cmd, unsigned long long borderPosition) {
    (void)borderPosition;
    if (gOrigSymbolCellSetBorderPosition) {
        gOrigSymbolCellSetBorderPosition(self, _cmd, 0);
    }
}

static void WKSSwizzleClassMethod(Class cls, SEL sel, IMP newImp, IMP *oldStore) {
    if (!cls) {
        return;
    }

    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        return;
    }

    IMP oldImp = method_getImplementation(method);
    if (!oldImp || oldImp == newImp) {
        return;
    }

    method_setImplementation(method, newImp);
    if (oldStore) {
        *oldStore = oldImp;
    }
}

__attribute__((constructor))
static void WKSInit(void) {
    WKSLoadPreferences();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                                    WKSPreferencesChanged,
                                    CFSTR("com.yourname.wechatkeyboardswitch/preferences.changed"), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    @autoreleasepool {
        Class panel = objc_getClass("WBCommonPanelView");
        WKSSwizzleClassMethod(panel, @selector(tryRecognizeSwipeTouch:keyView:supportsMoveCursorDirection:force:),
                              (IMP)WKSPanelTryRecognizeSwipeTouch,
                              (IMP *)&gOrigPanelTryRecognizeSwipeTouch);
        WKSSwizzleClassMethod(panel, @selector(processSwipeBegan:touch:),
                              (IMP)WKSPanelAnySwipeBegan, (IMP *)&gOrigPanelAnySwipeBegan);
        WKSSwizzleClassMethod(panel, @selector(processSwipeMoved:touch:),
                              (IMP)WKSPanelAnySwipeMoved, (IMP *)&gOrigPanelAnySwipeMoved);
        WKSSwizzleClassMethod(panel, @selector(processSwipeEnded:touch:),
                              (IMP)WKSPanelSwipeEnded, (IMP *)&gOrigPanelSwipeEnded);
        WKSSwizzleClassMethod(panel, @selector(touchesCancelled:withEvent:),
                              (IMP)WKSPanelTouchesCancelled, (IMP *)&gOrigPanelTouchesCancelled);
        WKSSwizzleClassMethod(panel, @selector(processTouchBegan:keyView:),
                              (IMP)WKSPanelProcessTouchBegan, (IMP *)&gOrigPanelProcessTouchBegan);
        WKSSwizzleClassMethod(panel, @selector(processTouchMoveWithTouch:keyView:),
                              (IMP)WKSPanelProcessTouchMoved, (IMP *)&gOrigPanelProcessTouchMoved);
        WKSSwizzleClassMethod(panel, @selector(processTouchCancel:keyView:),
                              (IMP)WKSPanelProcessTouchCancel, (IMP *)&gOrigPanelProcessTouchCancel);
        WKSSwizzleClassMethod(panel, @selector(processTouchEnd:keyView:),
                              (IMP)WKSPanelProcessTouchEnd, (IMP *)&gOrigPanelProcessTouchEnd);
        WKSSwizzleClassMethod(panel, @selector(processTouchEnd:keyView:interrupterKeyView:),
                              (IMP)WKSPanelProcessTouchEndWithInterrupter,
                              (IMP *)&gOrigPanelProcessTouchEndWithInterrupter);
        WKSSwizzleClassMethod(panel, @selector(processSwipeUpBegan:touch:isOpenUpTips:),
                              (IMP)WKSPanelSwipeUpBegan, (IMP *)&gOrigPanelSwipeUpBegan);
        WKSSwizzleClassMethod(panel, @selector(processSwipeUpMoved:touch:),
                              (IMP)WKSPanelSwipeUpMoved, (IMP *)&gOrigPanelSwipeUpMoved);
        WKSSwizzleClassMethod(panel, @selector(processSwipeUpEnded:),
                              (IMP)WKSPanelSwipeUp, (IMP *)&gOrigPanelSwipeUp);
        WKSSwizzleClassMethod(panel, @selector(processSwipeDownEnded:),
                              (IMP)WKSPanelSwipeDown, (IMP *)&gOrigPanelSwipeDown);
        WKSSwizzleClassMethod(panel, @selector(didAttachHosting),
                              (IMP)WKSPanelDidAttachHosting, (IMP *)&gOrigPanelDidAttachHosting);

        Class t9 = objc_getClass("WBT9Panel");
        WKSSwizzleClassMethod(t9, @selector(processSwipeUpBegan:touch:isOpenUpTips:),
                              (IMP)WKST9SwipeUpBegan, (IMP *)&gOrigT9SwipeUpBegan);
        WKSSwizzleClassMethod(t9, @selector(processSwipeUpMoved:touch:),
                              (IMP)WKST9SwipeUpMoved, (IMP *)&gOrigT9SwipeUpMoved);
        WKSSwizzleClassMethod(t9, @selector(processSwipeUpEnded:),
                              (IMP)WKST9SwipeUp, (IMP *)&gOrigT9SwipeUp);
        WKSSwizzleClassMethod(t9, @selector(processSwipeDownEnded:),
                              (IMP)WKST9SwipeDown, (IMP *)&gOrigT9SwipeDown);
        WKSSwizzleClassMethod(t9, @selector(didAttachHosting),
                              (IMP)WKST9DidAttachHosting, (IMP *)&gOrigT9DidAttachHosting);

        Class t26 = objc_getClass("WBT26Panel");
        WKSSwizzleClassMethod(t26, @selector(processSwipeUpBegan:touch:isOpenUpTips:),
                              (IMP)WKST26SwipeUpBegan, (IMP *)&gOrigT26SwipeUpBegan);
        WKSSwizzleClassMethod(t26, @selector(processSwipeUpMoved:touch:),
                              (IMP)WKST26SwipeUpMoved, (IMP *)&gOrigT26SwipeUpMoved);
        WKSSwizzleClassMethod(t26, @selector(processSwipeUpEnded:),
                              (IMP)WKST26SwipeUp, (IMP *)&gOrigT26SwipeUp);
        WKSSwizzleClassMethod(t26, @selector(processSwipeDownEnded:),
                              (IMP)WKST26SwipeDown, (IMP *)&gOrigT26SwipeDown);
        WKSSwizzleClassMethod(t26, @selector(didAttachHosting),
                              (IMP)WKST26DidAttachHosting, (IMP *)&gOrigT26DidAttachHosting);

        Class appButton = objc_getClass("WBAppButton");
        WKSSwizzleClassMethod(appButton, @selector(layoutSubviews),
                              (IMP)WKSAppButtonLayoutSubviews, (IMP *)&gOrigAppButtonLayoutSubviews);

        Class wbButton = objc_getClass("WBButton");
        WKSSwizzleClassMethod(wbButton, @selector(layoutSubviews),
                              (IMP)WKSButtonLayoutSubviews, (IMP *)&gOrigButtonLayoutSubviews);

        Class keyView = objc_getClass("WBKeyView");
        WKSSwizzleClassMethod(keyView, @selector(layoutSubviews),
                              (IMP)WKSKeyViewLayoutSubviews, (IMP *)&gOrigKeyViewLayoutSubviews);

        Class topBar = objc_getClass("WBTopBar");
        WKSSwizzleClassMethod(topBar, @selector(layoutSubviews),
                              (IMP)WKSTopBarLayoutSubviews, (IMP *)&gOrigTopBarLayoutSubviews);

        Class toolBarAux = objc_getClass("WBToolBarAuxiliary");
        WKSSwizzleClassMethod(toolBarAux, @selector(layoutSubviews),
                              (IMP)WKSToolBarAuxLayoutSubviews, (IMP *)&gOrigToolBarAuxLayoutSubviews);

        Class symbolList = objc_getClass("WBSymbolListView");
        WKSSwizzleClassMethod(symbolList, @selector(didAttachHosting),
                              (IMP)WKSSymbolListDidAttachHosting, (IMP *)&gOrigSymbolListDidAttachHosting);

        Class gridFill = objc_getClass("WBGridBoderFillLayer");
        WKSSwizzleClassMethod(gridFill, @selector(fillWithArrangeViewContentSize:lastCellFrame:cellSize:),
                              (IMP)WKSGridBoderFillLayerFill, (IMP *)&gOrigGridBoderFillLayerFill);

        Class borderLayer = objc_getClass("WBBorderLayer");
        WKSSwizzleClassMethod(borderLayer, @selector(layoutSublayers),
                              (IMP)WKSBorderLayerLayoutSublayers, (IMP *)&gOrigBorderLayerLayoutSublayers);

        Class symbolCell = objc_getClass("WBSymbolCell");
        WKSSwizzleClassMethod(symbolCell, @selector(setBorderPosition:),
                              (IMP)WKSSymbolCellSetBorderPosition, (IMP *)&gOrigSymbolCellSetBorderPosition);
    }
}
