#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <limits.h>
#import <math.h>
#import <stdint.h>

static BOOL gWKSInSwitch = NO;
static BOOL gWKSSwitchScheduled = NO;
static CFAbsoluteTime gWKSLastSwitchTs = 0;
static int gWKSSwipeCallbackDepth = 0;
static __weak id gWKSTextUpPanel = nil;
static uintptr_t gWKSTextUpTouchAddr = 0;
static CGPoint gWKSTextUpStartPoint = {0.0, 0.0};
static BOOL gWKSTextUpHasStartPoint = NO;
static CFAbsoluteTime gWKSTextUpArmedTs = 0;
static __weak id gWKSRecentMoveTriggerPanel = nil;
static uintptr_t gWKSRecentMoveTriggerTouchAddr = 0;
static CFAbsoluteTime gWKSRecentMoveTriggerTs = 0;

static const NSTimeInterval kWKSDebounceSeconds = 0.20;
static const NSTimeInterval kWKSScheduleDelaySeconds = 0.06;
static const NSTimeInterval kWKSSwitchCooldownSeconds = 0.12;
static const NSTimeInterval kWKSAdjustingRetryDelaySeconds = 0.06;
static const NSTimeInterval kWKSSwitchApplyDelaySeconds = 0.08;
static const int kWKSAdjustingMaxRetries = 10;
static const CGFloat kWKSTextUpMoveTriggerDistance = 12.0;
static const CGFloat kWKSTextUpMoveMaxHorizontal = 44.0;
static const CGFloat kWKSTextUpCancelTriggerDistance = 4.0;
static const NSTimeInterval kWKSTextUpStateTTLSeconds = 0.80;
static const NSTimeInterval kWKSRecentMoveTriggerTTLSeconds = 0.35;

static void (*gOrigPanelSwipeUp)(id, SEL, id) = NULL;
static void (*gOrigPanelSwipeDown)(id, SEL, id) = NULL;
static void (*gOrigPanelSwipeEnded)(id, SEL, id, id) = NULL;
static void (*gOrigPanelAnySwipeBegan)(id, SEL, id, id) = NULL;
static void (*gOrigPanelAnySwipeMoved)(id, SEL, id, id) = NULL;
static void (*gOrigPanelTouchesCancelled)(id, SEL, id, id) = NULL;
static void (*gOrigPanelProcessTouchMoved)(id, SEL, id, id) = NULL;
static void (*gOrigPanelProcessTouchCancel)(id, SEL, id, id) = NULL;
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
static void (*gOrigTopBarLayoutSubviews)(id, SEL) = NULL;
static void (*gOrigToolBarAuxLayoutSubviews)(id, SEL) = NULL;

static void (*gOrigSymbolListDidAttachHosting)(id, SEL) = NULL;
static void (*gOrigGridBoderFillLayerFill)(id, SEL, CGSize, CGRect, CGSize) = NULL;
static void (*gOrigBorderLayerLayoutSublayers)(id, SEL) = NULL;
static void (*gOrigSymbolCellSetBorderPosition)(id, SEL, unsigned long long) = NULL;

static void WKSHandleSwipe(id context);
static void WKSAttemptToggleWhenReady(id context, int retries);
static void WKSSwizzleClassMethod(Class cls, SEL sel, IMP newImp, IMP *oldStore);

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

static BOOL WKSShouldKeepNativeSpaceSwipe(id panel, id swipeArg) {
    return WKSIsSpaceKeyView(WKSGetSwipeKeyView(panel, swipeArg));
}

static BOOL WKSPanelShouldUseTextUpMoveMode(id panel, id swipeArg) {
    return (panel && !WKSShouldKeepNativeSpaceSwipe(panel, swipeArg));
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

static BOOL WKSConsumeRecentMoveTrigger(id panel, id swipeArg) {
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
    if (!WKSTextUpMoveTouchMatches(swipeArg)) {
        return;
    }

    CGPoint currentPoint = CGPointZero;
    if (!WKSGetTouchLocationInPanel(swipeArg, panel, &currentPoint)) {
        return;
    }
    if (!gWKSTextUpHasStartPoint) {
        gWKSTextUpStartPoint = currentPoint;
        gWKSTextUpHasStartPoint = YES;
        return;
    }

    CGFloat dy = currentPoint.y - gWKSTextUpStartPoint.y;
    CGFloat dx = (CGFloat)fabs(currentPoint.x - gWKSTextUpStartPoint.x);
    if (dy <= -kWKSTextUpMoveTriggerDistance && dx <= kWKSTextUpMoveMaxHorizontal) {
        WKSMarkRecentMoveTrigger(panel, swipeArg);
        WKSClearTextUpMoveState();
        WKSHandleSwipe(panel);
    }
}

static void WKSTryHandleTextUpSwipeCancelled(id panel, id swipeArg) {
    if (!panel || gWKSTextUpPanel != panel || WKSHasRecentMoveTrigger(panel, swipeArg)) {
        WKSClearTextUpMoveStateForPanel(panel);
        return;
    }
    if (!WKSTextUpMoveTouchMatches(swipeArg) || !gWKSTextUpHasStartPoint) {
        WKSClearTextUpMoveStateForPanel(panel);
        return;
    }

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if ((now - gWKSTextUpArmedTs) > kWKSTextUpStateTTLSeconds) {
        WKSClearTextUpMoveStateForPanel(panel);
        return;
    }

    CGPoint currentPoint = CGPointZero;
    if (!WKSGetTouchLocationInPanel(swipeArg, panel, &currentPoint)) {
        WKSClearTextUpMoveStateForPanel(panel);
        return;
    }

    CGFloat dy = currentPoint.y - gWKSTextUpStartPoint.y;
    CGFloat dx = (CGFloat)fabs(currentPoint.x - gWKSTextUpStartPoint.x);
    if (dy <= -kWKSTextUpCancelTriggerDistance && dx <= kWKSTextUpMoveMaxHorizontal) {
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

static long long WKSPanelTryRecognizeSwipeTouch(id self, SEL _cmd, id touch, id keyView,
                                                 unsigned long long *supportsMoveCursorDirection,
                                                 BOOL force) {
    BOOL keepNativeSpaceSwipe = WKSIsSpaceKeyView(keyView);
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
    if (adjusting && retries > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(kWKSAdjustingRetryDelaySeconds * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WKSAttemptToggleWhenReady(context, retries - 1);
        });
        return;
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
        WKSAttemptToggleWhenReady(strongContext, kWKSAdjustingMaxRetries);
    });
}

static void WKSEnsureDisableCursorAdjustForHost(id host) {
    (void)host;
}

static void WKSPanelAnySwipeBegan(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    if (!WKSShouldKeepNativeSpaceSwipe(self, swipeRef)) {
        WKSHandleTextUpSwipeBegan(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
    if (gOrigPanelAnySwipeBegan) {
        gOrigPanelAnySwipeBegan(self, _cmd, arg, touch);
    }
}

static void WKSPanelAnySwipeMoved(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    if (gOrigPanelAnySwipeMoved) {
        gOrigPanelAnySwipeMoved(self, _cmd, arg, touch);
    }
    if (!WKSShouldKeepNativeSpaceSwipe(self, swipeRef)) {
        WKSTryHandleTextUpSwipeMoved(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
}

static void WKSPanelTouchesCancelled(id self, SEL _cmd, id touches, id event) {
    id swipeRef = touches ?: event;
    if (!WKSShouldKeepNativeSpaceSwipe(self, swipeRef)) {
        WKSTryHandleTextUpSwipeCancelled(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
    if (gOrigPanelTouchesCancelled) {
        gOrigPanelTouchesCancelled(self, _cmd, touches, event);
    }
}

static void WKSPanelProcessTouchMoved(id self, SEL _cmd, id touch, id keyView) {
    if (gOrigPanelProcessTouchMoved) {
        gOrigPanelProcessTouchMoved(self, _cmd, touch, keyView);
    }
    if (!WKSIsSpaceKeyView(keyView)) {
        WKSTryHandleTextUpSwipeMoved(self, touch);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
}

static void WKSPanelProcessTouchCancel(id self, SEL _cmd, id touch, id keyView) {
    if (!WKSIsSpaceKeyView(keyView)) {
        WKSTryHandleTextUpSwipeCancelled(self, touch);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
    if (gOrigPanelProcessTouchCancel) {
        gOrigPanelProcessTouchCancel(self, _cmd, touch, keyView);
    }
}

static void WKSPanelSwipeUpBegan(id self, SEL _cmd, id arg, id touch, BOOL isOpenUpTips) {
    id swipeRef = touch ?: arg;
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    BOOL openUpTips = isOpenUpTips;
    if (!shouldKeepNative) {
        BOOL useTextUpMove = WKSPanelShouldUseTextUpMoveMode(self, swipeRef);
        if (useTextUpMove) {
            openUpTips = NO;
        }
        WKSHandleTextUpSwipeBegan(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
    if (gOrigPanelSwipeUpBegan) {
        gOrigPanelSwipeUpBegan(self, _cmd, arg, touch, openUpTips);
    }
}

static void WKSPanelSwipeUpMoved(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    if (gOrigPanelSwipeUpMoved) {
        gOrigPanelSwipeUpMoved(self, _cmd, arg, touch);
    }
    if (!WKSShouldKeepNativeSpaceSwipe(self, swipeRef)) {
        WKSTryHandleTextUpSwipeMoved(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
}

static void WKSPanelSwipeUp(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    BOOL skipByRecentMove = WKSConsumeRecentMoveTrigger(self, touch);
    if (gOrigPanelSwipeUp) {
        gOrigPanelSwipeUp(self, _cmd, touch);
    }
    if (shouldHandle && !shouldKeepNative && !skipByRecentMove) {
        WKSHandleSwipe(self);
    }
    WKSClearTextUpMoveStateForPanel(self);
    gWKSSwipeCallbackDepth -= 1;
}

static void WKSPanelSwipeDown(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    if (gOrigPanelSwipeDown) {
        gOrigPanelSwipeDown(self, _cmd, touch);
    }
    if (shouldHandle && !shouldKeepNative) {
        WKSHandleSwipe(self);
    }
    WKSClearTextUpMoveStateForPanel(self);
    gWKSSwipeCallbackDepth -= 1;
}

static void WKSPanelSwipeEnded(id self, SEL _cmd, id arg, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    id swipeRef = touch ?: arg;
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    BOOL skipByRecentMove = WKSConsumeRecentMoveTrigger(self, swipeRef);
    if (gOrigPanelSwipeEnded) {
        gOrigPanelSwipeEnded(self, _cmd, arg, touch);
    }
    if (shouldHandle && !shouldKeepNative && !skipByRecentMove) {
        WKSHandleSwipe(self);
    }
    WKSClearTextUpMoveStateForPanel(self);
    gWKSSwipeCallbackDepth -= 1;
}

static void WKST9SwipeUpBegan(id self, SEL _cmd, id arg, id touch, BOOL isOpenUpTips) {
    id swipeRef = touch ?: arg;
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    BOOL openUpTips = isOpenUpTips;
    if (!shouldKeepNative) {
        BOOL useTextUpMove = WKSPanelShouldUseTextUpMoveMode(self, swipeRef);
        if (useTextUpMove) {
            openUpTips = NO;
        }
        WKSHandleTextUpSwipeBegan(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
    if (gOrigT9SwipeUpBegan) {
        gOrigT9SwipeUpBegan(self, _cmd, arg, touch, openUpTips);
    }
}

static void WKST9SwipeUpMoved(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    if (gOrigT9SwipeUpMoved) {
        gOrigT9SwipeUpMoved(self, _cmd, arg, touch);
    }
    if (!WKSShouldKeepNativeSpaceSwipe(self, swipeRef)) {
        WKSTryHandleTextUpSwipeMoved(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
}

static void WKST9SwipeUp(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    BOOL skipByRecentMove = WKSConsumeRecentMoveTrigger(self, touch);
    if (gOrigT9SwipeUp) {
        gOrigT9SwipeUp(self, _cmd, touch);
    }
    if (shouldHandle && !shouldKeepNative && !skipByRecentMove) {
        WKSHandleSwipe(self);
    }
    WKSClearTextUpMoveStateForPanel(self);
    gWKSSwipeCallbackDepth -= 1;
}

static void WKST9SwipeDown(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    if (gOrigT9SwipeDown) {
        gOrigT9SwipeDown(self, _cmd, touch);
    }
    if (shouldHandle && !shouldKeepNative) {
        WKSHandleSwipe(self);
    }
    WKSClearTextUpMoveStateForPanel(self);
    gWKSSwipeCallbackDepth -= 1;
}

static void WKST26SwipeUpBegan(id self, SEL _cmd, id arg, id touch, BOOL isOpenUpTips) {
    id swipeRef = touch ?: arg;
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, swipeRef);
    BOOL openUpTips = isOpenUpTips;
    if (!shouldKeepNative) {
        BOOL useTextUpMove = WKSPanelShouldUseTextUpMoveMode(self, swipeRef);
        if (useTextUpMove) {
            openUpTips = NO;
        }
        WKSHandleTextUpSwipeBegan(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
    if (gOrigT26SwipeUpBegan) {
        gOrigT26SwipeUpBegan(self, _cmd, arg, touch, openUpTips);
    }
}

static void WKST26SwipeUpMoved(id self, SEL _cmd, id arg, id touch) {
    id swipeRef = touch ?: arg;
    if (gOrigT26SwipeUpMoved) {
        gOrigT26SwipeUpMoved(self, _cmd, arg, touch);
    }
    if (!WKSShouldKeepNativeSpaceSwipe(self, swipeRef)) {
        WKSTryHandleTextUpSwipeMoved(self, swipeRef);
    } else {
        WKSClearTextUpMoveStateForPanel(self);
    }
}

static void WKST26SwipeUp(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    BOOL skipByRecentMove = WKSConsumeRecentMoveTrigger(self, touch);
    if (gOrigT26SwipeUp) {
        gOrigT26SwipeUp(self, _cmd, touch);
    }
    if (shouldHandle && !shouldKeepNative && !skipByRecentMove) {
        WKSHandleSwipe(self);
    }
    WKSClearTextUpMoveStateForPanel(self);
    gWKSSwipeCallbackDepth -= 1;
}

static void WKST26SwipeDown(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    BOOL shouldKeepNative = WKSShouldKeepNativeSpaceSwipe(self, touch);
    if (gOrigT26SwipeDown) {
        gOrigT26SwipeDown(self, _cmd, touch);
    }
    if (shouldHandle && !shouldKeepNative) {
        WKSHandleSwipe(self);
    }
    WKSClearTextUpMoveStateForPanel(self);
    gWKSSwipeCallbackDepth -= 1;
}

static void WKSPanelDidAttachHosting(id self, SEL _cmd) {
    if (gOrigPanelDidAttachHosting) {
        gOrigPanelDidAttachHosting(self, _cmd);
    }
    WKSEnsureDisableCursorAdjustForHost(WKSGetPanelHosting(self));
    WKSApplyToolbarTransparency(self);
}

static void WKST9DidAttachHosting(id self, SEL _cmd) {
    if (gOrigT9DidAttachHosting) {
        gOrigT9DidAttachHosting(self, _cmd);
    }
    WKSEnsureDisableCursorAdjustForHost(WKSGetPanelHosting(self));
    WKSApplyToolbarTransparency(self);
    WKSDisableSymbolListGridFill(WKSGetSymbolListViewFromPanel(self));
}

static void WKST26DidAttachHosting(id self, SEL _cmd) {
    if (gOrigT26DidAttachHosting) {
        gOrigT26DidAttachHosting(self, _cmd);
    }
    WKSEnsureDisableCursorAdjustForHost(WKSGetPanelHosting(self));
    WKSApplyToolbarTransparency(self);
}

static void WKSAppButtonLayoutSubviews(id self, SEL _cmd) {
    if (gOrigAppButtonLayoutSubviews) {
        gOrigAppButtonLayoutSubviews(self, _cmd);
    }
    WKSClearViewBackground((UIView *)self);
}

static void WKSButtonLayoutSubviews(id self, SEL _cmd) {
    if (gOrigButtonLayoutSubviews) {
        gOrigButtonLayoutSubviews(self, _cmd);
    }
    WKSClearViewBackground((UIView *)self);
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
        WKSSwizzleClassMethod(panel, @selector(processTouchMoveWithTouch:keyView:),
                              (IMP)WKSPanelProcessTouchMoved, (IMP *)&gOrigPanelProcessTouchMoved);
        WKSSwizzleClassMethod(panel, @selector(processTouchCancel:keyView:),
                              (IMP)WKSPanelProcessTouchCancel, (IMP *)&gOrigPanelProcessTouchCancel);
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
