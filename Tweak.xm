// DynamicIslandDance — 灵动岛跳舞（纯净自研版）
// 素材绘制在独立覆盖层窗口上，用屏幕坐标定位，不会被灵动岛背板遮挡。
// 全自研：无联网、无设备指纹、无授权校验。

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdio.h>

static NSString *const DIDVersion     = @"2.6.2";
static const char *     DIDPrefNotify = "com.minis.didance.changed";
static NSString *const DIDDefaultRoot = @"/var/mobile/DynamicIsland";
static NSString *const DIDLogPath     = @"/var/mobile/DynamicIslandDance.log";
static CFStringRef const kDIDDomain   = CFSTR("com.minis.didance");

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

static NSMutableDictionary<NSString *, NSNumber *> *gBoolCache;
static NSTimeInterval gBoolAt = -1e9;

static BOOL DIDBool(NSString *key, BOOL fallback) {
    NSTimeInterval now = CACurrentMediaTime();
    if (!gBoolCache || now - gBoolAt > 0.6) {
        gBoolCache = [NSMutableDictionary dictionary];
        gBoolAt = now;
    }
    NSNumber *c = gBoolCache[key];
    if (c) return c.boolValue;
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kDIDDomain));
    BOOL r = v ? [v boolValue] : fallback;
    gBoolCache[key] = @(r);
    return r;
}

static CGFloat DIDFloat(NSString *key, CGFloat fallback, CGFloat lo, CGFloat hi) {
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kDIDDomain));
    return MAX(lo, MIN(hi, v ? [v doubleValue] : fallback));
}

static NSString *DIDString(NSString *key) {
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kDIDDomain));
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static void DIDFlushCaches(void) {
    gBoolCache = nil; gBoolAt = -1e9;
}

static NSString *DIDMediaRootDir(void) {
    NSString *v = DIDString(@"mediaRoot");
    return [(v.length ? v : DIDDefaultRoot) stringByStandardizingPath];
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
                                  : kind == 1 ? @[@"three-tomoe", @"itachi", @"sasuke", @"madara",
                                                  @"obito", @"shisui", @"izuna", @"two-tomoe",
                                                  @"one-tomoe"] : @[@"circle", @"squircle"];
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

#pragma mark - 覆盖层窗口

// 独立 window 绘制素材：不会被灵动岛的黑色背板遮挡，也不受容器裁剪影响。
static NSArray<UIWindow *> *DIDAllWindows(void);
static UIWindow *gOverlay;
static UIView *gStage;

@interface DIDOverlayWindow : UIWindow
@end
@implementation DIDOverlayWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)point; (void)event;
    return NO;                       // 完全不接收触摸
}
@end

static UIWindowScene *DIDWindowScene(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

static void DIDEnsureOverlay(void) {
    if (gOverlay && gStage) return;
    @try {
        UIWindowScene *scene = DIDWindowScene();
        UIWindow *w = scene ? [[DIDOverlayWindow alloc] initWithWindowScene:scene]
                            : [[DIDOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        w.frame = [UIScreen mainScreen].bounds;
        // 灵动岛/录屏指示器的窗口层级很高，覆盖层必须在它们之上，
        // 否则素材会被黑色背板盖住（表现为"只露出一点红色"）。
        CGFloat islandLevel = 0;
        for (UIWindow *iw in DIDAllWindows()) {
            if ([NSStringFromClass(iw.class) containsString:@"Aperture"] ||
                [NSStringFromClass(iw.class) containsString:@"RecordingIndicator"]) {
                islandLevel = MAX(islandLevel, iw.windowLevel);
            }
        }
        w.windowLevel = MAX(islandLevel + 100.0, 10000000.0);
        w.backgroundColor = [UIColor clearColor];
        w.userInteractionEnabled = NO;
        w.hidden = NO;

        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        vc.view.userInteractionEnabled = NO;
        w.rootViewController = vc;

        UIView *stage = [[UIView alloc] initWithFrame:w.bounds];
        stage.backgroundColor = [UIColor clearColor];
        stage.userInteractionEnabled = NO;
        [vc.view addSubview:stage];

        gOverlay = w;
        gStage = stage;
    } @catch (...) {
        gOverlay = nil; gStage = nil;
    }
}

#pragma mark - 精灵

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

static DIDSpriteView *gEyeSprite;
static DIDSpriteView *gDanceSprite;
static UIImageView *gSpinView;      // 圆形旋转的封面

static DIDSpriteView *DIDSprite(BOOL eye) {
    DIDEnsureOverlay();
    if (!gStage) return nil;
    __strong DIDSpriteView **slot = eye ? &gEyeSprite : &gDanceSprite;
    if (!*slot) {
        DIDSpriteView *fresh = [[DIDSpriteView alloc] initWithFrame:CGRectZero];
        fresh.hidden = YES;
        [gStage addSubview:fresh];
        *slot = fresh;
    }
    return *slot;
}

static void DIDHideSprite(BOOL eye) {
    __strong DIDSpriteView **slot = eye ? &gEyeSprite : &gDanceSprite;
    if (!*slot) return;
    [(*slot) halt];
    (*slot).hidden = YES;
    (*slot).frame = CGRectZero;
}

static void DIDPlace(DIDSpriteView *sp, CGRect frame, NSArray<UIImage *> *frames, CGFloat fps) {
    if (!sp || !frames.count) return;
    if (frame.size.width < 4 || frame.size.height < 4) { sp.hidden = YES; return; }
    if (!CGRectEqualToRect(sp.frame, frame)) {
        [UIView performWithoutAnimation:^{ sp.frame = frame; }];
    }
    sp.hidden = NO;
    sp.alpha = 1.0;
    [sp play:frames fps:fps];
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

// 必须走 window -> screen 两级换算：toView:nil 只到 window 坐标系，
// 而灵动岛在独立 window 里，直接用会算错位置。
static CGRect DIDScreenRect(UIView *v) {
    if (!v || !v.window) return CGRectZero;
    CGRect r = CGRectZero;
    @try {
        r = [v convertRect:v.bounds toView:v.window];
        r = [v.window convertRect:r toWindow:nil];
    } @catch (...) { return CGRectZero; }
    return r;
}

static BOOL DIDOnScreen(CGRect r) {
    if (r.size.width < 1.0 || r.size.height < 1.0) return NO;
    CGRect s = [UIScreen mainScreen].bounds;
    return CGRectGetMinX(r) > -10 && CGRectGetMaxX(r) < s.size.width + 10
        && CGRectGetMinY(r) > -10 && CGRectGetMaxY(r) < s.size.height + 10;
}

static NSArray<UIView *> *DIDPills(void) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) {
        if (gOverlay && w == gOverlay) continue;
        [stack addObject:w];
    }
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"SBSystemApertureContainerView"] &&
            v.window && !v.hidden && v.alpha > 0.01) {
            CGSize b = v.bounds.size;
            if (b.width >= 18 && b.width <= 330 && b.height >= 16 && b.height <= 96) {
                CGRect r = DIDScreenRect(v);
                if (DIDOnScreen(r)) [out addObject:v];
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

static NSArray<UIView *> *DIDDots(void) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) {
        if (gOverlay && w == gOverlay) continue;
        [stack addObject:w];
    }
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass(v.class) containsString:@"RecordingIndicator"]) {
            CGSize b = v.bounds.size;
            CGFloat m = MAX(b.width, b.height);
            if (m >= 1.5 && m <= 26.0 && v.window) [out addObject:v];
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    return out;
}

// 在 pill 内部找封面：返回图像 + 它在屏幕上的可见矩形（与 pill 取交集）
static UIImageView *DIDArtworkInPill(UIView *pill, CGRect *visibleOut) {
    CGRect pr = DIDScreenRect(pill);
    if (CGRectEqualToRect(pr, CGRectZero)) return nil;

    UIImageView *best = nil;
    CGRect bestVis = CGRectZero;
    CGFloat bestScore = -1;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:pill];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([v isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)v;
            if (iv.image) {
                CGRect ar = DIDScreenRect(iv);
                CGRect vis = CGRectIntersection(ar, pr);
                // 用可见区域判断：封面可能是一张整屏大图，被容器裁成了一个小圆
                if (vis.size.height >= 14 && vis.size.width >= 14) {
                    CGFloat squareness = 1.0 - fabs(vis.size.width - vis.size.height)
                                              / MAX(vis.size.width, vis.size.height);
                    BOOL artworkClass = [NSStringFromClass(v.class).lowercaseString containsString:@"artwork"];
                    CGFloat score = squareness * 2.0 + (artworkClass ? 1.5 : 0.0);
                    if (score > bestScore) { bestScore = score; best = iv; bestVis = vis; }
                }
            }
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
    if (best && visibleOut) *visibleOut = bestVis;
    return best;
}

static const void *kDotAlpha = &kDotAlpha;
static const void *kArtAlpha = &kArtAlpha;

static void DIDRestoreOriginals(void) {
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) {
        if (gOverlay && w == gOverlay) continue;
        [stack addObject:w];
    }
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        NSNumber *da = objc_getAssociatedObject(v, kDotAlpha);
        if (da) {
            v.alpha = da.doubleValue;
            objc_setAssociatedObject(v, kDotAlpha, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSNumber *aa = objc_getAssociatedObject(v, kArtAlpha);
        if (aa) {
            v.alpha = aa.doubleValue;
            objc_setAssociatedObject(v, kArtAlpha, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for (UIView *s in v.subviews) [stack addObject:s];
    }
}

#pragma mark - 录屏素材

// 在window坐标里，把"内部矩形"换算成以它为中心的正方形
static CGRect DIDSquareAround(CGPoint center, CGFloat side) {
    return CGRectMake(center.x - side / 2.0, center.y - side / 2.0, side, side);
}

static BOOL DIDPlaceEye(BOOL verbose) {
    if (!DIDEnabled() || !DIDEyeOn() || ![UIScreen mainScreen].isCaptured) return NO;
    NSArray<UIImage *> *frames = DIDLoadFrames(1);
    if (frames.count == 0) return NO;
    DIDSpriteView *sp = DIDSprite(1);
    if (!sp) return NO;

    CGFloat configured = DIDFloat(@"eyeSize", 36.7, 10.0, 36.7);
    NSArray<UIView *> *pills = DIDPills();

    // 1) 红点：直接用它的屏幕矩形，圆心最准
    for (UIView *dot in DIDDots()) {
        CGRect dr = DIDScreenRect(dot);
        if (!DIDOnScreen(dr)) continue;
        CGFloat side = MIN(configured, 36.7);
        CGRect frame = DIDSquareAround(CGPointMake(CGRectGetMidX(dr), CGRectGetMidY(dr)), side);
        DIDPlace(sp, frame, frames, DIDFloat(@"eyeFPS", 16.0, 2.0, 30.0));
        if (!objc_getAssociatedObject(dot, kDotAlpha)) {
            objc_setAssociatedObject(dot, kDotAlpha, @(dot.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            dot.alpha = 0.02;
        }
        if (verbose) DIDLog(@"eye: dot frame=%@", NSStringFromCGRect(frame));
        return YES;
    }

    // 2) 带 ScreenRecording 标记的岛。宽岛里系统把录屏点放在最左端。
    for (UIView *pill in pills) {
        if (!DIDPillHasTag(pill, @"ScreenRecording", 4)) continue;

        CGRect pr = DIDScreenRect(pill);
        if (CGRectEqualToRect(pr, CGRectZero)) continue;
        CGFloat side = MIN(configured, pr.size.height);
        CGPoint center;
        if (pr.size.width > pr.size.height * 2.0) {
            center = CGPointMake(CGRectGetMinX(pr) + pr.size.height / 2.0, CGRectGetMidY(pr));
        } else {
            center = CGPointMake(CGRectGetMidX(pr), CGRectGetMidY(pr));
        }
        DIDPlace(sp, DIDSquareAround(center, side), frames, DIDFloat(@"eyeFPS", 16.0, 2.0, 30.0));
        if (verbose) DIDLog(@"eye: tag->pill pr=%@ side=%.1f", NSStringFromCGRect(pr), side);
        return YES;
    }

    DIDHideSprite(1);
    if (verbose) {
        DIDLog(@"eye fail: pills=%lu dots=%lu", (unsigned long)pills.count,
               (unsigned long)DIDDots().count);
        for (UIView *p in pills)
            DIDLog(@"  pill id=%@ scr=%@", p.accessibilityIdentifier ?: @"-",
                   NSStringFromCGRect(DIDScreenRect(p)));
    }
    return NO;
}

#pragma mark - 跳舞素材

static BOOL DIDPlaceDance(BOOL verbose) {
    if (!DIDEnabled() || !DIDDanceOn()) return NO;
    NSArray<UIImage *> *frames = DIDLoadFrames(0);
    if (frames.count == 0) return NO;
    DIDSpriteView *sp = DIDSprite(0);
    if (!sp) return NO;

    UIView *bestPill = nil;
    CGRect bestVis = CGRectZero;

    for (UIView *pill in DIDPills()) {
        // 必须是音乐播放的岛；语音输入/导航/计时器等都带图片，不能靠"有图"判断
        if (!DIDPillHasTag(pill, @"NowPlaying", 5)) continue;
        CGRect vis = CGRectZero;
        if (!DIDArtworkInPill(pill, &vis)) continue;
        if (vis.size.height < 16) continue;
        bestPill = pill; bestVis = vis;
        break;
    }
    if (!bestPill) {
        DIDHideSprite(0);
        if (verbose) DIDLog(@"dance fail: pills=%lu", (unsigned long)DIDPills().count);
        return NO;
    }

    CGRect pr = DIDScreenRect(bestPill);
    CGFloat side = DIDFloat(@"danceSize", 22.0, 8.0, 44.0);
    side = MIN(side, MAX(pr.size.height * 1.15, 10.0));

    CGFloat offX = DIDFloat(@"danceOffsetX", 0.0, -200.0, 200.0);
    CGFloat offY = DIDFloat(@"danceOffsetY", 0.0, -40.0, 40.0);

    // 封面是岛端点被裁出的一个圆，直径等于岛高。
    // 判断封面在左还是右：看封面视图在岛坐标系里的中心（不用可见区域，那会被整屏大图带偏）。
    BOOL artLeft = YES;
    @try {
        UIView *pill = bestPill;
        UIImageView *art = DIDArtworkInPill(pill, NULL);
        if (art) {
            CGRect af = [art convertRect:art.bounds toView:pill];
            if (af.size.width > 0 && af.size.width <= pill.bounds.size.width + 4) {
                artLeft = CGRectGetMidX(af) < pill.bounds.size.width / 2.0;
            }
        }
    } @catch (...) {}

    // 素材放在封面对面的端点圆内，不会落到岛外被黑底盖住
    CGFloat radius = pr.size.height / 2.0;
    CGFloat x = artLeft ? (CGRectGetMaxX(pr) - radius) : (CGRectGetMinX(pr) + radius);
    CGFloat y = CGRectGetMidY(pr);
    x += offX;
    y += offY;

    // 夹在岛内：稍微放宽一点允许溢出，但不能整个跑到岛外
    CGFloat minX = CGRectGetMinX(pr) + side / 2.0 - radius * 0.5;
    CGFloat maxX = CGRectGetMaxX(pr) - side / 2.0 + radius * 0.5;
    x = MAX(minX, MIN(maxX, x));

    CGRect frame = DIDSquareAround(CGPointMake(x, y), side);
    DIDPlace(sp, frame, frames, DIDFloat(@"danceFPS", 12.0, 2.0, 30.0));
    if (verbose) DIDLog(@"dance: pr=%@ side=%.1f artLeft=%d frame=%@",
                        NSStringFromCGRect(pr), side, artLeft, NSStringFromCGRect(frame));
    return YES;
}

#pragma mark - 专辑封面旋转

static UIImage *gMaskImage;
static NSString *gMaskKey;

static UIImage *DIDMaskImage(void) {
    if (!DIDMaskOn()) return nil;
    NSString *folder = DIDString(@"selectedMaskFolder");
    if (folder.length == 0) folder = DIDDefaultTheme(2);
    NSString *path = DIDMaskPath(folder);
    if (path.length == 0) { gMaskImage = nil; gMaskKey = nil; return nil; }
    if (gMaskImage && [gMaskKey isEqualToString:path]) return gMaskImage;
    gMaskImage = [UIImage imageWithContentsOfFile:path];
    gMaskKey = path;
    return gMaskImage;
}

// 在覆盖层里重建一个圆形旋转封面：原封面常是整屏大图，直接转它会偏心。
static BOOL DIDPlaceSpin(BOOL verbose) {
    if (!DIDEnabled() || !DIDRotationOn()) return NO;
    DIDEnsureOverlay();
    if (!gStage) return NO;

    UIView *bestPill = nil;
    CGRect bestVis = CGRectZero;
    UIImageView *bestArt = nil;

    for (UIView *pill in DIDPills()) {
        if (!DIDPillHasTag(pill, @"NowPlaying", 5)) continue;
        CGRect vis = CGRectZero;
        UIImageView *art = DIDArtworkInPill(pill, &vis);
        if (!art || vis.size.height < 16) continue;
        bestPill = pill; bestVis = vis; bestArt = art;
        break;
    }
    if (!bestPill) {
        if (gSpinView) { gSpinView.hidden = YES; [gSpinView.layer removeAnimationForKey:@"did.rot"]; }
        if (verbose) DIDLog(@"spin fail");
        return NO;
    }

    CGFloat diameter = MIN(bestVis.size.height, bestVis.size.width);
    CGRect frame = DIDSquareAround(CGPointMake(CGRectGetMidX(bestVis), CGRectGetMidY(bestVis)), diameter);

    if (!gSpinView) {
        gSpinView = [[UIImageView alloc] initWithFrame:CGRectZero];
        gSpinView.userInteractionEnabled = NO;
        gSpinView.contentMode = UIViewContentModeScaleAspectFill;
        gSpinView.backgroundColor = [UIColor clearColor];
        gSpinView.layer.masksToBounds = YES;
        [gStage addSubview:gSpinView];
    }
    if (gSpinView.image != bestArt.image) gSpinView.image = bestArt.image;
    gSpinView.layer.cornerRadius = diameter / 2.0;
    gSpinView.layer.mask = nil;

    UIImage *mask = DIDMaskImage();
    if (mask && mask.CGImage) {
        // 用形状遮罩替代圆角
        CALayer *m = [CALayer layer];
        m.frame = CGRectMake(0, 0, diameter, diameter);
        m.contentsGravity = kCAGravityResize;
        m.contents = (__bridge id)mask.CGImage;
        gSpinView.layer.cornerRadius = 0;
        gSpinView.layer.mask = m;
    }

    if (!CGRectEqualToRect(gSpinView.frame, frame)) {
        [UIView performWithoutAnimation:^{ gSpinView.frame = frame; }];
    }
    gSpinView.hidden = NO;

    if (![gSpinView.layer animationForKey:@"did.rot"]) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        a.fromValue = @0; a.toValue = @(M_PI * 2);
        a.duration = 6.0 / DIDFloat(@"rotationSpeed", 0.6, 0.05, 3.0);
        a.repeatCount = HUGE_VALF;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        a.removedOnCompletion = NO;
        [gSpinView.layer addAnimation:a forKey:@"did.rot"];
    }

    // 盖掉原地那张（位置可能不同，避免重影）
    if (!objc_getAssociatedObject(bestArt, kArtAlpha)) {
        objc_setAssociatedObject(bestArt, kArtAlpha, @(bestArt.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        bestArt.alpha = 0.0;
    }
    if (verbose) DIDLog(@"spin vis=%@ d=%.1f", NSStringFromCGRect(bestVis), diameter);
    return YES;
}

#pragma mark - 扫描

static void DIDPurge(void) {
    DIDHideSprite(1);
    DIDHideSprite(0);
    if (gSpinView) {
        [gSpinView.layer removeAnimationForKey:@"did.rot"];
        gSpinView.hidden = YES;
    }
    DIDRestoreOriginals();
}

static void DIDScan(BOOL verbose) {
    if (!DIDEnabled()) { DIDPurge(); return; }
    @try { if (!DIDPlaceEye(verbose)) DIDHideSprite(1); } @catch (...) {}
    @try { if (!DIDPlaceDance(verbose)) DIDHideSprite(0); } @catch (...) {}
    @try { if (!DIDPlaceSpin(verbose) && gSpinView) {
        [gSpinView.layer removeAnimationForKey:@"did.rot"];
        gSpinView.hidden = YES;
    } } @catch (...) {}
    if (![UIScreen mainScreen].isCaptured) {
        // 录屏结束后立刻清掉录屏素材，其余靠各自条件维持
        @try { DIDHideSprite(1); } @catch (...) {}
        DIDRestoreOriginals();
        @try { DIDPlaceSpin(NO); } @catch (...) {}
        @try { DIDPlaceDance(NO); } @catch (...) {}
    }
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
        if (pill.bounds.size.width < 18 || pill.bounds.size.width > 330) return;
        if (pill.bounds.size.height < 16 || pill.bounds.size.height > 96) return;
        if ([UIScreen mainScreen].isCaptured) DIDPlaceEye(NO);
        DIDPlaceDance(NO);
        DIDPlaceSpin(NO);
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
    dispatch_async(dispatch_get_main_queue(), ^{ @try { DIDPlaceSpin(NO); } @catch (...) {} });
}

%end

#pragma mark - 通知

static void DIDObserve(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIScreenCapturedDidChangeNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *n) {
        BOOL captured = [UIScreen mainScreen].isCaptured;
        DIDLog(@"capture -> %d", captured);
        if (!captured) DIDHideSprite(1);
        DIDScanSoon(0.10, YES);
        DIDScanSoon(0.45, NO);
        DIDScanSoon(0.95, NO);
    }];
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"_MRMediaRemoteNowPlayingInfoDidChange",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            DIDScanSoon(0.08, NO);
        }];
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *n) {
        DIDScanSoon(0.30, NO);
    }];
}

#pragma mark - 设置变更

static NSInteger gTicket = 0;
static void DIDApplySettingsNow(void);

static void DIDApplySettings(void) {
    NSInteger t = ++gTicket;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (t != gTicket) return;
        @try { DIDApplySettingsNow(); } @catch (...) {}
    });
}

static void DIDApplySettingsNow(void) {
    DIDFlushCaches();
    DIDClearFrameCache();
    gMaskImage = nil; gMaskKey = nil;
    DIDLog(@"settings changed");
    // 先拆掉旧素材，再按新设置重建，保证尺寸/素材名立即生效
    @try { DIDPurge(); } @catch (...) {}
    DIDScan(NO);
}

#pragma mark - ctor

%ctor {
    @autoreleasepool {
        DIDLog(@"===== DynamicIslandDance v%@ loaded (pid %d) =====", DIDVersion, getpid());
        int token = 0;
        notify_register_dispatch(DIDPrefNotify, &token, dispatch_get_main_queue(), ^(__unused int t) {
            DIDApplySettings();
        });
        DIDObserve();
        DIDScanSoon(1.5, NO);
    }
}