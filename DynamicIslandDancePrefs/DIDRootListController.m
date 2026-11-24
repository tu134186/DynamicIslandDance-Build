#import "DIDRootListController.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *const DIDDomain = @"com.minis.didance";
static NSString *const DIDNotify = @"com.minis.didance.changed";
static NSString *const DIDDefaultPlist = @"/var/mobile/Library/Preferences/com.minis.didance.plist";
static NSString *const DIDMediaRoot = @"/var/mobile/DynamicIsland";

static id DIDPref(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)DIDDomain);
    return CFBridgingRelease(v);
}

static void DIDNotifyChanged(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)DIDNotify, NULL, NULL, YES);
}

@interface DIDRootListController ()
@property (nonatomic, copy) NSString *folderKind;   // mask / dance / eye
@property (nonatomic, copy) NSString *folderKey;    // selectedXFolder
@end

@implementation DIDRootListController

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id v = DIDPref(key);
    if (v) return v;
    id def = [specifier propertyForKey:@"default"];
    return def ?: @NO;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)DIDDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)DIDDomain);
    DIDNotifyChanged();
}

- (void)syncNow {
    CFPreferencesAppSynchronize((__bridge CFStringRef)DIDDomain);
    DIDNotifyChanged();
}

- (PSSpecifier *)switchRow:(NSString *)title key:(NSString *)key def:(BOOL)def {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:title
                                                      target:self
                                                         set:@selector(setPreferenceValue:specifier:)
                                                         get:@selector(readPreferenceValue:)
                                                  detail:nil
                                                    cell:PSListItemCell
                                                    edit:nil];
    [spec setProperty:key forKey:@"key"];
    [spec setProperty:@(def) forKey:@"default"];
    return spec;
}

- (PSSpecifier *)sliderRow:(NSString *)title key:(NSString *)key def:(CGFloat)def min:(CGFloat)lo max:(CGFloat)hi {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:title
                                                      target:self
                                                         set:@selector(setPreferenceValue:specifier:)
                                                         get:@selector(readPreferenceValue:)
                                                  detail:nil
                                                    cell:PSSliderCell
                                                    edit:nil];
    [spec setProperty:key forKey:@"key"];
    [spec setProperty:@(def) forKey:@"default"];
    [spec setProperty:@(lo) forKey:@"min"];
    [spec setProperty:@(hi) forKey:@"max"];
    [spec setProperty:@(def) forKey:@"PSSliderDefault"];
    return spec;
}

- (PSSpecifier *)folderRow:(NSString *)title kind:(NSString *)kind key:(NSString *)key {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:title
                                                      target:self
                                                         set:@selector(setPreferenceValue:specifier:)
                                                         get:@selector(readPreferenceValue:)
                                                  detail:nil
                                                    cell:PSButtonCell
                                                    edit:nil];
    [spec setProperty:key forKey:@"key"];
    [spec setProperty:kind forKey:@"didFolderKind"];
    [spec setProperty:@(YES) forKey:@"didFolderRow"];
    [spec setProperty:@"showFolderPicker:" forKey:@"action"];
    return spec;
}



- (void)showFolderPicker:(PSSpecifier *)specifier {
    NSString *kind = [specifier propertyForKey:@"didFolderKind"];
    NSString *dir = [DIDMediaRoot stringByAppendingPathComponent:kind];
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    NSMutableArray *folders = [NSMutableArray array];
    for (NSString *name in all) {
        if ([name hasPrefix:@"."]) continue;
        BOOL isDir = NO;
        NSString *full = [dir stringByAppendingPathComponent:name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir] && isDir) {
            [folders addObject:name];
        }
    }
    [folders sortUsingSelector:@selector(localizedStandardCompare:)];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:specifier.name
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"不使用（关闭）" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        [self setPreferenceValue:@"" specifier:specifier];
        [self reloadSpecifier:specifier animated:YES];
    }]];
    for (NSString *name in folders) {
        [sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self setPreferenceValue:name specifier:specifier];
            [self reloadSpecifier:specifier animated:YES];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                               CGRectGetMaxY(self.view.bounds) - 60, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)reloadFolderButtonTitles {
    for (PSSpecifier *spec in [self specifiers]) {
        if ([[spec propertyForKey:@"didFolderRow"] boolValue]) {
            id v = DIDPref([spec propertyForKey:@"key"]);
            NSString *name = ([v isKindOfClass:[NSString class]] && [v length]) ? v : @"未选择";
            [spec setProperty:[NSString stringWithFormat:@"%@：%@", spec.name, name] forKey:@"label"];
        }
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadFolderButtonTitles];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"灵动岛跳舞（纯净版）"];
        [group setProperty:@"素材目录与常见跳舞插件完全一致：/var/mobile/DynamicIsland/{dance,eye,mask}，已下载的素材包可直接使用。"
                   forKey:@"footerText"];
        [specs addObject:group];
        [specs addObject:[self switchRow:@"启用插件" key:@"shouldEnableCustomUI" def:YES]];
        [specs addObject:[self switchRow:@"灵动岛圆化（iOS17 适配）" key:@"enableIOS17Adaptation" def:YES]];

        group = [PSSpecifier groupSpecifierWithName:@"专辑封面"];
        [specs addObject:group];
        [specs addObject:[self switchRow:@"封面圆形旋转" key:@"enableAlbumRotation" def:YES]];
        [specs addObject:[self sliderRow:@"旋转速度" key:@"albumRotationSpeed" def:0.6 min:0.05 max:4.0]];
        [specs addObject:[self switchRow:@"使用自定义圆形遮罩" key:@"enableMaskLayer" def:YES]];
        [specs addObject:[self folderRow:@"遮罩主题" kind:@"mask" key:@"selectedMaskFolder"]];

        group = [PSSpecifier groupSpecifierWithName:@"跳舞动画"];
        [specs addObject:group];
        [specs addObject:[self switchRow:@"启用跳舞素材" key:@"enableDanceSprite" def:YES]];
        [specs addObject:[self folderRow:@"跳舞素材" kind:@"dance" key:@"selectedDanceFolder"]];
        [specs addObject:[self sliderRow:@"帧率" key:@"frameAnimationSpeed" def:12.0 min:1.0 max:60.0]];
        [specs addObject:[self sliderRow:@"素材大小" key:@"danceAnimationSize" def:22.0 min:4.0 max:64.0]];
        [specs addObject:[self sliderRow:@"水平偏移" key:@"plugin3XOffset" def:0.0 min:-120.0 max:120.0]];
        [specs addObject:[self sliderRow:@"垂直偏移" key:@"plugin3YOffset" def:0.0 min:-60.0 max:60.0]];

        group = [PSSpecifier groupSpecifierWithName:@"录屏写轮眼"];
        [group setProperty:@"若已安装独立的“录屏写轮眼”插件，请保持本组关闭，避免两套素材重叠。" forKey:@"footerText"];
        [specs addObject:group];
        [specs addObject:[self switchRow:@"启用写轮眼素材" key:@"enableEyeSprite" def:NO]];
        [specs addObject:[self folderRow:@"写轮眼素材" kind:@"eye" key:@"selectedEyeFolder"]];
        [specs addObject:[self sliderRow:@"帧率" key:@"eyeFrameAnimationSpeed" def:12.0 min:1.0 max:60.0]];
        [specs addObject:[self sliderRow:@"素材大小" key:@"eyeAnimationSize" def:22.0 min:4.0 max:64.0]];
        [specs addObject:[self sliderRow:@"水平偏移" key:@"plugin2XOffset" def:0.0 min:-120.0 max:120.0]];
        [specs addObject:[self sliderRow:@"垂直偏移" key:@"plugin2YOffset" def:0.0 min:-60.0 max:60.0]];

        _specifiers = specs;
    }
    return _specifiers;
}

@end