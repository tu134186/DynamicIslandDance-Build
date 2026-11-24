// DynamicIslandDance — 灵动岛跳舞（纯净自研版）
// 素材贴到灵动岛容器里，位置跟随系统红点 / 专辑封面。
// 全自研：无联网、无设备指纹、无授权校验。

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdio.h>

static NSString *const DIDVersion     = @"2.4.0";
static NSString *const DIDPrefPath    = @"/var/mobile/Library/Preferences/com.minis.didance.plist";
static const char *     DIDPrefNotify = "com.minis.didance.changed";
static NSString *const DIDDefaultRoot = @"/var/mobile/DynamicIsland";
static NSString *const DIDLogPath     = @"/var/mobile/DynamicIslandDance.log";

#pragma mark - 日志

static void DIDLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%.1f] %@\n", CFAbsoluteTimeGetCurrent(), msg];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        FILE *fp = fopen(DIDLogPath.UTF8String, "a");
        if (fp) { fputs(line.UTF8String, fp); fclose(fp); }
    });
}

#pragma mark - 设置

// 必须走 CFPreferences（cfprefsd），直接读 plist 文件会拿到未落盘的旧值
static CFStringRef const kDIDDomain = CFSTR("com.minis.didance");

static NSDictionary *gPrefs;
static NSTimeInterval gPrefsAt = -1e9;

static void DIDReloadPrefs(BOOL force) {
    NSTimeInterval now = CACurrentMediaTime();
    if (!force && gPrefs && now - gPrefsAt < 0.6) return;
    gPrefsAt = now;

    CFStringRef keys[8] = {
        CFSTR("shouldEnableCustomUI"), CFSTR("enableSprite"), CFSTR("enableAlbumRotation"),
        CFSTR("enableMaskLayer"), CFSTR("enableIOS17Adaptation"), CFSTR("enableEyeSprite"),
        CFSTR("enableDanceSprite"), CFSTR("hideNativeDot")
    };
    CFArrayRef keyArray = CFArrayCreate(NULL, (const void **)keys, 8, &kCFTypeArrayCallBacks);
    CFDictionaryRef dict = CFPreferencesCopyMultiple(keyArray, kDIDDomain,
                                                     kCFPreferencesCurrentUser,
                                                     kCFPreferencesAnyHost);
    CFRelease(keyArray);
    NSMutableDictionary *m = dict ? [(__bridge NSDictionary *)dict mutableCopy]
                                  : [NSMutableDictionary dictionary];
    if (dict) CFRelease(dict);
    gPrefs = m;
}

static id DIDRaw(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, kDIDDomain);
    return CFBridgingRelease(v);
}

static BOOL DIDBool(NSString *key, BOOL fallback) {
    // 布尔值走 gPrefs 批量缓存；其它直接取
    DIDReloadPrefs(NO);
    id v = gPrefs[key] ?: DIDRaw(key);
    return v ? [v boolValue] : fallback;
}

// 数值项缓存 0.4s：layoutSubviews 高频调用，不能每次都问 cfprefsd
static NSMutableDictionary<NSString *, NSNumber *> *gFloatCache;
static NSTimeInterval gFloatAt = -1e9;

static CGFloat DIDFloat(NSString *key, CGFloat fallback, CGFloat lo, CGFloat hi) {
    NSTimeInterval now = CACurrentMediaTime();
    if (!gFloatCache || now - gFloatAt > 0.4) {
        gFloatCache = [NSMutableDictionary dictionary];
        gFloatAt = now;
    }
    NSNumber *cached = gFloatCache[key];
    double raw;
    if (cached) {
        raw = cached.doubleValue;
    } else {
        id v = DIDRaw(key);
        raw = v ? [v doubleValue] : fallback;
        gFloatCache[key] = @(raw);
    }
    return MAX(lo, MIN(hi, raw));
}

static NSString *DIDString(NSString *key) {
    id v = DIDRaw(key);
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static NSString *DIDMediaRootDir(void) {
    static NSString *cached;
    static NSTimeInterval cachedAt = -1e9;
    NSTimeInterval now = CACurrentMediaTime();
    if (cached && now - cachedAt < 1.0) return cached;
    cachedAt = now;
    NSString *v = DIDString(@"mediaRoot");
    cached = [(v.length ? v : DIDDefaultRoot) stringByStandardizingPath];
    return cached;
}

static BOOL DIDEnabled(void)    { return DIDBool(@"shouldEnableCustomUI", YES); }
static BOOL DIDRotationOn(void) { return DIDBool(@"enableAlbumRotation", YES); }
static BOOL DIDMaskOn(void)     { return DIDBool(@"enableMaskLayer", YES); }
static BOOL DIDEyeOn(void)      { return DIDBool(@"enableEyeSprite", YES); }
static BOOL DIDDanceOn(void)    { return DIDBool(@"enableDanceSprite", YES); }

#pragma mark - 素材文件

static NSString *DIDKindName(NSInteger kind) {
    return kind == 0 ? @"dance" : (kind == 1 ? @"eye" : @"mask");
}

static NSString *DIDBundledRoot(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *root in @[@"/var/jb/Library/Application Support/DynamicIslandDance",
                                 @"/Library/Application Support/DynamicIslandDance"]) {
            BOOL isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:root isDirectory:&isDir] && isDir) {
                cached = root; break;
            }
        }
    });
    return cached;
}

static NSInteger DIDFileNumber(NSString *name) {
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
        else if (digits.length) break;
    }
    return digits.length ? digits.integerValue : 0;
}

static BOOL DIDFileIsImage(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    return [ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] ||
           [ext isEqualToString:@"jpeg"] || [ext isEqualToString:@"webp"] || [ext isEqualToString:@"gif"];
}

static NSArray<NSString *> *DIDFrameFilesIn(NSString *dir) {
    if (dir.length == 0) return @[];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL]) {
        if ([n hasPrefix:@"."] || !DIDFileIsImage(n)) continue;
        [files addObject:n];
    }
    NSMutableArray<NSString *> *replay = [NSMutableArray array];
    for (NSString *n in files) if ([n.lowercaseString hasPrefix:@"replay"]) [replay addObject:n];
    NSArray<NSString *> *use = replay.count ? replay : files;
    return [use sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger na = DIDFileNumber(a), nb = DIDFileNumber(b);
        if (na != nb) return na < nb ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];
}

static NSString *DIDThemeDir(NSInteger kind, NSString *folder) {
    if (folder.length == 0) return nil;
    BOOL isDir = NO;
    NSString *user = [[DIDMediaRootDir() stringByAppendingPathComponent:DIDKindName(kind)]
                      stringByAppendingPathComponent:folder];
    if ([[NSFileManager defaultManager] fileExistsAtPath:user isDirectory:&isDir] && isDir) return user;
    NSString *b = DIDBundledRoot();
    if (b) {
        NSString *bundled = [[b stringByAppendingPathComponent:DIDKindName(kind)]
                             stringByAppendingPathComponent:folder];
        if ([[NSFileManager defaultManager] fileExistsAtPath:bundled isDirectory:&isDir] && isDir) return bundled;
    }
    return nil;
}

static NSString *DIDMaskPath(NSString *folder) {
    if (folder.length == 0) return nil;
    NSString *user = [DIDMediaRootDir() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"mask/%@/Mask.png", folder]];
    if ([[NSFileManager defaultManager] fileExistsAtPath:user]) return user;
    NSString *b = DIDBundledRoot();
    if (b) {
        NSString *p = [b stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"mask/%@/Mask.png", folder]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
    }
    return nil;
}

static BOOL DIDThemeUsable(NSInteger kind, NSString *folder) {
    if (kind == 2) return DIDMaskPath(folder) != nil;
    NSString *dir = DIDThemeDir(kind, folder);
    return dir ? DIDFrameFilesIn(dir).count > 0 : NO;
}

static NSArray<NSString *> *DIDAvailableThemes(NSInteger kind) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    NSString *b = DIDBundledRoot();
    if (b) [roots addObject:[b stringByAppendingPathComponent:DIDKindName(kind)]];
    [roots addObject:[DIDMediaRootDir() stringByAppendingPathComponent:DIDKindName(kind)]];
    for (NSString *root in roots) {
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL]) {
            if ([name hasPrefix:@"."] || [seen containsObject:name]) continue;
            BOOL isDir = NO;
            if (![[NSFileManager defaultManager] fileExistsAtPath:[root stringByAppendingPathComponent:name]
                                                      isDirectory:&isDir] || !isDir) continue;
            if (!DIDThemeUsable(kind, name)) continue;
            [seen addObject:name];
            [out addObject:name];
        }
    }
    return out;
}

static NSString *DIDDefaultTheme(NSInteger kind) {
    NSArray<NSString *> *all = DIDAvailableThemes(kind);
    if (all.count == 0) return nil;
    NSArray<NSString *> *preferred = kind == 0 ? @[@"notedrop", @"equalizer", @"cat", @"ghost", @"star"]
                                  : kind == 1 ? @[@"three-tomoe", @"sharingan", @"itachi", @"sasuke",
                                                  @"madara", @"obito", @"shisui", @"izuna",
                                                  @"two-tomoe", @"one-tomoe", @"pulse"]
                                              : @[@"circle", @"squircle"];
    for (NSString *n in preferred) if ([all containsObject:n]) return n;
    return all.firstObject;
}

static NSArray<UIImage *> *gFramesDance, *gFramesEye;
static NSString *gKeyDance, *gKeyEye;

static NSArray<UIImage *> *DIDLoadFrames(NSInteger kind) {
    if (kind > 1) return nil;
    NSString *folder = DIDString(kind == 0 ? @"selectedDanceFolder" : @"selectedEyeFolder");
    if (folder.length == 0 || !DIDThemeUsable(kind, folder)) folder = DIDDefaultTheme(kind);
    if (folder.length == 0) return nil;

    NSString *key = [NSString stringWithFormat:@"%ld|%@", (long)kind, folder];
    NSArray<UIImage *> *cached = kind == 0 ? gFramesDance : gFramesEye;
    NSString *cachedKey = kind == 0 ? gKeyDance : gKeyEye;
    if (cached && [cachedKey isEqualToString:key]) return cached;

    NSString *dir = DIDThemeDir(kind, folder);
    NSMutableArray<UIImage *> *images = [NSMutableArray array];
    for (NSString *n in DIDFrameFilesIn(dir)) {
        UIImage *img = [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:n]];
        if (img) [images addObject:img];
    }
    NSArray<UIImage *> *result = images.count ? images : nil;
    if (kind == 0) { gFramesDance = result; gKeyDance = result ? key : nil; }
    else           { gFramesEye = result;   gKeyEye = result ? key : nil; }
    DIDLog(@"frames %@=%@ count=%lu", DIDKindName(kind), folder, (unsigned long)images.count);
    return result;
}

static void DIDClearFrameCache(void) {
    gFramesDance = nil; gFramesEye = nil;
    gKeyDance = nil; gKeyEye = nil;
}

#pragma mark - 精灵

@interface DIDSpriteView : UIImageView
@property (nonatomic, assign) NSInteger didKind;
@property (nonatomic, weak) UIView *didAnchor;
- (void)play:(NSArray<UIImage *> *)frames fps:(CGFloat)fps;
- (void)halt;
@end

@implementation DIDSpriteView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeScaleAspectFit;
        self.backgroundColor = UIColor.clearColor;
        self.layer.masksToBounds = NO;
    }
    return self;
}
- (void)play:(NSArray<UIImage *> *)frames fps:(CGFloat)fps {
    if (frames.count == 0) return;
    CGFloat d = frames.count / MAX(1.0, fps);
    if (self.animationImages == frames && fabs(self.animationDuration - d) < 0.001) {
        if (!self.isAnimating) [self startAnimating];
        return;
    }
    [self stopAnimating];
    self.animationImages = frames;
    self.animationDuration = d;
    self.animationRepeatCount = 0;
    [self startAnimating];
}
- (void)halt {
    [self stopAnimating];
    self.animationImages = nil;
}
@end

static NSHashTable *gSprites;

static DIDSpriteView *DIDNewSprite(NSInteger kind) {
    if (!gSprites) gSprites = [NSHashTable weakObjectsHashTable];
    DIDSpriteView *sp = [[DIDSpriteView alloc] initWithFrame:CGRectZero];
    sp.didKind = kind;
    [gSprites addObject:sp];
    return sp;
}

static DIDSpriteView *DIDSpriteFor(NSInteger kind, UIView *host) {
    DIDSpriteView *found = nil;
    for (DIDSpriteView *sp in gSprites.allObjects) {
        if (sp.didKind != kind) continue;
        if (sp.superview == host) { if (!found) found = sp; continue; }
        [sp halt];
        [sp removeFromSuperview];
    }
    return found;
}

static void DIDPurgeSprites(void) {
    for (DIDSpriteView *sp in gSprites.allObjects) {
        [sp halt];
        [sp removeFromSuperview];
    }
    [gSprites removeAllObjects];
}

#pragma mark - 视图查找

static NSArray<UIWindow *> *DIDAllWindows(void) {
    NSMutableArray<UIWindow *> *out = [NSMutableArray array];
    @try {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]])
                [out addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    } @catch (...) {}
    if (out.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [out addObjectsFromArray:UIApplication.sharedApplication.windows];
#pragma clang diagnostic pop
    }
    return out;
}

static CGRect DIDScreenBounds(void) {
    CGRect b = CGRectMake(0, 0, 393, 852);
    @try { b = [UIScreen mainScreen].bounds; } @catch (...) {}
    return b;
}

// 屏幕坐标系矩形；不要求视图自身可见（portal 的 sourceView 是离屏的）
static CGRect DIDScreenRect(UIView *v) {
    if (!v || !v.window) return CGRectZero;
    CGRect r = CGRectZero;
    @try { r = [v convertRect:v.bounds toView:nil]; } @catch (...) { return CGRectZero; }
    return r;
}

static BOOL DIDRectOnScreen(CGRect r) {
    if (r.size.width < 0.5 || r.size.height < 0.5) return NO;
    CGRect s = DIDScreenBounds();
    return CGRectGetMinX(r) > -12 && CGRectGetMaxX(r) < s.size.width + 12
        && CGRectGetMinY(r) > -12 && CGRectGetMaxY(r) < s.size.height + 12;
}

#pragma mark - 灵动岛容器

// 所有在屏的 SBSystemApertureContainerView（尺寸合理）
static NSArray<UIView *> *DIDPills(void) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"SBSystemApertureContainerView"] &&
            v.window && !v.hidden && v.alpha > 0.01) {
            CGSize b = v.bounds.size;
            if (b.width >= 16 && b.width <= 330 && b.height >= 14 && b.height <= 96) {
                CGRect r = DIDScreenRect(v);
                // 只排除明显飞出屏幕的副本（例如 x≈415 的隐藏复制视图）
                if (CGRectEqualToRect(r, CGRectZero)) continue;
                CGRect scr = DIDScreenBounds();
                if (CGRectGetMinX(r) > scr.size.width - 4 || CGRectGetMaxX(r) < 4) continue;
                if (CGRectGetMinY(r) > scr.size.height - 4 || CGRectGetMaxY(r) < 4) continue;
                [out addObject:v];
            }
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return out;
}

static BOOL DIDPillHasTag(UIView *pill, NSString *token, NSInteger depth) {
    if (!pill || depth < 0) return NO;
    NSString *ident = pill.accessibilityIdentifier;
    if ([ident isKindOfClass:[NSString class]] && [ident containsString:token]) return YES;
    for (UIView *s in pill.subviews) if (DIDPillHasTag(s, token, depth - 1)) return YES;
    return NO;
}

// 系统红点：类名含 RecordingIndicator、尺寸 2~26pt。
// 注意：它常被 portal 渲染，自身不一定可见，所以不要求 on-screen。
static NSArray<UIView *> *DIDDots(void) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        NSString *cls = NSStringFromClass(v.class);
        if ([cls containsString:@"RecordingIndicator"]) {
            CGSize b = v.bounds.size;
            CGFloat m = MAX(b.width, b.height);
            if (m >= 1.5 && m <= 26.0 && v.window) [out addObject:v];
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    [out sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGRect ra = DIDScreenRect(a), rb = DIDScreenRect(b);
        BOOL oa = DIDRectOnScreen(ra), ob = DIDRectOnScreen(rb);
        if (oa != ob) return oa ? NSOrderedAscending : NSOrderedDescending;
        CGFloat aa = a.bounds.size.width * a.bounds.size.height;
        CGFloat bb = b.bounds.size.width * b.bounds.size.height;
        return aa > bb ? NSOrderedAscending : NSOrderedDescending;
    }];
    return out;
}

// 找某个红点应该归属的岛：先按屏幕矩形包含关系，再按最近距离
static UIView *DIDPillForDot(UIView *dot, CGPoint *centerOut) {
    CGRect dr = DIDScreenRect(dot);
    if (CGRectEqualToRect(dr, CGRectZero)) return nil;
    CGPoint dc = CGPointMake(CGRectGetMidX(dr), CGRectGetMidY(dr));

    UIView *best = nil;
    CGFloat bestDist = 1e9;
    for (UIView *pill in DIDPills()) {
        CGRect pr = DIDScreenRect(pill);
        if (CGRectEqualToRect(pr, CGRectZero)) continue;
        if (CGRectContainsPoint(CGRectInset(pr, -8, -8), dc)) {
            // 直接包含：优先级最高
            CGRect local = CGRectZero;
            @try { local = [dot convertRect:dot.bounds toView:pill]; } @catch (...) { continue; }
            if (centerOut) *centerOut = CGPointMake(CGRectGetMidX(local), CGRectGetMidY(local));
            return pill;
        }
        CGFloat dx = fabs(CGRectGetMidX(pr) - dc.x);
        CGFloat dy = fabs(CGRectGetMidY(pr) - dc.y);
        CGFloat d = dx + dy;
        if (d < bestDist && d < 120.0) { bestDist = d; best = pill; }
    }
    if (best) {
        CGRect local = CGRectZero;
        @try { local = [dot convertRect:dot.bounds toView:best]; } @catch (...) { return nil; }
        CGPoint c = CGPointMake(CGRectGetMidX(local), CGRectGetMidY(local));
        c.x = MAX(0, MIN(best.bounds.size.width, c.x));
        c.y = MAX(0, MIN(best.bounds.size.height, c.y));
        if (centerOut) *centerOut = c;
        return best;
    }
    return nil;
}

// 找岛内真正的红点（含 portal sourceView 反查）
static UIView *DIDDotInsidePill(UIView *pill) {
    // 1) 子树里直接就有红点
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:pill];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass(v.class) containsString:@"RecordingIndicator"]) {
            CGSize b = v.bounds.size;
            if (MAX(b.width, b.height) >= 1.5 && MAX(b.width, b.height) <= 26.0) return v;
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    // 2) portal.sourceView
    stack = [NSMutableArray arrayWithObject:pill];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass(v.class) containsString:@"Portal"]) {
            id src = nil;
            @try { src = [v valueForKey:@"sourceView"]; } @catch (...) { src = nil; }
            if ([src isKindOfClass:[UIView class]]) {
                UIView *sv = (UIView *)src;
                if ([NSStringFromClass(sv.class) containsString:@"Indicator"]) return sv;
            }
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return nil;
}

// 岛里的封面必须是尺寸合理的方形图；整屏大图（426x310 之类）一律排除
static UIImageView *DIDArtworkIn(UIView *pill) {
    CGSize limit = pill.bounds.size;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:pill];
    UIImageView *best = nil;
    CGFloat bestScore = -1;

    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)v;
            CGSize b = iv.bounds.size;
            if (iv.image && b.width >= 8 && b.height >= 8) {
                // 不能比岛大太多
                BOOL fits = b.width <= limit.width + 8.0 && b.height <= limit.height + 8.0;
                if (fits) {
                    BOOL artworkClass = [NSStringFromClass(v.class).lowercaseString containsString:@"artwork"];
                    // 越接近正方形、尺寸越接近岛高，越可能是封面
                    CGFloat squareness = 1.0 - fabs(b.width - b.height) / MAX(b.width, b.height);
                    CGFloat score = squareness * 2.0 + (artworkClass ? 1.0 : 0.0);
                    if (score > bestScore) { bestScore = score; best = iv; }
                }
            }
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return best;
}

#pragma mark - 贴图

static void DIDAttachEx(DIDSpriteView *sp, UIView *host, CGPoint center, CGFloat side, BOOL clampToHost) {
    if (!sp || !host || side < 3.0) return;
    if (sp.superview != host) {
        [sp removeFromSuperview];
        [host addSubview:sp];
    }
    if (host.subviews.lastObject != sp) [host bringSubviewToFront:sp];
    CGFloat half = side / 2.0;
    CGPoint c = center;
    if (clampToHost) {
        c.x = MAX(half, MIN(MAX(half, host.bounds.size.width - half), c.x));
        c.y = MAX(half, MIN(MAX(half, host.bounds.size.height - half), c.y));
    }
    CGRect want = CGRectMake(c.x - half, c.y - half, side, side);
    if (!CGRectEqualToRect(sp.frame, want)) [UIView performWithoutAnimation:^{ sp.frame = want; }];
    sp.hidden = NO;
    sp.alpha = 1.0;
}

static void DIDAttach(DIDSpriteView *sp, UIView *host, CGPoint center, CGFloat side) {
    DIDAttachEx(sp, host, center, side, YES);
}

static const void *kDotAlpha = &kDotAlpha;

// 录屏素材：最大 = 岛高，也就是系统独立岛那个圆的直径，正好一样大
static CGFloat DIDEyeSide(CGFloat configured, CGSize pill) {
    return MAX(MIN(configured, pill.height), 4.0);
}

// 跳舞素材：可略超岛高，但不超出岛宽
static CGFloat DIDSpriteSide(CGFloat configured, CGSize pill) {
    CGFloat side = MIN(configured, MAX(pill.height * 1.2, 12.0));
    side = MIN(side, MAX(pill.width, 12.0));
    return MAX(side, 4.0);
}

static void DIDRestoreDots(void) {
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        NSNumber *saved = objc_getAssociatedObject(v, kDotAlpha);
        if (saved) {
            v.alpha = saved.doubleValue;
            objc_setAssociatedObject(v, kDotAlpha, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}

#pragma mark - 录屏素材

static BOOL DIDPlaceEye(BOOL verbose) {
    if (!DIDEnabled() || !DIDEyeOn()) return NO;
    NSArray<UIImage *> *frames = DIDLoadFrames(1);
    if (frames.count == 0) return NO;

    NSArray<UIView *> *pills = DIDPills();
    NSArray<UIView *> *dots = DIDDots();

    // 优先级 1：红点能匹配到所属岛（单独录屏、独立岛）
    for (UIView *dot in dots) {
        CGPoint c = CGPointZero;
        UIView *pill = DIDPillForDot(dot, &c);
        if (!pill) continue;
        CGFloat side = DIDEyeSide(DIDFloat(@"eyeSize", 36.7, 10.0, 36.7), pill.bounds.size);
        DIDSpriteView *sp = DIDSpriteFor(1, pill) ?: DIDNewSprite(1);
        sp.didAnchor = dot;
        DIDAttach(sp, pill, c, side);
        [sp play:frames fps:DIDFloat(@"eyeFPS", 16.0, 2.0, 30.0)];
        if (!objc_getAssociatedObject(dot, kDotAlpha)) {
            objc_setAssociatedObject(dot, kDotAlpha, @(dot.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            dot.alpha = 0.02;
        }
        if (verbose) DIDLog(@"eye: dot->pill c={%.1f,%.1f} side=%.1f w=%.1f",
                            c.x, c.y, side, pill.bounds.size.width);
        return YES;
    }

    // 优先级 2：带 ScreenRecording 标记的岛
    for (UIView *pill in pills) {
        if (!DIDPillHasTag(pill, @"ScreenRecording", 4)) continue;

        CGPoint c = CGPointZero;
        BOOL hasCenter = NO;
        UIView *dot = DIDDotInsidePill(pill);
        if (dot) {
            CGRect local = CGRectZero;
            @try { local = [dot convertRect:dot.bounds toView:pill]; } @catch (...) {}
            if (local.size.width > 0.5 && local.size.height > 0.5) {
                c = CGPointMake(CGRectGetMidX(local), CGRectGetMidY(local));
                hasCenter = YES;
            }
            if (!objc_getAssociatedObject(dot, kDotAlpha)) {
                objc_setAssociatedObject(dot, kDotAlpha, @(dot.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                dot.alpha = 0.02;
            }
        }
        CGFloat pw = pill.bounds.size.width, ph = pill.bounds.size.height;
        if (!hasCenter) {
            // 没有可用的红点：宽岛说明录屏点被并进了大岛，系统把它放在最左端
            c = pw > ph * 2.0 ? CGPointMake(ph / 2.0, ph / 2.0)
                              : CGPointMake(pw / 2.0, ph / 2.0);
        }
        CGFloat side = DIDEyeSide(DIDFloat(@"eyeSize", 36.7, 10.0, 36.7), pill.bounds.size);
        DIDSpriteView *sp = DIDSpriteFor(1, pill) ?: DIDNewSprite(1);
        sp.didAnchor = dot ?: pill;
        DIDAttach(sp, pill, c, side);
        [sp play:frames fps:DIDFloat(@"eyeFPS", 16.0, 2.0, 30.0)];
        if (verbose) DIDLog(@"eye: tag->pill c={%.1f,%.1f} side=%.1f w=%.1f dot=%@",
                            c.x, c.y, side, pw, dot ? NSStringFromClass(dot.class) : @"none");
        return YES;
    }

    if (verbose) {
        DIDLog(@"eye fail: pills=%lu dots=%lu", (unsigned long)pills.count, (unsigned long)dots.count);
        for (UIView *p in pills)
            DIDLog(@"  pill id=%@ bounds=%@ scr=%@", p.accessibilityIdentifier ?: @"-",
                   NSStringFromCGRect(p.bounds), NSStringFromCGRect(DIDScreenRect(p)));
        for (UIView *d in dots)
            DIDLog(@"  dot %@ bounds=%@", NSStringFromClass(d.class), NSStringFromCGRect(d.bounds));
    }
    return NO;
}

#pragma mark - 跳舞素材

static BOOL DIDPlaceDance(BOOL verbose) {
    if (!DIDEnabled() || !DIDDanceOn()) return NO;
    NSArray<UIImage *> *frames = DIDLoadFrames(0);
    if (frames.count == 0) return NO;

    NSArray<UIView *> *pills = DIDPills();
    UIView *bestPill = nil;
    UIImageView *bestArt = nil;
    BOOL bestTagged = NO;

    for (UIView *pill in pills) {
        UIImageView *art = DIDArtworkIn(pill);
        if (!art) continue;
        // 暂停时封面会被收起，跳过，避免素材压住暂停按钮
        if (art.bounds.size.height < 16 || art.hidden || art.alpha < 0.2) continue;
        BOOL tagged = DIDPillHasTag(pill, @"NowPlaying", 3);
        if (bestPill && bestTagged && !tagged) continue;
        bestPill = pill; bestArt = art; bestTagged = tagged;
        if (tagged) break;
    }
    if (!bestPill) {
        if (verbose) {
            DIDLog(@"dance fail: pills=%lu", (unsigned long)pills.count);
            for (UIView *p in pills) {
                UIImageView *a = DIDArtworkIn(p);
                DIDLog(@"  pill id=%@ w=%.1f h=%.1f art=%@ size=%@",
                       p.accessibilityIdentifier ?: @"-", p.bounds.size.width, p.bounds.size.height,
                       a ? NSStringFromClass(a.class) : @"none",
                       a ? NSStringFromCGSize(a.bounds.size) : @"-");
            }
        }
        return NO;
    }

    CGRect ar = CGRectZero;
    @try { ar = [bestArt convertRect:bestArt.bounds toView:bestPill]; } @catch (...) { return NO; }
    CGSize ps = bestPill.bounds.size;
    CGFloat side = DIDSpriteSide(DIDFloat(@"danceSize", 22.0, 6.0, 48.0), ps);
    CGFloat offX = DIDFloat(@"danceOffsetX", 0.0, -200.0, 200.0);
    CGFloat offY = DIDFloat(@"danceOffsetY", 0.0, -60.0, 60.0);

    CGPoint c;
    if (ps.width > ps.height * 2.0) {
        // 宽岛：封面贴着一端，素材放另一端
        BOOL artOnLeft = CGRectGetMidX(ar) < ps.width / 2.0;
        c = CGPointMake(artOnLeft ? ps.width - side / 2.0 - 1.0 : side / 2.0 + 1.0,
                        ps.height / 2.0);
    } else {
        // 圆形小岛：放右下外侧
        c = CGPointMake(ps.width - side / 2.0 - 1.0, ps.height - side / 2.0 - 1.0);
    }
    c.x += offX;
    c.y += offY;

    DIDSpriteView *sp = DIDSpriteFor(0, bestPill) ?: DIDNewSprite(0);
    sp.didAnchor = bestArt;
    DIDAttach(sp, bestPill, c, side);
    [sp play:frames fps:DIDFloat(@"danceFPS", 12.0, 2.0, 30.0)];
    if (verbose) DIDLog(@"dance: w=%.1f art=%@ c={%.1f,%.1f} side=%.1f",
                        ps.width, NSStringFromClass(bestArt.class), c.x, c.y, side);
    return YES;
}

#pragma mark - 清理

static void DIDReapSprites(void) {
    BOOL captureOn = [UIScreen mainScreen].isCaptured;
    BOOL eyeAllowed = DIDEnabled() && DIDEyeOn() && captureOn;

    for (DIDSpriteView *sp in gSprites.allObjects) {
        BOOL keep;
        if (sp.didKind == 1) {
            keep = eyeAllowed;
        } else {
            keep = DIDEnabled() && DIDDanceOn();
            // 封面收起（暂停）或消失时不留素材
            UIView *anchor = sp.didAnchor;
            keep = keep && anchor && anchor.window && !anchor.hidden
                && anchor.bounds.size.height >= 16 && sp.superview != nil;
        }
        if (!keep) {
            [sp halt];
            [sp removeFromSuperview];
        }
    }
    if (!eyeAllowed) DIDRestoreDots();
}

#pragma mark - 旋转

static CALayer *DIDMaskLayer(CGSize size, NSString *folder) {
    if (!DIDMaskOn()) return nil;
    if (folder.length == 0) folder = DIDDefaultTheme(2);
    NSString *path = DIDMaskPath(folder);
    UIImage *mask = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!mask.CGImage) return nil;

    static NSMutableDictionary<NSString *, CALayer *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    NSString *key = [NSString stringWithFormat:@"%@|%.0fx%.0f", path, size.width, size.height];
    if (cache[key]) return cache[key];

    CALayer *layer = [CALayer layer];
    layer.frame = CGRectMake(0, 0, size.width, size.height);
    layer.contentsGravity = kCAGravityResize;
    layer.contents = (__bridge id)mask.CGImage;
    cache[key] = layer;
    return layer;
}

static void DIDApplyRotation(UIView *art, BOOL playing) {
    (void)playing;
    if (!DIDRotationOn() || !DIDEnabled()) return;
    if (!art.window || art.bounds.size.width < 12) return;
    CGFloat side = MIN(art.bounds.size.width, art.bounds.size.height);
    CALayer *l = art.layer;
    if (fabs(l.cornerRadius - side / 2.0) > 0.5) l.cornerRadius = side / 2.0;
    if (!l.masksToBounds) l.masksToBounds = YES;

    CALayer *mask = DIDMaskLayer(art.bounds.size, DIDString(@"selectedMaskFolder"));
    if (mask && l.mask != mask) l.mask = mask;
    if (!mask && l.mask) l.mask = nil;

    if (![l animationForKey:@"did.rot"]) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        a.fromValue = @0; a.toValue = @(M_PI * 2);
        a.duration = 6.0 / DIDFloat(@"rotationSpeed", 0.6, 0.1, 4.0);
        a.repeatCount = HUGE_VALF;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        a.removedOnCompletion = NO;
        [l addAnimation:a forKey:@"did.rot"];
    }
}

// 旋转只在"封面可见"时保留：暂停时系统把封面收起，自然就不转了，
// 不依赖媒体通知（那套通知在部分机型上收不到）。
static void DIDSyncRotation(BOOL force) {
    (void)force;
    if (!DIDEnabled() || !DIDRotationOn()) {
        NSMutableArray<UIView *> *stack = [NSMutableArray array];
        for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            if ([v.layer animationForKey:@"did.rot"]) [v.layer removeAnimationForKey:@"did.rot"];
            for (UIView *s in v.subviews) [stack addObject:s];
        }
        return;
    }

    NSMutableSet<UIView *> *live = [NSMutableSet set];
    for (UIView *pill in DIDPills()) {
        UIImageView *art = DIDArtworkIn(pill);
        if (!art) continue;
        if (art.bounds.size.height < 16 || art.hidden || art.alpha < 0.2) continue;
        [live addObject:art];
        DIDApplyRotation(art, YES);
    }
    // 不在 live 里的旧动画清掉
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v.layer animationForKey:@"did.rot"] && ![live containsObject:v])
            [v.layer removeAnimationForKey:@"did.rot"];
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}

#pragma mark - 扫描

static void DIDScan(BOOL verbose) {
    if (!DIDEnabled()) {
        DIDPurgeSprites();
        DIDRestoreDots();
        DIDSyncRotation(NO);
        return;
    }
    BOOL captureOn = [UIScreen mainScreen].isCaptured;
    if (captureOn) @try { DIDPlaceEye(verbose); } @catch (...) {}
    @try { DIDPlaceDance(verbose); } @catch (...) {}
    @try { DIDReapSprites(); } @catch (...) {}
    @try { DIDSyncRotation(NO); } @catch (...) {}
}

static void DIDScanSoon(double delay, BOOL verbose) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ @try { DIDScan(verbose); } @catch (...) {} });
}

#pragma mark - Hooks

%hook SBSystemApertureContainerView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
    @try {
        UIView *pill = (UIView *)self;
        if (pill.bounds.size.width < 18 || pill.bounds.size.width > 320) return;
        if (pill.bounds.size.height < 14 || pill.bounds.size.height > 90) return;
        if ([UIScreen mainScreen].isCaptured) DIDPlaceEye(NO);
        DIDPlaceDance(NO);
    } @catch (...) {}
}

%end

%hook SBRecordingIndicatorView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled() || ![UIScreen mainScreen].isCaptured) return;
    dispatch_async(dispatch_get_main_queue(), ^{ @try { DIDPlaceEye(NO); } @catch (...) {} });
}

%end

%hook MRUArtworkView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled() || !DIDRotationOn()) return;
    @try {
        UIView *art = (UIView *)self;
        if (art.bounds.size.height >= 16) DIDApplyRotation(art, YES);
    } @catch (...) {}
}

%end

#pragma mark - 媒体通知

// 只用来触发重扫，播放/暂停的判断交给"封面是否可见"
static void DIDObservePlayback(void) {
    void (^handler)(NSNotification *) = ^(NSNotification *n) {
        (void)n;
        DIDScanSoon(0.08, NO);
    };
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"_MRMediaRemoteNowPlayingInfoDidChange",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:handler];
    }
}

#pragma mark - 设置变更

static NSInteger gSettingsTicket = 0;
static void DIDApplySettingsNow(void);

static void DIDApplySettings(void) {
    // 滑块拖动会连发通知，合并成一次
    NSInteger ticket = ++gSettingsTicket;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (ticket != gSettingsTicket) return;
        @try { DIDApplySettingsNow(); } @catch (...) {}
    });
}

static void DIDApplySettingsNow(void) {
    DIDReloadPrefs(YES);
    DIDClearFrameCache();
    gFloatCache = nil; gFloatAt = -1e9;
    DIDLog(@"settings changed");
    dispatch_async(dispatch_get_main_queue(), ^{
        // 先清掉旧素材，再按新设置重贴：尺寸/位置/素材名立即生效
        @try { DIDPurgeSprites(); } @catch (...) {}
        @try { DIDRestoreDots(); } @catch (...) {}
        @try { DIDSyncRotation(NO); } @catch (...) {}
        if (!DIDEnabled()) return;
        DIDScan(NO);
    });
}

#pragma mark - ctor

%ctor {
    @autoreleasepool {
        DIDLog(@"===== DynamicIslandDance v%@ loaded (pid %d) =====", DIDVersion, getpid());

        int token = 0;
        notify_register_dispatch(DIDPrefNotify, &token, dispatch_get_main_queue(), ^(__unused int t) {
            DIDApplySettings();
        });

        DIDObservePlayback();

        [[NSNotificationCenter defaultCenter] addObserverForName:UIScreenCapturedDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            BOOL captured = [UIScreen mainScreen].isCaptured;
            DIDLog(@"capture -> %d", captured);
            if (!captured) {
                DIDPurgeSprites();
                DIDRestoreDots();
            }
            DIDScanSoon(0.10, YES);
            DIDScanSoon(0.45, NO);
            DIDScanSoon(0.95, NO);
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            DIDScanSoon(0.30, NO);
        }];

        DIDScanSoon(1.5, NO);
    }
}