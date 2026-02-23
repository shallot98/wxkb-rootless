#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
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
static const NSTimeInterval kWKSRippleMinIntervalSeconds = 0.024;
static const NSInteger kWKSRippleFrameStride = 2;
static const CGFloat kWKSRippleDecodeMaxSide = 240.0;
static CFAbsoluteTime gWKSLastRippleEmitTs = 0;

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
static void (*gOrigPanelLayoutSubviews)(id, SEL) = NULL;
static void (*gOrigT9LayoutSubviews)(id, SEL) = NULL;
static void (*gOrigT26LayoutSubviews)(id, SEL) = NULL;

static void (*gOrigAppButtonLayoutSubviews)(id, SEL) = NULL;
static void (*gOrigButtonLayoutSubviews)(id, SEL) = NULL;
static void (*gOrigKeyViewLayoutSubviews)(id, SEL) = NULL;
static void (*gOrigRuleKeyUpdateKeyAppearance)(id, SEL) = NULL;
static void (*gOrigReturnKeyUpdateReturnStyle)(id, SEL) = NULL;
static void (*gOrigNewlineResponsibleForNewlineDidChange)(id, SEL) = NULL;
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
static BOOL WKSShouldCancelTouchForPanelSwipeUp(id panelObj);
static BOOL WKSIsKeyViewLike(UIView *view);
static void WKSShowKeyboardTouchRipple(id panel, id touch);

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
static const void *kWKSPanelCancelTouchEndUntilTsAssocKey = &kWKSPanelCancelTouchEndUntilTsAssocKey;

static void WKSSetPanelCancelTouchEndUntil(id panel, CFAbsoluteTime untilTs) {
    if (!panel) {
        return;
    }
    @try {
        objc_setAssociatedObject(panel, kWKSPanelCancelTouchEndUntilTsAssocKey,
                                 @(untilTs), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (__unused NSException *e) {
    }
}

static BOOL WKSConsumePanelCancelTouchEndIfNeeded(id panel) {
    if (!panel) {
        return NO;
    }
    @try {
        id value = objc_getAssociatedObject(panel, kWKSPanelCancelTouchEndUntilTsAssocKey);
        if ([value isKindOfClass:[NSNumber class]]) {
            CFAbsoluteTime untilTs = [(NSNumber *)value doubleValue];
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if (untilTs > now) {
                objc_setAssociatedObject(panel, kWKSPanelCancelTouchEndUntilTsAssocKey,
                                         @(0.0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return YES;
            }
        }
    } @catch (__unused NSException *e) {
    }
    return NO;
}

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

    if ((gesture.direction == UISwipeGestureRecognizerDirectionUp ||
         gesture.direction == UISwipeGestureRecognizerDirectionDown) &&
        WKSShouldCancelTouchForPanelSwipeUp(panel)) {
        // 九键/26 键上下滑时，下一次 touchEnd 改为 cancel，避免同时输入字母。
        WKSSetPanelCancelTouchEndUntil(panel, now + 0.45);
    }

    WKSResetSwipeRecognitionState(panel);
    WKSHandleSwipe(panel);
}

static BOOL WKSShouldCancelTouchForPanelSwipeUp(id panelObj) {
    if (!panelObj) {
        return NO;
    }
    Class t9Class = objc_getClass("WBT9Panel");
    if (t9Class && [panelObj isKindOfClass:t9Class]) {
        return YES;
    }
    Class t26Class = objc_getClass("WBT26Panel");
    if (t26Class && [panelObj isKindOfClass:t26Class]) {
        return YES;
    }
    NSString *className = NSStringFromClass([panelObj class]);
    return [className containsString:@"T26"] || [className containsString:@"T9"];
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
        swipeUp.cancelsTouchesInView = WKSShouldCancelTouchForPanelSwipeUp(panelObj);
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
        swipeDown.cancelsTouchesInView = WKSShouldCancelTouchForPanelSwipeUp(panelObj);
        swipeDown.delaysTouchesBegan = NO;
        swipeDown.delaysTouchesEnded = NO;
        swipeDown.delegate = bridge;
        [panel addGestureRecognizer:swipeDown];
        objc_setAssociatedObject(panel, kWKSPanelSwipeDownRecognizerAssocKey,
                                 swipeDown, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    swipeUp.cancelsTouchesInView = WKSShouldCancelTouchForPanelSwipeUp(panelObj);
    swipeDown.cancelsTouchesInView = WKSShouldCancelTouchForPanelSwipeUp(panelObj);
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

static NSString *const kWKSGlassFillLayerName = @"wks_glass_fill";
static NSString *const kWKSGlassGlossLayerName = @"wks_glass_gloss";
static NSString *const kWKSGlassBorderLayerName = @"wks_glass_border";
static NSString *const kWKSKeyboardGlassFillLayerName = @"wks_keyboard_glass_fill";
static NSString *const kWKSKeyboardGlassGlossLayerName = @"wks_keyboard_glass_gloss";
static NSString *const kWKSToolbarGlassFillLayerName = @"wks_toolbar_glass_fill";
static NSString *const kWKSToolbarGlassGlossLayerName = @"wks_toolbar_glass_gloss";
static NSString *const kWKSKeyboardNativeTopTintLayerName = @"wks_keyboard_bg_top_tint";
static NSString *const kWKSKeyboardSkinBackLayerName = @"wks_keyboard_skin_back";
static NSString *const kWKSKeyboardRippleHostLayerName = @"wks_keyboard_ripple_host";
static const NSInteger kWKSKeyboardNativeGlassEffectTag = 1464552193;
static const NSInteger kWKSKeyboardNativeGlassTintTag = 1464552194;
static const NSInteger kWKSKeyboardSkinImageViewTag = 1464552195;
static BOOL WKSSystemPrefersDarkAppearance(void);
static BOOL WKSKeyboardThemePrefersDarkAppearance(void);
static BOOL WKSReadKeyboardThemeDarkAppearance(BOOL *darkModeOut);

static BOOL WKSIsDarkAppearanceForView(UIView *view) {
    BOOL keyboardThemeDark = NO;
    if (WKSReadKeyboardThemeDarkAppearance(&keyboardThemeDark)) {
        return keyboardThemeDark;
    }
    if (!view) {
        return WKSSystemPrefersDarkAppearance();
    }
    if (@available(iOS 13.0, *)) {
        UITraitCollection *trait = view.traitCollection;
        if (trait && trait.userInterfaceStyle != UIUserInterfaceStyleUnspecified) {
            return trait.userInterfaceStyle == UIUserInterfaceStyleDark;
        }
        UIWindow *window = view.window;
        if (window) {
            UIUserInterfaceStyle style = window.traitCollection.userInterfaceStyle;
            if (style != UIUserInterfaceStyleUnspecified) {
                return style == UIUserInterfaceStyleDark;
            }
        }
    }
    return WKSSystemPrefersDarkAppearance();
}

static BOOL WKSIsDarkAppearanceForLayer(CALayer *layer) {
    if (!layer) {
        return NO;
    }
    id delegate = layer.delegate;
    if ([delegate isKindOfClass:[UIView class]]) {
        return WKSIsDarkAppearanceForView((UIView *)delegate);
    }
    if (@available(iOS 13.0, *)) {
        if ([delegate respondsToSelector:@selector(traitCollection)]) {
            UITraitCollection *trait = [delegate traitCollection];
            if (trait.userInterfaceStyle == UIUserInterfaceStyleDark) {
                return YES;
            }
        }
    }
    return NO;
}

static NSArray *WKSKeyboardGlassFillColors(BOOL darkMode) {
    if (darkMode) {
        return @[
            (id)[UIColor colorWithRed:0.20 green:0.22 blue:0.28 alpha:0.72].CGColor,
            (id)[UIColor colorWithRed:0.28 green:0.21 blue:0.34 alpha:0.66].CGColor,
            (id)[UIColor colorWithRed:0.17 green:0.33 blue:0.30 alpha:0.62].CGColor,
            (id)[UIColor colorWithRed:0.35 green:0.31 blue:0.18 alpha:0.58].CGColor
        ];
    }
    return @[
        (id)[UIColor colorWithRed:0.54 green:0.85 blue:1.00 alpha:0.28].CGColor,
        (id)[UIColor colorWithRed:0.68 green:0.63 blue:1.00 alpha:0.24].CGColor,
        (id)[UIColor colorWithRed:0.43 green:0.95 blue:0.85 alpha:0.20].CGColor,
        (id)[UIColor colorWithRed:1.00 green:0.79 blue:0.58 alpha:0.18].CGColor
    ];
}

static NSArray *WKSKeyboardGlassGlossColors(BOOL darkMode) {
    if (darkMode) {
        return @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.14].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.06].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.015].CGColor
        ];
    }
    return @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.26].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.03].CGColor
    ];
}

static CAGradientLayer *WKSFindNamedGradientLayer(CALayer *container, NSString *name) {
    if (!container || name.length == 0) {
        return nil;
    }

    for (CALayer *sub in container.sublayers) {
        if (![sub isKindOfClass:[CAGradientLayer class]]) {
            continue;
        }
        if ([sub.name isEqualToString:name]) {
            return (CAGradientLayer *)sub;
        }
    }
    return nil;
}

static CALayer *WKSFindNamedLayer(CALayer *container, NSString *name) {
    if (!container || name.length == 0) {
        return nil;
    }
    for (CALayer *sub in container.sublayers) {
        if ([sub.name isEqualToString:name]) {
            return sub;
        }
    }
    return nil;
}

static NSString *WKSKeyboardSkinBackgroundPath(BOOL darkMode) {
    NSString *fileName = darkMode ? @"bda_back_dark.png" : @"bda_back_light.png";
    NSArray<NSString *> *candidates = @[
        [@"/var/jb/Library/Application Support/WeChatKeyboardSwitch" stringByAppendingPathComponent:fileName],
        [@"/Library/Application Support/WeChatKeyboardSwitch" stringByAppendingPathComponent:fileName]
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        if ([fm fileExistsAtPath:path]) {
            return path;
        }
    }
    return nil;
}

static BOOL WKSSystemPrefersDarkAppearance(void) {
    NSString *style = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
    if (![style isKindOfClass:[NSString class]]) {
        return NO;
    }
    return [style caseInsensitiveCompare:@"dark"] == NSOrderedSame;
}

static BOOL WKSReadKeyboardThemeDarkAppearance(BOOL *darkModeOut) {
    Class colorClass = objc_getClass("WBColor");
    if (!colorClass || ![colorClass respondsToSelector:@selector(isDarkTheme)]) {
        return NO;
    }
    BOOL dark = NO;
    @try {
        dark = ((BOOL (*)(id, SEL))objc_msgSend)(colorClass, @selector(isDarkTheme));
    } @catch (__unused NSException *e) {
        return NO;
    }
    if (darkModeOut) {
        *darkModeOut = dark;
    }
    return YES;
}

static BOOL WKSKeyboardThemePrefersDarkAppearance(void) {
    BOOL dark = NO;
    if (WKSReadKeyboardThemeDarkAppearance(&dark)) {
        return dark;
    }
    return WKSSystemPrefersDarkAppearance();
}

static UIImage *WKSKeyboardSkinBackgroundImage(BOOL darkMode) {
    static UIImage *darkImage = nil;
    static UIImage *lightRawImage = nil;
    if (darkMode) {
        if (!darkImage) {
            NSString *path = WKSKeyboardSkinBackgroundPath(YES);
            if (path.length > 0) {
                darkImage = [UIImage imageWithContentsOfFile:path];
            }
        }
        return darkImage;
    }
    if (!lightRawImage) {
        NSString *path = WKSKeyboardSkinBackgroundPath(NO);
        if (path.length > 0) {
            lightRawImage = [UIImage imageWithContentsOfFile:path];
        }
    }
    return lightRawImage ?: darkImage;
}

static CALayer *WKSGetViewBackgroundLayer(UIView *view) {
    if (!view) {
        return nil;
    }
    @try {
        id layerObj = [view valueForKey:@"backgroundLayer"];
        if ([layerObj isKindOfClass:[CALayer class]]) {
            return (CALayer *)layerObj;
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
}

static UIVisualEffectView *WKSFindKeyboardNativeGlassEffectView(UIView *container) {
    if (!container) {
        return nil;
    }
    UIView *candidate = [container viewWithTag:kWKSKeyboardNativeGlassEffectTag];
    if ([candidate isKindOfClass:[UIVisualEffectView class]]) {
        return (UIVisualEffectView *)candidate;
    }
    return nil;
}

static UIImageView *WKSFindKeyboardSkinImageView(UIView *container) {
    if (!container) {
        return nil;
    }
    UIView *candidate = [container viewWithTag:kWKSKeyboardSkinImageViewTag];
    if ([candidate isKindOfClass:[UIImageView class]]) {
        return (UIImageView *)candidate;
    }
    return nil;
}

static void WKSRemoveKeyboardNativeGlassView(UIView *container) {
    UIVisualEffectView *effectView = WKSFindKeyboardNativeGlassEffectView(container);
    if (effectView) {
        [effectView removeFromSuperview];
    }
    UIImageView *skinView = WKSFindKeyboardSkinImageView(container);
    if (skinView) {
        [skinView removeFromSuperview];
    }
    CALayer *rippleHost = WKSFindNamedLayer(container.layer, kWKSKeyboardRippleHostLayerName);
    if (rippleHost) {
        [rippleHost removeFromSuperlayer];
    }
}

static UIBlurEffectStyle WKSKeyboardNativeBlurStyle(BOOL darkMode) {
    if (@available(iOS 13.0, *)) {
        return darkMode ? UIBlurEffectStyleSystemChromeMaterialDark
                        : UIBlurEffectStyleSystemChromeMaterialLight;
    }
    return darkMode ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;
}

static void WKSRemoveKeyboardGradientLayersOnly(CALayer *container) {
    if (!container || container.sublayers.count == 0) {
        return;
    }

    NSArray<CALayer *> *snapshot = [container.sublayers copy];
    for (CALayer *sub in snapshot) {
        if ([sub.name isEqualToString:kWKSKeyboardGlassFillLayerName] ||
            [sub.name isEqualToString:kWKSKeyboardGlassGlossLayerName] ||
            [sub.name isEqualToString:kWKSKeyboardNativeTopTintLayerName] ||
            [sub.name isEqualToString:kWKSKeyboardSkinBackLayerName]) {
            [sub removeFromSuperlayer];
        }
    }
}

static void WKSRemoveModernGlassLayers(CALayer *container) {
    if (!container || container.sublayers.count == 0) {
        return;
    }

    NSArray<CALayer *> *snapshot = [container.sublayers copy];
    for (CALayer *sub in snapshot) {
        if ([sub.name isEqualToString:kWKSGlassFillLayerName] ||
            [sub.name isEqualToString:kWKSGlassGlossLayerName] ||
            [sub.name isEqualToString:kWKSGlassBorderLayerName]) {
            [sub removeFromSuperlayer];
        }
    }
}

static void WKSRemoveToolbarGlassLayers(CALayer *container) {
    if (!container || container.sublayers.count == 0) {
        return;
    }

    NSArray<CALayer *> *snapshot = [container.sublayers copy];
    for (CALayer *sub in snapshot) {
        if ([sub.name isEqualToString:kWKSToolbarGlassFillLayerName] ||
            [sub.name isEqualToString:kWKSToolbarGlassGlossLayerName]) {
            [sub removeFromSuperlayer];
        }
    }
}

static void WKSRemoveKeyboardGlassLayers(CALayer *container) {
    if (!container) {
        return;
    }

    WKSRemoveKeyboardGradientLayersOnly(container);
    id delegate = container.delegate;
    if ([delegate isKindOfClass:[UIView class]]) {
        WKSRemoveKeyboardNativeGlassView((UIView *)delegate);
    }
}

__attribute__((unused))
static void WKSApplyModernGlassLayers(CALayer *container, CGFloat cornerRadius) {
    if (!container) {
        return;
    }

    CGRect bounds = container.bounds;
    if (CGRectIsEmpty(bounds) || bounds.size.width < 6.0 || bounds.size.height < 6.0) {
        return;
    }

    CAGradientLayer *fillLayer = WKSFindNamedGradientLayer(container, kWKSGlassFillLayerName);
    if (!fillLayer) {
        fillLayer = [CAGradientLayer layer];
        fillLayer.name = kWKSGlassFillLayerName;
        [container insertSublayer:fillLayer atIndex:0];
    }
    fillLayer.frame = bounds;
    fillLayer.cornerRadius = cornerRadius;
    fillLayer.startPoint = CGPointMake(0.0, 0.0);
    fillLayer.endPoint = CGPointMake(1.0, 1.0);
    fillLayer.locations = @[@0.0, @0.55, @1.0];
    BOOL darkMode = WKSIsDarkAppearanceForLayer(container);
    if (darkMode) {
        fillLayer.colors = @[
            (id)[UIColor colorWithWhite:0.08 alpha:0.84].CGColor,
            (id)[UIColor colorWithRed:0.11 green:0.13 blue:0.18 alpha:0.76].CGColor,
            (id)[UIColor colorWithRed:0.10 green:0.13 blue:0.11 alpha:0.72].CGColor
        ];
    } else {
        fillLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.23].CGColor,
            (id)[UIColor colorWithRed:0.84 green:0.92 blue:1.00 alpha:0.18].CGColor,
            (id)[UIColor colorWithRed:0.90 green:0.98 blue:0.94 alpha:0.14].CGColor
        ];
    }

    CAGradientLayer *glossLayer = WKSFindNamedGradientLayer(container, kWKSGlassGlossLayerName);
    if (!glossLayer) {
        glossLayer = [CAGradientLayer layer];
        glossLayer.name = kWKSGlassGlossLayerName;
        [container addSublayer:glossLayer];
    }
    glossLayer.frame = bounds;
    glossLayer.cornerRadius = cornerRadius;
    glossLayer.startPoint = CGPointMake(0.5, 0.0);
    glossLayer.endPoint = CGPointMake(0.5, 1.0);
    glossLayer.locations = @[@0.0, @0.35, @1.0];
    if (darkMode) {
        glossLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.05].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.01].CGColor
        ];
    } else {
        glossLayer.colors = @[
            (id)[UIColor colorWithWhite:1.0 alpha:0.24].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
            (id)[UIColor colorWithWhite:1.0 alpha:0.02].CGColor
        ];
    }

    CAGradientLayer *borderLayer = WKSFindNamedGradientLayer(container, kWKSGlassBorderLayerName);
    if (!borderLayer) {
        borderLayer = [CAGradientLayer layer];
        borderLayer.name = kWKSGlassBorderLayerName;
        [container addSublayer:borderLayer];
    }
    borderLayer.frame = bounds;
    borderLayer.startPoint = CGPointMake(0.0, 0.0);
    borderLayer.endPoint = CGPointMake(1.0, 1.0);
    borderLayer.locations = @[@0.0, @0.45, @1.0];
    if (darkMode) {
        borderLayer.colors = @[
            (id)[UIColor colorWithRed:0.62 green:0.76 blue:0.90 alpha:0.42].CGColor,
            (id)[UIColor colorWithRed:0.78 green:0.70 blue:0.90 alpha:0.34].CGColor,
            (id)[UIColor colorWithRed:0.62 green:0.86 blue:0.76 alpha:0.36].CGColor
        ];
    } else {
        borderLayer.colors = @[
            (id)[UIColor colorWithRed:0.69 green:0.91 blue:1.00 alpha:0.96].CGColor,
            (id)[UIColor colorWithRed:0.95 green:0.88 blue:1.00 alpha:0.90].CGColor,
            (id)[UIColor colorWithRed:0.75 green:1.00 blue:0.93 alpha:0.92].CGColor
        ];
    }

    CAShapeLayer *mask = nil;
    if ([borderLayer.mask isKindOfClass:[CAShapeLayer class]]) {
        mask = (CAShapeLayer *)borderLayer.mask;
    } else {
        mask = [CAShapeLayer layer];
        borderLayer.mask = mask;
    }
    CGRect strokeRect = CGRectInset(bounds, 0.65, 0.65);
    CGFloat strokeRadius = MAX(1.0, cornerRadius - 0.65);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:strokeRect cornerRadius:strokeRadius];
    mask.path = path.CGPath;
    mask.fillColor = UIColor.clearColor.CGColor;
    mask.strokeColor = [UIColor colorWithWhite:1.0 alpha:(darkMode ? 0.54 : 1.0)].CGColor;
    mask.lineWidth = 1.2;
}

__attribute__((unused))
static void WKSApplyToolbarGlassBackgroundOnView(UIView *view) {
    if (!view) {
        return;
    }

    CGRect bounds = view.bounds;
    if (CGRectIsEmpty(bounds) || bounds.size.width < 20.0 || bounds.size.height < 12.0) {
        return;
    }

    view.opaque = NO;
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;

    // 工具栏使用父容器坐标系取样，尽量与键盘主背景保持连续。
    CGRect samplingFrame = bounds;
    UIView *superview = view.superview;
    if (superview) {
        CGRect superBounds = superview.bounds;
        if (!CGRectIsEmpty(superBounds)) {
            samplingFrame = [view convertRect:superBounds fromView:superview];
        }
    }

    CAGradientLayer *fillLayer = WKSFindNamedGradientLayer(view.layer, kWKSToolbarGlassFillLayerName);
    if (!fillLayer) {
        fillLayer = [CAGradientLayer layer];
        fillLayer.name = kWKSToolbarGlassFillLayerName;
        [view.layer insertSublayer:fillLayer atIndex:0];
    }
    fillLayer.frame = samplingFrame;
    fillLayer.cornerRadius = 0.0;
    fillLayer.startPoint = CGPointMake(0.0, 0.0);
    fillLayer.endPoint = CGPointMake(1.0, 1.0);
    fillLayer.locations = @[@0.0, @0.33, @0.68, @1.0];
    BOOL darkMode = WKSIsDarkAppearanceForView(view);
    fillLayer.colors = WKSKeyboardGlassFillColors(darkMode);

    CAGradientLayer *glossLayer = WKSFindNamedGradientLayer(view.layer, kWKSToolbarGlassGlossLayerName);
    if (!glossLayer) {
        glossLayer = [CAGradientLayer layer];
        glossLayer.name = kWKSToolbarGlassGlossLayerName;
        [view.layer addSublayer:glossLayer];
    }
    glossLayer.frame = samplingFrame;
    glossLayer.cornerRadius = 0.0;
    glossLayer.startPoint = CGPointMake(0.5, 0.0);
    glossLayer.endPoint = CGPointMake(0.5, 1.0);
    glossLayer.locations = @[@0.0, @0.3, @1.0];
    glossLayer.colors = WKSKeyboardGlassGlossColors(darkMode);
}

__attribute__((unused))
static void WKSApplyKeyboardGlassBackgroundOnView(UIView *view) {
    if (!view) {
        return;
    }

    CGRect bounds = view.bounds;
    if (CGRectIsEmpty(bounds) || bounds.size.width < 24.0 || bounds.size.height < 24.0) {
        return;
    }

    view.opaque = NO;
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;

    CGFloat cornerRadius = 14.0;
    CGRect renderRect = bounds;

    CAGradientLayer *fillLayer = WKSFindNamedGradientLayer(view.layer, kWKSKeyboardGlassFillLayerName);
    if (!fillLayer) {
        fillLayer = [CAGradientLayer layer];
        fillLayer.name = kWKSKeyboardGlassFillLayerName;
        [view.layer insertSublayer:fillLayer atIndex:0];
    }
    fillLayer.frame = renderRect;
    fillLayer.cornerRadius = cornerRadius;
    fillLayer.startPoint = CGPointMake(0.0, 0.0);
    fillLayer.endPoint = CGPointMake(1.0, 1.0);
    fillLayer.locations = @[@0.0, @0.33, @0.68, @1.0];
    BOOL darkMode = WKSKeyboardThemePrefersDarkAppearance();
    fillLayer.colors = WKSKeyboardGlassFillColors(darkMode);

    CAGradientLayer *glossLayer = WKSFindNamedGradientLayer(view.layer, kWKSKeyboardGlassGlossLayerName);
    if (!glossLayer) {
        glossLayer = [CAGradientLayer layer];
        glossLayer.name = kWKSKeyboardGlassGlossLayerName;
        [view.layer addSublayer:glossLayer];
    }
    glossLayer.frame = renderRect;
    glossLayer.cornerRadius = cornerRadius;
    glossLayer.startPoint = CGPointMake(0.5, 0.0);
    glossLayer.endPoint = CGPointMake(0.5, 1.0);
    glossLayer.locations = @[@0.0, @0.3, @1.0];
    glossLayer.colors = WKSKeyboardGlassGlossColors(darkMode);
}

static UIView *WKSFindToolbarViewInTree(UIView *root, int depth) {
    if (!root || depth > 6) {
        return nil;
    }
    if (WKSClassNameLooksToolbar(NSStringFromClass([root class]))) {
        return root;
    }
    for (UIView *sub in root.subviews) {
        UIView *found = WKSFindToolbarViewInTree(sub, depth + 1);
        if (found) {
            return found;
        }
    }
    return nil;
}

static UIView *WKSCommonAncestorView(UIView *a, UIView *b) {
    if (!a || !b) {
        return nil;
    }
    for (UIView *ca = a; ca; ca = ca.superview) {
        for (UIView *cb = b; cb; cb = cb.superview) {
            if (ca == cb) {
                return ca;
            }
        }
    }
    return nil;
}

static UIView *WKSFindWiderGlassPaintView(UIView *baseView, CGFloat minRequiredHeight) {
    if (!baseView || CGRectIsEmpty(baseView.bounds)) {
        return baseView;
    }

    (void)minRequiredHeight;

    // 直接上提到窗口前一层，确保键盘缩放后两侧露白仍被同一背景覆盖。
    UIView *top = baseView;
    UIView *cursor = baseView;
    for (int i = 0; cursor && i < 12; i++) {
        UIView *sup = cursor.superview;
        if (!sup || [sup isKindOfClass:[UIWindow class]]) {
            break;
        }
        if (!CGRectIsEmpty(sup.bounds) && sup.bounds.size.width >= 24.0 && sup.bounds.size.height >= 24.0) {
            top = sup;
        }
        cursor = sup;
    }
    return top ?: baseView;
}

static void WKSCollectKeyRectsInView(UIView *root, UIView *convertTo,
                                     NSMutableArray<NSValue *> *rects, int depth) {
    if (!root || !convertTo || !rects || depth > 9) {
        return;
    }

    if (WKSIsKeyViewLike(root) && !root.hidden && root.alpha > 0.01f) {
        CGRect rect = [root convertRect:root.bounds toView:convertTo];
        if (!CGRectIsEmpty(rect) && rect.size.width >= 12.0 && rect.size.height >= 12.0) {
            [rects addObject:[NSValue valueWithCGRect:rect]];
        }
    }

    for (UIView *sub in root.subviews) {
        WKSCollectKeyRectsInView(sub, convertTo, rects, depth + 1);
    }
}

static BOOL WKSBuildToolbarFirstRowGlassRect(UIView *common,
                                             UIView *hostingView,
                                             UIView *toolbarView,
                                             CGRect *outRect) {
    if (!common || !hostingView || !toolbarView || !outRect) {
        return NO;
    }

    CGRect commonBounds = common.bounds;
    CGRect hostRect = [hostingView convertRect:hostingView.bounds toView:common];
    CGRect toolbarRect = [toolbarView convertRect:toolbarView.bounds toView:common];
    if (CGRectIsEmpty(commonBounds) || CGRectIsEmpty(hostRect) || CGRectIsEmpty(toolbarRect)) {
        return NO;
    }

    NSMutableArray<NSValue *> *keyRects = [NSMutableArray array];
    WKSCollectKeyRectsInView(hostingView, common, keyRects, 0);

    CGFloat hostMinY = CGRectGetMinY(hostRect);
    CGFloat hostMaxY = CGRectGetMaxY(hostRect);
    CGFloat minKeyY = CGFLOAT_MAX;

    for (NSValue *value in keyRects) {
        CGRect keyRect = value.CGRectValue;
        if (CGRectIsEmpty(keyRect)) {
            continue;
        }
        CGFloat y = CGRectGetMinY(keyRect);
        if (y < (hostMinY - 1.0) || y > (hostMaxY + 1.0)) {
            continue;
        }
        if (y < minKeyY) {
            minKeyY = y;
        }
    }

    CGFloat firstRowTop = hostMinY;
    CGFloat firstRowBottom = hostMinY + MAX(56.0, MIN(hostRect.size.height * 0.24, 116.0));
    if (minKeyY != CGFLOAT_MAX) {
        firstRowTop = MAX(hostMinY, minKeyY);
        CGFloat rowTolerance = MAX(18.0, MIN(30.0, hostRect.size.height * 0.05));
        firstRowBottom = firstRowTop;
        for (NSValue *value in keyRects) {
            CGRect keyRect = value.CGRectValue;
            if (CGRectIsEmpty(keyRect)) {
                continue;
            }
            if (CGRectGetMinY(keyRect) <= (firstRowTop + rowTolerance)) {
                firstRowBottom = MAX(firstRowBottom, CGRectGetMaxY(keyRect));
            }
        }
    }

    firstRowBottom = MIN(hostMaxY, firstRowBottom);
    if (firstRowBottom <= firstRowTop + 4.0) {
        return NO;
    }

    CGRect firstRowRect = CGRectMake(hostRect.origin.x,
                                     firstRowTop,
                                     hostRect.size.width,
                                     firstRowBottom - firstRowTop);
    CGRect topGlassRect = CGRectUnion(toolbarRect, firstRowRect);
    CGRect clipped = CGRectIntersection(topGlassRect, commonBounds);
    if (CGRectIsEmpty(clipped) || clipped.size.width < 24.0 || clipped.size.height < 24.0) {
        return NO;
    }
    *outRect = clipped;
    return YES;
}

static void WKSApplyKeyboardGlassBackgroundInView(UIView *view, CGRect renderRect, CGFloat cornerRadius, CGFloat toolbarTintHeight) {
    if (!view) {
        return;
    }
    (void)toolbarTintHeight;
    CAGradientLayer *topTintLayer = WKSFindNamedGradientLayer(view.layer, kWKSKeyboardNativeTopTintLayerName);
    if (CGRectIsEmpty(renderRect) || renderRect.size.width < 24.0 || renderRect.size.height < 24.0) {
        if (topTintLayer) {
            [topTintLayer removeFromSuperlayer];
        }
        CALayer *skinLayer = WKSFindNamedLayer(view.layer, kWKSKeyboardSkinBackLayerName);
        if (skinLayer) {
            [skinLayer removeFromSuperlayer];
        }
        CALayer *rippleHostLayer = WKSFindNamedLayer(view.layer, kWKSKeyboardRippleHostLayerName);
        if (rippleHostLayer) {
            [rippleHostLayer removeFromSuperlayer];
        }
        WKSRemoveKeyboardGradientLayersOnly(view.layer);
        WKSRemoveKeyboardNativeGlassView(view);
        return;
    }

    view.opaque = NO;
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
    BOOL darkMode = WKSIsDarkAppearanceForView(view);
    WKSRemoveKeyboardGradientLayersOnly(view.layer);

    UIVisualEffectView *effectView = WKSFindKeyboardNativeGlassEffectView(view);
    if (!effectView) {
        effectView = [[UIVisualEffectView alloc] initWithEffect:nil];
        effectView.tag = kWKSKeyboardNativeGlassEffectTag;
        effectView.userInteractionEnabled = NO;
        [view insertSubview:effectView atIndex:0];
    } else if (effectView.superview != view) {
        [effectView removeFromSuperview];
        [view insertSubview:effectView atIndex:0];
    }
    effectView.effect = [UIBlurEffect effectWithStyle:WKSKeyboardNativeBlurStyle(darkMode)];
    effectView.frame = renderRect;
    effectView.alpha = 0.0;
    effectView.clipsToBounds = YES;
    effectView.layer.cornerRadius = cornerRadius;
    effectView.layer.masksToBounds = YES;

    UIView *tintView = [effectView.contentView viewWithTag:kWKSKeyboardNativeGlassTintTag];
    if (!tintView) {
        tintView = [[UIView alloc] initWithFrame:effectView.contentView.bounds];
        tintView.tag = kWKSKeyboardNativeGlassTintTag;
        tintView.userInteractionEnabled = NO;
        tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [effectView.contentView addSubview:tintView];
    }
    tintView.frame = effectView.contentView.bounds;
    tintView.backgroundColor = UIColor.clearColor;
    UIImage *skinImage = WKSKeyboardSkinBackgroundImage(darkMode);
    UIImageView *skinView = WKSFindKeyboardSkinImageView(view);
    if (skinImage) {
        if (!skinView) {
            skinView = [[UIImageView alloc] initWithFrame:renderRect];
            skinView.tag = kWKSKeyboardSkinImageViewTag;
            skinView.userInteractionEnabled = NO;
            [view insertSubview:skinView atIndex:0];
        } else if (skinView.superview != view) {
            [skinView removeFromSuperview];
            [view insertSubview:skinView atIndex:0];
        }
        skinView.frame = renderRect;
        skinView.image = skinImage;
        skinView.alpha = 1.0;
        skinView.backgroundColor = UIColor.clearColor;
        skinView.contentMode = UIViewContentModeScaleToFill;
        skinView.clipsToBounds = YES;
        skinView.layer.cornerRadius = cornerRadius;
        skinView.layer.masksToBounds = YES;
    } else if (skinView) {
        [skinView removeFromSuperview];
    }

    CALayer *hostBackgroundLayer = WKSGetViewBackgroundLayer(view);
    if (hostBackgroundLayer) {
        if (skinImage.CGImage) {
            hostBackgroundLayer.contents = (__bridge id)skinImage.CGImage;
            hostBackgroundLayer.contentsGravity = kCAGravityResize;
            hostBackgroundLayer.contentsRect = CGRectMake(0.0, 0.0, 1.0, 1.0);
            hostBackgroundLayer.contentsScale = UIScreen.mainScreen.scale;
            hostBackgroundLayer.backgroundColor = UIColor.clearColor.CGColor;
        } else {
            hostBackgroundLayer.contents = nil;
        }
    }

    CALayer *skinLayer = WKSFindNamedLayer(view.layer, kWKSKeyboardSkinBackLayerName);
    CALayer *rippleHostLayer = WKSFindNamedLayer(view.layer, kWKSKeyboardRippleHostLayerName);
    if (skinImage.CGImage) {
        if (!skinLayer) {
            skinLayer = [CALayer layer];
            skinLayer.name = kWKSKeyboardSkinBackLayerName;
            [view.layer insertSublayer:skinLayer atIndex:0];
        }
        skinLayer.frame = renderRect;
        skinLayer.contents = (__bridge id)skinImage.CGImage;
        skinLayer.contentsGravity = kCAGravityResize;
        skinLayer.contentsRect = CGRectMake(0.0, 0.0, 1.0, 1.0);
        skinLayer.contentsScale = UIScreen.mainScreen.scale;
        skinLayer.opacity = 1.0f;
        skinLayer.backgroundColor = UIColor.clearColor.CGColor;
        skinLayer.cornerRadius = cornerRadius;
        skinLayer.masksToBounds = YES;
        if (rippleHostLayer) {
            [rippleHostLayer removeFromSuperlayer];
        }
    } else if (skinLayer) {
        [skinLayer removeFromSuperlayer];
        if (rippleHostLayer) {
            [rippleHostLayer removeFromSuperlayer];
        }
    } else if (rippleHostLayer) {
        [rippleHostLayer removeFromSuperlayer];
    }
    if (topTintLayer) {
        [topTintLayer removeFromSuperlayer];
    }
}

static UIView *WKSFindKeyboardBackgroundContainerView(id panelObj, UIView **hostingOut) {
    UIView *hostingView = nil;
    id hosting = WKSGetPanelHosting(panelObj);
    if ([hosting isKindOfClass:[UIView class]]) {
        hostingView = (UIView *)hosting;
    } else if ([panelObj isKindOfClass:[UIView class]]) {
        hostingView = (UIView *)panelObj;
    }

    if (hostingOut) {
        *hostingOut = hostingView;
    }
    if (!hostingView) {
        return nil;
    }

    UIView *container = hostingView;
    UIView *superview = hostingView.superview;
    if (!superview || CGRectIsEmpty(superview.bounds)) {
        return container;
    }

    CGFloat hostW = hostingView.bounds.size.width;
    CGFloat hostH = hostingView.bounds.size.height;
    CGFloat supW = superview.bounds.size.width;
    CGFloat supH = superview.bounds.size.height;

    BOOL widthMatched = hostW > 1.0 && fabs(supW - hostW) <= MAX(24.0, hostW * 0.12);
    BOOL heightExpanded = supH > (hostH + 8.0) && supH <= (hostH * 1.9);
    if (widthMatched && heightExpanded) {
        container = superview;
    }

    return container;
}

static NSString *WKSKeyboardSupportDirectoryPath(void) {
    static NSString *cached = nil;
    if (cached.length > 0) {
        return cached;
    }
    NSArray<NSString *> *candidates = @[
        @"/var/jb/Library/Application Support/WeChatKeyboardSwitch",
        @"/Library/Application Support/WeChatKeyboardSwitch"
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in candidates) {
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            cached = [path copy];
            return cached;
        }
    }
    return nil;
}

static NSString *WKSKeyboardRipplePrefixFromString(NSString *value) {
    if (value.length == 0) {
        return nil;
    }
    NSString *lower = value.lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar ch = [lower characterAtIndex:i];
        if (ch >= 'a' && ch <= 'z') {
            return [NSString stringWithCharacters:&ch length:1];
        }
    }
    return nil;
}

static NSString *WKSKeyboardRipplePrefixForKeyView(id keyView) {
    if (!keyView) {
        return nil;
    }

    NSArray<NSString *> *directKeys = @[@"defaultInputForNormalState", @"defaultTitle", @"title", @"input"];
    for (NSString *key in directKeys) {
        NSString *prefix = WKSKeyboardRipplePrefixFromString(WKSStringForKVC(keyView, key));
        if (prefix.length == 1) {
            return prefix;
        }
    }

    id item = nil;
    @try {
        item = [keyView valueForKey:@"item"];
    } @catch (__unused NSException *e) {
    }
    NSArray<NSString *> *itemKeys = @[@"input", @"upInput", @"title", @"identifier"];
    for (NSString *key in itemKeys) {
        NSString *prefix = WKSKeyboardRipplePrefixFromString(WKSStringForKVC(item, key));
        if (prefix.length == 1) {
            return prefix;
        }
    }
    return nil;
}

static NSArray *WKSKeyboardRippleFrameCGImages(NSString *prefix, BOOL darkMode) {
    static NSCache<NSString *, NSArray *> *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 8;
        cache.totalCostLimit = (NSUInteger)(48 * 1024 * 1024);
    });

    NSString *setKey = (prefix.length == 1) ? prefix.lowercaseString : @"_default";
    NSString *cacheKey = [NSString stringWithFormat:@"%@:%@", darkMode ? @"d" : @"l", setKey];
    NSArray *cached = [cache objectForKey:cacheKey];
    if (cached.count > 1) {
        return cached;
    }

    NSString *baseDir = WKSKeyboardSupportDirectoryPath();
    if (baseDir.length == 0) {
        return @[];
    }

    NSArray<NSDictionary<NSString *, id> *> *attempts = @[
        @{@"dark": @(darkMode), @"set": setKey},
        @{@"dark": @(darkMode), @"set": @"_default"},
        @{@"dark": @(!darkMode), @"set": setKey},
        @{@"dark": @(!darkMode), @"set": @"_default"}
    ];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *values = nil;
    for (NSDictionary<NSString *, id> *attempt in attempts) {
        BOOL attemptDark = [attempt[@"dark"] boolValue];
        NSString *attemptSet = attempt[@"set"];
        NSString *attemptCacheKey = [NSString stringWithFormat:@"%@:%@",
                                     attemptDark ? @"d" : @"l", attemptSet];
        NSArray *attemptCached = [cache objectForKey:attemptCacheKey];
        if (attemptCached.count > 1) {
            values = attemptCached;
            break;
        }

        NSString *folder = attemptDark ? @"llee_dark" : @"llee_light";
        NSMutableArray *tmp = [NSMutableArray arrayWithCapacity:16];
        NSUInteger byteCost = 0;
        for (NSInteger idx = 0; idx <= 30; idx += kWKSRippleFrameStride) {
            NSString *name = [attemptSet isEqualToString:@"_default"]
                ? [NSString stringWithFormat:@"lleeimage_%ld.png", (long)idx]
                : [NSString stringWithFormat:@"%@_lleeimage_%ld.png", attemptSet, (long)idx];
            NSString *path = [[baseDir stringByAppendingPathComponent:folder]
                              stringByAppendingPathComponent:name];
            if (![fm fileExistsAtPath:path]) {
                continue;
            }

            UIImage *raw = [UIImage imageWithContentsOfFile:path];
            if (!raw.CGImage) {
                continue;
            }

            // 压缩到较小尺寸后再入缓存，避免快打时内存暴涨导致崩溃。
            CGSize rawSize = raw.size;
            CGFloat maxSide = MAX(rawSize.width, rawSize.height);
            UIImage *prepared = raw;
            if (maxSide > kWKSRippleDecodeMaxSide) {
                CGFloat ratio = kWKSRippleDecodeMaxSide / maxSide;
                CGSize target = CGSizeMake(MAX(1.0, floor(rawSize.width * ratio)),
                                           MAX(1.0, floor(rawSize.height * ratio)));
                UIGraphicsBeginImageContextWithOptions(target, NO, 1.0);
                [raw drawInRect:CGRectMake(0.0, 0.0, target.width, target.height)];
                UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                if (scaled.CGImage) {
                    prepared = scaled;
                }
            }

            if (prepared.CGImage) {
                [tmp addObject:(__bridge id)prepared.CGImage];
                CGSize sz = prepared.size;
                byteCost += (NSUInteger)(MAX(1.0, sz.width) * MAX(1.0, sz.height) * 4.0);
            }
        }

        if (tmp.count > 1) {
            values = [tmp copy];
            [cache setObject:values forKey:attemptCacheKey cost:byteCost];
            break;
        }
    }
    if (values.count < 2) {
        return @[];
    }
    return values;
}

static UIView *WKSFindKeyboardRipplePaintViewAroundPanel(UIView *panelView, CALayer **rippleHostLayerOut) {
    if (rippleHostLayerOut) {
        *rippleHostLayerOut = nil;
    }
    if (!panelView) {
        return nil;
    }

    UIView *cursor = panelView;
    for (int i = 0; cursor && i < 14; i++) {
        // 清理旧版本可能挂在父层的波纹宿主，避免在按钮前景层可见。
        CALayer *legacyHost = WKSFindNamedLayer(cursor.layer, kWKSKeyboardRippleHostLayerName);
        if (legacyHost) {
            [legacyHost removeFromSuperlayer];
        }

        UIView *candidate = [cursor viewWithTag:kWKSKeyboardSkinImageViewTag];
        if ([candidate isKindOfClass:[UIImageView class]]) {
            UIImageView *skinView = (UIImageView *)candidate;
            CALayer *rippleLayer = WKSFindNamedLayer(skinView.layer, kWKSKeyboardRippleHostLayerName);
            if (!rippleLayer) {
                rippleLayer = [CALayer layer];
                rippleLayer.name = kWKSKeyboardRippleHostLayerName;
                rippleLayer.backgroundColor = UIColor.clearColor.CGColor;
                [skinView.layer addSublayer:rippleLayer];
            }
            rippleLayer.frame = skinView.bounds;
            rippleLayer.cornerRadius = skinView.layer.cornerRadius;
            rippleLayer.masksToBounds = YES;
            if (rippleHostLayerOut) {
                *rippleHostLayerOut = rippleLayer;
            }
            return skinView;
        }
        cursor = cursor.superview;
    }
    return nil;
}

static void WKSShowKeyboardTouchRipple(id panel, id touch) {
    if (!panel || !touch || ![panel isKindOfClass:[UIView class]]) {
        return;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (gWKSLastRippleEmitTs > 0.0 &&
        (now - gWKSLastRippleEmitTs) < kWKSRippleMinIntervalSeconds) {
        return;
    }
    gWKSLastRippleEmitTs = now;

    CGPoint pointInPanel = CGPointZero;
    if (!WKSGetTouchLocationInPanel(touch, panel, &pointInPanel)) {
        return;
    }

    UIView *panelView = (UIView *)panel;
    CALayer *rippleHostLayer = nil;
    UIView *paintView = WKSFindKeyboardRipplePaintViewAroundPanel(panelView, &rippleHostLayer);
    if (!paintView || !rippleHostLayer ||
        rippleHostLayer.bounds.size.width < 20.0 || rippleHostLayer.bounds.size.height < 20.0) {
        return;
    }

    CGPoint pointInPaint = [panelView convertPoint:pointInPanel toView:paintView];
    CGPoint pointInHost = CGPointMake(pointInPaint.x - CGRectGetMinX(rippleHostLayer.frame),
                                      pointInPaint.y - CGRectGetMinY(rippleHostLayer.frame));
    if (!CGRectContainsPoint(rippleHostLayer.bounds, pointInHost)) {
        return;
    }

    CGFloat effectSize = 340.0;
    id keyView = WKSGetKeyViewFromTouch(panel, touch);
    BOOL darkMode = WKSIsDarkAppearanceForView(paintView);
    NSString *prefix = WKSKeyboardRipplePrefixForKeyView(keyView);
    NSArray *frameValues = WKSKeyboardRippleFrameCGImages(prefix, darkMode);
    if (frameValues.count < 2) {
        return;
    }
    if ([keyView isKindOfClass:[UIView class]]) {
        CGRect keyRect = [(UIView *)keyView convertRect:((UIView *)keyView).bounds toView:paintView];
        CGFloat keySide = MAX(CGRectGetWidth(keyRect), CGRectGetHeight(keyRect));
        if (keySide > 1.0) {
            effectSize = MIN(430.0, MAX(220.0, keySide * 3.7));
        }
    }

    NSArray *renderFrames = frameValues;
    if (frameValues.count > 4) {
        renderFrames = [frameValues subarrayWithRange:NSMakeRange(1, frameValues.count - 2)];
    }
    if (renderFrames.count < 2) {
        renderFrames = frameValues;
    }

    CALayer *rippleLayer = [CALayer layer];
    rippleLayer.frame = CGRectMake(pointInHost.x - effectSize * 0.5,
                                   pointInHost.y - effectSize * 0.5,
                                   effectSize, effectSize);
    rippleLayer.contentsScale = UIScreen.mainScreen.scale;
    rippleLayer.contentsGravity = kCAGravityResizeAspectFill;
    CGFloat baseOpacity = darkMode ? 0.58f : 0.80f;
    rippleLayer.opacity = 0.0f;
    rippleLayer.contents = renderFrames.firstObject;
    rippleLayer.transform = CATransform3DMakeScale(0.94, 0.94, 1.0);
    [rippleHostLayer addSublayer:rippleLayer];

    while (rippleHostLayer.sublayers.count > 8) {
        CALayer *oldest = rippleHostLayer.sublayers.firstObject;
        if (!oldest || oldest == rippleLayer) {
            break;
        }
        [oldest removeFromSuperlayer];
    }

    CAKeyframeAnimation *contentsAnim = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
    contentsAnim.values = renderFrames;
    contentsAnim.calculationMode = kCAAnimationDiscrete;
    contentsAnim.duration = 0.66;
    contentsAnim.removedOnCompletion = YES;

    CAKeyframeAnimation *alphaAnim = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    alphaAnim.values = @[@0.0, @(baseOpacity * 0.38), @(baseOpacity), @(baseOpacity * 0.45), @0.0];
    alphaAnim.keyTimes = @[@0.0, @0.30, @0.62, @0.86, @1.0];
    alphaAnim.duration = 0.66;
    alphaAnim.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]
    ];
    alphaAnim.removedOnCompletion = YES;

    CAKeyframeAnimation *scaleAnim = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    scaleAnim.values = @[@0.94, @1.00, @1.06];
    scaleAnim.keyTimes = @[@0.0, @0.40, @1.0];
    scaleAnim.duration = 0.66;
    scaleAnim.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]
    ];
    scaleAnim.removedOnCompletion = YES;

    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[contentsAnim, alphaAnim, scaleAnim];
    group.duration = 0.66;
    group.removedOnCompletion = YES;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [CATransaction setCompletionBlock:^{
        [rippleLayer removeFromSuperlayer];
    }];
    [rippleLayer addAnimation:group forKey:@"wks_keyboard_ripple"];
    rippleLayer.contents = renderFrames.lastObject;
    rippleLayer.opacity = 0.0f;
    rippleLayer.transform = CATransform3DMakeScale(1.06, 1.06, 1.0);
    [CATransaction commit];
}

static void WKSApplyKeyboardGlassBackgroundForPanel(id panelObj) {
    if (!panelObj) {
        return;
    }

    UIView *hostingView = nil;
    UIView *targetView = WKSFindKeyboardBackgroundContainerView(panelObj, &hostingView);
    if (!targetView) {
        return;
    }

    UIView *searchRoot = targetView;
    if (hostingView && hostingView.superview) {
        searchRoot = hostingView.superview;
    }
    UIView *toolbarView = WKSFindToolbarViewInTree(searchRoot, 0);
    if (!toolbarView && searchRoot.superview) {
        toolbarView = WKSFindToolbarViewInTree(searchRoot.superview, 0);
    }

    if (hostingView && toolbarView) {
        UIView *common = WKSCommonAncestorView(hostingView, toolbarView);
        if (common && !CGRectIsEmpty(common.bounds)) {
            CGRect clipped = CGRectZero;
            if (WKSBuildToolbarFirstRowGlassRect(common, hostingView, toolbarView, &clipped)) {
                UIView *paintView = WKSFindWiderGlassPaintView(common, CGRectGetMaxY(clipped));
                CGRect paintRect = clipped;
                if (paintView && paintView != common) {
                    paintRect = [common convertRect:clipped toView:paintView];
                    paintRect.origin.x = 0.0;
                    paintRect.size.width = paintView.bounds.size.width;
                    paintRect = CGRectIntersection(paintRect, paintView.bounds);
                    if (CGRectIsEmpty(paintRect) || paintRect.size.width < 24.0 || paintRect.size.height < 24.0) {
                        paintView = common;
                        paintRect = clipped;
                    }
                } else {
                    paintView = common;
                }
                if (!CGRectIsEmpty(paintRect)) {
                    paintRect.size.height = MAX(0.0, paintView.bounds.size.height - paintRect.origin.y);
                }
                if (CGRectIsEmpty(paintRect) || paintRect.size.width < 24.0 || paintRect.size.height < 24.0) {
                    paintRect = paintView.bounds;
                }

                if (hostingView != paintView) {
                    WKSRemoveKeyboardGlassLayers(hostingView.layer);
                }
                if (targetView != paintView) {
                    WKSRemoveKeyboardGlassLayers(targetView.layer);
                }
                if (common != paintView) {
                    WKSRemoveKeyboardGlassLayers(common.layer);
                }
                if (toolbarView != paintView) {
                    WKSRemoveToolbarGlassLayers(toolbarView.layer);
                    WKSRemoveModernGlassLayers(toolbarView.layer);
                }
                CGFloat toolbarTintHeight = 0.0;
                CGRect topBandRectInPaint = [common convertRect:clipped toView:paintView];
                CGRect topBandInRender = CGRectIntersection(topBandRectInPaint, paintRect);
                if (!CGRectIsEmpty(topBandInRender)) {
                    toolbarTintHeight = CGRectGetMaxY(topBandInRender) - paintRect.origin.y;
                    toolbarTintHeight = MIN(paintRect.size.height,
                                            MAX(topBandInRender.size.height, toolbarTintHeight));
                } else {
                    CGRect toolbarRectInPaint = [toolbarView convertRect:toolbarView.bounds toView:paintView];
                    CGRect toolbarInRender = CGRectIntersection(toolbarRectInPaint, paintRect);
                    if (!CGRectIsEmpty(toolbarInRender)) {
                        toolbarTintHeight = CGRectGetMaxY(toolbarInRender) - paintRect.origin.y;
                        toolbarTintHeight = MIN(paintRect.size.height,
                                                MAX(toolbarInRender.size.height, toolbarTintHeight));
                    }
                }
                WKSApplyKeyboardGlassBackgroundInView(paintView, paintRect, 0.0, toolbarTintHeight);
                return;
            }
        }
    }

    if (hostingView && targetView != hostingView) {
        WKSRemoveKeyboardGlassLayers(hostingView.layer);
    }
    CGRect fallbackRect = targetView.bounds;
    UIView *fallbackView = WKSFindWiderGlassPaintView(targetView, CGRectGetMaxY(fallbackRect));
    CGRect fallbackPaint = fallbackRect;
    if (fallbackView && fallbackView != targetView) {
        fallbackPaint = [targetView convertRect:fallbackRect toView:fallbackView];
        fallbackPaint.origin.x = 0.0;
        fallbackPaint.size.width = fallbackView.bounds.size.width;
        fallbackPaint.origin.y = MAX(0.0, fallbackPaint.origin.y);
        fallbackPaint.size.height = MAX(0.0, fallbackView.bounds.size.height - fallbackPaint.origin.y);
        fallbackPaint = CGRectIntersection(fallbackPaint, fallbackView.bounds);
        if (CGRectIsEmpty(fallbackPaint) || fallbackPaint.size.width < 24.0 || fallbackPaint.size.height < 24.0) {
            fallbackView = targetView;
            fallbackPaint = fallbackRect;
        }
        WKSRemoveKeyboardGlassLayers(targetView.layer);
    } else {
        fallbackView = targetView;
        fallbackPaint = fallbackView.bounds;
    }
    WKSApplyKeyboardGlassBackgroundInView(fallbackView, fallbackPaint, 0.0, 0.0);
}

static BOOL WKSIsKeyViewLike(UIView *view) {
    if (!view) {
        return NO;
    }

    Class keyViewClass = objc_getClass("WBKeyView");
    if (keyViewClass && [view isKindOfClass:keyViewClass]) {
        return YES;
    }

    NSString *name = NSStringFromClass([view class]).lowercaseString;
    return [name containsString:@"keyview"];
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

    WKSRemoveToolbarGlassLayers(view.layer);
    WKSRemoveKeyboardGlassLayers(view.layer);
    WKSRemoveModernGlassLayers(view.layer);

    view.opaque = NO;
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
    view.layer.borderWidth = 0.0;
    view.layer.borderColor = nil;

    @try {
        id bgLayerObj = [view valueForKey:@"backgroundLayer"];
        if ([bgLayerObj isKindOfClass:[CALayer class]]) {
            CALayer *bgLayer = (CALayer *)bgLayerObj;
            WKSRemoveToolbarGlassLayers(bgLayer);
            WKSRemoveKeyboardGlassLayers(bgLayer);
            WKSRemoveModernGlassLayers(bgLayer);
            bgLayer.backgroundColor = UIColor.clearColor.CGColor;
            bgLayer.borderWidth = 0.0;
            bgLayer.borderColor = nil;
        }
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
    if (!view || depth > 6) {
        return;
    }

    BOOL classMatched = WKSClassNameLooksToolbar(NSStringFromClass([view class]));
    BOOL candidateMatched = WKSIsToolbarCandidateView(view);
    BOOL shouldClear = force || classMatched || candidateMatched;

    if (shouldClear) {
        WKSRemoveToolbarGlassLayers(view.layer);
        WKSClearViewBackground(view);
    } else {
        WKSRemoveToolbarGlassLayers(view.layer);
    }

    BOOL nextForce = force || classMatched || candidateMatched;
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
    if (!keepNativeSwipe) {
        WKSShowKeyboardTouchRipple(self, touch);
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
    if (!WKSUseGestureRecognizerMode() || !self || !touch) {
        return NO;
    }
    if (!WKSConsumePanelCancelTouchEndIfNeeded(self)) {
        return NO;
    }
    // 仅对非空格/删除键生效，避免破坏原生空格滑动与删除行为。
    return !WKSShouldKeepNativeSpaceSwipe(self, touch);
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
    WKSApplyKeyboardGlassBackgroundForPanel(self);
    WKSApplyToolbarTransparency(self);
    WKSEnsurePanelSwipeRecognizers(self);
}

static void WKST9DidAttachHosting(id self, SEL _cmd) {
    if (gOrigT9DidAttachHosting) {
        gOrigT9DidAttachHosting(self, _cmd);
    }
    WKSEnsureDisableCursorAdjustForHost(WKSGetPanelHosting(self));
    WKSApplyKeyboardGlassBackgroundForPanel(self);
    WKSApplyToolbarTransparency(self);
    WKSDisableSymbolListGridFill(WKSGetSymbolListViewFromPanel(self));
    WKSEnsurePanelSwipeRecognizers(self);
}

static void WKST26DidAttachHosting(id self, SEL _cmd) {
    if (gOrigT26DidAttachHosting) {
        gOrigT26DidAttachHosting(self, _cmd);
    }
    WKSEnsureDisableCursorAdjustForHost(WKSGetPanelHosting(self));
    WKSApplyKeyboardGlassBackgroundForPanel(self);
    WKSApplyToolbarTransparency(self);
    WKSEnsurePanelSwipeRecognizers(self);
}

static void WKSPanelLayoutSubviews(id self, SEL _cmd) {
    if (gOrigPanelLayoutSubviews) {
        gOrigPanelLayoutSubviews(self, _cmd);
    }
    WKSApplyToolbarTransparency(self);
    WKSApplyKeyboardGlassBackgroundForPanel(self);
}

static void WKST9LayoutSubviews(id self, SEL _cmd) {
    if (gOrigT9LayoutSubviews) {
        gOrigT9LayoutSubviews(self, _cmd);
    }
    WKSApplyToolbarTransparency(self);
    WKSApplyKeyboardGlassBackgroundForPanel(self);
}

static void WKST26LayoutSubviews(id self, SEL _cmd) {
    if (gOrigT26LayoutSubviews) {
        gOrigT26LayoutSubviews(self, _cmd);
    }
    WKSApplyToolbarTransparency(self);
    WKSApplyKeyboardGlassBackgroundForPanel(self);
}

static void WKSApplyButtonBorderExcludingToolbar(UIView *view) {
    if (!view) {
        return;
    }

    // 工具栏按钮保持透明，其他按钮统一增加边框。
    BOOL isKeyViewLike = WKSIsKeyViewLike(view);
    BOOL isToolbarButton =
        !isKeyViewLike &&
        (WKSIsToolbarCandidateView(view) ||
         WKSClassNameLooksToolbar(NSStringFromClass([view class])));
    BOOL darkMode = WKSIsDarkAppearanceForView(view);
    UIColor *borderColor = darkMode
        ? [UIColor colorWithWhite:1.0 alpha:0.56]
        : [UIColor colorWithWhite:1.0 alpha:0.85];
    CALayer *backgroundLayer = nil;
    @try {
        id layerObj = [view valueForKey:@"backgroundLayer"];
        if ([layerObj isKindOfClass:[CALayer class]]) {
            backgroundLayer = (CALayer *)layerObj;
        }
    } @catch (__unused NSException *e) {
    }

    if (isToolbarButton) {
        WKSRemoveModernGlassLayers(view.layer);
        if (backgroundLayer && backgroundLayer != view.layer) {
            WKSRemoveModernGlassLayers(backgroundLayer);
        }
        view.layer.borderWidth = 0.0;
        view.layer.borderColor = nil;
        view.layer.cornerRadius = 0.0;
        view.layer.masksToBounds = NO;
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
        if (backgroundLayer) {
            backgroundLayer.borderWidth = 0.0;
            backgroundLayer.borderColor = nil;
            backgroundLayer.backgroundColor = UIColor.clearColor.CGColor;
        }
    } else {
        WKSRemoveModernGlassLayers(view.layer);
        if (backgroundLayer && backgroundLayer != view.layer) {
            WKSRemoveModernGlassLayers(backgroundLayer);
        }
        view.layer.borderWidth = 0.0;
        view.layer.borderColor = nil;
        if (backgroundLayer && backgroundLayer != view.layer) {
            backgroundLayer.borderWidth = 0.0;
            backgroundLayer.borderColor = nil;
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
    WKSApplyButtonBorderExcludingToolbar(view);
}

static void WKSButtonLayoutSubviews(id self, SEL _cmd) {
    if (gOrigButtonLayoutSubviews) {
        gOrigButtonLayoutSubviews(self, _cmd);
    }
    UIView *view = (UIView *)self;
    WKSApplyButtonBorderExcludingToolbar(view);
}

static void WKSKeyViewLayoutSubviews(id self, SEL _cmd) {
    if (gOrigKeyViewLayoutSubviews) {
        gOrigKeyViewLayoutSubviews(self, _cmd);
    }
    WKSApplyButtonBorderExcludingToolbar((UIView *)self);
}

static void WKSRuleKeyUpdateKeyAppearance(id self, SEL _cmd) {
    if (gOrigRuleKeyUpdateKeyAppearance) {
        gOrigRuleKeyUpdateKeyAppearance(self, _cmd);
    }
    WKSApplyButtonBorderExcludingToolbar((UIView *)self);
}

static void WKSReturnKeyUpdateReturnStyle(id self, SEL _cmd) {
    if (gOrigReturnKeyUpdateReturnStyle) {
        gOrigReturnKeyUpdateReturnStyle(self, _cmd);
    }
    WKSApplyButtonBorderExcludingToolbar((UIView *)self);
}

static void WKSNewlineResponsibleForNewlineDidChange(id self, SEL _cmd) {
    if (gOrigNewlineResponsibleForNewlineDidChange) {
        gOrigNewlineResponsibleForNewlineDidChange(self, _cmd);
    }
    WKSApplyButtonBorderExcludingToolbar((UIView *)self);
}

static void WKSTopBarLayoutSubviews(id self, SEL _cmd) {
    if (gOrigTopBarLayoutSubviews) {
        gOrigTopBarLayoutSubviews(self, _cmd);
    }
    WKSClearViewBackground((UIView *)self);
    WKSApplyToolbarTransparency(self);
}

static void WKSToolBarAuxLayoutSubviews(id self, SEL _cmd) {
    if (gOrigToolBarAuxLayoutSubviews) {
        gOrigToolBarAuxLayoutSubviews(self, _cmd);
    }
    WKSClearViewBackground((UIView *)self);
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
        WKSSwizzleClassMethod(panel, @selector(layoutSubviews),
                              (IMP)WKSPanelLayoutSubviews, (IMP *)&gOrigPanelLayoutSubviews);

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
        WKSSwizzleClassMethod(t9, @selector(layoutSubviews),
                              (IMP)WKST9LayoutSubviews, (IMP *)&gOrigT9LayoutSubviews);

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
        WKSSwizzleClassMethod(t26, @selector(layoutSubviews),
                              (IMP)WKST26LayoutSubviews, (IMP *)&gOrigT26LayoutSubviews);

        Class appButton = objc_getClass("WBAppButton");
        WKSSwizzleClassMethod(appButton, @selector(layoutSubviews),
                              (IMP)WKSAppButtonLayoutSubviews, (IMP *)&gOrigAppButtonLayoutSubviews);

        Class wbButton = objc_getClass("WBButton");
        WKSSwizzleClassMethod(wbButton, @selector(layoutSubviews),
                              (IMP)WKSButtonLayoutSubviews, (IMP *)&gOrigButtonLayoutSubviews);

        Class keyView = objc_getClass("WBKeyView");
        WKSSwizzleClassMethod(keyView, @selector(layoutSubviews),
                              (IMP)WKSKeyViewLayoutSubviews, (IMP *)&gOrigKeyViewLayoutSubviews);

        Class ruleKeyView = objc_getClass("WBRuleKeyView");
        WKSSwizzleClassMethod(ruleKeyView, @selector(updateKeyAppearance),
                              (IMP)WKSRuleKeyUpdateKeyAppearance, (IMP *)&gOrigRuleKeyUpdateKeyAppearance);

        Class returnKeyView = objc_getClass("WBReturnKeyView");
        WKSSwizzleClassMethod(returnKeyView, @selector(updateReturnStyle),
                              (IMP)WKSReturnKeyUpdateReturnStyle, (IMP *)&gOrigReturnKeyUpdateReturnStyle);

        Class newlineKeyView = objc_getClass("WBNewlineKeyView");
        WKSSwizzleClassMethod(newlineKeyView, @selector(responsibleForNewlineDidChange),
                              (IMP)WKSNewlineResponsibleForNewlineDidChange,
                              (IMP *)&gOrigNewlineResponsibleForNewlineDidChange);

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
