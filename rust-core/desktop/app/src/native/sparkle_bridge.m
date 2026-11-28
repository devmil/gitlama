// Runs Sparkle for the update service.
//
// Sparkle is loaded at run time from the bundle's Frameworks folder, so a
// build without it (a development run) has no updater. The updater starts
// on the first configure, so a process that never configures it leaves
// Sparkle and its user defaults untouched. The feed and the release channel
// come from here, never from user defaults.

#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdbool.h>
#include <string.h>

static NSString *const GitLamaFeedURL = @"https://devmil.de/gitlama/appcast.xml";
static const NSTimeInterval GitLamaCheckInterval = 24 * 60 * 60;

@interface GitLamaUpdateDelegate : NSObject
@property(nonatomic, copy) NSSet<NSString *> *allowedChannels;
@end

@implementation GitLamaUpdateDelegate
- (NSSet<NSString *> *)allowedChannelsForUpdater:(id)updater {
    return self.allowedChannels ?: [NSSet set];
}
- (NSString *)feedURLStringForUpdater:(id)updater {
    return GitLamaFeedURL;
}
@end

static GitLamaUpdateDelegate *gitlama_delegate;
static id gitlama_driver;
static id gitlama_updater;

/// Loads Sparkle.framework from the application bundle once.
static bool gitlama_sparkle_load(void) {
    if (NSClassFromString(@"SPUUpdater") != nil) {
        return true;
    }
    NSString *frameworks = [[NSBundle mainBundle] privateFrameworksPath];
    if (frameworks == nil) {
        return false;
    }
    NSBundle *sparkle = [NSBundle bundleWithPath:[frameworks stringByAppendingPathComponent:@"Sparkle.framework"]];
    return sparkle != nil && [sparkle load] && NSClassFromString(@"SPUUpdater") != nil;
}

bool gitlama_sparkle_loaded(void) {
    @autoreleasepool {
        return gitlama_sparkle_load();
    }
}

/// The started updater, made on first use.
static id gitlama_started_updater(void) {
    if (gitlama_updater != nil) {
        return gitlama_updater;
    }
    if (!gitlama_sparkle_load()) {
        return nil;
    }
    Class driverClass = NSClassFromString(@"SPUStandardUserDriver");
    Class updaterClass = NSClassFromString(@"SPUUpdater");
    if (driverClass == nil || updaterClass == nil) {
        return nil;
    }
    NSBundle *bundle = [NSBundle mainBundle];
    if (gitlama_delegate == nil) {
        gitlama_delegate = [GitLamaUpdateDelegate new];
    }
    id driver = ((id (*)(id, SEL, NSBundle *, id))objc_msgSend)(
        [driverClass alloc], NSSelectorFromString(@"initWithHostBundle:delegate:"), bundle, nil);
    id candidate = ((id (*)(id, SEL, NSBundle *, NSBundle *, id, id))objc_msgSend)(
        [updaterClass alloc], NSSelectorFromString(@"initWithHostBundle:applicationBundle:userDriver:delegate:"),
        bundle, bundle, driver, gitlama_delegate);
    if (candidate == nil) {
        return nil;
    }
    // The feed comes from the delegate; drop any value a user default holds.
    SEL clear = NSSelectorFromString(@"clearFeedURLFromUserDefaults");
    if ([candidate respondsToSelector:clear]) {
        ((void (*)(id, SEL))objc_msgSend)(candidate, clear);
    }
    NSError *error = nil;
    BOOL started = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(candidate, NSSelectorFromString(@"startUpdater:"), &error);
    if (!started) {
        return nil;
    }
    gitlama_driver = driver;
    gitlama_updater = candidate;
    return candidate;
}

bool gitlama_sparkle_configure(const char *channel) {
    @autoreleasepool {
        if (channel == NULL || (strcmp(channel, "stable") != 0 && strcmp(channel, "beta") != 0)) {
            return false;
        }
        if (gitlama_delegate == nil) {
            gitlama_delegate = [GitLamaUpdateDelegate new];
        }
        gitlama_delegate.allowedChannels = strcmp(channel, "beta") == 0 ? [NSSet setWithObject:@"beta"] : [NSSet set];
        id updater = gitlama_started_updater();
        if (updater == nil) {
            return false;
        }
        ((void (*)(id, SEL, NSTimeInterval))objc_msgSend)(updater, NSSelectorFromString(@"setUpdateCheckInterval:"), GitLamaCheckInterval);
        ((void (*)(id, SEL))objc_msgSend)(updater, NSSelectorFromString(@"resetUpdateCycle"));
        return true;
    }
}

bool gitlama_sparkle_check(void) {
    @autoreleasepool {
        if (gitlama_updater == nil) {
            return false;
        }
        ((void (*)(id, SEL))objc_msgSend)(gitlama_updater, NSSelectorFromString(@"checkForUpdates"));
        return true;
    }
}
