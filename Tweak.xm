// DynamicIslandDance — 灵动岛跳舞（纯净自研版）
// 素材跟随系统红点 / 专辑封面；全自研代码，无联网、无指纹、无授权校验。

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdio.h>

static NSString *const DIDVersion     = @"2.1.0";
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

static NSDictionary *gPrefs;
static NSTimeInterval gPrefsAt = -1e9;

static void DIDReloadPrefs(BOOL force) {
    NSTimeInterval now = CACurrentMediaTime();
    if (!force && gPrefs && now - gPrefsAt < 1.0) return;
    gPrefsAt = now;
    gPrefs = [NSDictionary dictionaryWithContentsOfFile:DIDPrefPath] ?: @{};
}

static BOOL DIDBool(NSString *key, BOOL fallback) {
    DIDReloadPrefs(NO);
    id v = gPrefs[key];
    return v ? [v boolValue] : fallback;
}

static CGFloat DIDFloat(NSString *key, CGFloat fallback, CGFloat lo, CGFloat hi) {
    DIDReloadPrefs(NO);
    id v = gPrefs[key];
    return MAX(lo, MIN(hi, v ? [v doubleValue] : fallback));
}

static NSString *DIDString(NSString *key) {
    DIDReloadPrefs(NO);
    id v = gPrefs[key];
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
static BOOL DIDSpriteOn(void)   { return DIDBool(@"enableSprite", YES); }
static BOOL DIDRotationOn(void) { return DIDBool(@"enableAlbumRotation", YES); }
static BOOL DIDMaskOn(void)     { return DIDBool(@"enableMaskLayer", YES); }
static BOOL DIDReshapeOn(void)  { return DIDBool(@"enableIOS17Adaptation", NO); }
static BOOL DIDEyeOn(void)      { return DIDBool(@"enableEyeSprite", YES); }
static BOOL DIDDanceOn(void)    { return DIDBool(@"enableDanceSprite", YES); }
static BOOL DIDHideDot(void)    { return DIDBool(@"hideNativeDot", YES); }

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
                                  : kind == 1 ? @[@"sharingan", @"pulse"] : @[@"circle", @"squircle"];
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
    DIDLog(@"load %@ frames=%@ count=%lu", DIDKindName(kind), folder, (unsigned long)images.count);
    return result;
}

static void DIDClearFrameCache(void) {
    gFramesDance = nil; gFramesEye = nil;
    gKeyDance = nil; gKeyEye = nil;
}

#pragma mark - 精灵视图

@interface DIDSpriteView : UIImageView
@property (nonatomic, assign) NSInteger didKind;
@property (nonatomic, weak) UIView *didConditionView;   // 素材依附的条件视图（红点 / 封面）
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

// 全局登记所有精灵：清理时不再依赖宿主类名，任何残留都能找到并移除
static NSHashTable *gSprites;      // DIDSpriteView，弱引用

static void DIDRegisterSprite(DIDSpriteView *sp) {
    if (!gSprites) gSprites = [NSHashTable weakObjectsHashTable];
    if (sp) [gSprites addObject:sp];
}

static void DIDPurgeAllSprites(void) {
    for (DIDSpriteView *sp in gSprites.allObjects) {
        [sp halt];
        [sp removeFromSuperview];
    }
    [gSprites removeAllObjects];
}

#pragma mark - 窗口与视图查找

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

// 视图在屏幕坐标系里的矩形；离屏（右侧 x≈415 那种副本）会被判定为不可用
static BOOL DIDOnScreen(UIView *v) {
    if (!v || !v.window || v.hidden || v.alpha < 0.05) return NO;
    CGRect r = CGRectZero;
    @try { r = [v convertRect:v.bounds toView:nil]; } @catch (...) { return NO; }
    if (r.size.width < 1 || r.size.height < 1) return NO;
    CGRect screen = DIDScreenBounds();
    return CGRectGetMinX(r) >= -8 && CGRectGetMaxX(r) <= screen.size.width + 8
        && CGRectGetMinY(r) >= -8 && CGRectGetMaxY(r) <= screen.size.height + 8;
}

static NSArray<UIView *> *DIDCollectViews(NSString *token) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass(v.class) containsString:token] && DIDOnScreen(v)) [out addObject:v];
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return out;
}

static UIView *DIDContainerFor(UIView *v) {
    for (UIView *cur = v; cur; cur = cur.superview) {
        NSString *cls = NSStringFromClass(cur.class);
        if ([cls isEqualToString:@"SBSystemApertureContainerView"] ||
            [cls containsString:@"ApertureSceneElementAccessoryView"] ||
            [cls containsString:@"SAUIProvidedViewContainerView"]) return cur;
    }
    return nil;
}

static BOOL DIDTagInSubtree(UIView *root, NSString *token, NSInteger depth) {
    if (!root || depth < 0) return NO;
    NSString *ident = root.accessibilityIdentifier;
    if ([ident isKindOfClass:[NSString class]] && [ident containsString:token]) return YES;
    for (UIView *s in root.subviews) if (DIDTagInSubtree(s, token, depth - 1)) return YES;
    return NO;
}

static UIImageView *DIDArtworkIn(UIView *root) {
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    UIImageView *fallback = nil;
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)v;
            if (iv.image && iv.bounds.size.width >= 8 && iv.bounds.size.height >= 8) {
                if ([NSStringFromClass(v.class).lowercaseString containsString:@"artwork"]) return iv;
                if (!fallback) fallback = iv;
            }
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return fallback;
}

#pragma mark - 精灵贴放

static void DIDAttach(DIDSpriteView *sp, UIView *host, CGPoint center, CGFloat side) {
    if (!sp || !host || side < 3.0) return;
    if (sp.superview != host) {
        [sp removeFromSuperview];
        [host addSubview:sp];
    }
    if (host.subviews.lastObject != sp) [host bringSubviewToFront:sp];

    CGFloat half = side / 2.0;
    CGPoint c = center;
    c.x = MAX(half, MIN(MAX(half, host.bounds.size.width - half), c.x));
    c.y = MAX(half, MIN(MAX(half, host.bounds.size.height - half), c.y));
    CGRect want = CGRectMake(c.x - half, c.y - half, side, side);
    if (!CGRectEqualToRect(sp.frame, want)) {
        [UIView performWithoutAnimation:^{ sp.frame = want; }];
    }
    sp.hidden = NO;
    sp.alpha = 1.0;
}

static const void *kDotAlpha = &kDotAlpha;

#pragma mark - 录屏：跟随系统红点

static NSArray<UIView *> *DIDRecordingDots(void) {
    NSMutableArray<UIView *> *dots = [NSMutableArray array];
    for (UIView *v in DIDCollectViews(@"RecordingIndicator")) {
        CGSize b = v.bounds.size;
        CGFloat m = MAX(b.width, b.height);
        // 真正的红点只有 3~24pt；窗口/容器都远大于这个值
        if (m < 2.0 || m > 24.0) continue;
        if (!DIDContainerFor(v)) continue;
        [dots addObject:v];
    }
    [dots sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat aa = a.bounds.size.width * a.bounds.size.height;
        CGFloat bb = b.bounds.size.width * b.bounds.size.height;
        if (aa > bb) return NSOrderedAscending;
        if (aa < bb) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return dots;
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

static BOOL DIDPlaceEye(void) {
    if (!DIDEnabled() || !DIDSpriteOn() || !DIDEyeOn()) return NO;
    NSArray<UIImage *> *frames = DIDLoadFrames(1);
    if (frames.count == 0) return NO;

    for (UIView *dot in DIDRecordingDots()) {
        UIView *host = DIDContainerFor(dot);
        if (!host || !DIDOnScreen(host)) continue;
        if (host.bounds.size.height < 14 || host.bounds.size.width < 14) continue;

        CGRect r = CGRectZero;
        @try { r = [dot convertRect:dot.bounds toView:host]; } @catch (...) { continue; }
        if (r.size.width < 1 || r.size.height < 1) continue;

        // 圆心必须落在宿主内，否则是离屏副本
        CGPoint c = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
        if (c.x < 0 || c.x > host.bounds.size.width || c.y < 0 || c.y > host.bounds.size.height) continue;

        CGFloat configured = DIDFloat(@"eyeAnimationSize", 22.0, 6.0, 48.0);
        CGFloat side = MIN(configured, host.bounds.size.height);

        DIDSpriteView *sp = nil;
        for (DIDSpriteView *cand in gSprites.allObjects) {
            if (cand.didKind != 1) continue;
            if (cand.superview == host && !sp) { sp = cand; continue; }
            if (cand.superview != host) { [cand halt]; [cand removeFromSuperview]; }
        }
        if (!sp) {
            sp = [[DIDSpriteView alloc] initWithFrame:CGRectZero];
            sp.didKind = 1;
            DIDRegisterSprite(sp);
        }
        sp.didConditionView = dot;
        DIDAttach(sp, host, c, side);
        [sp play:frames fps:DIDFloat(@"eyeFrameRate", 12.0, 2.0, 30.0)];

        if (DIDHideDot() && !objc_getAssociatedObject(dot, kDotAlpha)) {
            objc_setAssociatedObject(dot, kDotAlpha, @(dot.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            dot.alpha = 0.02;
        }
        return YES;
    }
    return NO;
}

#pragma mark - 音乐：跟随专辑封面

static BOOL DIDPlaceDance(void) {
    if (!DIDEnabled() || !DIDSpriteOn() || !DIDDanceOn()) return NO;
    NSArray<UIImage *> *frames = DIDLoadFrames(0);
    if (frames.count == 0) return NO;

    for (UIView *host in DIDCollectViews(@"SystemApertureContainerView")) {
        if (host.bounds.size.width < 30 || host.bounds.size.height < 16) continue;
        if (!DIDTagInSubtree(host, @"NowPlaying", 3)) continue;
        UIImageView *art = DIDArtworkIn(host);
        if (!art || !DIDOnScreen(art)) continue;
        // 暂停时封面被系统收起，这时不贴素材，避免压住暂停按钮
        if (art.bounds.size.height < 16 || art.hidden || art.alpha < 0.2) continue;

        CGFloat configured = DIDFloat(@"danceAnimationSize", 22.0, 6.0, 48.0);
        CGFloat side = MIN(configured, host.bounds.size.height);
        CGRect ar = CGRectZero;
        @try { ar = [art convertRect:art.bounds toView:host]; } @catch (...) { continue; }

        CGPoint c = CGPointMake(CGRectGetMaxX(ar) + side / 2.0 + 2.0, CGRectGetMidY(ar));
        if (c.x + side / 2.0 > host.bounds.size.width) {
            c.x = CGRectGetMinX(ar) - side / 2.0 - 2.0;
        }

        DIDSpriteView *sp = nil;
        for (DIDSpriteView *cand in gSprites.allObjects) {
            if (cand.didKind != 0) continue;
            if (cand.superview == host && !sp) { sp = cand; continue; }
            if (cand.superview != host) { [cand halt]; [cand removeFromSuperview]; }
        }
        if (!sp) {
            sp = [[DIDSpriteView alloc] initWithFrame:CGRectZero];
            sp.didKind = 0;
            DIDRegisterSprite(sp);
        }
        sp.didConditionView = art;
        DIDAttach(sp, host, c, side);
        [sp play:frames fps:DIDFloat(@"danceFrameRate", 12.0, 2.0, 30.0)];
        return YES;
    }
    return NO;
}

#pragma mark - 素材生命周期

// 只保留"依附条件仍然成立"的精灵，其余全部移除
static void DIDReapSprites(void) {
    BOOL captureOn = [UIScreen mainScreen].isCaptured;
    BOOL eyeAllowed = DIDEnabled() && DIDSpriteOn() && DIDEyeOn() && captureOn;
    BOOL danceAllowed = DIDEnabled() && DIDSpriteOn() && DIDDanceOn();

    for (DIDSpriteView *sp in gSprites.allObjects) {
        BOOL keep = NO;
        if (sp.didKind == 1) keep = eyeAllowed;
        else if (sp.didKind == 0) keep = danceAllowed;

        if (keep && sp.didConditionView && DIDOnScreen(sp.didConditionView) && sp.superview) {
            // 条件视图还在，素材也在宿主里，继续保留
            continue;
        }
        keep = NO;

        if (!keep) {
            [sp halt];
            [sp removeFromSuperview];
        }
    }
    if (!eyeAllowed) DIDRestoreDots();
}

#pragma mark - 专辑封面旋转

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

static void DIDApplyRotation(UIView *art) {
    if (!DIDRotationOn() || !DIDEnabled()) return;
    if (!DIDOnScreen(art) || art.bounds.size.width < 12) return;
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
        a.duration = 6.0 / DIDFloat(@"albumRotationSpeed", 0.6, 0.1, 4.0);
        a.repeatCount = HUGE_VALF;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        a.removedOnCompletion = NO;
        [l addAnimation:a forKey:@"did.rot"];
    }
}

// 只有正在播放的岛才转；其余一律清掉动画，避免暂停后还在转
static void DIDSyncRotation(BOOL playing) {
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v.layer animationForKey:@"did.rot"]) [v.layer removeAnimationForKey:@"did.rot"];
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    if (!playing || !DIDRotationOn() || !DIDEnabled()) return;

    for (UIView *host in DIDCollectViews(@"SystemApertureContainerView")) {
        if (!DIDTagInSubtree(host, @"NowPlaying", 3)) continue;
        UIImageView *art = DIDArtworkIn(host);
        if (art) DIDApplyRotation(art);
    }
}

#pragma mark - 岛形

static BOOL gInSetFrame = NO;

// 只圆化紧凑小岛；绝不动展开态宽度，否则会把音乐/录屏两个容器压到一起（粘住）
static CGRect DIDReshapedFrame(UIView *container, CGRect frame) {
    if (!DIDEnabled() || !DIDReshapeOn()) return frame;
    CGFloat w = frame.size.width, h = frame.size.height;
    if (w < 18.0 || w > 50.0) return frame;
    if (h < 26.0 || h > 46.0) return frame;
    CGFloat side = MAX(h, 36.6667);
    if (fabs(w - side) < 0.5) return frame;
    return CGRectMake(CGRectGetMidX(frame) - side / 2.0, frame.origin.y, side, side);
}

#pragma mark - 扫描

static void DIDScan(void) {
    BOOL captureOn = [UIScreen mainScreen].isCaptured;

    if (!DIDEnabled()) {
        DIDPurgeAllSprites();
        DIDRestoreDots();
        DIDSyncRotation(NO);
        return;
    }
    if (captureOn) {
        @try {
            BOOL ok = DIDPlaceEye();
            static NSTimeInterval lastLog = 0;
            NSTimeInterval now = CACurrentMediaTime();
            if (now - lastLog > 2.0) {
                lastLog = now;
                DIDLog(@"capture scan: dots=%lu placed=%d sprites=%lu",
                       (unsigned long)DIDRecordingDots().count, ok, (unsigned long)gSprites.allObjects.count);
            }
        } @catch (...) {}
    }
    @try { DIDPlaceDance(); } @catch (...) {}
    @try { DIDReapSprites(); } @catch (...) {}
    @try { DIDSyncRotation(captureOn || DIDBool(@"alwaysRotate", NO)); } @catch (...) {}
}

#pragma mark - Hooks

%hook SBSystemApertureContainerView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
    @try {
        if (self.bounds.size.width < 16 || self.bounds.size.height < 14) return;
        if ([UIScreen mainScreen].isCaptured) DIDPlaceEye();
        DIDPlaceDance();
    } @catch (...) {}
}

- (void)setFrame:(CGRect)frame {
    CGRect target = frame;
    if (!gInSetFrame) @try { target = DIDReshapedFrame((UIView *)self, frame); } @catch (...) {}
    gInSetFrame = YES;
    %orig(target);
    gInSetFrame = NO;
}

%end

%hook SBRecordingIndicatorView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
    dispatch_async(dispatch_get_main_queue(), ^{ @try { DIDPlaceEye(); } @catch (...) {} });
}

%end

%hook MRUArtworkView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled() || !DIDRotationOn()) return;
    @try { DIDApplyRotation((UIView *)self); } @catch (...) {}
}

%end

#pragma mark - 设置变更

static void DIDApplySettings(void) {
    DIDReloadPrefs(YES);
    DIDClearFrameCache();
    DIDLog(@"settings changed");
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!DIDEnabled()) {
            DIDPurgeAllSprites();
            DIDRestoreDots();
            DIDSyncRotation(NO);
            return;
        }
        DIDScan();
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

        [[NSNotificationCenter defaultCenter] addObserverForName:UIScreenCapturedDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            BOOL captured = [UIScreen mainScreen].isCaptured;
            DIDLog(@"capture -> %d", captured);
            if (!captured) {
                // 立刻清掉录屏素材，不等扫描
                DIDPurgeAllSprites();
                DIDRestoreDots();
                DIDSyncRotation(NO);
            }
            for (double d = 0.05; d < 1.2; d += 0.25) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{ @try { DIDScan(); } @catch (...) {} });
            }
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ @try { DIDScan(); } @catch (...) {} });
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ @try { DIDScan(); } @catch (...) {} });
    }
}