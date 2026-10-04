#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static CGFloat FLTCell(NSString *ch, CGFloat digitW, NSDictionary *attrs) {
    unichar c = [ch characterAtIndex:0];
    if (c >= '0' && c <= '9') return digitW;
    return [ch sizeWithAttributes:attrs].width;
}

@interface FLTDigitsView : UIView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, strong) UIFont *font;
@end

@implementation FLTDigitsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    return self;
}

- (void)setText:(NSString *)text {
    if ([_text isEqualToString:text]) return;
    _text = [text copy];
    [self setNeedsDisplay];
}

- (void)setColor:(UIColor *)color {
    _color = color;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (!self.text || !self.font || !self.color) return;
    NSDictionary *attrs = @{NSFontAttributeName: self.font,
                            NSForegroundColorAttributeName: self.color};

    CGFloat digitW = 0;
    for (int i = 0; i < 10; i++) {
        NSString *d = [NSString stringWithFormat:@"%d", i];
        CGFloat w = [d sizeWithAttributes:attrs].width;
        if (w > digitW) digitW = w;
    }

    CGFloat total = 0;
    for (NSUInteger i = 0; i < self.text.length; i++) {
        NSString *ch = [self.text substringWithRange:NSMakeRange(i, 1)];
        total += FLTCell(ch, digitW, attrs);
    }

    CGFloat scale = 1.0;
    if (total > self.bounds.size.width) {
        scale = self.bounds.size.width / total;
    }
    CGFloat lineH = self.font.lineHeight;
    CGFloat sx = (self.bounds.size.width - total * scale) / 2;
    CGFloat sy = (self.bounds.size.height - lineH * scale) / 2;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx, sx, sy);
    CGContextScaleCTM(ctx, scale, scale);

    CGFloat x = 0;
    for (NSUInteger i = 0; i < self.text.length; i++) {
        NSString *ch = [self.text substringWithRange:NSMakeRange(i, 1)];
        CGFloat cw = FLTCell(ch, digitW, attrs);
        CGFloat w = [ch sizeWithAttributes:attrs].width;
        [ch drawAtPoint:CGPointMake(x + (cw - w) / 2, 0) withAttributes:attrs];
        x += cw;
    }
    CGContextRestoreGState(ctx);
}

@end

@interface FLTCardView : UIView
@property (nonatomic) BOOL going;
@property (nonatomic) CFTimeInterval t0;
@property (nonatomic) CFTimeInterval banked;
@property (nonatomic) NSInteger tint;
@property (nonatomic, strong) FLTDigitsView *digits;
@property (nonatomic, strong) UIButton *playBtn;
@property (nonatomic, strong) UIButton *resetBtn;
@property (nonatomic, strong) UIButton *tintBtn;
@end

@implementation FLTCardView

- (instancetype)initWithOrigin:(CGPoint)o {
    CGRect f = CGRectMake(o.x, o.y, 264, 104);
    self = [super initWithFrame:f];
    if (!self) return nil;

    self.backgroundColor = [UIColor blackColor];
    self.layer.cornerRadius = 14;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.45;
    self.layer.shadowRadius = 8;
    self.layer.shadowOffset = CGSizeMake(0, 3);

    self.digits =
        [[FLTDigitsView alloc] initWithFrame:CGRectMake(8, 8, 248, 52)];
    UIFont *font = [UIFont fontWithName:@"Georgia" size:40];
    if (!font) font = [UIFont systemFontOfSize:40];
    self.digits.font = font;
    [self addSubview:self.digits];

    self.playBtn = [self roundButton:@"\u25B6\uFE0E"
                                   x:71
                              action:@selector(onPlay)];
    self.resetBtn = [self roundButton:@"\u21BA"
                                    x:117
                               action:@selector(onReset)];
    self.tintBtn = [self roundButton:@"\u25CF"
                                   x:163
                              action:@selector(onTint)];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                action:@selector(onDrag:)];
    [self addGestureRecognizer:pan];

    CADisplayLink *link =
        [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrame)];
    link.preferredFramesPerSecond = 30;
    [link addToRunLoop:[NSRunLoop mainRunLoop]
               forMode:NSRunLoopCommonModes];

    [self applyTint];
    [self redraw];
    return self;
}

- (UIButton *)roundButton:(NSString *)title x:(CGFloat)x action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(x, 66, 30, 30);
    b.layer.cornerRadius = 15;
    b.layer.borderWidth = 1;
    b.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:1.0].CGColor;
    b.titleLabel.font = [UIFont systemFontOfSize:14];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor colorWithWhite:0.85 alpha:1.0]
            forState:UIControlStateNormal];
    [b addTarget:self
          action:sel
forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    return b;
}

- (UIColor *)tintColorForIndex:(NSInteger)i {
    if (i == 1) {
        return [UIColor colorWithRed:0.20 green:0.52 blue:1.0 alpha:1.0];
    }
    if (i == 2) {
        return [UIColor colorWithRed:0.55 green:0.82 blue:1.0 alpha:1.0];
    }
    return [UIColor whiteColor];
}

- (void)applyTint {
    UIColor *c = [self tintColorForIndex:self.tint];
    self.digits.color = c;
    [self.tintBtn setTitleColor:c forState:UIControlStateNormal];
}

- (CFTimeInterval)total {
    if (self.going) {
        return self.banked + (CACurrentMediaTime() - self.t0);
    }
    return self.banked;
}

- (void)onPlay {
    CFTimeInterval now = CACurrentMediaTime();
    if (self.going) {
        self.banked += now - self.t0;
        self.going = NO;
        [self.playBtn setTitle:@"\u25B6\uFE0E" forState:UIControlStateNormal];
    } else {
        self.t0 = now;
        self.going = YES;
        [self.playBtn setTitle:@"\u2759\u2759" forState:UIControlStateNormal];
    }
    [self redraw];
}

- (void)onReset {
    self.going = NO;
    self.banked = 0;
    [self.playBtn setTitle:@"\u25B6\uFE0E" forState:UIControlStateNormal];
    [self redraw];
}

- (void)onTint {
    self.tint = (self.tint + 1) % 3;
    [self applyTint];
}

- (void)onDrag:(UIPanGestureRecognizer *)g {
    UIView *host = self.superview;
    CGPoint d = [g translationInView:host];
    CGFloat hw = self.bounds.size.width / 2;
    CGFloat hh = self.bounds.size.height / 2;
    CGFloat x = self.center.x + d.x;
    CGFloat y = self.center.y + d.y;
    x = fmax(hw, fmin(x, host.bounds.size.width - hw));
    y = fmax(hh, fmin(y, host.bounds.size.height - hh));
    self.center = CGPointMake(x, y);
    [g setTranslation:CGPointZero inView:host];
}

- (void)onFrame {
    if (self.going) {
        [self redraw];
    }
}

- (void)redraw {
    CFTimeInterval e = [self total];
    if (e < 0) e = 0;
    long long tenths = (long long)(e * 10.0);
    long long d = tenths % 10;
    long long sec = tenths / 10;
    long long s = sec % 60;
    long long m = (sec / 60) % 60;
    long long h = sec / 3600;
    self.digits.text =
        [NSString stringWithFormat:@"%02lld: %02lld: %02lld. %lld",
         h, m, s, d];
}

@end

@interface FLTHostWindow : UIWindow
@end

@implementation FLTHostWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (v == self) return nil;
    if (v == self.rootViewController.view) return nil;
    return v;
}
@end

static FLTHostWindow *sHost;
static FLTCardView *sCard;

static void FLTShow(void) {
    if (sHost) return;

    CGRect screen = [UIScreen mainScreen].bounds;
    FLTHostWindow *w = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]]) {
                w = [[FLTHostWindow alloc]
                     initWithWindowScene:(UIWindowScene *)sc];
                break;
            }
        }
    }
    if (!w) {
        w = [[FLTHostWindow alloc] initWithFrame:screen];
    }

    w.frame = screen;
    w.windowLevel = UIWindowLevelAlert + 100;
    w.backgroundColor = [UIColor clearColor];

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    w.rootViewController = vc;

    CGFloat x = (screen.size.width - 264) / 2;
    sCard = [[FLTCardView alloc] initWithOrigin:CGPointMake(x, 70)];
    [vc.view addSubview:sCard];

    w.hidden = NO;
    sHost = w;
}

__attribute__((constructor))
static void FLTBoot(void) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{ FLTShow(); });
    }];
}
