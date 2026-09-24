#import <UIKit/UIKit.h>

@interface TPOverlay : NSObject
+ (instancetype)sharedOverlay;
- (void)install;
@end
