// DynamicIslandDance — 灵动岛跳舞（纯净自研版）
// 功能：灵动岛专辑封面圆形旋转、跳舞逐帧动画、录屏写轮眼素材、iOS17 岛屿圆化。
// 全部代码为自研，不含许可证校验、设备指纹、混淆或任何联网行为。

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdio.h>

static NSString *const DIDVersion     = @"1.2.0";
static NSString *const DIDPrefPath    = @"/var/mobile/Library/Preferences/com.minis.didance.plist";
static const char *     DIDPrefNotify = "com.minis.didance.changed";
static NSString *const DIDImageRoot   = @"/var/mobile/DynamicIsland";
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

static NSDictionary *gDIDPrefs;
static NSTimeInterval gDIDPrefsAt = -1e9;
static NSLock *gDIDPrefsLock;

static void DIDReloadPrefs(BOOL force) {
    NSTimeInterval now = CACurrentMediaTime();
    if (!force && gDIDPrefs && now - gDIDPrefsAt < 1.0) return;
    if (!gDIDPrefsLock) gDIDPrefsLock = [NSLock new];
    if (![gDIDPrefsLock tryLock]) return;
    gDIDPrefsAt = now;
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:DIDPrefPath];
    gDIDPrefs = d ?: @{};
    [gDIDPrefsLock unlock];
}

static BOOL DIDBool(NSString *key, BOOL fallback) {
    DIDReloadPrefs(NO);
    id v = gDIDPrefs[key];
    return v ? [v boolValue] : fallback;
}

static CGFloat DIDFloat(NSString *key, CGFloat fallback, CGFloat lo, CGFloat hi) {
    DIDReloadPrefs(NO);
    id v = gDIDPrefs[key];
    CGFloat f = v ? [v doubleValue] : fallback;
    if (f < lo) f = lo;
    if (f > hi) f = hi;
    return f;
}

static NSString *DIDString(NSString *key) {
    DIDReloadPrefs(NO);
    id v = gDIDPrefs[key];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

static BOOL DIDEnabled(void)              { return DIDBool(@"shouldEnableCustomUI", YES); }
static BOOL DIDAlbumRotationEnabled(void) { return DIDBool(@"enableAlbumRotation", YES); }
static BOOL DIDIOS17Adaptation(void)      { return DIDBool(@"enableIOS17Adaptation", YES); }
static BOOL DIDDanceEnabled(void)         { return DIDBool(@"enableDanceSprite", YES); }
static BOOL DIDEyeEnabled(void)           { return DIDBool(@"enableEyeSprite", YES); }

static CGFloat DIDRotationDuration(void) {
    CGFloat speed = DIDFloat(@"albumRotationSpeed", 0.6, 0.05, 4.0);
    return 6.0 / speed;
}

#pragma mark - 逐帧素材

static NSArray<UIImage *> *gDIDFramesDance;
static NSArray<UIImage *> *gDIDFramesEye;
static NSString *gDIDFrameKeyDance;
static NSString *gDIDFrameKeyEye;

static NSString *DIDKindName(NSInteger kind) {
    return kind == 0 ? @"dance" : (kind == 1 ? @"eye" : @"mask");
}

// 内置素材随插件包一起安装（rootless 在 /var/jb 下，无根在 / 下）
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

// 返回 { 用户主题目录, 内置主题目录 } 中所有可用主题名（去重、排序）
static NSArray<NSString *> *DIDAvailableThemes(NSInteger kind) {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    [roots addObject:[DIDImageRoot stringByAppendingPathComponent:DIDKindName(kind)]];
    NSString *b = DIDBundledRoot();
    if (b) [roots addObject:[b stringByAppendingPathComponent:DIDKindName(kind)]];
    for (NSString *root in roots) {
        for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:root error:NULL]) {
            if ([name hasPrefix:@"."]) continue;
            BOOL isDir = NO;
            NSString *full = [root stringByAppendingPathComponent:name];
            if ([[NSFileManager defaultManager] fileExistsAtPath:full isDirectory:&isDir] && isDir) [set addObject:name];
        }
    }
    return [[set allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

static NSString *DIDDefaultTheme(NSInteger kind) {
    NSArray<NSString *> *all = DIDAvailableThemes(kind);
    return all.count ? all.firstObject : nil;
}

// 在用户目录找不到就回退到内置目录
static NSString *DIDThemeDir(NSInteger kind, NSString *folder) {
    if (folder.length == 0) return nil;
    NSString *user = [[DIDImageRoot stringByAppendingPathComponent:DIDKindName(kind)] stringByAppendingPathComponent:folder];
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:user isDirectory:&isDir] && isDir) return user;
    NSString *b = DIDBundledRoot();
    if (b) {
        NSString *bundled = [[b stringByAppendingPathComponent:DIDKindName(kind)] stringByAppendingPathComponent:folder];
        if ([[NSFileManager defaultManager] fileExistsAtPath:bundled isDirectory:&isDir] && isDir) return bundled;
    }
    return nil;
}

static NSString *DIDMaskPath(NSString *folder) {
    if (folder.length == 0) return nil;
    NSString *user = [DIDImageRoot stringByAppendingPathComponent:
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

static NSInteger DIDFileNumber(NSString *name) {
    NSMutableString *digits = [NSMutableString string];
    for (NSUInteger i = 0; i < name.length; i++) {
        unichar c = [name characterAtIndex:i];
        if (c >= '0' && c <= '9') [digits appendFormat:@"%C", c];
    }
    return digits.length ? digits.integerValue : 0;
}

static BOOL DIDFileIsImage(NSString *path) {
    NSString *ext = path.pathExtension.lowercaseString;
    return [ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] ||
           [ext isEqualToString:@"jpeg"] || [ext isEqualToString:@"webp"] || [ext isEqualToString:@"gif"];
}

static NSArray<UIImage *> *DIDLoadFrames(NSInteger kind) {
    NSString *folder = DIDString(kind == 0 ? @"selectedDanceFolder" : @"selectedEyeFolder");
    if (folder.length == 0) folder = DIDDefaultTheme(kind);
    if (folder.length == 0) return nil;

    NSString *dir = DIDThemeDir(kind, folder);
    if (dir == nil) return nil;

    NSArray<UIImage *> *cached = kind == 0 ? gDIDFramesDance : gDIDFramesEye;
    NSString *cachedKey = kind == 0 ? gDIDFrameKeyDance : gDIDFrameKeyEye;
    NSString *key = [NSString stringWithFormat:@"%ld|%@", (long)kind, folder];
    if (cached && [cachedKey isEqualToString:key]) return cached;

    NSArray<NSString *> *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *n in names) {
        if ([n hasPrefix:@"."] || !DIDFileIsImage(n)) continue;
        [files addObject:n];
    }

    NSMutableArray<NSString *> *preferred = [NSMutableArray array];
    for (NSString *n in files) {
        if ([n.lowercaseString hasPrefix:@"replay"]) [preferred addObject:n];
    }
    NSArray<NSString *> *use = preferred.count ? preferred : files;
    use = [use sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger na = DIDFileNumber(a), nb = DIDFileNumber(b);
        if (na != nb) return na < nb ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];

    NSMutableArray<UIImage *> *images = [NSMutableArray array];
    for (NSString *n in use) {
        UIImage *img = [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:n]];
        if (img) [images addObject:img];
    }
    NSArray<UIImage *> *result = images.count ? images : nil;
    if (kind == 0) { gDIDFramesDance = result; gDIDFrameKeyDance = result ? key : nil; }
    else           { gDIDFramesEye = result;   gDIDFrameKeyEye = result ? key : nil; }
    DIDLog(@"load %@ frames folder=%@ count=%lu", DIDKindName(kind), folder, (unsigned long)images.count);
    return result;
}

static void DIDClearFrameCache(void) {
    gDIDFramesDance = nil; gDIDFramesEye = nil;
    gDIDFrameKeyDance = nil; gDIDFrameKeyEye = nil;
}

#pragma mark - 逐帧视图

@interface DIDSpriteView : UIImageView
- (void)playFrames:(NSArray<UIImage *> *)frames fps:(CGFloat)fps;
- (void)stopFrames;
@end

@implementation DIDSpriteView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeScaleAspectFit;
        self.backgroundColor = UIColor.clearColor;
        self.layer.masksToBounds = NO;
    }
    return self;
}
- (void)playFrames:(NSArray<UIImage *> *)frames fps:(CGFloat)fps {
    if (frames.count == 0) return;
    if (fps < 1) fps = 1;
    CGFloat d = frames.count / fps;
    if (self.animationImages == (NSArray *)frames && fabs(self.animationDuration - d) < 0.001) {
        if (!self.isAnimating) [self startAnimating];
        return;
    }
    [self stopAnimating];
    self.animationImages = frames;
    self.animationDuration = d;
    self.animationRepeatCount = 0;
    [self startAnimating];
}
- (void)stopFrames {
    [self stopAnimating];
    self.animationImages = nil;
}
@end

#pragma mark - 归属判定

static NSArray<UIWindow *> *DIDAllWindows(void) {
    NSMutableArray<UIWindow *> *out = [NSMutableArray array];
    @try {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
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

static UIView *DIDPillForView(UIView *v) {
    UIView *cur = v;
    for (NSInteger i = 0; i < 14 && cur; i++, cur = cur.superview) {
        if ([NSStringFromClass(cur.class) isEqualToString:@"SBSystemApertureContainerView"] &&
            cur.window && !cur.hidden && cur.alpha > 0.01) {
            return cur;
        }
    }
    return nil;
}

static BOOL DIDTagMatches(UIView *v, NSString *token) {
    NSString *ident = v.accessibilityIdentifier;
    return [ident isKindOfClass:[NSString class]] && [ident containsString:token];
}

static BOOL DIDAnyTagInSubtree(UIView *root, NSString *token, NSInteger depth) {
    if (!root || depth < 0) return NO;
    if (DIDTagMatches(root, token)) return YES;
    for (UIView *sub in root.subviews) {
        if (DIDAnyTagInSubtree(sub, token, depth - 1)) return YES;
    }
    return NO;
}

static BOOL DIDPillIsNowPlayingFast(UIView *pill) {
    return DIDTagMatches(pill, @"NowPlaying") || DIDTagMatches(pill, @"ScreenRecording");
}

static BOOL DIDPillIsNowPlaying(UIView *pill) {
    if (DIDTagMatches(pill, @"NowPlaying")) return YES;
    return DIDAnyTagInSubtree(pill, @"NowPlaying", 2);
}

static BOOL DIDPillIsRecording(UIView *pill) {
    if (DIDTagMatches(pill, @"ScreenRecording")) return YES;
    return DIDAnyTagInSubtree(pill, @"ScreenRecording", 6);
}

#pragma mark - 专辑封面圆形旋转

static CALayer *DIDMaskLayerForSize(CGSize size, NSString *folder) {
    if (!DIDBool(@"enableMaskLayer", YES)) return nil;
    if (folder.length == 0) folder = DIDDefaultTheme(2);
    NSString *path = DIDMaskPath(folder);
    UIImage *mask = path ? [UIImage imageWithContentsOfFile:path] : nil;
    if (!mask || !mask.CGImage) return nil;

    static NSMutableDictionary<NSString *, CALayer *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary dictionary]; });
    NSString *key = [NSString stringWithFormat:@"%@|%.0fx%.0f", path, size.width, size.height];
    CALayer *cached = cache[key];
    if (cached) return cached;

    CGImageRef inverted = NULL;
    @try {
        CIImage *ci = [CIImage imageWithCGImage:mask.CGImage];
        CIFilter *f = [CIFilter filterWithName:@"CIColorInvert"];
        [f setValue:ci forKey:kCIInputImageKey];
        CIImage *out = f.outputImage;
        static CIContext *ctx;
        if (!ctx) ctx = [CIContext contextWithOptions:nil];
        inverted = [ctx createCGImage:out fromRect:out.extent];
    } @catch (...) { inverted = NULL; }

    CALayer *layer = [CALayer layer];
    layer.frame = CGRectMake(0, 0, size.width, size.height);
    layer.contentsGravity = kCAGravityResize;
    layer.contents = inverted ? (__bridge id)inverted : (__bridge id)mask.CGImage;
    if (inverted) CGImageRelease(inverted);
    cache[key] = layer;
    return layer;
}

// 岛屿里的专辑封面：优先类名含 artwork 的视图，否则取第一个非空 UIImageView。
static UIImageView *DIDFindArtworkView(UIView *root, NSInteger depth) {
    if (!root || depth < 0) return nil;
    NSString *cls = NSStringFromClass(root.class).lowercaseString;
    BOOL artworkClass = [cls containsString:@"artwork"];
    if ([root isKindOfClass:[UIImageView class]]) {
        UIImageView *iv = (UIImageView *)root;
        if (iv.image && (artworkClass || (iv.bounds.size.width >= 12 && iv.bounds.size.height >= 12))) return iv;
    }
    NSMutableArray<UIImageView *> *fallback = [NSMutableArray array];
    for (UIView *sub in root.subviews) {
        NSString *scls = NSStringFromClass(sub.class).lowercaseString;
        if ([scls containsString:@"artwork"]) {
            if ([sub isKindOfClass:[UIImageView class]] && ((UIImageView *)sub).image) return (UIImageView *)sub;
            UIImageView *deep = DIDFindArtworkView(sub, depth - 1);
            if (deep) return deep;
        }
        if ([sub isKindOfClass:[UIImageView class]] && ((UIImageView *)sub).image) [fallback addObject:(UIImageView *)sub];
    }
    if (artworkClass && fallback.count) return fallback.firstObject;
    return nil;
}

static void DIDApplyAlbumRotation(UIView *pill) {
    if (!DIDEnabled() || !DIDAlbumRotationEnabled()) return;
    if (!pill.window || !DIDPillIsNowPlaying(pill)) return;

    UIImageView *art = DIDFindArtworkView(pill, 6);
    if (!art) return;

    CGSize b = art.bounds.size;
    CGFloat side = MIN(b.width, b.height);
    if (side < 12) {
        CGSize pb = pill.bounds.size;
        side = MIN(pb.height - 6.0, pb.width * 0.5);
    }
    if (side < 12) return;

    CALayer *layer = art.layer;
    if (fabs(layer.cornerRadius - side / 2.0) > 0.5) layer.cornerRadius = side / 2.0;
    if (!layer.masksToBounds) layer.masksToBounds = YES;

    CALayer *mask = DIDMaskLayerForSize(art.bounds.size, DIDString(@"selectedMaskFolder"));
    if (mask && layer.mask != mask) layer.mask = mask;
    if (!mask && layer.mask) layer.mask = nil;

    if (![layer animationForKey:@"did.album.rotation"]) {
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        a.fromValue = @(0.0);
        a.toValue = @(M_PI * 2.0);
        a.duration = DIDRotationDuration();
        a.repeatCount = HUGE_VALF;
        a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        a.removedOnCompletion = NO;
        [layer addAnimation:a forKey:@"did.album.rotation"];
    }
}

static void DIDStopAlbumRotation(UIView *root, NSInteger depth) {
    if (!root || depth < 0) return;
    [root.layer removeAnimationForKey:@"did.album.rotation"];
    for (UIView *sub in root.subviews) DIDStopAlbumRotation(sub, depth - 1);
}

#pragma mark - 精灵放置

static const void *DIDDanceSpriteKey = &DIDDanceSpriteKey;
static const void *DIDEyeSpriteKey   = &DIDEyeSpriteKey;
static const void *DIDPlaceScheduledKey = &DIDPlaceScheduledKey;

static CGFloat DIDSpriteSide(NSInteger kind, CGSize pillSize, CGFloat configured) {
    CGFloat side = MIN(configured, pillSize.height);
    if (side > pillSize.width) side = pillSize.width;
    return MAX(4.0, side);
}

static void DIDDoPlace(UIView *pill, NSInteger kind) {
    if (!pill || !pill.window) return;
    const void *key = kind == 0 ? DIDDanceSpriteKey : DIDEyeSpriteKey;
    DIDSpriteView *sprite = objc_getAssociatedObject(pill, key);

    BOOL allowed = kind == 0 ? DIDDanceEnabled() : DIDEyeEnabled();
    NSArray<UIImage *> *frames = allowed ? DIDLoadFrames(kind) : nil;
    if (frames.count == 0) {
        if (sprite.superview) [sprite removeFromSuperview];
        return;
    }

    CGSize ps = pill.bounds.size;
    if (ps.width < 8 || ps.height < 8) return;

    if (!sprite) {
        sprite = [[DIDSpriteView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(pill, key, sprite, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    CGFloat configured = DIDFloat(kind == 0 ? @"danceAnimationSize" : @"eyeAnimationSize", 22.0, 4.0, 64.0);
    CGFloat side = DIDSpriteSide(kind, ps, configured);
    CGFloat offX = DIDFloat(kind == 0 ? @"plugin3XOffset" : @"plugin2XOffset", 0.0, -120.0, 120.0);
    CGFloat offY = DIDFloat(kind == 0 ? @"plugin3YOffset" : @"plugin2YOffset", 0.0, -60.0, 60.0);

    CGPoint c = CGPointMake(ps.width / 2.0 + offX, ps.height / 2.0 + offY);
    c.x = MAX(side / 2.0, MIN(ps.width - side / 2.0, c.x));
    c.y = MAX(side / 2.0, MIN(ps.height - side / 2.0, c.y));

    if (sprite.superview != pill) {
        [sprite removeFromSuperview];
        [pill addSubview:sprite];
    }
    if (pill.subviews.lastObject != sprite) [pill bringSubviewToFront:sprite];

    CGRect want = CGRectMake(c.x - side / 2.0, c.y - side / 2.0, side, side);
    if (!CGRectEqualToRect(sprite.frame, want)) {
        [UIView performWithoutAnimation:^{ sprite.frame = want; }];
    }
    if (sprite.hidden) sprite.hidden = NO;

    CGFloat fps = DIDFloat(kind == 0 ? @"frameAnimationSpeed" : @"eyeFrameAnimationSpeed", 12.0, 1.0, 60.0);
    [sprite playFrames:frames fps:fps];
}

// 布局回调里不要直接改层级，合并到下一轮主队列执行。
static void DIDRequestPlace(UIView *pill, NSInteger kind) {
    if (!pill) return;
    NSNumber *flag = objc_getAssociatedObject(pill, DIDPlaceScheduledKey);
    if (flag.boolValue) return;
    objc_setAssociatedObject(pill, DIDPlaceScheduledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakPill = pill;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *strongPill = weakPill;
        objc_setAssociatedObject(strongPill, DIDPlaceScheduledKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        @try { DIDDoPlace(strongPill, kind); } @catch (...) {}
    });
}

static void DIDScanAllPills(void) {
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
    NSMutableArray<UIView *> *pills = [NSMutableArray array];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if ([NSStringFromClass(v.class) isEqualToString:@"SBSystemApertureContainerView"]) [pills addObject:v];
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    for (UIView *pill in pills) {
        @try {
            if (DIDPillIsNowPlaying(pill)) {
                DIDApplyAlbumRotation(pill);
                DIDDoPlace(pill, 0);
            }
            if (DIDEyeEnabled() && DIDPillIsRecording(pill)) DIDDoPlace(pill, 1);
        } @catch (...) {}
    }
    DIDLog(@"scan pills=%lu", (unsigned long)pills.count);
}

static void DIDScheduleScan(NSString *reason, double delay) {
    (void)reason;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @try { DIDScanAllPills(); } @catch (...) {}
    });
}

static void DIDRemoveSprites(void) {
    NSMutableArray<UIView *> *stack = [NSMutableArray array];
    for (UIWindow *w in DIDAllWindows()) [stack addObject:w];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        id d = objc_getAssociatedObject(v, DIDDanceSpriteKey);
        if (d) { [d stopFrames]; [d removeFromSuperview]; objc_setAssociatedObject(v, DIDDanceSpriteKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        id e = objc_getAssociatedObject(v, DIDEyeSpriteKey);
        if (e) { [e stopFrames]; [e removeFromSuperview]; objc_setAssociatedObject(v, DIDEyeSpriteKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
}

#pragma mark - iOS17 岛屿圆化

static BOOL gDIDInSetFrame = NO;

static CGRect DIDReshapedFrame(UIView *container, CGRect frame) {
    if (!DIDEnabled() || !DIDIOS17Adaptation()) return frame;
    CGFloat w = frame.size.width, h = frame.size.height;
    if (w < 1.0 || h < 1.0) return frame;
    if (!DIDPillIsNowPlayingFast(container)) return frame;

    if (w <= 50.0 && h >= 16.0 && h <= 60.0) {
        CGFloat side = MAX(h, 36.6667);
        return CGRectMake(CGRectGetMidX(frame) - side / 2.0, frame.origin.y, side, side);
    }
    if (DIDTagMatches(container, @"NowPlaying") && w >= 170.0 && w <= 215.0 && h >= 24.0 && h <= 60.0) {
        return CGRectMake(CGRectGetMidX(frame) - 193.0 / 2.0, frame.origin.y, 193.0, h);
    }
    return frame;
}

#pragma mark - Hooks

%hook SBSystemApertureContainerView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
    @try {
        UIView *pill = (UIView *)self;
        if (DIDPillIsNowPlaying(pill)) {
            DIDApplyAlbumRotation(pill);
            DIDRequestPlace(pill, 0);
        }
        if (DIDEyeEnabled() && DIDPillIsRecording(pill)) DIDRequestPlace(pill, 1);
    } @catch (...) {}
}

- (void)didMoveToWindow {
    %orig;
    if (!DIDEnabled()) return;
    @try {
        UIView *pill = (UIView *)self;
        if (DIDPillIsNowPlaying(pill)) { DIDApplyAlbumRotation(pill); DIDRequestPlace(pill, 0); }
        if (DIDEyeEnabled() && DIDPillIsRecording(pill)) DIDRequestPlace(pill, 1);
    } @catch (...) {}
}

- (void)setFrame:(CGRect)frame {
    CGRect target = frame;
    if (!gDIDInSetFrame) {
        @try {
            CGRect reshaped = DIDReshapedFrame((UIView *)self, frame);
            if (!CGSizeEqualToSize(reshaped.size, frame.size) ||
                fabs(reshaped.origin.x - frame.origin.x) > 0.01) {
                target = reshaped;
            }
        } @catch (...) { target = frame; }
    }
    gDIDInSetFrame = YES;
    %orig(target);
    gDIDInSetFrame = NO;
}

%end

%hook _SAUIProvidedViewContainerView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
    @try {
        UIView *pill = DIDPillForView((UIView *)self);
        if (!pill) return;
        if (DIDPillIsNowPlaying(pill)) { DIDApplyAlbumRotation(pill); DIDRequestPlace(pill, 0); }
        if (DIDEyeEnabled() && DIDPillIsRecording(pill)) DIDRequestPlace(pill, 1);
    } @catch (...) {}
}

%end

%hook SAUIElementView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
    @try {
        UIView *element = (UIView *)self;
        NSString *ident = element.accessibilityIdentifier;
        BOOL recording = [ident isKindOfClass:[NSString class]] && [ident containsString:@"ScreenRecording"];
        if (DIDEyeEnabled() && recording) {
            UIView *pill = DIDPillForView(element);
            if (pill) DIDRequestPlace(pill, 1);
        }
    } @catch (...) {}
}

%end

%hook MRUArtworkView

- (void)layoutSubviews {
    %orig;
    if (!DIDEnabled()) return;
    @try {
        UIView *pill = DIDPillForView((UIView *)self);
        if (pill) DIDApplyAlbumRotation(pill);
    } @catch (...) {}
}

%end

#pragma mark - 设置变更

static void DIDApplySettingsChange(void) {
    DIDReloadPrefs(YES);
    DIDClearFrameCache();
    DIDLog(@"settings changed");

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!DIDEnabled()) {
            DIDRemoveSprites();
            for (UIWindow *w in DIDAllWindows()) DIDStopAlbumRotation(w, 12);
            return;
        }
        DIDScanAllPills();
    });
}

static void DIDPreload(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        DIDReloadPrefs(YES);
        NSUInteger dance = DIDLoadFrames(0).count;
        NSUInteger eye = DIDLoadFrames(1).count;
        DIDLog(@"preload completed: %lu dance, %lu eye", (unsigned long)dance, (unsigned long)eye);
    });
}

#pragma mark - ctor

%ctor {
    @autoreleasepool {
        DIDLog(@"===== DynamicIslandDance v%@ loaded (pid %d) =====", DIDVersion, getpid());
        DIDLog(@"bundled root = %@", DIDBundledRoot() ?: @"(not found)");
        DIDLog(@"themes dance=%@ eye=%@ mask=%@",
               DIDAvailableThemes(0), DIDAvailableThemes(1), DIDAvailableThemes(2));
        int token = 0;
        notify_register_dispatch(DIDPrefNotify, &token, dispatch_get_main_queue(), ^(__unused int t) {
            DIDApplySettingsChange();
        });
        [[NSNotificationCenter defaultCenter] addObserverForName:UIScreenCapturedDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            BOOL captured = [UIScreen mainScreen].isCaptured;
            DIDLog(@"capture changed -> %d", captured);
            DIDScheduleScan(@"capture", captured ? 0.25 : 0.05);
            DIDScheduleScan(@"capture-late", 0.9);
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(__unused NSNotification *n) {
            DIDScheduleScan(@"active", 0.4);
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DIDPreload();
            DIDScheduleScan(@"launch", 0.5);
        });
    }
}