#import <WMF/NSFileManager+WMFGroup.h>
#import "WMFQuoteMacros.h"

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
