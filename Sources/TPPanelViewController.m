#import "TPPanelViewController.h"
#import "TPStats.h"
#import "TPTweakStore.h"
#import <objc/message.h>

static const CGFloat kCardWidth = 340;
static const CGFloat kPadding = 20;

static UIFont *TPMono(CGFloat size, UIFontWeight weight) {
	return [UIFont monospacedSystemFontOfSize:size weight:weight];
}

// Liquid Glass on iOS 26, regular material blur on iOS 18–25.
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
@property (nonatomic, strong) UIStackView *tweakStack;
@property (nonatomic, strong) UILabel *pendingLabel;
@property (nonatomic, strong) UILabel *ramValue;
@property (nonatomic, strong) UILabel *cpuValue;
@property (nonatomic, strong) UILabel *batteryValue;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) NSLayoutConstraint *scrollHeight;
@end

@implementation TPPanelViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
	self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

	UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTapped:)];
	dismissTap.delegate = self;
	[self.view addGestureRecognizer:dismissTap];

	self.card = [[UIVisualEffectView alloc] initWithEffect:TPCardEffect()];
	self.card.translatesAutoresizingMaskIntoConstraints = NO;
	self.card.layer.cornerRadius = 28;
	self.card.layer.cornerCurve = kCACornerCurveContinuous;
	self.card.clipsToBounds = YES;
	[self.view addSubview:self.card];

	self.scrollView = [UIScrollView new];
	self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
	self.scrollView.alwaysBounceVertical = NO;
	[self.card.contentView addSubview:self.scrollView];

	UIStackView *content = [UIStackView new];
	content.axis = UILayoutConstraintAxisVertical;
	content.spacing = 10;
	content.translatesAutoresizingMaskIntoConstraints = NO;
	[self.scrollView addSubview:content];

	[self buildContentInto:content];

	UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
	NSLayoutConstraint *preferredWidth = [self.card.widthAnchor constraintEqualToConstant:kCardWidth];
	preferredWidth.priority = UILayoutPriorityDefaultHigh;
	self.scrollHeight = [self.scrollView.heightAnchor constraintEqualToConstant:300];
	self.scrollHeight.priority = UILayoutPriorityDefaultHigh;

	[NSLayoutConstraint activateConstraints:@[
		[self.card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[self.card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		preferredWidth,
		[self.card.widthAnchor constraintLessThanOrEqualToAnchor:safe.widthAnchor constant:-32],
		[self.card.heightAnchor constraintLessThanOrEqualToAnchor:safe.heightAnchor multiplier:0.85],

		[self.scrollView.topAnchor constraintEqualToAnchor:self.card.contentView.topAnchor],
		[self.scrollView.bottomAnchor constraintEqualToAnchor:self.card.contentView.bottomAnchor],
		[self.scrollView.leadingAnchor constraintEqualToAnchor:self.card.contentView.leadingAnchor],
		[self.scrollView.trailingAnchor constraintEqualToAnchor:self.card.contentView.trailingAnchor],
		self.scrollHeight,

		[content.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:kPadding],
		[content.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-kPadding],
		[content.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:kPadding],
		[content.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-kPadding],
	]];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	// Size the card to its content; the max-height constraint caps it and the rest scrolls.
	CGFloat contentHeight = self.scrollView.contentSize.height;
	if (contentHeight > 0 && fabs(self.scrollHeight.constant - contentHeight) > 0.5) {
		self.scrollHeight.constant = contentHeight;
	}
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reloadTweaks];
	[TPStats cpuUsage]; // prime the delta
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

#pragma mark - Building

- (void)buildContentInto:(UIStackView *)content {
	[content addArrangedSubview:[self sectionHeader:@"Installed Tweaks"]];

	self.tweakStack = [UIStackView new];
	self.tweakStack.axis = UILayoutConstraintAxisVertical;
	self.tweakStack.spacing = 2;
	[content addArrangedSubview:self.tweakStack];

	self.pendingLabel = [UILabel new];
	self.pendingLabel.font = TPMono(11, UIFontWeightRegular);
	self.pendingLabel.textColor = UIColor.systemOrangeColor;
	self.pendingLabel.text = @"↻ Respring to apply changes";
	self.pendingLabel.hidden = YES;
	[content addArrangedSubview:self.pendingLabel];

	[content setCustomSpacing:22 afterView:self.pendingLabel];
	[content setCustomSpacing:22 afterView:self.tweakStack];

	[content addArrangedSubview:[self sectionHeader:@"Performance"]];
	self.ramValue = [self addStatRow:@"RAM" to:content];
	self.cpuValue = [self addStatRow:@"CPU" to:content];
	self.batteryValue = [self addStatRow:@"Battery" to:content];
	[content setCustomSpacing:22 afterView:content.arrangedSubviews.lastObject];

	[content addArrangedSubview:[self sectionHeader:@"Quick Actions"]];
	UIStackView *actions = [UIStackView new];
	actions.axis = UILayoutConstraintAxisHorizontal;
	actions.spacing = 10;
	actions.distribution = UIStackViewDistributionFillEqually;
	[actions addArrangedSubview:[self actionButton:@"Respring" color:UIColor.systemBlueColor action:@selector(respringTapped)]];
	[actions addArrangedSubview:[self actionButton:@"Restart Injection" color:UIColor.systemIndigoColor action:@selector(restartInjectionTapped)]];
	[content addArrangedSubview:actions];
}

- (UIView *)sectionHeader:(NSString *)title {
	UIStackView *stack = [UIStackView new];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 6;

	UILabel *label = [UILabel new];
	label.text = title;
	label.font = TPMono(15, UIFontWeightBold);
	label.textColor = UIColor.labelColor;
	[stack addArrangedSubview:label];

	UIView *rule = [UIView new];
	rule.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.25];
	[rule.heightAnchor constraintEqualToConstant:1].active = YES;
	[stack addArrangedSubview:rule];
	return stack;
}

- (UILabel *)addStatRow:(NSString *)title to:(UIStackView *)content {
	UILabel *titleLabel = [UILabel new];
	titleLabel.text = title;
	titleLabel.font = TPMono(14, UIFontWeightRegular);
	titleLabel.textColor = UIColor.secondaryLabelColor;
	[titleLabel.widthAnchor constraintEqualToConstant:90].active = YES;

	UILabel *value = [UILabel new];
	value.text = @"—";
	value.font = TPMono(14, UIFontWeightSemibold);
	value.textColor = UIColor.labelColor;

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, value]];
	row.axis = UILayoutConstraintAxisHorizontal;
	[content addArrangedSubview:row];
	return value;
}

- (UIButton *)actionButton:(NSString *)title color:(UIColor *)color action:(SEL)action {
	UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
	config.baseBackgroundColor = color;
	config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
	config.contentInsets = NSDirectionalEdgeInsetsMake(10, 8, 10, 8);
	config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: TPMono(12, UIFontWeightSemibold)}];
	config.titleLineBreakMode = NSLineBreakByTruncatingTail;

	UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (UIControl *)tweakRow:(TPTweakEntry *)entry {
	UIControl *row = [UIControl new];
	row.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", entry.name, entry.enabled ? @"on" : @"off"];
	row.accessibilityTraits = UIAccessibilityTraitButton;
	[row.heightAnchor constraintGreaterThanOrEqualToConstant:34].active = YES;

	UILabel *dot = [UILabel new];
	dot.text = @"●";
	dot.font = TPMono(13, UIFontWeightRegular);
	dot.textColor = entry.enabled ? UIColor.systemGreenColor : UIColor.systemGrayColor;
	[dot setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	UILabel *name = [UILabel new];
	name.text = entry.name;
	name.font = TPMono(14, UIFontWeightRegular);
	name.textColor = entry.enabled ? UIColor.labelColor : UIColor.secondaryLabelColor;
	name.lineBreakMode = NSLineBreakByTruncatingTail;
	[name setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

	UILabel *state = [UILabel new];
	state.text = [NSString stringWithFormat:@"%@%@", entry.pending ? @"↻ " : @"", entry.enabled ? @"ON" : @"OFF"];
	state.font = TPMono(13, UIFontWeightBold);
	state.textColor = entry.pending ? UIColor.systemOrangeColor : (entry.enabled ? UIColor.systemGreenColor : UIColor.systemGrayColor);
	state.textAlignment = NSTextAlignmentRight;
	[state setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

	UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[dot, name, state]];
	stack.axis = UILayoutConstraintAxisHorizontal;
	stack.spacing = 10;
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
		empty.font = TPMono(13, UIFontWeightRegular);
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
	[TPTweakStore setEnabled:!entry.enabled forTweak:entry.name completion:^(BOOL success) {
		if (!success) [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];
		[weakSelf reloadTweaks];
	}];
}

- (void)respringTapped {
	[self confirm:@"Respring?" message:nil action:^{ [TPTweakStore respring]; }];
}

- (void)restartInjectionTapped {
	[self confirm:@"Restart Injection?"
		  message:@"Performs a userspace reboot so every process is re-injected. Open apps will be closed."
		   action:^{ [TPTweakStore restartInjection]; }];
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
