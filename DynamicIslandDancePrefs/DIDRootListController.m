#import "DIDRootListController.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *const DIDDomain = @"com.minis.didance";
static NSString *const DIDNotify = @"com.minis.didance.changed";
static NSString *const DIDDefaultPlist = @"/var/mobile/Library/Preferences/com.minis.didance.plist";
static NSString *const DIDMediaRoot = @"/var/mobile/DynamicIsland";

static NSArray<NSString *> *DIDBundledRoots(void) {
    return @[@"/var/jb/Library/Application Support/DynamicIslandDance",
             @"/Library/Application Support/DynamicIslandDance"];
}

static NSString *DIDBundledRoot(void) {
    for (NSString *root in DIDBundledRoots()) {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:root isDirectory:&isDir] && isDir) return root;
    }
    return nil;
}

// 合并内置 + 用户目录里的主题，返回 名称 -> 是否内置 的有序数组
static NSArray<NSDictionary *> *DIDThemeEntries(NSString *kind) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSString *bundled = DIDBundledRoot();
    NSArray<NSString *> *roots = @[bundled ? [bundled stringByAppendingPathComponent:kind] : @"",
                                   [DIDMediaRoot stringByAppendingPathComponent:kind]];
    NSArray<NSNumber *> *builtinFlag = @[@YES, @NO];
    for (NSUInteger i = 0; i < roots.count; i++) {
        NSString *root = roots[i];
        BOOL isDir = NO;
        if (root.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:root isDirectory:&isDir] || !isDir) continue;
        BOOL builtin = builtinFlag[i].boolValue;
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL]) {
            if ([name hasPrefix:@"."] || [seen containsObject:name]) continue;
            BOOL d = NO;
            if (![[NSFileManager defaultManager] fileExistsAtPath:[root stringByAppendingPathComponent:name] isDirectory:&d] || !d) continue;
            [seen addObject:name];
            [out addObject:@{@"name": name, @"builtin": @(builtin)}];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedStandardCompare:b[@"name"]];
    }];
    return out;
}

static NSString *DIDDefaultThemeName(NSString *kind) {
    NSArray<NSDictionary *> *entries = DIDThemeEntries(kind);
    return entries.count ? entries.firstObject[@"name"] : nil;
}

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
    [spec setProperty:title forKey:@"didTitle"];
    [spec setProperty:@(YES) forKey:@"didFolderRow"];
    [spec setProperty:@"showFolderPicker:" forKey:@"action"];
    return spec;
}



- (void)showFolderPicker:(PSSpecifier *)specifier {
    NSString *kind = [specifier propertyForKey:@"didFolderKind"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[specifier propertyForKey:@"didTitle"]
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSDictionary *> *entries = DIDThemeEntries(kind);
    if (entries.count == 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"没有找到任何主题" style:UIAlertActionStyleDefault handler:nil]];
    }
    for (NSDictionary *e in entries) {
        NSString *name = e[@"name"];
        BOOL builtin = [e[@"builtin"] boolValue];
        NSString *title = builtin ? [NSString stringWithFormat:@"%@  ·内置", name] : name;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self setPreferenceValue:name specifier:specifier];
            [self reloadSpecifier:specifier animated:YES];
            [self reloadFolderButtonTitles];
        }]];
    }
    if (DIDPref([specifier propertyForKey:@"key"])) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"恢复默认主题" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
            [self setPreferenceValue:@"" specifier:specifier];
            [self reloadSpecifier:specifier animated:YES];
            [self reloadFolderButtonTitles];
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
        if (![[spec propertyForKey:@"didFolderRow"] boolValue]) continue;
        NSString *kind = [spec propertyForKey:@"didFolderKind"];
        NSString *title = [spec propertyForKey:@"didTitle"];
        id v = DIDPref([spec propertyForKey:@"key"]);
        NSString *name = ([v isKindOfClass:[NSString class]] && [v length]) ? v : nil;
        BOOL builtin = NO;
        if (!name) {
            name = DIDDefaultThemeName(kind);
            builtin = YES;
        }
        NSString *shown = name ? name : @"无可用主题";
        [spec setProperty:[NSString stringWithFormat:@"%@    %@%@", title ?: spec.name,
                           shown, builtin ? @"（默认）" : @""] forKey:@"label"];
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
        [group setProperty:@"已内置 5 套跳舞、2 套写轮眼、2 套遮罩，装完即用。自己下载的素材也可以放到 /var/mobile/DynamicIsland/{dance,eye,mask}，会和内置主题一起出现在选择列表里。"
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
        [group setProperty:@"若已安装独立的“录屏写轮眼”插件，请保持本组关闭，避免两套素材重叠；只装本插件的话可以打开。" forKey:@"footerText"];
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