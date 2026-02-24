#import <UIKit/UIKit.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

static BOOL WKSIsWeChatKeyboardSwitchPage(UIViewController *controller) {
    if (!controller) {
        return NO;
    }
    NSString *title = controller.navigationItem.title ?: controller.title;
    if (![title isKindOfClass:[NSString class]]) {
        return NO;
    }
    return [title isEqualToString:@"微信键盘切换"];
}

static void WKSSpawnCommand(const char *path, const char *const argv[]) {
    if (!path || !argv) {
        return;
    }
    pid_t pid = 0;
    posix_spawn(&pid, path, NULL, NULL, (char *const *)argv, environ);
}

static void WKSPerformLogout(void) {
    const char *sbreload = "/usr/bin/sbreload";
    if (access(sbreload, X_OK) == 0) {
        const char *const args[] = {"sbreload", NULL};
        WKSSpawnCommand(sbreload, args);
        return;
    }

    const char *killall = "/usr/bin/killall";
    if (access(killall, X_OK) == 0) {
        const char *const args[] = {"killall", "-9", "SpringBoard", NULL};
        WKSSpawnCommand(killall, args);
    }
}

%hook PSListController

- (void)viewDidLoad {
    %orig;

    @try {
        UIViewController *vc = (UIViewController *)self;
        if (!WKSIsWeChatKeyboardSwitchPage(vc)) {
            return;
        }

        UIBarButtonItem *existing = vc.navigationItem.rightBarButtonItem;
        if (existing && [existing.title isEqualToString:@"注销"]) {
            return;
        }

        UIBarButtonItem *logoutItem =
            [[UIBarButtonItem alloc] initWithTitle:@"注销"
                                             style:UIBarButtonItemStyleDone
                                            target:self
                                            action:@selector(wks_logoutDeviceTapped)];
        vc.navigationItem.rightBarButtonItem = logoutItem;
    } @catch (__unused NSException *e) {
    }
}

%new
- (void)wks_logoutDeviceTapped {
    UIViewController *vc = (UIViewController *)self;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"注销设备"
                                                                   message:@"将重启 SpringBoard 以应用更改。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"注销"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        WKSPerformLogout();
    }]];
    [vc presentViewController:alert animated:YES completion:nil];
}

%end
