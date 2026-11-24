// 滑块 + 减号 + 加号 + 数值，用于素材大小 / 位置 / 速度等可精细调节的项。
#import "DIDAdjustCell.h"
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static NSString *const kDomain = @"com.minis.didance";
static CFStringRef const kNotify = CFSTR("com.minis.didance.changed");

@interface DIDAdjustCell ()
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, assign) float step;
@end

@implementation DIDAdjustCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault
                    reuseIdentifier:reuseIdentifier
                          specifier:specifier])) {
        _slider = [UISlider new];
        _valueLabel = [UILabel new];
        _minusButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _plusButton = [UIButton buttonWithType:UIButtonTypeSystem];

        [_minusButton setTitle:@"−" forState:UIControlStateNormal];
        [_plusButton setTitle:@"+" forState:UIControlStateNormal];
        _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.adjustsFontSizeToFitWidth = YES;

        [_slider addTarget:self action:@selector(sliderChanged:)
          forControlEvents:UIControlEventValueChanged];
        [_slider addTarget:self action:@selector(sliderTouched:)
          forControlEvents:UIControlEventTouchDown];
        [_minusButton addTarget:self action:@selector(stepDown)
               forControlEvents:UIControlEventTouchUpInside];
        [_plusButton addTarget:self action:@selector(stepUp)
              forControlEvents:UIControlEventTouchUpInside];

        for (UIView *v in @[_slider, _valueLabel, _minusButton, _plusButton])
            [self.contentView addSubview:v];

        self.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self reload];
}

- (float)currentValue {
    NSString *key = [self.specifier propertyForKey:@"key"];
    CFPropertyListRef stored = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                         (__bridge CFStringRef)kDomain);
    float v = stored ? [(__bridge id)stored floatValue]
                     : [[self.specifier propertyForKey:@"default"] floatValue];
    if (stored) CFRelease(stored);
    return v;
}

- (void)reload {
    self.textLabel.text = self.specifier.name;
    self.textLabel.adjustsFontSizeToFitWidth = YES;
    self.slider.minimumValue = [[self.specifier propertyForKey:@"min"] floatValue];
    self.slider.maximumValue = [[self.specifier propertyForKey:@"max"] floatValue];
    self.step = [[self.specifier propertyForKey:@"step"] floatValue];
    if (self.step <= 0) self.step = 0.5f;

    float v = [self currentValue];
    v = fmaxf(self.slider.minimumValue, fminf(self.slider.maximumValue, v));
    self.slider.value = v;
    [self showValue];
}

- (void)showValue {
    NSString *unit = [self.specifier propertyForKey:@"unit"];
    self.valueLabel.text = [NSString stringWithFormat:@"%.1f%@", self.slider.value, unit ?: @""];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width;
    CGFloat h = self.contentView.bounds.size.height;
    CGFloat pad = 12.0;
    CGFloat labelW = 74.0;
    CGFloat btnW = 34.0;
    CGFloat valueW = 52.0;

    self.textLabel.frame = CGRectMake(pad, 0, labelW, h);
    self.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];

    CGFloat valueX = w - pad - valueW;
    CGFloat plusX = valueX - 2.0 - btnW;
    CGFloat minusX = pad + labelW;
    CGFloat sliderX = minusX + btnW + 2.0;
    CGFloat sliderEnd = plusX - 4.0;

    self.minusButton.frame = CGRectMake(minusX, 0, btnW, h);
    self.slider.frame = CGRectMake(sliderX, (h - 30.0) / 2.0,
                                   MAX(40.0, sliderEnd - sliderX), 30.0);
    self.plusButton.frame = CGRectMake(plusX, 0, btnW, h);
    self.valueLabel.frame = CGRectMake(valueX, 0, valueW, h);

    UIFont *btnFont = [UIFont systemFontOfSize:21 weight:UIFontWeightMedium];
    self.minusButton.titleLabel.font = btnFont;
    self.plusButton.titleLabel.font = btnFont;
}

- (void)save {
    NSString *key = [self.specifier propertyForKey:@"key"];
    if (!key) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)@(self.slider.value),
                             (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         kNotify, NULL, NULL, YES);
    [self showValue];
}

- (void)sliderChanged:(UISlider *)slider {
    (void)slider;
    [self save];
}

- (void)sliderTouched:(UISlider *)slider {
    (void)slider;
}

- (void)stepDown { [self applyDelta:-self.step]; }
- (void)stepUp   { [self applyDelta:self.step]; }

- (void)applyDelta:(float)delta {
    float v = self.slider.value + delta;
    v = roundf(v / self.step) * self.step;
    self.slider.value = fmaxf(self.slider.minimumValue, fminf(self.slider.maximumValue, v));
    [self save];
}

@end