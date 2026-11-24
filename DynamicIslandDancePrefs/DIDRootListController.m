#import "DIDRootListController.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *const DIDDomain = @"com.minis.didance";
static NSString *const DIDNotify = @"com.minis.didance.changed";
static NSString *const DIDDefaultMediaRoot = @"/var/mobile/DynamicIsland";

static id DIDPref(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)DIDDomain);
    return CFBridgingRelease(v);
}

static void DIDNotifyChanged(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)DIDNotify, NULL, NULL, YES);
}

static NSString *DIDMediaRoot(void) {
    id v = DIDPref(@"mediaRoot");
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) {
        return [(NSString *)v stringByStandardizingPath];
    }
    return DIDDefaultMediaRoot;
}

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

static BOOL DIDIsDir(NSString *path) {
    BOOL d = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&d] && d;
}

static NSString *DIDKindFolder(NSString *kind) {
    return [DIDMediaRoot() stringByAppendingPathComponent:kind];
}

// 合并内置 + 用户主题；空目录跳过。返回 @{name, builtin, path}
static NSArray<NSDictionary *> *DIDThemeEntries(NSString *kind) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableArray<NSArray *> *roots = [NSMutableArray array];
    NSString *b = DIDBundledRoot();
    if (b) [roots addObject:@[ [b stringByAppendingPathComponent:kind], @YES ]];
    [roots addObject:@[ [DIDMediaRoot() stringByAppendingPathComponent:kind], @NO ]];

    for (NSArray *pair in roots) {
        NSString *root = (NSString *)pair[0];
        BOOL builtin = [(NSNumber *)pair[1] boolValue];
        if (!DIDIsDir(root)) continue;
        NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL];
        for (NSString *name in names) {
            if ([name hasPrefix:@"."] || [seen containsObject:name]) continue;
            NSString *full = [root stringByAppendingPathComponent:name];
            if (!DIDIsDir(full)) continue;
            BOOL usable = NO;
            if ([kind isEqualToString:@"mask"]) {
                usable = [[NSFileManager defaultManager] fileExistsAtPath:
                          [full stringByAppendingPathComponent:@"Mask.png"]];
            } else {
                NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:full error:NULL];
                for (NSString *f in files) {
                    NSString *ext = f.pathExtension.lowercaseString;
                    if ([ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] ||
                        [ext isEqualToString:@"jpeg"] || [ext isEqualToString:@"webp"]) { usable = YES; break; }
                }
            }
            if (!usable) continue;
            [seen addObject:name];
            [out addObject:@{@"name": name, @"builtin": @(builtin), @"path": full}];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [(NSString *)a[@"name"] localizedStandardCompare:(NSString *)b[@"name"]];
    }];
    return out;
}

static NSString *DIDDefaultThemeName(NSString *kind) {
    NSArray<NSDictionary *> *e = DIDThemeEntries(kind);
    if (e.count == 0) return nil;
    NSArray<NSString *> *preferred = [kind isEqualToString:@"dance"]
        ? @[@"notedrop", @"equalizer", @"cat", @"ghost", @"star"]
        : [kind isEqualToString:@"eye"] ? @[@"sharingan", @"pulse"] : @[@"circle", @"squircle"];
    for (NSString *name in preferred) {
        for (NSDictionary *d in e) {
            if ([(NSString *)d[@"name"] isEqualToString:name]) return name;
        }
    }
    return (NSString *)e.firstObject[@"name"];
}

@interface DIDRootListController ()
@end

@implementation DIDRootListController

#pragma mark - 读写偏好

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id v = DIDPref(key);
    if (v != nil) return v;
    return [specifier propertyForKey:@"default"] ?: @NO;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)DIDDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)DIDDomain);
    DIDNotifyChanged();
}

#pragma mark - 行构造函数

- (PSSpecifier *)switchRow:(NSString *)title key:(NSString *)key def:(BOOL)def {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title
                                                    target:self
                                                       set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:)
                                                    detail:nil
                                                      cell:PSListItemCell
                                                      edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:@(def) forKey:@"default"];
    [s setProperty:key forKey:@"id"];
    return s;
}

- (PSSpecifier *)sliderRow:(NSString *)title key:(NSString *)key def:(CGFloat)def min:(CGFloat)lo max:(CGFloat)hi {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title
                                                    target:self
                                                       set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:)
                                                    detail:nil
                                                      cell:PSSliderCell
                                                      edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:@(def) forKey:@"default"];
    [s setProperty:@(lo) forKey:@"min"];
    [s setProperty:@(hi) forKey:@"max"];
    [s setProperty:@(def) forKey:@"PSSliderDefault"];
    [s setProperty:key forKey:@"id"];
    return s;
}

- (PSSpecifier *)themeRow:(NSString *)title kind:(NSString *)kind key:(NSString *)key {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title
                                                    target:self
                                                       set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:)
                                                    detail:nil
                                                      cell:PSButtonCell
                                                      edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:kind forKey:@"didKind"];
    [s setProperty:title forKey:@"didTitle"];
    [s setProperty:@(YES) forKey:@"didThemeRow"];
    [s setProperty:@"pickTheme:" forKey:@"action"];
    [s setProperty:key forKey:@"id"];
    return s;
}

- (PSSpecifier *)buttonRow:(NSString *)title action:(NSString *)action key:(NSString *)key {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title
                                                    target:self
                                                       set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:)
                                                    detail:nil
                                                      cell:PSButtonCell
                                                      edit:nil];
    [s setProperty:action forKey:@"action"];
    if (key) [s setProperty:key forKey:@"key"];
    [s setProperty:key ?: action forKey:@"id"];
    return s;
}

- (PSSpecifier *)infoRow:(NSString *)title value:(NSString *)value {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title
                                                    target:nil
                                                       set:nil
                                                       get:nil
                                                    detail:nil
                                                      cell:PSTitleValueCell
                                                      edit:nil];
    [s setProperty:value forKey:@"label"];
    return s;
}

- (PSSpecifier *)groupNamed:(NSString *)name footer:(NSString *)footer {
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:name];
    if (footer.length) [g setProperty:footer forKey:@"footerText"];
    return g;
}

#pragma mark - 主题选择

- (void)reloadThemeTitles {
    for (PSSpecifier *s in [self specifiers]) {
        if (![[s propertyForKey:@"didThemeRow"] boolValue]) continue;
        NSString *kind = [s propertyForKey:@"didKind"];
        NSString *title = [s propertyForKey:@"didTitle"];
        id v = DIDPref([s propertyForKey:@"key"]);
        NSString *name = ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) ? v : nil;
        BOOL builtin = NO;
        if (!name) {
            name = DIDDefaultThemeName(kind);
            builtin = YES;
        }
        NSString *shown = name ? name : @"无可用素材";
        [s setProperty:[NSString stringWithFormat:@"%@    %@%@", title, shown,
                        builtin ? @"  ·内置" : @""] forKey:@"label"];
    }
}

- (void)pickTheme:(PSSpecifier *)specifier {
    NSString *kind = [specifier propertyForKey:@"didKind"];
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *title = [specifier propertyForKey:@"didTitle"];
    NSArray<NSDictionary *> *entries = DIDThemeEntries(kind);

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                  message:[NSString stringWithFormat:@"素材目录：%@", DIDKindFolder(kind)]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    id current = DIDPref(key);
    for (NSDictionary *e in entries) {
        NSString *name = e[@"name"];
        BOOL isCurrent = [current isKindOfClass:[NSString class]] && [current isEqualToString:name];
        NSString *label = [NSString stringWithFormat:@"%@%@%@", name,
                           [e[@"builtin"] boolValue] ? @"  ·内置" : @"",
                           isCurrent ? @"  ✓" : @""];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            [self setPreferenceValue:name specifier:specifier];
            [self reloadThemeTitles];
        }]];
    }
    if (entries.count == 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"没有找到素材，请按下面的路径放进去"
                                                  style:UIAlertActionStyleDefault handler:nil]];
    }
    if (current) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"恢复默认（第一个内置素材）"
                                                  style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
            [self setPreferenceValue:@"" specifier:specifier];
            [self reloadThemeTitles];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                               CGRectGetMaxY(self.view.bounds) - 60, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - 素材根目录

- (void)editMediaRoot:(PSSpecifier *)specifier {
    NSString *current = DIDMediaRoot();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"素材根目录"
                                                                   message:@"下面三个子目录 dance / eye / mask 会放在这里。改完把素材放进去，列表会自动刷新。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = current;
        tf.placeholder = DIDDefaultMediaRoot;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        [self setPreferenceValue:@"" specifier:specifier];
        [self reloadThemeTitles];
        [self reloadSpecifiers];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [self setPreferenceValue:(text.length ? text : @"") specifier:specifier];
        [self reloadThemeTitles];
        [self reloadSpecifiers];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 应用 / 重载

- (void)applyNow:(PSSpecifier *)specifier {
    (void)specifier;
    DIDNotifyChanged();
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已立即生效"
                                                              message:@"若灵动岛上暂时没变化，播放或暂停一次音乐即可刷新。"
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadThemeTitles];
}

#pragma mark - 列表

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        // ===== 1. 总开关 =====
        [specs addObject:[self groupNamed:@"灵动岛跳舞" footer:@"关闭总开关后，专辑旋转、岛上素材、岛形调整全部停止，等于临时停用插件。"]];
        [specs addObject:[self switchRow:@"开启插件" key:@"shouldEnableCustomUI" def:YES]];

        // ===== 2. 跳舞素材 =====
        [specs addObject:[self groupNamed:@"跳舞动画（音乐播放时出现在岛上）"
                                   footer:[NSString stringWithFormat:
                                           @"素材位置：%@/dance/<素材名>/replay1.png …\n\n把整套帧图放进上面这个目录，列表里就会出现新的素材名。内置素材随插件安装，删不掉也不占地方。",
                                           DIDMediaRoot()]]];
        [specs addObject:[self switchRow:@"启用跳舞素材" key:@"enableDanceSprite" def:YES]];
        [specs addObject:[self themeRow:@"跳舞素材" kind:@"dance" key:@"selectedDanceFolder"]];
        [specs addObject:[self sliderRow:@"素材大小" key:@"danceAnimationSize" def:22.0 min:4.0 max:64.0]];
        [specs addObject:[self sliderRow:@"播放帧率" key:@"frameAnimationSpeed" def:12.0 min:1.0 max:60.0]];
        [specs addObject:[self sliderRow:@"水平位置" key:@"plugin3XOffset" def:0.0 min:-120.0 max:120.0]];
        [specs addObject:[self sliderRow:@"垂直位置" key:@"plugin3YOffset" def:0.0 min:-60.0 max:60.0]];

        // ===== 3. 专辑封面 =====
        [specs addObject:[self groupNamed:@"专辑封面旋转"
                                   footer:[NSString stringWithFormat:
                                           @"遮罩位置：%@/mask/<遮罩名>/Mask.png\n\n遮罩是一张白色形状图，插件会自动反色后裁出可旋转的封面形状。不想要自定义形状就关掉“使用圆形遮罩”，直接用正圆。",
                                           DIDMediaRoot()]]];
        [specs addObject:[self switchRow:@"旋转专辑封面" key:@"enableAlbumRotation" def:YES]];
        [specs addObject:[self sliderRow:@"旋转速度" key:@"albumRotationSpeed" def:0.6 min:0.05 max:4.0]];
        [specs addObject:[self switchRow:@"使用自定义遮罩" key:@"enableMaskLayer" def:YES]];
        [specs addObject:[self themeRow:@"遮罩素材" kind:@"mask" key:@"selectedMaskFolder"]];

        // ===== 4. 录屏素材 =====
        [specs addObject:[self groupNamed:@"录屏写轮眼（录屏时出现在岛上）"
                                   footer:[NSString stringWithFormat:
                                           @"素材位置：%@/eye/<素材名>/replay1.png …\n\n如果你还装了独立的“录屏写轮眼”插件，请把这一组关掉，否则两套素材会重叠。",
                                           DIDMediaRoot()]]];
        [specs addObject:[self switchRow:@"启用录屏素材" key:@"enableEyeSprite" def:YES]];
        [specs addObject:[self themeRow:@"录屏素材" kind:@"eye" key:@"selectedEyeFolder"]];
        [specs addObject:[self sliderRow:@"素材大小" key:@"eyeAnimationSize" def:22.0 min:4.0 max:64.0]];
        [specs addObject:[self sliderRow:@"播放帧率" key:@"eyeFrameAnimationSpeed" def:12.0 min:1.0 max:60.0]];
        [specs addObject:[self sliderRow:@"水平位置" key:@"plugin2XOffset" def:0.0 min:-120.0 max:120.0]];
        [specs addObject:[self sliderRow:@"垂直位置" key:@"plugin2YOffset" def:0.0 min:-60.0 max:60.0]];

        // ===== 5. 岛形 =====
        [specs addObject:[self groupNamed:@"灵动岛外观" footer:@"圆化会把展开/折叠状态的岛改成 iOS17 的圆形与 193pt 宽，让旋转的封面看起来是圆的。"]];
        [specs addObject:[self switchRow:@"灵动岛圆化（iOS17 适配）" key:@"enableIOS17Adaptation" def:YES]];

        // ===== 6. 路径与工具 =====
        NSString *bundled = DIDBundledRoot();
        [specs addObject:[self groupNamed:@"素材路径"
                                   footer:[NSString stringWithFormat:
                                           @"当前根目录：%@\n跳舞：%@/dance\n录屏：%@/eye\n遮罩：%@/mask\n内置素材：%@\n\n点上面一行可以改成任意路径（比如放到 App 的 Documents 里）。",
                                           DIDMediaRoot(), DIDMediaRoot(), DIDMediaRoot(), DIDMediaRoot(),
                                           bundled ?: @"(未找到内置素材)"]];
        [specs addObject:[self buttonRow:@"修改素材根目录" action:@"editMediaRoot:" key:@"mediaRoot"]];
        [specs addObject:[self buttonRow:@"立即生效（不重启设置）" action:@"applyNow:" key:nil]];

        _specifiers = specs;
        [self reloadThemeTitles];
    }
    return _specifiers;
}

@end