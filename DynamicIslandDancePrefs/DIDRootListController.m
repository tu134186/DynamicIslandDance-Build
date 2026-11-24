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

static void DIDSetPref(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)DIDDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)DIDDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         kDIDNotify, NULL, NULL, YES);
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

// 合并内置 + 用户目录，跳过空目录。元素：@{name, builtin}
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
            if (!DIDIsDir(full)) continue;

            BOOL usable = NO;
            if ([kind isEqualToString:@"mask"]) {
                usable = [[NSFileManager defaultManager] fileExistsAtPath:
                          [full stringByAppendingPathComponent:@"Mask.png"]];
            } else {
                for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:full error:NULL]) {
                    NSString *e = f.pathExtension.lowercaseString;
                    if ([e isEqualToString:@"png"] || [e isEqualToString:@"jpg"] ||
                        [e isEqualToString:@"jpeg"] || [e isEqualToString:@"webp"]) { usable = YES; break; }
                }
            }
            if (!usable) continue;
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
    for (NSString *want in preferred) {
        for (NSDictionary *d in all) if ([(NSString *)d[@"name"] isEqualToString:want]) return want;
    }
    return (NSString *)all.firstObject[@"name"];
}

@implementation DIDRootListController

#pragma mark - 主题行标题

- (void)refreshThemeLabels {
    for (PSSpecifier *spec in [self specifiers]) {
        NSString *title = [spec propertyForKey:@"didTitle"];
        if (![title isKindOfClass:[NSString class]]) continue;
        NSString *kind = [spec propertyForKey:@"didKind"];
        NSString *key = [spec propertyForKey:@"didKey"];
        id v = DIDPref(key);
        BOOL custom = ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) ? YES : NO;
        NSString *name = custom ? (NSString *)v : DIDDefaultTheme(kind);
        NSString *text;
        if (name.length) {
            text = [NSString stringWithFormat:@"%@：%@%@", title, name, custom ? @"" : @"（默认）"];
        } else {
            text = [NSString stringWithFormat:@"%@：无素材", title];
        }
        if (![spec.name isEqualToString:text]) [spec setProperty:text forKey:@"label"];
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

#pragma mark - 选择主题

- (void)presentThemes:(NSString *)kind key:(NSString *)key title:(NSString *)title specifier:(PSSpecifier *)specifier {
    NSArray<NSDictionary *> *entries = DIDThemes(kind);
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    id current = DIDPref(key);
    for (NSDictionary *e in entries) {
        NSString *name = (NSString *)e[@"name"];
        BOOL isCurrent = [current isKindOfClass:[NSString class]] && [(NSString *)current isEqualToString:name];
        NSString *label = [NSString stringWithFormat:@"%@%@%@", name,
                           [(NSNumber *)e[@"builtin"] boolValue] ? @"（内置）" : @"",
                           isCurrent ? @"  ✓" : @""];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            DIDSetPref(key, name);
            [self refreshThemeLabels];
        }]];
    }
    if (entries.count == 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"没有找到素材"
                                                  style:UIAlertActionStyleDefault handler:nil]];
    }
    if (current) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"恢复默认"
                                                  style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, (__bridge CFStringRef)DIDDomain);
            CFPreferencesAppSynchronize((__bridge CFStringRef)DIDDomain);
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 kDIDNotify, NULL, NULL, YES);
            [self refreshThemeLabels];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds),
                                                               CGRectGetMaxY(self.view.bounds) - 60, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pickDanceTheme:(PSSpecifier *)specifier {
    [self presentThemes:@"dance" key:@"selectedDanceFolder" title:@"跳舞素材" specifier:specifier];
}
- (void)pickEyeTheme:(PSSpecifier *)specifier {
    [self presentThemes:@"eye" key:@"selectedEyeFolder" title:@"录屏素材" specifier:specifier];
}
- (void)pickMaskTheme:(PSSpecifier *)specifier {
    [self presentThemes:@"mask" key:@"selectedMaskFolder" title:@"遮罩素材" specifier:specifier];
}

#pragma mark - 素材根目录

- (void)editMediaRoot:(PSSpecifier *)specifier {
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
    [alert addAction:[UIAlertAction actionWithTitle:@"默认" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) {
        CFPreferencesSetAppValue(CFSTR("mediaRoot"), NULL, (__bridge CFStringRef)DIDDomain);
        CFPreferencesAppSynchronize((__bridge CFStringRef)DIDDomain);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             kDIDNotify, NULL, NULL, YES);
        [self refreshThemeLabels];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        NSString *text = alert.textFields.firstObject.text ?: @"";
        text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (text.length && ![text isEqualToString:DIDDefaultRoot]) {
            DIDSetPref(@"mediaRoot", text);
        } else {
            CFPreferencesSetAppValue(CFSTR("mediaRoot"), NULL, (__bridge CFStringRef)DIDDomain);
            CFPreferencesAppSynchronize((__bridge CFStringRef)DIDDomain);
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 kDIDNotify, NULL, NULL, YES);
        }
        [self refreshThemeLabels];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end