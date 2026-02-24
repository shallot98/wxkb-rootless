#import "WKSRootListController.h"
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

@implementation WKSRootListController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"微信键盘切换";
    UIBarButtonItem *logoutItem = [[UIBarButtonItem alloc] initWithTitle:@"注销"
                                                                    style:UIBarButtonItemStyleDone
                                                                   target:self
                                                                   action:@selector(wks_logoutDeviceTapped)];
    self.navigationItem.rightBarButtonItem = logoutItem;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] copy];
    }
    return _specifiers;
}

- (void)wks_logoutDeviceTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"注销设备"
                                                                   message:@"将重启 SpringBoard 以应用更改。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    __weak __typeof__(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"注销"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        [weakSelf wks_performDeviceLogout];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)wks_performDeviceLogout {
    const char *tool = "/usr/bin/sbreload";
    if (access(tool, X_OK) == 0) {
        pid_t pid = 0;
        char *const args[] = {"sbreload", NULL};
        posix_spawn(&pid, tool, NULL, NULL, args, environ);
        return;
    }

    const char *killall = "/usr/bin/killall";
    if (access(killall, X_OK) == 0) {
        pid_t pid = 0;
        char *const args[] = {"killall", "-9", "SpringBoard", NULL};
        posix_spawn(&pid, killall, NULL, NULL, args, environ);
    }
}

@end
