#import "TPOverlay.h"
#import "TPPanelViewController.h"
#import <notify.h>

static NSString *const kDefaultsSuite = @"com.xsxs18.tweakpilot";
static NSString *const kBubbleCenterKey = @"BubbleCenter";
static const CGFloat kBubbleSize = 46;

@interface TPPassthroughWindow : UIWindow
@end

@implementation TPPassthroughWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
	UIView *hit = [super hitTest:point withEvent:event];
	if (hit == self || hit == self.rootViewController.view) return nil;
	return hit;
}
@end

@interface TPOverlayRootViewController : UIViewController
@end

@implementation TPOverlayRootViewController
- (BOOL)prefersStatusBarHidden {
	return NO;
}
@end

@interface TPOverlay ()
@property (nonatomic, strong) TPPassthroughWindow *window;
@property (nonatomic, strong) UIButton *bubble;
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic) int lockToken;
@end

@implementation TPOverlay

+ (instancetype)sharedOverlay {
	static TPOverlay *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [TPOverlay new]; });
	return shared;
}

- (UIWindowScene *)springBoardScene {
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if ([scene isKindOfClass:UIWindowScene.class]) return (UIWindowScene *)scene;
	}
	return nil;
}

- (void)install {
	if (self.window) return;
	UIWindowScene *scene = [self springBoardScene];
	if (!scene) return;

	self.defaults = [[NSUserDefaults alloc] initWithSuiteName:kDefaultsSuite];

	self.window = [[TPPassthroughWindow alloc] initWithWindowScene:scene];
	self.window.windowLevel = UIWindowLevelStatusBar + 100;
	self.window.backgroundColor = UIColor.clearColor;
	self.window.rootViewController = [TPOverlayRootViewController new];
	self.window.hidden = NO;

	[self buildBubble];
	[self observeLockState];
}

- (void)buildBubble {
	UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
	config.image = [UIImage systemImageNamed:@"slider.horizontal.3"
						   withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold]];
	config.baseBackgroundColor = [UIColor colorWithWhite:0.1 alpha:0.75];
	config.baseForegroundColor = UIColor.whiteColor;
	config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;

	self.bubble = [UIButton buttonWithConfiguration:config primaryAction:nil];
	self.bubble.frame = CGRectMake(0, 0, kBubbleSize, kBubbleSize);
	self.bubble.accessibilityLabel = @"TweakPilot";
	self.bubble.layer.shadowColor = UIColor.blackColor.CGColor;
	self.bubble.layer.shadowOpacity = 0.3;
	self.bubble.layer.shadowRadius = 8;
	self.bubble.layer.shadowOffset = CGSizeMake(0, 3);
	[self.bubble addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];
	[self.bubble addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragBubble:)]];

	UIView *root = self.window.rootViewController.view;
	[root addSubview:self.bubble];

	NSString *saved = [self.defaults stringForKey:kBubbleCenterKey];
	CGRect bounds = root.bounds;
	CGPoint center = saved ? CGPointFromString(saved) : CGPointMake(CGRectGetMaxX(bounds) - kBubbleSize, CGRectGetMidY(bounds));
	self.bubble.center = [self clampedCenter:center];
}

- (CGPoint)clampedCenter:(CGPoint)point {
	UIView *root = self.window.rootViewController.view;
	CGRect area = UIEdgeInsetsInsetRect(root.bounds, root.safeAreaInsets);
	CGFloat half = kBubbleSize / 2 + 6;
	return CGPointMake(MIN(MAX(point.x, CGRectGetMinX(area) + half), CGRectGetMaxX(area) - half),
					   MIN(MAX(point.y, CGRectGetMinY(area) + half), CGRectGetMaxY(area) - half));
}

- (void)dragBubble:(UIPanGestureRecognizer *)pan {
	UIView *root = self.window.rootViewController.view;
	CGPoint translation = [pan translationInView:root];
	self.bubble.center = [self clampedCenter:CGPointMake(self.bubble.center.x + translation.x, self.bubble.center.y + translation.y)];
	[pan setTranslation:CGPointZero inView:root];

	if (pan.state != UIGestureRecognizerStateEnded && pan.state != UIGestureRecognizerStateCancelled) return;

	BOOL left = self.bubble.center.x < CGRectGetMidX(root.bounds);
	CGPoint target = [self clampedCenter:CGPointMake(left ? 0 : CGRectGetMaxX(root.bounds), self.bubble.center.y)];
	[UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.6 options:0 animations:^{
		self.bubble.center = target;
	} completion:nil];
	[self.defaults setObject:NSStringFromCGPoint(target) forKey:kBubbleCenterKey];
}

- (void)openPanel {
	UIViewController *root = self.window.rootViewController;
	if (root.presentedViewController) return;

	TPPanelViewController *panel = [TPPanelViewController new];
	panel.modalPresentationStyle = UIModalPresentationOverFullScreen;
	__weak typeof(self) weakSelf = self;
	__weak TPPanelViewController *weakPanel = panel;
	panel.dismissHandler = ^{
		[weakPanel dismissViewControllerAnimated:NO completion:nil];
		weakSelf.bubble.hidden = NO;
	};
	self.bubble.hidden = YES;
	[root presentViewController:panel animated:NO completion:nil];
}

#pragma mark - Lock state

- (void)observeLockState {
	int token = 0;
	__weak typeof(self) weakSelf = self;
	notify_register_dispatch("com.apple.springboard.lockstate", &token, dispatch_get_main_queue(), ^(int t) {
		[weakSelf applyLockState];
	});
	self.lockToken = token;
	[self applyLockState];
}

- (void)applyLockState {
	uint64_t locked = 0;
	notify_get_state(self.lockToken, &locked);
	if (locked) {
		UIViewController *root = self.window.rootViewController;
		if (root.presentedViewController) [root dismissViewControllerAnimated:NO completion:nil];
		self.bubble.hidden = NO;
	}
	self.window.hidden = locked != 0;
}

@end
