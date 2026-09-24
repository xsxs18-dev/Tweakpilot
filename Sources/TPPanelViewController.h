#import <UIKit/UIKit.h>

@interface TPPanelViewController : UIViewController
@property (nonatomic, copy) void (^dismissHandler)(void);
@end
