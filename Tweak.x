#import <UIKit/UIKit.h>
#import "TPOverlay.h"

@interface SpringBoard : UIApplication
@end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
	%orig;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[[TPOverlay sharedOverlay] install];
	});
}

%end
