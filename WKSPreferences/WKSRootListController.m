#import "WKSRootListController.h"

@implementation WKSRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSArray *loadedSpecifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        _specifiers = loadedSpecifiers ? [loadedSpecifiers mutableCopy] : [NSMutableArray array];
    }
    return _specifiers;
}

@end
