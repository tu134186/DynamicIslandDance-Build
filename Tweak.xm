// DynamicIslandDance — 灵动岛跳舞（纯净自研版）
// 录屏素材跟随系统红点、跳舞素材跟随专辑封面，全部为自研代码，无联网/无指纹/无授权校验。

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdio.h>

static NSString *const DIDVersion     = @"2.0.0";
static NSString *const DIDPrefPath    = @"/var/mobile/Library/Preferences/com.minis.didance.plist";
static const char *     DIDPrefNotify = "com.minis.didance.changed";
static NSString *const DIDDefaultRoot = @"/var/mobile/DynamicIsland";
static NSString *const DIDLogPath     = @"/var/mobile/DynamicIslandDance.log";

#pragma mark - 日志

static void DIDLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[%.3f] %@\n", CFAbsoluteTimeGetCurrent(), msg];
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
    CGFloat f = v ? [v doubleValue] : fallback;
    return MAX(lo, MIN(hi, f));
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

static BOOL DIDEnabled(void)          { return DIDBool(@"shouldEnableCustomUI", YES); }
static BOOL DIDSpriteOn(void)         { return DIDBool(@"enableSprite", YES); }
static BOOL DIDRotationOn(void)       { return DIDBool(@"enableAlbumRotation", YES); }
static BOOL DIDMaskOn(void)           { return DIDBool(@"enableMaskLayer", YES); }
static BOOL DIDReshapeOn(void)        { return DIDBool(@"enableIOS17Adaptation", YES); }
static BOOL DIDEyeOn(void)            { return DIDBool(@"enableEyeSprite", YES); }
static BOOL DIDDanceOn(void)          { return DIDBool(@"enableDanceSprite", YES); }

static CGFloat DIDRotationPeriod(void) {
    CGFloat speed = DIDFloat(@"albumRotationSpeed", 0.6, 0.05, 4.0);
    return 6.0 / speed;
}

#pragma mark - 素材文件

static NSString *DIDKindName(NSInteger kind) {
    return kind == 0 ? @"dance" : (kind == 1 ? @"eye" : @"mask");
}

static NSArray<NSString *> *DIDBundledRoots(void) {
    return @[@"/var/jb/Library/Application Support/DynamicIslandDance",
             @"/Library/Application Support/DynamicIslandDance"];
}

static NSString *DIDBundledRoot(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *root in DIDBundledRoots()) {
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
    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *n in names) {
        if ([n hasPrefix:@"."] || !DIDFileIsImage(n)) continue;
        [files addObject:n];
    }
    NSMutableArray<NSString *> *replay = [NSMutableArray array];
    for (NSString *n in files) {
        if ([n.lowercaseString hasPrefix:@"replay"]) [replay addObject:n];
    }
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

static NSArray<UIImage *> *gFramesDance;
static NSArray<UIImage *> *gFramesEye;
static NSString *gKeyDance;
static NSString *gKeyEye;

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
    DIDLog(@"load %@ frames folder=%@ count=%lu", DIDKindName(kind), folder, (unsigned long)images.count);
    return result;
}

static void DIDClearFrameCache(void) {
    gFramesDance = nil; gFramesEye = nil;
    gKeyDance = nil; gKeyEye = nil;
}

#pragma mark - 逐帧视图

@interface DIDSpriteView : UIImageView
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

// 从任意视图向上找像素级容器（系统每个 element 都有自己的 container）
static UIView *DIDContainerFor(UIView *v) {
    for (UIView *cur = v; cur; cur = cur.superview) {
        if ([NSStringFromClass(cur.class) isEqualToString:@"SBSystemApertureContainerView"]) return cur;
        if ([NSStringFromClass(cur.class) isEqualToString:@"SBSystemApertureSceneElementAccessoryView"]) return cur;
    }
    return nil;
}

// 遍历整棵视图树，收集类名包含 token 的可见视图
static NSArray<UIView *> *DIDCollectViews(NSString *token) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass(v.class) containsString:token] && v.window && !v.hidden && v.alpha > 0.01)
            [out addObject:v];
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return out;
}

// 在子树里按类名前缀找第一个有图像内容的 UIImageView
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

static BOOL DIDNearPlaybackCaption(UIView *v, NSInteger depth) {
    if (depth < 0 || !v) return NO;
    NSString *ident = v.accessibilityIdentifier;
    if ([ident isKindOfClass:[NSString class]]) {
        for (NSString *t in @[@"NowPlaying", @"Artwork", @"MediaControls", @"Playback"]) {
            if ([ident containsString:t]) return YES;
        }
    }
    for (UIView *s in v.subviews) if (DIDNearPlaybackCaption(s, depth - 1)) return YES;
    return NO;
}

#pragma mark - 精灵挂载

static const void *kDanceSprite  = &kDanceSprite;
static const void *kEyeSprite    = &kEyeSprite;
static const void *kEyeDotRef    = &kEyeDotRef;
static const void *kDanceArtRef  = &kDanceArtRef;

static DIDSpriteView *DIDEnsureSprite(UIView *host, const void *key) {
    DIDSpriteView *sp = objc_getAssociatedObject(host, key);
    if (!sp) {
        sp = [[DIDSpriteView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(host, key, sp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return sp;
}

// 把精灵贴到 host 内、以 localCenter 为中心、边长为 side
static void DIDAttach(DIDSpriteView *sp, UIView *host, CGPoint localCenter, CGFloat side) {
    if (!sp || !host) return;
    if (side < 2.0) return;
    if (sp.superview != host) {
        [sp removeFromSuperview];
        [host addSubview:sp];
    }
    if (host.subviews.lastObject != sp) [host bringSubviewToFront:sp];

    CGFloat half = side / 2.0;
    CGPoint c = localCenter;
    c.x = MAX(half, MIN(MAX(half, host.bounds.size.width - half), c.x));
    c.y = MAX(half, MIN(MAX(half, host.bounds.size.height - half), c.y));
    CGRect want = CGRectMake(c.x - half, c.y - half, side, side);
    if (!CGRectEqualToRect(sp.frame, want)) {
        [UIView performWithoutAnimation:^{ sp.frame = want; }];
    }
    if (sp.hidden) sp.hidden = NO;
    if (sp.alpha < 0.99) sp.alpha = 1.0;
}

#pragma mark - 录屏：跟随系统红点

// 系统红点：SBRecordingIndicatorView 及其内部实现类；只取最外层，避免重复计入
static NSArray<UIView *> *DIDRecordingDots(void) {
    NSArray<UIView *> *all = DIDCollectViews(@"RecordingIndicator");
    NSMutableArray<UIView *> *dots = [NSMutableArray array];
    for (UIView *v in all) {
        BOOL nested = NO;
        for (UIView *other in all) {
            if (other != v && [v isDescendantOfView:other]) { nested = YES; break; }
        }
        if (!nested) [dots addObject:v];
    }
    return dots;
}

// 找到红点所在的容器，返回容器与该点在容器坐标系里的中心
static BOOL DIDDotPlacement(UIView *dot, UIView **hostOut, CGPoint *centerOut, CGFloat *dotSideOut) {
    if (!dot || !dot.window || dot.hidden || dot.alpha < 0.05) return NO;
    UIView *host = DIDContainerFor(dot);
    if (!host) host = dot.superview;
    if (!host) return NO;

    CGRect r = CGRectZero;
    @try {
        r = [dot convertRect:dot.bounds toView:host];
    } @catch (...) { return NO; }
    if (r.size.width < 2 || r.size.height < 2) {
        @try { r = [dot convertRect:dot.frame toView:host]; } @catch (...) { return NO; }
    }
    if (r.size.width < 2 || r.size.height < 2) return NO;

    *hostOut = host;
    *centerOut = CGPointMake(CGRectGetMidX(r), CGRectGetMidY(r));
    *dotSideOut = MAX(CGRectGetWidth(r), CGRectGetHeight(r));
    return YES;
}

static void DIDPlaceEyeSprite(void) {
    if (!DIDEnabled() || !DIDSpriteOn() || !DIDEyeOn()) return;
    NSArray<UIImage *> *frames = DIDLoadFrames(1);
    if (frames.count == 0) return;

    NSArray<UIView *> *dots = DIDRecordingDots();
    if (dots.count == 0) return;

    UIView *best = nil; UIView *bestHost = nil; CGPoint bestCenter = CGPointZero; CGFloat bestSide = 0;
    for (UIView *dot in dots) {
        UIView *host = nil; CGPoint c = CGPointZero; CGFloat side = 0;
        if (!DIDDotPlacement(dot, &host, &c, &side)) continue;
        // 只认有实际尺寸的容器
        if (host.bounds.size.height < 16 || host.bounds.size.width < 16) continue;
        best = dot; bestHost = host; bestCenter = c; bestSide = side;
        break;
    }
    if (!best) return;

    CGFloat configured = DIDFloat(@"eyeAnimationSize", 22.0, 4.0, 64.0);
    CGFloat side = MIN(configured, bestHost.bounds.size.height);
    DIDSpriteView *sp = DIDEnsureSprite(bestHost, kEyeSprite);
    DIDAttach(sp, bestHost, bestCenter, side);
    CGFloat fps = DIDFloat(@"eyeFrameRate", 12.0, 1.0, 60.0);
    [sp play:frames fps:fps];

    // 记录"这块宿主的素材归属这个红点"，红点消失时据此清理
    objc_setAssociatedObject(bestHost, kEyeDotRef, best, OBJC_ASSOCIATION_ASSIGN);

    // 盖住系统红点，避免素材旁边露出原色圆点
    if (DIDBool(@"hideNativeDot", YES)) {
        static const void *kDotAlpha = &kDotAlpha;
        NSNumber *saved = objc_getAssociatedObject(best, kDotAlpha);
        if (!saved) {
            objc_setAssociatedObject(best, kDotAlpha, @(best.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            best.alpha = 0.02;
        }
    }
}

static void DIDCleanupEyeSprites(void) {
    static const void *kDotAlpha = &kDotAlpha;
    BOOL shouldShow = DIDEnabled() && DIDSpriteOn() && DIDEyeOn();
    for (UIView *host in DIDCollectViews(@"SystemApertureContainerView")) {
        DIDSpriteView *sp = objc_getAssociatedObject(host, kEyeSprite);
        if (!sp) continue;
        UIView *dot = objc_getAssociatedObject(host, kEyeDotRef);
        BOOL alive = shouldShow && dot && dot.window && !dot.hidden;
        if (!alive) {
            [sp halt];
            [sp removeFromSuperview];
            objc_setAssociatedObject(host, kEyeSprite, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(host, kEyeDotRef, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    // 恢复被我们压掉的原生红点
    if (!DIDEnabled() || !DIDSpriteOn() || !DIDEyeOn()) {
        for (UIView *v in DIDCollectViews(@"RecordingIndicator")) {
            NSNumber *saved = objc_getAssociatedObject(v, kDotAlpha);
            if (saved) {
                v.alpha = saved.doubleValue;
                objc_setAssociatedObject(v, kDotAlpha, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}

#pragma mark - 音乐：跟随专辑封面

static void DIDPlaceDanceSprite(void) {
    if (!DIDEnabled() || !DIDSpriteOn() || !DIDDanceOn()) return;
    NSArray<UIImage *> *frames = DIDLoadFrames(0);
    if (frames.count == 0) return;

    UIView *bestArt = nil; UIView *bestHost = nil;
    for (UIView *p in DIDCollectViews(@"SystemApertureContainerView")) {
        if (p.bounds.size.width < 24 || p.bounds.size.height < 16) continue;
        if (!DIDNearPlaybackCaption(p, 3)) continue;
        UIImageView *art = DIDArtworkIn(p);
        if (!art) continue;
        // 暂停时系统把封面收起来，这时不贴跳舞素材（否则会盖住暂停按钮）
        if (art.bounds.size.height < 16 || art.hidden || art.alpha < 0.2) continue;
        bestArt = art; bestHost = p;
        break;
    }
    if (!bestArt) return;

    CGFloat configured = DIDFloat(@"danceAnimationSize", 22.0, 4.0, 64.0);
    CGFloat side = MIN(configured, bestHost.bounds.size.height);
    CGRect ar = CGRectZero;
    @try { ar = [bestArt convertRect:bestArt.bounds toView:bestHost]; } @catch (...) { return; }
    CGPoint c = CGPointMake(CGRectGetMaxX(ar) + side / 2.0 + 2.0, CGRectGetMidY(ar));
    if (c.x + side / 2.0 > bestHost.bounds.size.width) {
        c.x = CGRectGetMinX(ar) - side / 2.0 - 2.0;   // 封面在右半区时放到左边
    }
    c.x += DIDFloat(@"danceOffsetX", 0.0, -120.0, 120.0);
    c.y += DIDFloat(@"danceOffsetY", 0.0, -60.0, 60.0);

    DIDSpriteView *sp = DIDEnsureSprite(bestHost, kDanceSprite);
    DIDAttach(sp, bestHost, c, side);
    CGFloat fps = DIDFloat(@"danceFrameRate", 12.0, 1.0, 60.0);
    [sp play:frames fps:fps];
    objc_setAssociatedObject(bestHost, kDanceArtRef, bestArt, OBJC_ASSOCIATION_ASSIGN);
}

static void DIDCleanupDanceSprites(void) {
    for (UIView *host in DIDCollectViews(@"SystemApertureContainerView")) {
        DIDSpriteView *sp = objc_getAssociatedObject(host, kDanceSprite);
        if (!sp) continue;
        UIView *art = objc_getAssociatedObject(host, kDanceArtRef);
        BOOL alive = art && art.window && art.bounds.size.height >= 16;
        if (!alive) {
            [sp halt];
            [sp removeFromSuperview];
            objc_setAssociatedObject(host, kDanceSprite, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
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
    layer.contents = (__bridge id)mask.CGImage;   // 遮罩用原图：CI 前置会把形状反掉
    cache[key] = layer;
    return layer;
}

static void DIDApplyRotation(UIView *art) {
    if (!DIDEnabled() || !DIDRotationOn()) return;
    if (!art.window || art.bounds.size.width < 12) return;
    CGFloat side = MIN(art.bounds.size.width, art.bounds.size.height);
    CALayer *l = art.layer;
    if (fabs(l.cornerRadius - side / 2.0) > 0.5) l.cornerRadius = side / 2.0;
    if (!l.masksToBounds) l.masksToBounds = YES;

    CALayer *mask = DIDMaskLayer(art.bounds.size, DIDString(@"selectedMaskFolder"));
    if (mask && l.mask != mask) l.mask = mask;

    if (![l animationForKey:@"did.rot"]) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        a.fromValue = @0; a.toValue = @(M_PI * 2);
        a.duration = DIDRotationPeriod();
        a.repeatCount = HUGE_VALF;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        a.removedOnCompletion = NO;
        [l addAnimation:a forKey:@"did.rot"];
    }
}

static void DIDRotateIn(UIView *root, NSInteger depth) {
    if (!root || depth < 0) return;
    if ([root isKindOfClass:[UIImageView class]] && ((UIImageView *)root).image &&
        [root.class.description.lowercaseString containsString:@"artwork"]) {
        DIDApplyRotation(root);
    }
    for (UIView *s in root.subviews) DIDRotateIn(s, depth - 1);
}

static void DIDStopRotation(void) {
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        [v.layer removeAnimationForKey:@"did.rot"];
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}
#pragma mark - 岛形调整

static BOOL gInSetFrame = NO;

static CGRect DIDReshapedFrame(UIView *container, CGRect frame) {
    if (!DIDEnabled() || !DIDReshapeOn()) return frame;
    CGFloat w = frame.size.width, h = frame.size.height;
    if (w < 1.0 || h < 1.0) return frame;
    if (w > 260.0) return frame;                 // 已展开的大岛不动
    if (h < 26.0 || h > 46.0) return frame;      // 只处理标准岛高

    // 折叠态小岛：改成和高度相等的正圆，让封面/素材看起来是圆的
    if (w < 60.0) {
        CGFloat side = MAX(h, 36.6667);
        return CGRectMake(CGRectGetMidX(frame) - side / 2.0, frame.origin.y, side, side);
    }
    // 展开态：统一 193 宽，中心不动
    if (w >= 130.0 && w <= 215.0) {
        return CGRectMake(CGRectGetMidX(frame) - 193.0 / 2.0, frame.origin.y, 193.0, h);
    }
    return frame;
}

#pragma mark - 扫描

static void DIDScan(void) {
    if (!DIDEnabled()) {
        DIDCleanupEyeSprites();
        DIDCleanupDanceSprites();
        DIDStopRotation();
        return;
    }
    @try { DIDPlaceEyeSprite(); } @catch (...) {}
    @try { DIDCleanupEyeSprites(); } @catch (...) {}
    if (DIDSpriteOn()) {
        @try { DIDPlaceDanceSprite(); } @catch (...) {}
        @try { DIDCleanupDanceSprites(); } @catch (...) {}
    } else {
        @try { DIDCleanupDanceSprites(); } @catch (...) {}
    }
    if (DIDRotationOn()) {
        if (DIDBool(@"rotateNowPlayingOnly", YES)) {
            for (UIView *p in DIDCollectViews(@"SystemApertureContainerView")) {
                if (DIDNearPlaybackCaption(p, 3)) @try { DIDRotateIn(p, 6); } @catch (...) {}
            }
        }
    }
    for (UIView *p in DIDCollectViews(@"SystemApertureContainerView")) [p setNeedsLayout];
}

static NSInteger gScanScheduled = 0;
static void DIDScheduleScan(double delay) {
    gScanScheduled++;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ @try { DIDScan(); } @catch (...) {} });
}

#pragma mark - Hooks

%hook SBSystemApertureContainerView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
    @try {
        UIView *pill = (UIView *)self;
        if (pill.bounds.size.width < 16 || pill.bounds.size.height < 14) return;
        DIDPlaceEyeSprite();
        if (DIDSpriteOn()) DIDPlaceDanceSprite();
    } @catch (...) {}
}

- (void)setFrame:(CGRect)frame {
    CGRect target = frame;
    if (!gInSetFrame) {
        @try { target = DIDReshapedFrame((UIView *)self, frame); } @catch (...) {}
    }
    gInSetFrame = YES;
    %orig(target);
    gInSetFrame = NO;
}

%end

%hook SBRecordingIndicatorView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @try { DIDPlaceEyeSprite(); } @catch (...) {}
    });
}

%end

%hook SAUIElementView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
    @try {
        NSString *ident = ((UIView *)self).accessibilityIdentifier;
        if ([ident isKindOfClass:[NSString class]] && [ident containsString:@"ScreenRecording"]) {
            DIDPlaceEyeSprite();
        }
    } @catch (...) {}
}

%end

%hook MRUArtworkView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
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
            DIDCleanupEyeSprites();
            DIDCleanupDanceSprites();
            DIDStopRotation();
            return;
        }
        DIDScan();
    });
}

#pragma mark - ctor

%ctor {
    @autoreleasepool {
        DIDLog(@"===== DynamicIslandDance v%@ loaded (pid %d) =====", DIDVersion, getpid());
        DIDLog(@"bundled root = %@", DIDBundledRoot() ?: @"(missing)");
        DIDLog(@"themes dance=%@ eye=%@ mask=%@",
               DIDAvailableThemes(0), DIDAvailableThemes(1), DIDAvailableThemes(2));

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
            DIDScheduleScan(0.10);
            DIDScheduleScan(0.45);
            DIDScheduleScan(1.10);
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            DIDScheduleScan(0.30);
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:@"_MRMediaRemoteNowPlayingInfoDidChange"
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            DIDScheduleScan(0.05);
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:@"kMRMediaRemoteNowPlayingInfoDidChange"
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            DIDScheduleScan(0.05);
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try { DIDScan(); } @catch (...) {}
        });
    }
}
