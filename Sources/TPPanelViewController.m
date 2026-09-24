#import "TPPanelViewController.h"
#import "TPStats.h"
#import "TPTweakStore.h"
#import <objc/message.h>

static const CGFloat kCardWidth = 340;
static const CGFloat kPadding = 20;
static const CGFloat kMinScale = 0.75;
static const CGFloat kMaxScale = 1.5;
static NSString *const kScaleKey = @"PanelScale";

static UIVisualEffect *TPCardEffect(void) {
	Class glass = NSClassFromString(@"UIGlassEffect");
	SEL effectWithStyle = NSSelectorFromString(@"effectWithStyle:");
	if (glass && [glass respondsToSelector:effectWithStyle]) {
		return ((UIVisualEffect *(*)(id, SEL, NSInteger))objc_msgSend)(glass, effectWithStyle, 0);
	}
	return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
}

@interface TPPanelViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIVisualEffectView *card;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *content;
@property (nonatomic, strong) UIStackView *tweakStack;
@property (nonatomic, strong) UILabel *pendingLabel;
@property (nonatomic, strong) UILabel *ramValue;
@property (nonatomic, strong) UILabel *cpuValue;
@property (nonatomic, strong) UILabel *batteryValue;
@property (nonatomic, strong) UIImageView *grip;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSLayoutConstraint *cardWidth;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *paddingConstraints;
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic) CGFloat scale;
@property (nonatomic) CGFloat liveScale;
@end

@implementation TPPanelViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
	self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

	self.defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.xsxs18.tweakpilot"];
	CGFloat saved = [self.defaults doubleForKey:kScaleKey];
	self.scale = saved > 0 ? MIN(MAX(saved, kMinScale), kMaxScale) : 1;

	UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)];
	dismissTap.delegate = self;
	[self.view addGestureRecognizer:dismissTap];

	self.card = [[UIVisualEffectView alloc] initWithEffect:TPCardEffect()];
	self.card.translatesAutoresizingMaskIntoConstraints = NO;
	self.card.layer.cornerCurve = kCACornerCurveContinuous;
	self.card.clipsToBounds = YES;
	[self.view addSubview:self.card];
	[self.card addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)]];

	self.scrollView = [UIScrollView new];
	self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	[self.card.contentView addSubview:self.scrollView];

	self.content = [UIStackView new];
	self.content.axis = UILayoutConstraintAxisVertical;
	self.content.translatesAutoresizingMaskIntoConstraints = NO;
	[self.scrollView addSubview:self.content];

	UIImageSymbolConfiguration *gripConfig = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold];
	self.grip = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right" withConfiguration:gripConfig]];
	self.grip.tintColor = UIColor.tertiaryLabelColor;
	self.grip.contentMode = UIViewContentModeCenter;
	self.grip.userInteractionEnabled = YES;
	self.grip.accessibilityLabel = @"Resize";
	self.grip.translatesAutoresizingMaskIntoConstraints = NO;
	[self.card.contentView addSubview:self.grip];
	[self.grip addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(gripDragged:)]];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	self.cardWidth = [self.card.widthAnchor constraintEqualToConstant:kCardWidth];
	self.cardWidth.priority = UILayoutPriorityDefaultHigh;
	// Sized straight from the content instead of copying contentSize back in viewDidLayoutSubviews:
	// on iOS 16 contentSize is still stale at that point, so the card flickered between heights.
	NSLayoutConstraint *fitContent = [self.scrollView.frameLayoutGuide.heightAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.heightAnchor];
	fitContent.priority = UILayoutPriorityDefaultHigh;
	self.paddingConstraints = @[
		[self.content.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
		[self.scrollView.contentLayoutGuide.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor],
		[self.content.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor],
		[self.scrollView.frameLayoutGuide.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor],
	];

	[NSLayoutConstraint activateConstraints:self.paddingConstraints];
	[NSLayoutConstraint activateConstraints:@[
		[self.card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		self.cardWidth,
		[self.card.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor constant:-32],
		[self.card.heightAnchor constraintLessThanOrEqualToAnchor:safe.heightAnchor multiplier:0.85],

		[self.scrollView.topAnchor constraintEqualToAnchor:self.card.contentView.topAnchor],
		[self.scrollView.bottomAnchor constraintEqualToAnchor:self.card.contentView.bottomAnchor],
		[self.scrollView.leadingAnchor constraintEqualToAnchor:self.card.contentView.leadingAnchor],
		[self.scrollView.trailingAnchor constraintEqualToAnchor:self.card.contentView.trailingAnchor],
		fitContent,

		[self.grip.widthAnchor constraintEqualToConstant:36],
		[self.grip.heightAnchor constraintEqualToConstant:36],
		[self.grip.trailingAnchor constraintEqualToAnchor:self.card.contentView.trailingAnchor],
		[self.grip.bottomAnchor constraintEqualToAnchor:self.card.contentView.bottomAnchor],
	]];

	[self rebuild];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[TPStats cpuUsage];
	[self refreshStats];
	self.timer = [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(refreshStats) userInfo:nil repeats:YES];

	self.card.transform = CGAffineTransformMakeScale(0.9, 0.9);
	self.card.alpha = 0;
	[UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
		self.card.transform = CGAffineTransformIdentity;
		self.card.alpha = 1;
	} completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self.timer invalidate];
	self.timer = nil;
}

#pragma mark - Layout

- (UIFont *)mono:(CGFloat)size weight:(UIFontWeight)weight {
	return [UIFont monospacedSystemFontOfSize:round(size * self.scale) weight:weight];
}

- (void)rebuild {
	CGFloat s = self.scale;
	self.cardWidth.constant = kCardWidth * s;
	self.card.layer.cornerRadius = 28 * s;
	self.content.spacing = 10 * s;
	for (NSLayoutConstraint *constraint in self.paddingConstraints) constraint.constant = kPadding * s;

	for (UIView *view in self.content.arrangedSubviews) [view removeFromSuperview];
	[self buildContent];
	[self reloadTweaks];
	[self refreshStats];
}

- (void)buildContent {
	UIStackView *content = self.content;
	CGFloat gap = 22 * self.scale;

	[content addArrangedSubview:[self sectionHeader:@"Installed Tweaks"]];

	self.tweakStack = [UIStackView new];
	self.tweakStack.axis = UILayoutConstraintAxisVertical;
	self.tweakStack.spacing = 2;
	[content addArrangedSubview:self.tweakStack];

	self.pendingLabel = [UILabel new];
	self.pendingLabel.font = [self mono:11 weight:UIFontWeightRegular];
	self.pendingLabel.textColor = UIColor.systemOrangeColor;
	self.pendingLabel.text = @"↻ Respring to apply changes";
	self.pendingLabel.hidden = YES;
	[content addArrangedSubview:self.pendingLabel];

	[content setCustomSpacing:gap afterView:self.tweakStack];
	[content setCustomSpacing:gap afterView:self.pendingLabel];

	[content addArrangedSubview:[self sectionHeader:@"Performance"]];
	self.ramValue = [self addStatRow:@"RAM"];
	self.cpuValue = [self addStatRow:@"CPU"];
	self.batteryValue = [self addStatRow:@"Battery"];
	[content setCustomSpacing:gap afterView:content.arrangedSubviews.lastObject];

	[content addArrangedSubview:[self sectionHeader:@"Quick Actions"]];
	UIStackView *actions = [UIStackView new];
	actions.axis = UILayoutConstraintAxisHorizontal;
	actions.spacing = 10 * self.scale;
	actions.distribution = UIStackViewDistributionFillEqually;
	[actions addArrangedSubview:[self actionButton:@"Respring" color:UIColor.systemBlueColor action:@selector(respringTapped)]];
	[actions addArrangedSubview:[self actionButton:@"Restart Injection" color:UIColor.systemIndigoColor action:@selector(restartInjectionTapped)]];
	[content addArrangedSubview:actions];
}

- (UIView *)sectionHeader:(NSString *)title {
	UIStackView *stack = [UIStackView new];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 6 * self.scale;

	UILabel *label = [UILabel new];
	label.text = title;
	label.font = [self mono:15 weight:UIFontWeightBold];
	label.textColor = UIColor.labelColor;
	[stack addArrangedSubview:label];

	UIView *rule = [UIView new];
	rule.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.25];
	[rule.heightAnchor constraintEqualToConstant:1].active = YES;
	[stack addArrangedSubview:rule];
	return stack;
}

- (UILabel *)addStatRow:(NSString *)title {
	UILabel *titleLabel = [UILabel new];
	titleLabel.text = title;
	titleLabel.font = [self mono:14 weight:UIFontWeightRegular];
	titleLabel.textColor = UIColor.secondaryLabelColor;
	[titleLabel.widthAnchor constraintEqualToConstant:90 * self.scale].active = YES;

	UILabel *value = [UILabel new];
	value.text = @"—";
	value.font = [self mono:14 weight:UIFontWeightSemibold];
	value.textColor = UIColor.labelColor;

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, value]];
	row.axis = UILayoutConstraintAxisHorizontal;
	[self.content addArrangedSubview:row];
	return value;
}

- (UIButton *)actionButton:(NSString *)title color:(UIColor *)color action:(SEL)action {
	CGFloat s = self.scale;
	UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
	config.baseBackgroundColor = color;
	config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
	config.contentInsets = NSDirectionalEdgeInsetsMake(10 * s, 8 * s, 10 * s, 8 * s);
	config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [self mono:12 weight:UIFontWeightSemibold]}];
	config.titleLineBreakMode = NSLineBreakByTruncatingTail;

	UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (UIControl *)tweakRow:(TPTweakEntry *)entry {
	UIControl *row = [UIControl new];
	row.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", entry.name, entry.enabled ? @"on" : @"off"];
	row.accessibilityTraits = UIAccessibilityTraitButton;
	[row.heightAnchor constraintGreaterThanOrEqualToConstant:34 * self.scale].active = YES;

	UILabel *dot = [UILabel new];
	dot.text = @"●";
	dot.font = [self mono:13 weight:UIFontWeightRegular];
	dot.textColor = entry.enabled ? UIColor.systemGreenColor : UIColor.systemGrayColor;
	[dot setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	UILabel *name = [UILabel new];
	name.text = entry.name;
	name.font = [self mono:14 weight:UIFontWeightRegular];
	name.textColor = entry.enabled ? UIColor.labelColor : UIColor.secondaryLabelColor;
	name.lineBreakMode = NSLineBreakByTruncatingTail;
	[name setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

	UILabel *state = [UILabel new];
	state.text = [NSString stringWithFormat:@"%@%@", entry.pending ? @"↻ " : @"", entry.enabled ? @"ON" : @"OFF"];
	state.font = [self mono:13 weight:UIFontWeightBold];
	state.textColor = entry.pending ? UIColor.systemOrangeColor : (entry.enabled ? UIColor.systemGreenColor : UIColor.systemGrayColor);
	state.textAlignment = NSTextAlignmentRight;
	[state setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[dot, name, state]];
	stack.axis = UILayoutConstraintAxisHorizontal;
	stack.spacing = 10 * self.scale;
	stack.alignment = UIStackViewAlignmentCenter;
	stack.userInteractionEnabled = NO;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[row addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.topAnchor constraintEqualToAnchor:row.topAnchor],
		[stack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
		[stack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
		[stack.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
	]];

	__weak typeof(self) weakSelf = self;
	[row addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
		[weakSelf toggle:entry control:row];
	}] forControlEvents:UIControlEventTouchUpInside];
	return row;
}

#pragma mark - Resizing

- (void)previewScale:(CGFloat)factor {
	self.liveScale = MIN(MAX(self.scale * factor, kMinScale), kMaxScale);
	CGFloat t = self.liveScale / self.scale;
	self.card.transform = CGAffineTransformMakeScale(t, t);
}

- (void)commitScale {
	if (self.liveScale <= 0 || fabs(self.liveScale - self.scale) < 0.01) {
		self.card.transform = CGAffineTransformIdentity;
		return;
	}
	self.scale = self.liveScale;
	[self.defaults setDouble:self.scale forKey:kScaleKey];
	[self rebuild];
	// Lay out the new size before dropping the preview transform, so no frame shows the old size.
	[self.view layoutIfNeeded];
	self.card.transform = CGAffineTransformIdentity;
	[[UIImpactFeedbackGenerator new] impactOccurred];
}

- (void)pinched:(UIPinchGestureRecognizer *)pinch {
	[self previewScale:pinch.scale];
	if (pinch.state == UIGestureRecognizerStateEnded || pinch.state == UIGestureRecognizerStateCancelled) [self commitScale];
}

- (void)gripDragged:(UIPanGestureRecognizer *)pan {
	// The preview scales around the card's center, so the corner moves half the size change per axis.
	CGPoint drag = [pan translationInView:self.view];
	CGSize size = self.card.bounds.size;
	CGFloat growth = 2 * (drag.x + drag.y) / MAX(size.width + size.height, 1);
	[self previewScale:1 + growth];
	if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) [self commitScale];
}

#pragma mark - Data

- (void)reloadTweaks {
	for (UIView *view in self.tweakStack.arrangedSubviews) [view removeFromSuperview];

	NSArray<TPTweakEntry *> *entries = [TPTweakStore loadEntries];
	BOOL anyPending = NO;
	for (TPTweakEntry *entry in entries) {
		[self.tweakStack addArrangedSubview:[self tweakRow:entry]];
		anyPending |= entry.pending;
	}
	if (entries.count == 0) {
		UILabel *empty = [UILabel new];
		empty.text = @"No tweaks found";
		empty.font = [self mono:13 weight:UIFontWeightRegular];
		empty.textColor = UIColor.secondaryLabelColor;
		[self.tweakStack addArrangedSubview:empty];
	}
	self.pendingLabel.hidden = !anyPending;
	[self.view setNeedsLayout];
}

- (void)refreshStats {
	double gb = (double)[TPStats usedMemory] / (1024.0 * 1024.0 * 1024.0);
	self.ramValue.text = [NSString stringWithFormat:@"%.1f GB", gb];
	self.cpuValue.text = [NSString stringWithFormat:@"%.0f%%", [TPStats cpuUsage]];
	NSInteger battery = [TPStats batteryLevel];
	self.batteryValue.text = battery < 0 ? @"—" : [NSString stringWithFormat:@"%ld%%", (long)battery];
}

#pragma mark - Actions

- (void)toggle:(TPTweakEntry *)entry control:(UIControl *)row {
	row.enabled = NO;
	row.alpha = 0.5;
	[[UIImpactFeedbackGenerator new] impactOccurred];

	__weak typeof(self) weakSelf = self;
	[TPTweakStore setEnabled:!entry.enabled forTweak:entry.name completion:^(NSString *error) {
		[weakSelf reloadTweaks];
		if (error) [weakSelf showError:error title:[NSString stringWithFormat:@"Couldn't switch %@", entry.name]];
	}];
}

- (void)respringTapped {
	__weak typeof(self) weakSelf = self;
	[self confirm:@"Respring?" message:nil action:^{
		[TPTweakStore respring:^(NSString *error) {
			if (error) [weakSelf showError:error title:@"Respring failed"];
		}];
	}];
}

- (void)restartInjectionTapped {
	__weak typeof(self) weakSelf = self;
	[self confirm:@"Restart Injection?"
		  message:@"Performs a userspace reboot so every process is re-injected. Open apps will be closed."
		   action:^{
		[TPTweakStore restartInjection:^(NSString *error) {
			if (error) [weakSelf showError:error title:@"Restart Injection failed"];
		}];
	}];
}

- (void)showError:(NSString *)message title:(NSString *)title {
	[[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)confirm:(NSString *)title message:(NSString *)message action:(void (^)(void))action {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { action(); }]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
	return ![touch.view isDescendantOfView:self.card];
}

- (void)backgroundTapped:(UITapGestureRecognizer *)tap {
	[UIView animateWithDuration:0.2 animations:^{
		self.card.alpha = 0;
		self.card.transform = CGAffineTransformMakeScale(0.92, 0.92);
		self.view.alpha = 0;
	} completion:^(BOOL finished) {
		if (self.dismissHandler) self.dismissHandler();
	}];
}

@end
