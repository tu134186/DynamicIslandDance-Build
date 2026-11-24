#import "DIDRootListController.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *const DIDDomain = @"com.minis.didance";
static CFStringRef const kDIDNotify = CFSTR("com.minis.didance.changed");
static NSString *const DIDDefaultRoot = @"/var/mobile/DynamicIsland";

static id DIDPref(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)DIDDomain);
    return CFBridgingRelease(v);
}

static void DIDPost(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)DIDDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         kDIDNotify, NULL, NULL, YES);
}

static void DIDSetPref(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)DIDDomain);
    DIDPost();
}

static void DIDRemovePref(NSString *key) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)DIDDomain);
    DIDPost();
}

static NSString *DIDRoot(void) {
    id v = DIDPref(@"mediaRoot");
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length])
        return [(NSString *)v stringByStandardizingPath];
    return DIDDefaultRoot;
}

static BOOL DIDIsDir(NSString *path) {
    BOOL d = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&d] && d;
}

static NSString *DIDBundledRoot(void) {
    for (NSString *r in @[@"/var/jb/Library/Application Support/DynamicIslandDance",
                          @"/Library/Application Support/DynamicIslandDance"]) {
        if (DIDIsDir(r)) return r;
    }
    return nil;
}

static BOOL DIDThemeUsable(NSString *kind, NSString *dir) {
    if ([kind isEqualToString:@"mask"])
        return [[NSFileManager defaultManager] fileExistsAtPath:
                [dir stringByAppendingPathComponent:@"Mask.png"]];
    for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
        NSString *e = f.pathExtension.lowercaseString;
        if ([e isEqualToString:@"png"] || [e isEqualToString:@"jpg"] ||
            [e isEqualToString:@"jpeg"] || [e isEqualToString:@"webp"]) return YES;
    }
    return NO;
}

// 合并内置 + 用户素材；空目录跳过
static NSArray<NSDictionary *> *DIDThemes(NSString *kind) {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableArray<NSArray *> *roots = [NSMutableArray array];
    NSString *b = DIDBundledRoot();
    if (b) [roots addObject:@[ [b stringByAppendingPathComponent:kind], @YES ]];
    [roots addObject:@[ [DIDRoot() stringByAppendingPathComponent:kind], @NO ]];

    for (NSArray *pair in roots) {
        NSString *root = (NSString *)pair[0];
        BOOL builtin = [(NSNumber *)pair[1] boolValue];
        if (!DIDIsDir(root)) continue;
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL]) {
            if ([name hasPrefix:@"."] || [seen containsObject:name]) continue;
            NSString *full = [root stringByAppendingPathComponent:name];
            if (!DIDIsDir(full) || !DIDThemeUsable(kind, full)) continue;
            [seen addObject:name];
            [out addObject:@{@"name": name, @"builtin": @(builtin)}];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [(NSString *)a[@"name"] localizedStandardCompare:(NSString *)b[@"name"]];
    }];
    return out;
}

static NSString *DIDDefaultTheme(NSString *kind) {
    NSArray<NSDictionary *> *all = DIDThemes(kind);
    if (all.count == 0) return nil;
    NSArray<NSString *> *preferred = [kind isEqualToString:@"dance"]
        ? @[@"notedrop", @"equalizer", @"cat", @"ghost", @"star"]
        : [kind isEqualToString:@"eye"] ? @[@"sharingan", @"pulse"] : @[@"circle", @"squircle"];
    for (NSString *want in preferred)
        for (NSDictionary *d in all)
            if ([(NSString *)d[@"name"] isEqualToString:want]) return want;
    return (NSString *)all.firstObject[@"name"];
}

@implementation DIDRootListController

#pragma mark - 关键：必须显式加载 Root.plist（PreferenceLoader 不会自动加载）

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSArray *loaded = [self loadSpecifiersFromPlistName:@"Root" target:self];
        if (loaded.count == 0) {
            PSSpecifier *err = [PSSpecifier preferenceSpecifierNamed:@"设置加载失败（Root.plist 未读取）"
                                                              target:self set:nil get:nil
                                                            detail:nil cell:PSStaticTextCell edit:nil];
            loaded = @[err];
        }
        _specifiers = [loaded mutableCopy];
        for (PSSpecifier *spec in _specifiers) {
            if ([spec propertyForKey:@"action"]) [spec setTarget:self];
        }
    }
    return _specifiers;
}

#pragma mark - 主题行显示当前素材名

- (void)refreshThemeLabels {
    for (PSSpecifier *spec in self.specifiers) {
        NSString *title = [spec propertyForKey:@"didTitle"];
        if (![title isKindOfClass:[NSString class]]) continue;
        NSString *kind = [spec propertyForKey:@"didKind"];
        NSString *key = [spec propertyForKey:@"didKey"];
        id v = DIDPref(key);
        BOOL custom = ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) ? YES : NO;
        NSString *name = custom ? (NSString *)v : DIDDefaultTheme(kind);
        NSString *text = name.length
            ? [NSString stringWithFormat:@"%@：%@%@", title, name, custom ? @"" : @"（默认）"]
            : [NSString stringWithFormat:@"%@：无素材", title];
        [spec setProperty:text forKey:@"label"];
    }
    [self reloadSpecifiers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshThemeLabels];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshThemeLabels];
}

#pragma mark - 选择素材

- (void)presentThemesForKind:(NSString *)kind key:(NSString *)key title:(NSString *)title {
    NSArray<NSDictionary *> *entries = DIDThemes(kind);
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                  message:[NSString stringWithFormat:@"目录：%@/%@", DIDRoot(), kind]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    id current = DIDPref(key);
    for (NSDictionary *e in entries) {
        NSString *name = (NSString *)e[@"name"];
        BOOL isCurrent = [current isKindOfClass:[NSString class]] && [(NSString *)current isEqualToString:name];
        NSString *label = [NSString stringWithFormat:@"%@%@%@", name,
                           [(NSNumber *)e[@"builtin"] boolValue] ? @"（内置）" : @"",
                           isCurrent ? @"  ✓" : @""];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault
                                               handler:^(__unused UIAlertAction *a) {
            DIDSetPref(key, name);
            [self refreshThemeLabels];
        }]];
    }
    if (entries.count == 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"没有找到素材" style:UIAlertActionStyleDefault handler:nil]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"恢复默认" style:UIAlertActionStyleDestructive
                                           handler:^(__unused UIAlertAction *a) {
        DIDRemovePref(key);
        [self refreshThemeLabels];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect =
        CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds) - 60, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pickDanceTheme:(PSSpecifier *)specifier {
    (void)specifier;
    [self presentThemesForKind:@"dance" key:@"selectedDanceFolder" title:@"跳舞素材"];
}
- (void)pickEyeTheme:(PSSpecifier *)specifier {
    (void)specifier;
    [self presentThemesForKind:@"eye" key:@"selectedEyeFolder" title:@"录屏素材"];
}
- (void)pickMaskTheme:(PSSpecifier *)specifier {
    (void)specifier;
    [self presentThemesForKind:@"mask" key:@"selectedMaskFolder" title:@"遮罩素材"];
}

#pragma mark - 素材目录

- (void)editMediaRoot:(PSSpecifier *)specifier {
    (void)specifier;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"素材根目录"
                                                                   message:@"下面自动使用 dance / eye / mask 三个子目录。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = DIDRoot();
        tf.placeholder = DIDDefaultRoot;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"默认" style:UIAlertActionStyleDestructive
                                           handler:^(__unused UIAlertAction *a) {
        DIDRemovePref(@"mediaRoot");
        [self refreshThemeLabels];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
                                           handler:^(__unused UIAlertAction *a) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length && ![text isEqualToString:DIDDefaultRoot]) DIDSetPref(@"mediaRoot", text);
        else DIDRemovePref(@"mediaRoot");
        [self refreshThemeLabels];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end