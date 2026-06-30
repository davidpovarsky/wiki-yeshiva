#import <WMF/NSFileManager+WMFGroup.h>
#import "WMFQuoteMacros.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

NSString *const WMFApplicationGroupIdentifier = @QUOTE(WMF_APP_GROUP_IDENTIFIER);

@implementation NSFileManager (WMFGroup)

- (nonnull NSURL *)wmf_containerURL {
    NSURL *containerURL = [self containerURLForSecurityApplicationGroupIdentifier:WMFApplicationGroupIdentifier];
    if (containerURL) {
        return containerURL;
    }

    NSURL *applicationSupportURL = [self URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *fallbackURL = [applicationSupportURL URLByAppendingPathComponent:@"Wikipedia" isDirectory:YES];
    NSError *error = nil;
    if (![self createDirectoryAtURL:fallbackURL withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSLog(@"Error creating fallback app container: %@", error);
    }
    return fallbackURL;
}

- (nonnull NSString *)wmf_containerPath {
    return [[self wmf_containerURL] path];
}

@end

#pragma mark - Wiki source menu layer

static NSString * const WMFWikiSourceSelectionDefaultsKey = @"WMFSelectedWikiSourceIdentifier";
static void WMFConfigureExploreWikiSourceMenu(UIViewController *viewController);

typedef void (*WMFExploreViewWillAppearIMP)(id, SEL, BOOL);
static WMFExploreViewWillAppearIMP WMFOriginalExploreViewWillAppear = NULL;

@interface WMFWikiSourceMenuInstaller : NSObject
@end

@implementation WMFWikiSourceMenuInstaller

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self installIfNeeded];
    });
}

+ (void)installIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class exploreClass = NSClassFromString(@"Wikipedia.ExploreViewController");
        if (!exploreClass) {
            exploreClass = NSClassFromString(@"ExploreViewController");
        }
        if (!exploreClass) {
            return;
        }

        SEL selector = @selector(viewWillAppear:);
        Method method = class_getInstanceMethod(exploreClass, selector);
        if (!method) {
            return;
        }

        WMFOriginalExploreViewWillAppear = (WMFExploreViewWillAppearIMP)method_getImplementation(method);
        const char *types = method_getTypeEncoding(method);

        IMP replacement = imp_implementationWithBlock(^(UIViewController *viewController, BOOL animated) {
            if (WMFOriginalExploreViewWillAppear) {
                WMFOriginalExploreViewWillAppear(viewController, selector, animated);
            }
            WMFConfigureExploreWikiSourceMenu(viewController);
        });

        class_replaceMethod(exploreClass, selector, replacement, types);
    });
}

@end

static NSArray<NSDictionary<NSString *, NSString *> *> *WMFWikiSourceMenuSources(void) {
    return @[
        @{@"id": @"wikipedia", @"title": @"Wikipedia"},
        @{@"id": @"wiktionary", @"title": @"Wiktionary"},
        @{@"id": @"wikisource", @"title": @"Wikisource"},
        @{@"id": @"wikiquote", @"title": @"Wikiquote"},
        @{@"id": @"wikibooks", @"title": @"Wikibooks"},
        @{@"id": @"wikiversity", @"title": @"Wikiversity"},
        @{@"id": @"wikinews", @"title": @"Wikinews"},
        @{@"id": @"wikivoyage", @"title": @"Wikivoyage"},
        @{@"id": @"wikiYeshiva", @"title": @"WikiYeshiva"}
    ];
}

static NSString *WMFSelectedWikiSourceIdentifier(void) {
    NSString *identifier = [[NSUserDefaults standardUserDefaults] stringForKey:WMFWikiSourceSelectionDefaultsKey];
    if (identifier.length == 0) {
        return @"wikipedia";
    }
    return identifier;
}

static NSString *WMFWikiSourceTitleForIdentifier(NSString *identifier) {
    for (NSDictionary<NSString *, NSString *> *source in WMFWikiSourceMenuSources()) {
        if ([source[@"id"] isEqualToString:identifier]) {
            return source[@"title"];
        }
    }
    return @"Wikipedia";
}

static UIMenu *WMFMakeExploreWikiSourceMenu(UIViewController *viewController) API_AVAILABLE(ios(14.0)) {
    NSString *selectedIdentifier = WMFSelectedWikiSourceIdentifier();
    NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];

    for (NSDictionary<NSString *, NSString *> *source in WMFWikiSourceMenuSources()) {
        NSString *identifier = source[@"id"];
        NSString *title = source[@"title"];
        UIAction *action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:WMFWikiSourceSelectionDefaultsKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            WMFConfigureExploreWikiSourceMenu(viewController);
        }];
        action.state = [identifier isEqualToString:selectedIdentifier] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }

    return [UIMenu menuWithTitle:@"Choose Wiki" children:actions];
}

static void WMFConfigureExploreWikiSourceMenu(UIViewController *viewController) {
    if (@available(iOS 14.0, *)) {
        UIBarButtonItem *existingItem = viewController.navigationItem.leftBarButtonItem;
        UIImage *logoImage = existingItem.image ?: [UIImage imageNamed:@"W"];
        UIBarButtonItem *wikiMenuItem = [[UIBarButtonItem alloc] initWithImage:logoImage menu:WMFMakeExploreWikiSourceMenu(viewController)];
        wikiMenuItem.accessibilityLabel = [NSString stringWithFormat:@"Choose Wiki source. Current source: %@", WMFWikiSourceTitleForIdentifier(WMFSelectedWikiSourceIdentifier())];
        wikiMenuItem.tintColor = existingItem.tintColor;
        viewController.navigationItem.leftBarButtonItem = wikiMenuItem;
    }
}
