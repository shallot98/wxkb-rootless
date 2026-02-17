#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <limits.h>

static BOOL gWKSInSwitch = NO;
static BOOL gWKSSwitchScheduled = NO;
static CFAbsoluteTime gWKSLastSwitchTs = 0;
static int gWKSSwipeCallbackDepth = 0;

static const NSTimeInterval kWKSDebounceSeconds = 0.25;
static const NSTimeInterval kWKSScheduleDelaySeconds = 0.06;
static const NSTimeInterval kWKSSwitchCooldownSeconds = 0.45;
static const NSTimeInterval kWKSAdjustingRetryDelaySeconds = 0.03;
static const int kWKSAdjustingMaxRetries = 6;

static void (*gOrigPanelSwipeUp)(id, SEL, id) = NULL;
static void (*gOrigPanelSwipeDown)(id, SEL, id) = NULL;
static void (*gOrigPanelSwipeEnded)(id, SEL, id, id) = NULL;
static void (*gOrigT9SwipeUp)(id, SEL, id) = NULL;
static void (*gOrigT9SwipeDown)(id, SEL, id) = NULL;
static void (*gOrigT26SwipeUp)(id, SEL, id) = NULL;
static void (*gOrigT26SwipeDown)(id, SEL, id) = NULL;
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

static BOOL WKSIsEnglishPanel(id panel) {
    Class cls = objc_getClass("WBT26Panel");
    return (cls && panel && [panel isKindOfClass:cls]);
}

static long long WKSPanelTryRecognizeSwipeTouch(id self, SEL _cmd, id touch, id keyView,
                                                 unsigned long long *supportsMoveCursorDirection,
                                                 BOOL force) {
    long long result = 0;
    if (gOrigPanelTryRecognizeSwipeTouch) {
        result = gOrigPanelTryRecognizeSwipeTouch(self, _cmd, touch, keyView,
                                                  supportsMoveCursorDirection, force);
    }
    // 仅对英文面板阻止进入“全键盘光标移动”方向。
    if (supportsMoveCursorDirection && WKSIsEnglishPanel(self)) {
        *supportsMoveCursorDirection = 0;
    }
    return result;
}

static BOOL WKSToggleByHandleLangSwitch(UIView *panel, id host) {
    if (!panel || !host) {
        return NO;
    }
    if (![host respondsToSelector:@selector(handleLangSwitch)] ||
        ![host respondsToSelector:@selector(currentPanelType)]) {
        return NO;
    }

    long long beforeHostType = WKSGetLongLongProperty(host, @selector(currentPanelType), LLONG_MIN);
    long long beforePanelType = WKSGetLongLongProperty(panel, @selector(panelType), LLONG_MIN);

    if (!WKSInvokeVoidNoArg(host, @selector(handleLangSwitch))) {
        return NO;
    }

    long long afterHostType = WKSGetLongLongProperty(host, @selector(currentPanelType), LLONG_MIN);
    long long afterPanelType = WKSGetLongLongProperty(panel, @selector(panelType), LLONG_MIN);

    if (afterHostType != LLONG_MIN && afterHostType != beforeHostType) {
        WKSInvokeSwitchEngineSession(host, afterHostType);
    }

    if (beforeHostType != LLONG_MIN && afterHostType != LLONG_MIN && beforeHostType != afterHostType) {
        return YES;
    }
    if (beforePanelType != LLONG_MIN && afterPanelType != LLONG_MIN && beforePanelType != afterPanelType) {
        return YES;
    }
    return YES;
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

    // 超时后不再继续等待，强制执行一次切换，避免英文上下滑“永远失效”。
    BOOL switched = WKSToggleByHandleLangSwitch(panel, host);
    if (switched) {
        gWKSLastSwitchTs = CFAbsoluteTimeGetCurrent();
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kWKSDebounceSeconds * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        gWKSInSwitch = NO;
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

static void WKSHostAdjustTextPositionNo(id self, SEL _cmd, long long offset) {
    (void)self;
    (void)_cmd;
    (void)offset;
}

static void WKSHostAdjustTextPositionVerticalNo(id self, SEL _cmd, long long offset) {
    (void)self;
    (void)_cmd;
    (void)offset;
}

static void WKSEnsureDisableCursorAdjustForHost(id host) {
    if (!host) {
        return;
    }
    Class cls = [host class];
    // 仅阻断“实际光标位移执行”，保留原生滑动识别状态机，避免回落到字母确认输入。
    WKSSwizzleClassMethod(cls, @selector(adjustTextPositionWithOffset:),
                          (IMP)WKSHostAdjustTextPositionNo, NULL);
    WKSSwizzleClassMethod(cls, @selector(adjustTextPositionWithVerticalOffset:),
                          (IMP)WKSHostAdjustTextPositionVerticalNo, NULL);
}

static void WKSPanelSwipeUp(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    if (gOrigPanelSwipeUp) {
        gOrigPanelSwipeUp(self, _cmd, touch);
    }
    if (shouldHandle) {
        WKSHandleSwipe(self);
    }
    gWKSSwipeCallbackDepth -= 1;
}

static void WKSPanelSwipeDown(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    if (gOrigPanelSwipeDown) {
        gOrigPanelSwipeDown(self, _cmd, touch);
    }
    if (shouldHandle) {
        WKSHandleSwipe(self);
    }
    gWKSSwipeCallbackDepth -= 1;
}

static void WKSPanelSwipeEnded(id self, SEL _cmd, id arg, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    if (gOrigPanelSwipeEnded) {
        gOrigPanelSwipeEnded(self, _cmd, arg, touch);
    }
    if (shouldHandle) {
        WKSHandleSwipe(self);
    }
    gWKSSwipeCallbackDepth -= 1;
}

static void WKST9SwipeUp(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    if (gOrigT9SwipeUp) {
        gOrigT9SwipeUp(self, _cmd, touch);
    }
    if (shouldHandle) {
        WKSHandleSwipe(self);
    }
    gWKSSwipeCallbackDepth -= 1;
}

static void WKST9SwipeDown(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    if (gOrigT9SwipeDown) {
        gOrigT9SwipeDown(self, _cmd, touch);
    }
    if (shouldHandle) {
        WKSHandleSwipe(self);
    }
    gWKSSwipeCallbackDepth -= 1;
}

static void WKST26SwipeUp(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    if (gOrigT26SwipeUp) {
        gOrigT26SwipeUp(self, _cmd, touch);
    }
    if (shouldHandle) {
        WKSHandleSwipe(self);
    }
    gWKSSwipeCallbackDepth -= 1;
}

static void WKST26SwipeDown(id self, SEL _cmd, id touch) {
    gWKSSwipeCallbackDepth += 1;
    BOOL shouldHandle = (gWKSSwipeCallbackDepth == 1);
    if (gOrigT26SwipeDown) {
        gOrigT26SwipeDown(self, _cmd, touch);
    }
    if (shouldHandle) {
        WKSHandleSwipe(self);
    }
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
        WKSSwizzleClassMethod(panel, @selector(processSwipeEnded:touch:),
                              (IMP)WKSPanelSwipeEnded, (IMP *)&gOrigPanelSwipeEnded);
        WKSSwizzleClassMethod(panel, @selector(processSwipeUpEnded:),
                              (IMP)WKSPanelSwipeUp, (IMP *)&gOrigPanelSwipeUp);
        WKSSwizzleClassMethod(panel, @selector(processSwipeDownEnded:),
                              (IMP)WKSPanelSwipeDown, (IMP *)&gOrigPanelSwipeDown);
        WKSSwizzleClassMethod(panel, @selector(didAttachHosting),
                              (IMP)WKSPanelDidAttachHosting, (IMP *)&gOrigPanelDidAttachHosting);

        Class t9 = objc_getClass("WBT9Panel");
        WKSSwizzleClassMethod(t9, @selector(processSwipeUpEnded:),
                              (IMP)WKST9SwipeUp, (IMP *)&gOrigT9SwipeUp);
        WKSSwizzleClassMethod(t9, @selector(processSwipeDownEnded:),
                              (IMP)WKST9SwipeDown, (IMP *)&gOrigT9SwipeDown);
        WKSSwizzleClassMethod(t9, @selector(didAttachHosting),
                              (IMP)WKST9DidAttachHosting, (IMP *)&gOrigT9DidAttachHosting);

        Class t26 = objc_getClass("WBT26Panel");
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
