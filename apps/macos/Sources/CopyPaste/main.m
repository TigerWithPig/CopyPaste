#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const CSKindText = @"text";
static NSString * const CSKindLink = @"link";
static NSString * const CSKindImage = @"image";
static NSString * const CSKindFile = @"file";
static NSString * const CSAppearanceModeLight = @"light";
static NSString * const CSAppearanceModeDark = @"dark";
static NSString * const CSAppearanceModeSystem = @"system";
static NSString * const CSPanelSizeModeTemporary = @"temporary";
static NSString * const CSPanelSizeModeSaved = @"saved";
static NSString * const CSPanelPositionModeDefault = @"default";
static NSString * const CSPanelPositionModeCustom = @"custom";
static NSString * const CSPanelPositionModeLast = @"last";
static NSString * const CSPanelPositionModeMouse = @"mouse";
static NSString * const CSPanelPositionModeInput = @"input";
static NSString * const CSInterfaceStyleClassic = @"classic";
static NSString * const CSInterfaceStyleModern = @"modern";
static UInt32 const CSHotKeySignature = 'CPST';

static NSString *CSUUID(void) {
    return NSUUID.UUID.UUIDString;
}

static NSString *CSTrim(NSString *value) {
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

static NSString *CSCondense(NSString *value) {
    NSArray<NSString *> *parts = [value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSString *part, NSDictionary *bindings) {
        return part.length > 0;
    }];
    return [[parts filteredArrayUsingPredicate:predicate] componentsJoinedByString:@" "];
}

static NSString *CSTruncate(NSString *value, NSUInteger length) {
    if (value.length <= length) {
        return value ?: @"";
    }
    return [[value substringToIndex:length] stringByAppendingString:@"..."];
}

static NSString *CSKindTitle(NSString *kind) {
    if ([kind isEqualToString:CSKindLink]) return @"链接";
    if ([kind isEqualToString:CSKindImage]) return @"图片";
    if ([kind isEqualToString:CSKindFile]) return @"文件";
    return @"文本";
}

static NSString *CSKindSymbol(NSString *kind) {
    if ([kind isEqualToString:CSKindLink]) return @"link";
    if ([kind isEqualToString:CSKindImage]) return @"photo";
    if ([kind isEqualToString:CSKindFile]) return @"doc";
    return @"text.alignleft";
}

static NSString *CSSHA256(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding] ?: NSData.data;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);

    NSMutableString *result = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

static NSString *CSDominantTitle(NSString *text) {
    NSString *trimmed = CSTrim(text);
    if (trimmed.length == 0) {
        return @"空文本";
    }
    NSString *firstLine = [trimmed componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet].firstObject ?: trimmed;
    return CSTruncate(CSCondense(firstLine), 58);
}

static BOOL CSIsLikelyURL(NSString *value) {
    NSURLComponents *components = [NSURLComponents componentsWithString:CSTrim(value)];
    NSString *scheme = components.scheme.lowercaseString;
    if (scheme.length == 0) {
        return NO;
    }
    if ([scheme isEqualToString:@"mailto"]) {
        return YES;
    }
    return ([@[@"http", @"https", @"ftp"] containsObject:scheme] && components.host.length > 0);
}

static NSString *CSRelativeDate(NSNumber *timestamp) {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:timestamp.doubleValue];
    NSRelativeDateTimeFormatter *formatter = NSRelativeDateTimeFormatter.new;
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_Hans_CN"];
    formatter.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleShort;
    return [formatter localizedStringForDate:date relativeToDate:NSDate.date];
}

static NSColor *CSColorFromHex(NSString *hex, CGFloat alpha) {
    NSString *clean = [[hex ?: @"" stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    unsigned int value = 0;
    if (clean.length != 6 || ![[NSScanner scannerWithString:clean] scanHexInt:&value]) {
        return [NSColor.systemTealColor colorWithAlphaComponent:alpha];
    }
    CGFloat red = ((value >> 16) & 0xff) / 255.0;
    CGFloat green = ((value >> 8) & 0xff) / 255.0;
    CGFloat blue = (value & 0xff) / 255.0;
    return [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

static CGFloat CSClampCGFloat(CGFloat value, CGFloat lower, CGFloat upper) {
    return MIN(MAX(value, lower), upper);
}

static CGFloat CSPanelOpacityFromPreferences(NSDictionary *preferences) {
    id value = preferences[@"panelOpacity"];
    if (![value respondsToSelector:@selector(doubleValue)]) {
        return 0.90;
    }
    return CSClampCGFloat([value doubleValue], 0.55, 1.0);
}

static CGFloat CSTransparencyPercentFromPreferences(NSDictionary *preferences) {
    return (1.0 - CSPanelOpacityFromPreferences(preferences)) * 100.0;
}

static NSString *CSAppearanceModeFromPreferences(NSDictionary *preferences) {
    NSString *mode = preferences[@"appearanceMode"];
    if ([mode isEqualToString:CSAppearanceModeLight] ||
        [mode isEqualToString:CSAppearanceModeDark] ||
        [mode isEqualToString:CSAppearanceModeSystem]) {
        return mode;
    }
    return CSAppearanceModeSystem;
}

static NSAppearance *CSAppearanceFromMode(NSString *mode) {
    if ([mode isEqualToString:CSAppearanceModeLight]) {
        return [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    }
    if ([mode isEqualToString:CSAppearanceModeDark]) {
        return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    }
    return nil;
}

static NSString *CSInterfaceStyleFromPreferences(NSDictionary *preferences) {
    NSString *style = preferences[@"interfaceStyle"];
    if ([style isEqualToString:CSInterfaceStyleModern]) {
        return style;
    }
    return CSInterfaceStyleClassic;
}

static NSString *CSPanelSizeModeFromPreferences(NSDictionary *preferences) {
    NSString *mode = preferences[@"panelSizeMode"];
    if ([mode isEqualToString:CSPanelSizeModeSaved]) {
        return mode;
    }
    return CSPanelSizeModeTemporary;
}

static NSString *CSPanelPositionModeFromPreferences(NSDictionary *preferences) {
    NSString *mode = preferences[@"panelPositionMode"];
    if ([mode isEqualToString:CSPanelPositionModeCustom] ||
        [mode isEqualToString:CSPanelPositionModeLast] ||
        [mode isEqualToString:CSPanelPositionModeMouse] ||
        [mode isEqualToString:CSPanelPositionModeInput]) {
        return mode;
    }
    return CSPanelPositionModeDefault;
}

static NSDictionary *CSFramePreferenceFromRect(NSRect frame) {
    return @{
        @"x": @(frame.origin.x),
        @"y": @(frame.origin.y),
        @"width": @(frame.size.width),
        @"height": @(frame.size.height)
    };
}

static BOOL CSRectFromFramePreference(id value, NSRect *rect) {
    if (![value isKindOfClass:NSDictionary.class]) {
        return NO;
    }
    NSDictionary *dictionary = value;
    id x = dictionary[@"x"];
    id y = dictionary[@"y"];
    id width = dictionary[@"width"];
    id height = dictionary[@"height"];
    if (![x respondsToSelector:@selector(doubleValue)] ||
        ![y respondsToSelector:@selector(doubleValue)] ||
        ![width respondsToSelector:@selector(doubleValue)] ||
        ![height respondsToSelector:@selector(doubleValue)]) {
        return NO;
    }
    NSRect candidate = NSMakeRect([x doubleValue], [y doubleValue], [width doubleValue], [height doubleValue]);
    if (candidate.size.width < 640 || candidate.size.height < 360) {
        return NO;
    }
    if (rect) {
        *rect = candidate;
    }
    return YES;
}

static NSScreen *CSScreenForPoint(NSPoint point) {
    for (NSScreen *screen in NSScreen.screens) {
        if (NSPointInRect(point, screen.frame)) {
            return screen;
        }
    }
    return NSScreen.mainScreen ?: NSScreen.screens.firstObject;
}

static NSScreen *CSScreenForRect(NSRect rect) {
    NSPoint center = NSMakePoint(NSMidX(rect), NSMidY(rect));
    return CSScreenForPoint(center);
}

static NSRect CSClampFrameToVisibleScreen(NSRect frame, NSScreen *screen) {
    NSScreen *targetScreen = screen ?: CSScreenForRect(frame);
    NSRect visible = targetScreen.visibleFrame;
    frame.size.width = MIN(MAX(frame.size.width, 640), visible.size.width);
    frame.size.height = MIN(MAX(frame.size.height, 360), visible.size.height);
    frame.origin.x = CSClampCGFloat(frame.origin.x, NSMinX(visible), NSMaxX(visible) - frame.size.width);
    frame.origin.y = CSClampCGFloat(frame.origin.y, NSMinY(visible), NSMaxY(visible) - frame.size.height);
    return frame;
}

static UInt32 CSCarbonModifiersFromEvent(NSEvent *event) {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    UInt32 modifiers = 0;
    if (flags & NSEventModifierFlagCommand) modifiers |= cmdKey;
    if (flags & NSEventModifierFlagShift) modifiers |= shiftKey;
    if (flags & NSEventModifierFlagOption) modifiers |= optionKey;
    if (flags & NSEventModifierFlagControl) modifiers |= controlKey;
    return modifiers;
}

static UInt32 CSCarbonModifiersFromCGEvent(CGEventRef event) {
    CGEventFlags flags = CGEventGetFlags(event);
    UInt32 modifiers = 0;
    if (flags & kCGEventFlagMaskCommand) modifiers |= cmdKey;
    if (flags & kCGEventFlagMaskShift) modifiers |= shiftKey;
    if (flags & kCGEventFlagMaskAlternate) modifiers |= optionKey;
    if (flags & kCGEventFlagMaskControl) modifiers |= controlKey;
    return modifiers;
}

static NSString *CSKeyDisplayFromKeyCode(UInt32 keyCode, NSString *fallback) {
    NSDictionary<NSNumber *, NSString *> *specialKeys = @{
        @(kVK_ANSI_A): @"A",
        @(kVK_ANSI_B): @"B",
        @(kVK_ANSI_C): @"C",
        @(kVK_ANSI_D): @"D",
        @(kVK_ANSI_E): @"E",
        @(kVK_ANSI_F): @"F",
        @(kVK_ANSI_G): @"G",
        @(kVK_ANSI_H): @"H",
        @(kVK_ANSI_I): @"I",
        @(kVK_ANSI_J): @"J",
        @(kVK_ANSI_K): @"K",
        @(kVK_ANSI_L): @"L",
        @(kVK_ANSI_M): @"M",
        @(kVK_ANSI_N): @"N",
        @(kVK_ANSI_O): @"O",
        @(kVK_ANSI_P): @"P",
        @(kVK_ANSI_Q): @"Q",
        @(kVK_ANSI_R): @"R",
        @(kVK_ANSI_S): @"S",
        @(kVK_ANSI_T): @"T",
        @(kVK_ANSI_U): @"U",
        @(kVK_ANSI_V): @"V",
        @(kVK_ANSI_W): @"W",
        @(kVK_ANSI_X): @"X",
        @(kVK_ANSI_Y): @"Y",
        @(kVK_ANSI_Z): @"Z",
        @(kVK_ANSI_0): @"0",
        @(kVK_ANSI_1): @"1",
        @(kVK_ANSI_2): @"2",
        @(kVK_ANSI_3): @"3",
        @(kVK_ANSI_4): @"4",
        @(kVK_ANSI_5): @"5",
        @(kVK_ANSI_6): @"6",
        @(kVK_ANSI_7): @"7",
        @(kVK_ANSI_8): @"8",
        @(kVK_ANSI_9): @"9",
        @(kVK_ANSI_Minus): @"-",
        @(kVK_ANSI_Equal): @"=",
        @(kVK_ANSI_LeftBracket): @"[",
        @(kVK_ANSI_RightBracket): @"]",
        @(kVK_ANSI_Backslash): @"\\",
        @(kVK_ANSI_Semicolon): @";",
        @(kVK_ANSI_Quote): @"'",
        @(kVK_ANSI_Grave): @"`",
        @(kVK_ANSI_Comma): @",",
        @(kVK_ANSI_Period): @".",
        @(kVK_ANSI_Slash): @"/",
        @(kVK_Space): @"Space",
        @(kVK_Return): @"Return",
        @(kVK_ANSI_KeypadEnter): @"Enter",
        @(kVK_Tab): @"Tab",
        @(kVK_Escape): @"Esc",
        @(kVK_Delete): @"Delete",
        @(kVK_ForwardDelete): @"Forward Delete",
        @(kVK_LeftArrow): @"Left",
        @(kVK_RightArrow): @"Right",
        @(kVK_UpArrow): @"Up",
        @(kVK_DownArrow): @"Down",
        @(kVK_F1): @"F1",
        @(kVK_F2): @"F2",
        @(kVK_F3): @"F3",
        @(kVK_F4): @"F4",
        @(kVK_F5): @"F5",
        @(kVK_F6): @"F6",
        @(kVK_F7): @"F7",
        @(kVK_F8): @"F8",
        @(kVK_F9): @"F9",
        @(kVK_F10): @"F10",
        @(kVK_F11): @"F11",
        @(kVK_F12): @"F12"
    };
    NSString *special = specialKeys[@(keyCode)];
    if (special.length > 0) {
        return special;
    }
    NSString *trimmed = CSTrim(fallback ?: @"");
    if (trimmed.length > 0) {
        return trimmed.uppercaseString;
    }
    return [NSString stringWithFormat:@"Key %u", keyCode];
}

static NSString *CSHotKeyDisplay(UInt32 keyCode, UInt32 modifiers, NSString *fallbackKey) {
    NSMutableString *display = NSMutableString.string;
    if (modifiers & controlKey) [display appendString:@"⌃"];
    if (modifiers & optionKey) [display appendString:@"⌥"];
    if (modifiers & shiftKey) [display appendString:@"⇧"];
    if (modifiers & cmdKey) [display appendString:@"⌘"];
    [display appendString:CSKeyDisplayFromKeyCode(keyCode, fallbackKey)];
    return display;
}

static NSDictionary *CSHotKeyPreference(UInt32 keyCode, UInt32 modifiers, NSString *display) {
    NSString *displayName = display.length > 0 ? display : CSHotKeyDisplay(keyCode, modifiers, nil);
    return @{
        @"keyCode": @(keyCode),
        @"modifiers": @(modifiers),
        @"display": displayName
    };
}

static NSDictionary *CSDefaultHotKeyPreference(void) {
    return CSHotKeyPreference(kVK_ANSI_V, cmdKey | shiftKey, @"⇧⌘V");
}

static NSDictionary *CSHotKeyFromPreferences(NSDictionary *preferences) {
    NSDictionary *hotKey = preferences[@"hotKey"];
    if (![hotKey isKindOfClass:NSDictionary.class]) {
        return CSDefaultHotKeyPreference();
    }

    id keyCodeValue = hotKey[@"keyCode"];
    id modifiersValue = hotKey[@"modifiers"];
    if (![keyCodeValue respondsToSelector:@selector(unsignedIntValue)] ||
        ![modifiersValue respondsToSelector:@selector(unsignedIntValue)]) {
        return CSDefaultHotKeyPreference();
    }

    UInt32 keyCode = [keyCodeValue unsignedIntValue];
    UInt32 modifiers = [modifiersValue unsignedIntValue] & (cmdKey | shiftKey | optionKey | controlKey);
    if ((modifiers & (cmdKey | optionKey | controlKey)) == 0) {
        return CSDefaultHotKeyPreference();
    }

    NSString *display = [hotKey[@"display"] isKindOfClass:NSString.class] ? hotKey[@"display"] : nil;
    return CSHotKeyPreference(keyCode, modifiers, display);
}

static NSTextField *CSLabel(NSString *text, NSFont *font, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:text ?: @""];
    label.font = font;
    label.textColor = color ?: NSColor.labelColor;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

static NSData *CSPNGDataFromImage(NSImage *image, CGFloat maxPixelSize) {
    if (image.size.width <= 0 || image.size.height <= 0) {
        return nil;
    }

    CGFloat scale = MIN(1.0, maxPixelSize / MAX(image.size.width, image.size.height));
    NSSize targetSize = NSMakeSize(image.size.width * scale, image.size.height * scale);
    NSImage *target = [[NSImage alloc] initWithSize:targetSize];
    [target lockFocus];
    [image drawInRect:NSMakeRect(0, 0, targetSize.width, targetSize.height)
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1.0];
    [target unlockFocus];

    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:target.TIFFRepresentation];
    return [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}

static void CSClearSubviews(NSView *view) {
    for (NSView *subview in view.subviews.copy) {
        [subview removeFromSuperview];
    }
}

static void CSClearStack(NSStackView *stack) {
    for (NSView *view in stack.arrangedSubviews.copy) {
        [stack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
}

@interface CSActionButton : NSButton
@property (nonatomic, copy) void (^handler)(void);
+ (instancetype)buttonWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(void (^)(void))handler;
@end

@implementation CSActionButton
+ (instancetype)buttonWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(void (^)(void))handler {
    CSActionButton *button = [[CSActionButton alloc] initWithFrame:NSZeroRect];
    button.title = title ?: @"";
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeRegular;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    button.handler = handler;
    button.target = button;
    button.action = @selector(runAction:);
    if (symbol.length > 0) {
        button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
        button.imagePosition = title.length > 0 ? NSImageLeft : NSImageOnly;
    }
    return button;
}

- (void)runAction:(id)sender {
    if (self.handler) {
        self.handler();
    }
}
@end

@interface CSFlippedView : NSView
@end

@implementation CSFlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface CSCardView : NSView
@property (nonatomic, copy) void (^singleClick)(NSEvent *event);
@property (nonatomic, copy) void (^doubleClick)(NSEvent *event);
@property (nonatomic, copy) NSString *itemID;
@end

@implementation CSCardView
- (void)mouseDown:(NSEvent *)event {
    if (event.clickCount >= 2) {
        if (self.doubleClick) self.doubleClick(event);
    } else {
        if (self.singleClick) self.singleClick(event);
    }
}
@end

@interface CSFloatingPanel : NSPanel
@property (nonatomic, copy) void (^returnKeyHandler)(BOOL plainText);
@property (nonatomic, copy) void (^leftKeyHandler)(void);
@property (nonatomic, copy) void (^rightKeyHandler)(void);
@property (nonatomic, copy) void (^deleteKeyHandler)(void);
@property (nonatomic, copy) void (^selectAllKeyHandler)(void);
@property (nonatomic, copy) BOOL (^mouseDownHandler)(NSEvent *event);
@end

@implementation CSFloatingPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
- (void)sendEvent:(NSEvent *)event {
    if ((event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown) && self.mouseDownHandler) {
        if (self.mouseDownHandler(event)) {
            return;
        }
    }
    [super sendEvent:event];
}

- (void)keyDown:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL commandOnly = (flags & NSEventModifierFlagCommand) &&
        !(flags & (NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl));
    if (commandOnly && event.keyCode == kVK_ANSI_A) {
        if (self.selectAllKeyHandler) {
            self.selectAllKeyHandler();
        }
        return;
    }
    if (event.keyCode == kVK_Escape) {
        if (self.mouseDownHandler && self.mouseDownHandler(event)) {
            return;
        }
    }
    if (event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter) {
        if (self.returnKeyHandler) {
            BOOL shiftPressed = (flags & NSEventModifierFlagShift) == NSEventModifierFlagShift;
            self.returnKeyHandler(shiftPressed);
        }
        return;
    }
    if (event.keyCode == kVK_LeftArrow) {
        if (self.leftKeyHandler) {
            self.leftKeyHandler();
        }
        return;
    }
    if (event.keyCode == kVK_RightArrow) {
        if (self.rightKeyHandler) {
            self.rightKeyHandler();
        }
        return;
    }
    if (event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete) {
        if (self.deleteKeyHandler) {
            self.deleteKeyHandler();
        }
        return;
    }
    [super keyDown:event];
}
@end

@interface CSSearchField : NSSearchField
@property (nonatomic, copy) void (^emptyCommandAHandler)(void);
@end

@implementation CSSearchField
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    BOOL commandPressed = (event.modifierFlags & NSEventModifierFlagCommand) == NSEventModifierFlagCommand;
    NSString *key = event.charactersIgnoringModifiers.lowercaseString ?: @"";
    if (commandPressed && [key isEqualToString:@"a"]) {
        if (self.stringValue.length == 0 && self.emptyCommandAHandler) {
            self.emptyCommandAHandler();
            return YES;
        }
        NSText *editor = self.currentEditor;
        if (editor) {
            [editor selectAll:nil];
        } else {
            [self selectText:nil];
        }
        return YES;
    }
    return [super performKeyEquivalent:event];
}
@end

@interface CSHotKeyRecorder : NSTextField
@property (nonatomic, copy) NSString *restingDisplayValue;
@property (nonatomic, copy) void (^hotKeyChanged)(UInt32 keyCode, UInt32 modifiers, NSString *displayName);
@property (nonatomic, copy) void (^recordingChanged)(BOOL recording);
@property (nonatomic, assign) CFMachPortRef eventTap;
@property (nonatomic, assign) CFRunLoopSourceRef eventTapRunLoopSource;
- (void)setHotKeyDisplayValue:(NSString *)displayValue;
- (void)recordHotKeyWithKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers fallbackKey:(NSString *)fallbackKey;
- (void)startEventTap;
- (void)stopEventTap;
@end

static CGEventRef CSHotKeyRecorderEventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    CSHotKeyRecorder *recorder = (__bridge CSHotKeyRecorder *)userInfo;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (recorder.eventTap) {
            CGEventTapEnable(recorder.eventTap, true);
        }
        return event;
    }
    if (type != kCGEventKeyDown || recorder.window.firstResponder != recorder) {
        return event;
    }

    UInt32 keyCode = (UInt32)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    UInt32 modifiers = CSCarbonModifiersFromCGEvent(event);
    NSEvent *nsEvent = [NSEvent eventWithCGEvent:event];
    NSString *fallback = [nsEvent.charactersIgnoringModifiers copy];
    if (NSThread.isMainThread) {
        [recorder recordHotKeyWithKeyCode:keyCode modifiers:modifiers fallbackKey:fallback];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [recorder recordHotKeyWithKeyCode:keyCode modifiers:modifiers fallbackKey:fallback];
        });
    }
    return event;
}

@implementation CSHotKeyRecorder
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.editable = NO;
    self.selectable = NO;
    self.bezeled = YES;
    self.bordered = YES;
    self.drawsBackground = YES;
    self.alignment = NSTextAlignmentCenter;
    self.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.focusRingType = NSFocusRingTypeExterior;
    self.toolTip = @"点击后按下新的快捷键组合";
    return self;
}

- (void)dealloc {
    [self stopEventTap];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
}

- (BOOL)becomeFirstResponder {
    self.restingDisplayValue = self.stringValue ?: @"";
    self.stringValue = @"请按新的快捷键";
    self.textColor = NSColor.secondaryLabelColor;
    if (self.recordingChanged) {
        self.recordingChanged(YES);
    }
    [self startEventTap];
    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder {
    [self stopEventTap];
    if ([self.stringValue isEqualToString:@"请按新的快捷键"]) {
        self.stringValue = self.restingDisplayValue ?: @"";
    }
    self.textColor = NSColor.labelColor;
    if (self.recordingChanged) {
        self.recordingChanged(NO);
    }
    return [super resignFirstResponder];
}

- (void)setHotKeyDisplayValue:(NSString *)displayValue {
    self.restingDisplayValue = displayValue ?: @"";
    self.stringValue = self.restingDisplayValue;
    self.textColor = NSColor.labelColor;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.window.firstResponder == self && event.type == NSEventTypeKeyDown) {
        [self recordHotKeyFromEvent:event];
        return YES;
    }
    return [super performKeyEquivalent:event];
}

- (void)keyDown:(NSEvent *)event {
    [self recordHotKeyFromEvent:event];
}

- (void)recordHotKeyFromEvent:(NSEvent *)event {
    if (event.keyCode == kVK_Escape) {
        [self.window makeFirstResponder:nil];
        return;
    }

    [self recordHotKeyWithKeyCode:(UInt32)event.keyCode
                         modifiers:CSCarbonModifiersFromEvent(event)
                       fallbackKey:event.charactersIgnoringModifiers];
}

- (void)recordHotKeyWithKeyCode:(UInt32)keyCode modifiers:(UInt32)modifiers fallbackKey:(NSString *)fallbackKey {
    if (keyCode == kVK_Escape) {
        [self.window makeFirstResponder:nil];
        return;
    }

    if ((modifiers & (cmdKey | optionKey | controlKey)) == 0) {
        self.stringValue = @"需包含 ⌘/⌥/⌃";
        self.textColor = NSColor.systemRedColor;
        NSBeep();
        return;
    }

    NSString *displayName = CSHotKeyDisplay(keyCode, modifiers, fallbackKey);
    [self setHotKeyDisplayValue:displayName];
    if (self.hotKeyChanged) {
        self.hotKeyChanged(keyCode, modifiers, displayName);
    }
    [self.window makeFirstResponder:nil];
}

- (void)startEventTap {
    if (self.eventTap) {
        return;
    }

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown);
    self.eventTap = CGEventTapCreate(kCGSessionEventTap,
                                     kCGHeadInsertEventTap,
                                     kCGEventTapOptionListenOnly,
                                     mask,
                                     CSHotKeyRecorderEventTapCallback,
                                     (__bridge void *)self);
    if (!self.eventTap) {
        if (!AXIsProcessTrusted()) {
            NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        }
        return;
    }

    self.eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, self.eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), self.eventTapRunLoopSource, kCFRunLoopCommonModes);
    CGEventTapEnable(self.eventTap, true);
}

- (void)stopEventTap {
    if (self.eventTapRunLoopSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), self.eventTapRunLoopSource, kCFRunLoopCommonModes);
        CFRelease(self.eventTapRunLoopSource);
        self.eventTapRunLoopSource = NULL;
    }
    if (self.eventTap) {
        CGEventTapEnable(self.eventTap, false);
        CFRelease(self.eventTap);
        self.eventTap = NULL;
    }
}
@end

@interface CSStore : NSObject
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *items;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *boards;
@property (nonatomic, strong) NSMutableDictionary *preferences;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) NSString *filterMode;
@property (nonatomic, copy) NSString *filterValue;
@property (nonatomic, copy) NSString *selectedItemID;
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *selectedItemIDs;
@property (nonatomic, copy) NSString *lastNotice;
@property (nonatomic, copy) void (^didChange)(void);
@property (nonatomic, copy) void (^didDeleteItems)(NSSet<NSString *> *deletedItemIDs);
@property (nonatomic, copy) void (^didChangeAppearance)(NSString *key);
@property (nonatomic, copy) void (^didChangeHotKey)(void);
- (void)load;
- (void)save;
- (void)scheduleSave;
- (void)flushPendingSave;
- (NSArray<NSMutableDictionary *> *)filteredItems;
- (NSMutableDictionary *)selectedItem;
- (NSArray<NSMutableDictionary *> *)selectedItems;
- (BOOL)isItemSelected:(NSDictionary *)item;
- (void)addCapturedItem:(NSMutableDictionary *)item;
- (void)selectItem:(NSMutableDictionary *)item;
- (void)selectAllFilteredItems;
- (void)toggleSelectionForItem:(NSMutableDictionary *)item;
- (void)togglePin:(NSMutableDictionary *)item;
- (void)toggleBoard:(NSDictionary *)board forItem:(NSMutableDictionary *)item;
- (void)addBoardNamed:(NSString *)name;
- (void)deleteItem:(NSMutableDictionary *)item;
- (void)deleteItems:(NSArray<NSMutableDictionary *> *)items;
- (void)clearHistoryKeepingPinned:(BOOL)keepingPinned;
- (void)writeItemToPasteboard:(NSMutableDictionary *)item asPlainText:(BOOL)plainText;
- (void)writeItemsToPasteboard:(NSArray<NSMutableDictionary *> *)items asPlainText:(BOOL)plainText;
- (void)restoreItemToPasteboard:(NSMutableDictionary *)item asPlainText:(BOOL)plainText;
- (void)updatePreferenceKey:(NSString *)key value:(id)value;
- (void)normalizePreferences;
@end

@implementation CSStore {
    NSURL *_libraryURL;
    NSMutableSet<NSString *> *_transientFingerprints;
    dispatch_queue_t _saveQueue;
    NSUInteger _saveGeneration;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    NSURL *appSupport = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [appSupport URLByAppendingPathComponent:@"CopyPaste" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    _libraryURL = [folder URLByAppendingPathComponent:@"library.json"];
    _transientFingerprints = NSMutableSet.set;
    _saveQueue = dispatch_queue_create("io.github.TigerWithPig.CopyPaste.librarySave", DISPATCH_QUEUE_SERIAL);
    _query = @"";
    _filterMode = @"all";
    _filterValue = @"";
    _selectedItemIDs = NSMutableOrderedSet.orderedSet;
    [self load];
    return self;
}

- (NSArray<NSMutableDictionary *> *)defaultBoards {
    return @[
        @{@"id": @"935F197B-16E7-49FE-847C-9B8377D80B3F", @"name": @"设计", @"color": @"#2F80ED"}.mutableCopy,
        @{@"id": @"B62CE3C7-391B-4C06-85D6-C732E61537E4", @"name": @"代码", @"color": @"#26A269"}.mutableCopy,
        @{@"id": @"B4DBB0A4-DAAB-465A-BAE3-8A843721D5D4", @"name": @"回复", @"color": @"#D97706"}.mutableCopy
    ];
}

- (NSMutableDictionary *)defaultPreferences {
    return @{
        @"maxItems": @400,
        @"captureImages": @YES,
        @"autoPaste": @YES,
        @"hideAfterSelection": @YES,
        @"showDetailPreview": @YES,
        @"panelOpacity": @0.90,
        @"appearanceMode": CSAppearanceModeSystem,
        @"panelSizeMode": CSPanelSizeModeTemporary,
        @"panelPositionMode": CSPanelPositionModeDefault,
        @"interfaceStyle": CSInterfaceStyleClassic,
        @"hotKey": CSDefaultHotKeyPreference(),
        @"ignoredBundleIDs": @[@"com.apple.keychainaccess", @"com.apple.Passwords"],
        @"showDock": @NO
    }.mutableCopy;
}

- (void)normalizePreferences {
    id maxItemsValue = self.preferences[@"maxItems"];
    NSInteger maxItems = [maxItemsValue respondsToSelector:@selector(integerValue)] ? [maxItemsValue integerValue] : 400;
    self.preferences[@"maxItems"] = @(MIN(MAX(maxItems, 50), 2000));
    self.preferences[@"panelOpacity"] = @(CSPanelOpacityFromPreferences(self.preferences));
    self.preferences[@"appearanceMode"] = CSAppearanceModeFromPreferences(self.preferences);
    self.preferences[@"panelSizeMode"] = CSPanelSizeModeFromPreferences(self.preferences);
    self.preferences[@"panelPositionMode"] = CSPanelPositionModeFromPreferences(self.preferences);
    self.preferences[@"interfaceStyle"] = CSInterfaceStyleFromPreferences(self.preferences);
    self.preferences[@"hotKey"] = CSHotKeyFromPreferences(self.preferences);
    [self.preferences removeObjectForKey:@"interfaceBrightness"];
}

- (void)load {
    NSData *data = [NSData dataWithContentsOfURL:_libraryURL];
    self.items = NSMutableArray.array;
    self.boards = [self defaultBoards].mutableCopy;
    self.preferences = [self defaultPreferences];

    if (data.length == 0) {
        [self normalizePreferences];
        return;
    }

    NSDictionary *library = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if (![library isKindOfClass:NSDictionary.class]) {
        self.lastNotice = @"历史库读取失败，已使用新库。";
        [self normalizePreferences];
        return;
    }

    NSArray *items = library[@"items"];
    NSArray *boards = library[@"boards"];
    NSDictionary *preferences = library[@"preferences"];
    if ([items isKindOfClass:NSArray.class]) {
        self.items = [items mutableCopy];
    }
    if ([boards isKindOfClass:NSArray.class] && boards.count > 0) {
        self.boards = [boards mutableCopy];
    }
    if ([preferences isKindOfClass:NSDictionary.class]) {
        [self.preferences addEntriesFromDictionary:preferences];
    }
    [self normalizePreferences];
}

- (NSDictionary *)librarySnapshot {
    NSDictionary *library = @{
        @"version": @1,
        @"items": self.items ?: @[],
        @"boards": self.boards ?: @[],
        @"preferences": self.preferences ?: @{}
    };
    CFPropertyListRef snapshot = CFPropertyListCreateDeepCopy(kCFAllocatorDefault,
                                                              (__bridge CFPropertyListRef)library,
                                                              kCFPropertyListImmutable);
    return CFBridgingRelease(snapshot);
}

- (void)writeLibrarySnapshot:(NSDictionary *)snapshot {
    if (!snapshot) {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToURL:_libraryURL atomically:YES];
}

- (void)saveSnapshotAsync:(NSDictionary *)snapshot {
    NSURL *libraryURL = _libraryURL;
    dispatch_async(_saveQueue, ^{
        @autoreleasepool {
            NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
            [data writeToURL:libraryURL atomically:YES];
        }
    });
}

- (void)scheduleSave {
    _saveGeneration++;
    NSUInteger generation = _saveGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self->_saveGeneration) {
            return;
        }
        NSDictionary *snapshot = [self librarySnapshot];
        [self saveSnapshotAsync:snapshot];
    });
}

- (void)save {
    NSDictionary *snapshot = [self librarySnapshot];
    [self writeLibrarySnapshot:snapshot];
}

- (void)flushPendingSave {
    _saveGeneration++;
    NSDictionary *snapshot = [self librarySnapshot];
    dispatch_sync(_saveQueue, ^{
        [self writeLibrarySnapshot:snapshot];
    });
}

- (void)notifyChanged {
    if (self.didChange) {
        self.didChange();
    }
    [self scheduleSave];
}

- (NSArray<NSMutableDictionary *> *)filteredItems {
    NSMutableArray<NSMutableDictionary *> *result = NSMutableArray.array;
    NSString *needle = CSTrim(self.query).lowercaseString;

    for (NSMutableDictionary *item in self.items) {
        BOOL include = YES;
        if ([self.filterMode isEqualToString:@"pinned"]) {
            include = [item[@"pinned"] boolValue];
        } else if ([self.filterMode isEqualToString:@"kind"]) {
            include = [item[@"kind"] isEqualToString:self.filterValue];
        } else if ([self.filterMode isEqualToString:@"board"]) {
            include = [item[@"boardIDs"] containsObject:self.filterValue];
        }

        if (include && needle.length > 0) {
            NSString *haystack = [NSString stringWithFormat:@"%@ %@ %@",
                                  item[@"title"] ?: @"",
                                  item[@"body"] ?: @"",
                                  item[@"sourceAppName"] ?: @""].lowercaseString;
            include = [haystack containsString:needle];
        }

        if (include) {
            [result addObject:item];
        }
    }

    [result sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        BOOL leftPinned = [left[@"pinned"] boolValue];
        BOOL rightPinned = [right[@"pinned"] boolValue];
        if (leftPinned != rightPinned) {
            return leftPinned ? NSOrderedAscending : NSOrderedDescending;
        }
        NSTimeInterval leftDate = [left[@"date"] doubleValue];
        NSTimeInterval rightDate = [right[@"date"] doubleValue];
        if (leftDate > rightDate) return NSOrderedAscending;
        if (leftDate < rightDate) return NSOrderedDescending;
        return NSOrderedSame;
    }];

    return result;
}

- (NSMutableDictionary *)selectedItem {
    if (self.selectedItemID.length > 0) {
        for (NSMutableDictionary *item in self.items) {
            if ([item[@"id"] isEqualToString:self.selectedItemID]) {
                return item;
            }
        }
    }
    return self.filteredItems.firstObject;
}

- (NSArray<NSMutableDictionary *> *)selectedItems {
    NSMutableArray<NSMutableDictionary *> *result = NSMutableArray.array;
    NSMutableSet<NSString *> *selectedIDs = NSMutableSet.set;
    for (NSString *itemID in self.selectedItemIDs) {
        if (itemID.length > 0) {
            [selectedIDs addObject:itemID];
        }
    }
    if (selectedIDs.count == 0 && self.selectedItemID.length > 0) {
        [selectedIDs addObject:self.selectedItemID];
    }

    for (NSMutableDictionary *item in self.filteredItems) {
        if ([selectedIDs containsObject:item[@"id"]]) {
            [result addObject:item];
        }
    }
    if (result.count == 0 && self.selectedItem) {
        [result addObject:self.selectedItem];
    }
    return result;
}

- (BOOL)isItemSelected:(NSDictionary *)item {
    NSString *itemID = item[@"id"];
    return itemID.length > 0 && [self.selectedItemIDs containsObject:itemID];
}

- (void)addCapturedItem:(NSMutableDictionary *)item {
    NSString *fingerprint = item[@"fingerprint"];
    if (fingerprint.length > 0 && [_transientFingerprints containsObject:fingerprint]) {
        [_transientFingerprints removeObject:fingerprint];
        return;
    }

    NSMutableArray *next = NSMutableArray.array;
    NSMutableDictionary *duplicate = nil;
    for (NSMutableDictionary *existing in self.items) {
        if (fingerprint.length > 0 && [existing[@"fingerprint"] isEqualToString:fingerprint]) {
            duplicate = existing;
            continue;
        }
        [next addObject:existing];
    }

    if (duplicate) {
        NSMutableDictionary *replacement = item.mutableCopy;
        replacement[@"id"] = duplicate[@"id"] ?: replacement[@"id"] ?: CSUUID();
        replacement[@"pinned"] = duplicate[@"pinned"] ?: replacement[@"pinned"] ?: @NO;
        replacement[@"boardIDs"] = [duplicate[@"boardIDs"] mutableCopy] ?: replacement[@"boardIDs"] ?: NSMutableArray.array;
        replacement[@"pasteCount"] = duplicate[@"pasteCount"] ?: replacement[@"pasteCount"] ?: @0;
        item = replacement;
    }

    [next insertObject:item atIndex:0];
    self.items = [self compactedItems:next];
    self.selectedItemID = item[@"id"];
    [self.selectedItemIDs removeAllObjects];
    if (self.selectedItemID.length > 0) {
        [self.selectedItemIDs addObject:self.selectedItemID];
    }
    [self notifyChanged];
}

- (NSMutableArray<NSMutableDictionary *> *)compactedItems:(NSArray<NSMutableDictionary *> *)incoming {
    NSInteger maxItems = [self.preferences[@"maxItems"] integerValue];
    NSMutableArray *pinned = NSMutableArray.array;
    NSMutableArray *regular = NSMutableArray.array;
    for (NSMutableDictionary *item in incoming) {
        if ([item[@"pinned"] boolValue]) {
            [pinned addObject:item];
        } else {
            [regular addObject:item];
        }
    }
    NSInteger limit = MAX(maxItems - (NSInteger)pinned.count, 0);
    NSMutableArray *result = pinned.mutableCopy;
    for (NSUInteger index = 0; index < regular.count && index < (NSUInteger)limit; index++) {
        [result addObject:regular[index]];
    }
    return result;
}

- (void)selectItem:(NSMutableDictionary *)item {
    self.selectedItemID = item[@"id"];
    [self.selectedItemIDs removeAllObjects];
    if (self.selectedItemID.length > 0) {
        [self.selectedItemIDs addObject:self.selectedItemID];
    }
}

- (void)selectAllFilteredItems {
    NSArray<NSMutableDictionary *> *items = self.filteredItems;
    [self.selectedItemIDs removeAllObjects];
    for (NSDictionary *item in items) {
        NSString *itemID = item[@"id"];
        if (itemID.length > 0) {
            [self.selectedItemIDs addObject:itemID];
        }
    }
    self.selectedItemID = self.selectedItemIDs.lastObject ?: @"";
}

- (void)toggleSelectionForItem:(NSMutableDictionary *)item {
    NSString *itemID = item[@"id"];
    if (itemID.length == 0) {
        return;
    }
    if ([self.selectedItemIDs containsObject:itemID] && self.selectedItemIDs.count > 1) {
        [self.selectedItemIDs removeObject:itemID];
        self.selectedItemID = self.selectedItemIDs.lastObject ?: self.selectedItemID;
    } else {
        [self.selectedItemIDs addObject:itemID];
        self.selectedItemID = itemID;
    }
}

- (void)togglePin:(NSMutableDictionary *)item {
    item[@"pinned"] = @(![item[@"pinned"] boolValue]);
    [self notifyChanged];
}

- (void)toggleBoard:(NSDictionary *)board forItem:(NSMutableDictionary *)item {
    NSString *boardID = board[@"id"];
    NSMutableArray *boardIDs = [item[@"boardIDs"] mutableCopy] ?: NSMutableArray.array;
    if ([boardIDs containsObject:boardID]) {
        [boardIDs removeObject:boardID];
    } else {
        [boardIDs addObject:boardID];
    }
    item[@"boardIDs"] = boardIDs;
    [self notifyChanged];
}

- (void)addBoardNamed:(NSString *)name {
    NSString *trimmed = CSTrim(name);
    if (trimmed.length == 0) return;
    for (NSDictionary *board in self.boards) {
        if ([board[@"name"] isEqualToString:trimmed]) return;
    }
    NSArray *palette = @[@"#2F80ED", @"#1A936F", @"#C2410C", @"#7C3AED", @"#C026D3", @"#0E7490"];
    [self.boards addObject:@{
        @"id": CSUUID(),
        @"name": trimmed,
        @"color": palette[self.boards.count % palette.count]
    }.mutableCopy];
    [self notifyChanged];
}

- (void)deleteItem:(NSMutableDictionary *)item {
    if (item) {
        [self deleteItems:@[item]];
    }
}

- (void)deleteItems:(NSArray<NSMutableDictionary *> *)items {
    if (items.count == 0) {
        return;
    }
    NSMutableSet<NSString *> *ids = NSMutableSet.set;
    for (NSDictionary *item in items) {
        NSString *itemID = item[@"id"];
        if (itemID.length > 0) {
            [ids addObject:itemID];
        }
    }
    if (ids.count == 0) {
        return;
    }

    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        return ![ids containsObject:item[@"id"]];
    }];
    self.items = [[self.items filteredArrayUsingPredicate:predicate] mutableCopy];
    self.selectedItemID = self.filteredItems.firstObject[@"id"];
    [self.selectedItemIDs removeAllObjects];
    if (self.selectedItemID.length > 0) {
        [self.selectedItemIDs addObject:self.selectedItemID];
    }
    self.lastNotice = [NSString stringWithFormat:@"已删除 %lu 条记录", (unsigned long)ids.count];
    if (self.didDeleteItems) {
        self.didDeleteItems(ids.copy);
    } else if (self.didChange) {
        self.didChange();
    }
    [self scheduleSave];
}

- (void)clearHistoryKeepingPinned:(BOOL)keepingPinned {
    if (keepingPinned) {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
            return [item[@"pinned"] boolValue];
        }];
        self.items = [[self.items filteredArrayUsingPredicate:predicate] mutableCopy];
    } else {
        [self.items removeAllObjects];
    }
    self.selectedItemID = self.items.firstObject[@"id"];
    [self.selectedItemIDs removeAllObjects];
    if (self.selectedItemID.length > 0) {
        [self.selectedItemIDs addObject:self.selectedItemID];
    }
    [self notifyChanged];
}

- (void)writeItemToPasteboard:(NSMutableDictionary *)item asPlainText:(BOOL)plainText {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];

    NSString *kind = item[@"kind"];
    if ([kind isEqualToString:CSKindImage]) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:item[@"imageBase64"] ?: @"" options:0];
        NSImage *image = [[NSImage alloc] initWithData:data];
        if (image) {
            [pasteboard writeObjects:@[image]];
        } else {
            [pasteboard setString:item[@"body"] ?: @"" forType:NSPasteboardTypeString];
        }
    } else if ([kind isEqualToString:CSKindFile]) {
        NSMutableArray<NSURL *> *urls = NSMutableArray.array;
        for (NSString *path in item[@"filePaths"] ?: @[]) {
            [urls addObject:[NSURL fileURLWithPath:path]];
        }
        if (urls.count > 0) {
            [pasteboard writeObjects:urls];
        } else {
            [pasteboard setString:item[@"body"] ?: @"" forType:NSPasteboardTypeString];
        }
    } else {
        [pasteboard setString:item[@"body"] ?: @"" forType:NSPasteboardTypeString];
        if (!plainText) {
            NSData *rtfData = [[NSData alloc] initWithBase64EncodedString:item[@"rtfBase64"] ?: @"" options:0];
            NSData *htmlData = [[NSData alloc] initWithBase64EncodedString:item[@"htmlBase64"] ?: @"" options:0];
            if (rtfData.length > 0) {
                [pasteboard setData:rtfData forType:NSPasteboardTypeRTF];
            }
            if (htmlData.length > 0) {
                [pasteboard setData:htmlData forType:NSPasteboardTypeHTML];
            }
        }
    }

    NSString *fingerprint = item[@"fingerprint"];
    if (fingerprint.length > 0) {
        [_transientFingerprints addObject:fingerprint];
    }
}

- (void)writeItemsToPasteboard:(NSArray<NSMutableDictionary *> *)items asPlainText:(BOOL)plainText {
    if (items.count == 0) {
        return;
    }
    if (items.count == 1) {
        [self writeItemToPasteboard:items.firstObject asPlainText:plainText];
        return;
    }

    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    [pasteboard clearContents];

    BOOL allFiles = YES;
    for (NSDictionary *item in items) {
        NSString *kind = item[@"kind"];
        allFiles = allFiles && [kind isEqualToString:CSKindFile];
    }

    if (allFiles) {
        NSMutableArray<NSURL *> *urls = NSMutableArray.array;
        NSMutableArray<NSString *> *paths = NSMutableArray.array;
        for (NSDictionary *item in items) {
            for (NSString *path in item[@"filePaths"] ?: @[]) {
                [urls addObject:[NSURL fileURLWithPath:path]];
                [paths addObject:path];
            }
        }
        if (urls.count > 0) {
            [pasteboard writeObjects:urls];
            [_transientFingerprints addObject:CSSHA256([@"file:" stringByAppendingString:[paths componentsJoinedByString:@"|"]])];
        }
    } else if (!plainText && items.count == 1 && [items.firstObject[@"kind"] isEqualToString:CSKindImage]) {
        [self writeItemToPasteboard:items.firstObject asPlainText:plainText];
    } else {
        NSMutableArray<NSString *> *parts = NSMutableArray.array;
        for (NSDictionary *item in items) {
            NSString *body = item[@"body"] ?: @"";
            if ([item[@"kind"] isEqualToString:CSKindImage]) {
                body = item[@"title"] ?: @"图片";
            }
            if (body.length > 0) {
                [parts addObject:body];
            }
        }
        NSString *combined = [parts componentsJoinedByString:@"\n"];
        [pasteboard setString:combined forType:NSPasteboardTypeString];
        NSString *trimmed = CSTrim(combined);
        if (trimmed.length > 0) {
            NSString *kind = CSIsLikelyURL(trimmed) ? CSKindLink : CSKindText;
            [_transientFingerprints addObject:CSSHA256([NSString stringWithFormat:@"%@:%@", kind, trimmed])];
        }
    }

    for (NSDictionary *item in items) {
        NSString *fingerprint = item[@"fingerprint"];
        if (fingerprint.length > 0) {
            [_transientFingerprints addObject:fingerprint];
        }
    }
}

- (void)restoreItemToPasteboard:(NSMutableDictionary *)item asPlainText:(BOOL)plainText {
    [self writeItemToPasteboard:item asPlainText:plainText];
    item[@"pasteCount"] = @([item[@"pasteCount"] integerValue] + 1);
    item[@"date"] = @(NSDate.date.timeIntervalSince1970);
    self.lastNotice = @"已放回剪贴板";
    [self notifyChanged];
}

- (void)updatePreferenceKey:(NSString *)key value:(id)value {
    self.preferences[key] = value ?: NSNull.null;
    [self normalizePreferences];
    if ([key isEqualToString:@"panelOpacity"] || [key isEqualToString:@"appearanceMode"]) {
        if (self.didChangeAppearance) {
            self.didChangeAppearance(key);
        } else if (self.didChange) {
            self.didChange();
        }
        [self scheduleSave];
        return;
    }
    if ([key isEqualToString:@"hotKey"]) {
        if (self.didChangeHotKey) {
            self.didChangeHotKey();
        } else if (self.didChange) {
            self.didChange();
        }
        [self scheduleSave];
        return;
    }
    if ([key isEqualToString:@"maxItems"]) {
        self.items = [self compactedItems:self.items];
    }
    [self notifyChanged];
}
@end

@interface CSClipboardMonitor : NSObject
@property (nonatomic, weak) CSStore *store;
- (instancetype)initWithStore:(CSStore *)store;
- (void)start;
- (void)stop;
@end

@implementation CSClipboardMonitor {
    NSTimer *_timer;
    NSInteger _lastChangeCount;
}

- (instancetype)initWithStore:(CSStore *)store {
    self = [super init];
    if (!self) return nil;
    _store = store;
    _lastChangeCount = NSPasteboard.generalPasteboard.changeCount;
    return self;
}

- (void)start {
    [self stop];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.65 target:self selector:@selector(captureIfNeeded) userInfo:nil repeats:YES];
}

- (void)stop {
    [_timer invalidate];
    _timer = nil;
}

- (void)captureIfNeeded {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    if (pasteboard.changeCount == _lastChangeCount) {
        return;
    }
    _lastChangeCount = pasteboard.changeCount;

    NSRunningApplication *frontApp = NSWorkspace.sharedWorkspace.frontmostApplication;
    NSString *bundleID = frontApp.bundleIdentifier;
    if (bundleID.length > 0 && [self.store.preferences[@"ignoredBundleIDs"] containsObject:bundleID]) {
        return;
    }

    NSMutableDictionary *item = [self clipItemFromPasteboard:pasteboard sourceApp:frontApp];
    if (item) {
        [self.store addCapturedItem:item];
    }
}

- (NSMutableDictionary *)clipItemFromPasteboard:(NSPasteboard *)pasteboard sourceApp:(NSRunningApplication *)sourceApp {
    NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[NSURL.class] options:nil];
    BOOL allFileURLs = urls.count > 0;
    for (NSURL *url in urls) {
        allFileURLs = allFileURLs && url.isFileURL;
    }
    if (allFileURLs) {
        return [self fileItemFromURLs:urls sourceApp:sourceApp];
    }

    if ([self.store.preferences[@"captureImages"] boolValue]) {
        NSImage *image = [[NSImage alloc] initWithPasteboard:pasteboard];
        NSData *pngData = image ? CSPNGDataFromImage(image, 640) : nil;
        if (pngData.length > 0) {
            NSString *base64 = [pngData base64EncodedStringWithOptions:0];
            NSString *dimensions = [NSString stringWithFormat:@"%ld x %ld", (long)image.size.width, (long)image.size.height];
            return @{
                @"id": CSUUID(),
                @"kind": CSKindImage,
                @"title": [@"图片 " stringByAppendingString:dimensions],
                @"body": dimensions,
                @"date": @(NSDate.date.timeIntervalSince1970),
                @"sourceAppName": sourceApp.localizedName ?: @"",
                @"sourceBundleID": sourceApp.bundleIdentifier ?: @"",
                @"pinned": @NO,
                @"boardIDs": NSMutableArray.array,
                @"pasteCount": @0,
                @"imageBase64": base64,
                @"filePaths": @[],
                @"fingerprint": CSSHA256([@"image:" stringByAppendingString:base64])
            }.mutableCopy;
        }
    }

    NSString *string = [pasteboard stringForType:NSPasteboardTypeString];
    NSString *trimmed = CSTrim(string);
    if (trimmed.length == 0) {
        return nil;
    }

    NSString *kind = CSIsLikelyURL(trimmed) ? CSKindLink : CSKindText;
    NSData *rtfData = [pasteboard dataForType:NSPasteboardTypeRTF];
    NSData *htmlData = [pasteboard dataForType:NSPasteboardTypeHTML];
    return @{
        @"id": CSUUID(),
        @"kind": kind,
        @"title": CSDominantTitle(trimmed),
        @"body": string ?: @"",
        @"date": @(NSDate.date.timeIntervalSince1970),
        @"sourceAppName": sourceApp.localizedName ?: @"",
        @"sourceBundleID": sourceApp.bundleIdentifier ?: @"",
        @"pinned": @NO,
        @"boardIDs": NSMutableArray.array,
        @"pasteCount": @0,
        @"imageBase64": @"",
        @"rtfBase64": rtfData.length > 0 ? [rtfData base64EncodedStringWithOptions:0] : @"",
        @"htmlBase64": htmlData.length > 0 ? [htmlData base64EncodedStringWithOptions:0] : @"",
        @"filePaths": @[],
        @"fingerprint": CSSHA256([NSString stringWithFormat:@"%@:%@", kind, trimmed])
    }.mutableCopy;
}

- (NSMutableDictionary *)fileItemFromURLs:(NSArray<NSURL *> *)urls sourceApp:(NSRunningApplication *)sourceApp {
    NSMutableArray<NSString *> *paths = NSMutableArray.array;
    for (NSURL *url in urls) {
        [paths addObject:url.path ?: url.absoluteString];
    }
    NSString *title = urls.count == 1 ? urls.firstObject.lastPathComponent : [NSString stringWithFormat:@"%lu 个文件", (unsigned long)urls.count];
    return @{
        @"id": CSUUID(),
        @"kind": CSKindFile,
        @"title": title ?: @"文件",
        @"body": [paths componentsJoinedByString:@"\n"],
        @"date": @(NSDate.date.timeIntervalSince1970),
        @"sourceAppName": sourceApp.localizedName ?: @"",
        @"sourceBundleID": sourceApp.bundleIdentifier ?: @"",
        @"pinned": @NO,
        @"boardIDs": NSMutableArray.array,
        @"pasteCount": @0,
        @"imageBase64": @"",
        @"filePaths": paths,
        @"fingerprint": CSSHA256([@"file:" stringByAppendingString:[paths componentsJoinedByString:@"|"]])
    }.mutableCopy;
}
@end

@interface CSPanelController : NSObject <NSSearchFieldDelegate, NSWindowDelegate>
@property (nonatomic, strong) CSStore *store;
@property (nonatomic, strong) CSFloatingPanel *panel;
@property (nonatomic, strong) NSVisualEffectView *panelEffectView;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSStackView *sidebarStack;
@property (nonatomic, strong) NSStackView *kindFilterStack;
@property (nonatomic, strong) NSScrollView *cardScrollView;
@property (nonatomic, strong) NSView *cardsDocumentView;
@property (nonatomic, strong) NSStackView *detailStack;
@property (nonatomic, strong) CSActionButton *windowPinButton;
@property (nonatomic, strong) NSPopover *shortcutsPopover;
@property (nonatomic, strong) NSRunningApplication *lastTargetApplication;
@property (nonatomic, copy) NSString *currentInterfaceStyle;
@property (nonatomic, assign) BOOL windowPinned;
@property (nonatomic, assign) BOOL suppressNextDeactivateClose;
- (instancetype)initWithStore:(CSStore *)store;
- (void)toggle;
- (void)show;
- (void)close;
- (void)reloadAll;
- (void)refreshInterfaceAppearance;
- (void)handleDeletedItemsWithIDs:(NSSet<NSString *> *)deletedItemIDs;
- (void)previewPanelLayout;
- (void)saveCurrentPanelLayout;
- (void)closeIfNotPinned;
- (void)executeSelectedItem;
- (void)executeSelectedItemAsPlainText:(BOOL)plainText;
- (void)deleteSelectedItems;
- (void)selectAllItems;
- (void)selectRelativeItem:(NSInteger)offset;
- (void)selectItem:(NSMutableDictionary *)item extendingSelection:(BOOL)extendingSelection;
- (void)applyInterfaceAppearance;
- (void)updateCardSelectionStyles;
- (void)showShortcutsHelpFromView:(NSView *)view;
- (void)pasteItems:(NSArray<NSMutableDictionary *> *)items plainText:(BOOL)plainText;
@end

@implementation CSPanelController

- (instancetype)initWithStore:(CSStore *)store {
    self = [super init];
    if (!self) return nil;
    _store = store;
    [self buildPanel];
    return self;
}

- (void)buildPanel {
    self.currentInterfaceStyle = CSInterfaceStyleFromPreferences(self.store.preferences);
    BOOL modern = [self.currentInterfaceStyle isEqualToString:CSInterfaceStyleModern];
    self.panel = [[CSFloatingPanel alloc] initWithContentRect:modern ? NSMakeRect(0, 0, 1180, 640) : NSMakeRect(0, 0, 1080, 500)
                                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView | NSWindowStyleMaskResizable
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    self.panel.title = @"CopyPaste";
    self.panel.titleVisibility = NSWindowTitleHidden;
    self.panel.titlebarAppearsTransparent = YES;
    self.panel.movableByWindowBackground = YES;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorTransient;
    self.panel.opaque = NO;
    self.panel.backgroundColor = NSColor.clearColor;
    self.panel.hasShadow = YES;
    self.panel.minSize = modern ? NSMakeSize(980, 540) : NSMakeSize(820, 430);
    self.panel.delegate = self;
    [[self.panel standardWindowButton:NSWindowCloseButton] setHidden:YES];
    [[self.panel standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
    [[self.panel standardWindowButton:NSWindowZoomButton] setHidden:YES];
    __weak typeof(self) weakSelfForPanel = self;
    self.panel.returnKeyHandler = ^(BOOL plainText) {
        [weakSelfForPanel executeSelectedItemAsPlainText:plainText];
    };
    self.panel.leftKeyHandler = ^{
        [weakSelfForPanel selectRelativeItem:-1];
    };
    self.panel.rightKeyHandler = ^{
        [weakSelfForPanel selectRelativeItem:1];
    };
    self.panel.deleteKeyHandler = ^{
        [weakSelfForPanel deleteSelectedItems];
    };
    self.panel.selectAllKeyHandler = ^{
        [weakSelfForPanel selectAllItems];
    };
    self.panel.mouseDownHandler = ^BOOL(NSEvent *event) {
        if (weakSelfForPanel.shortcutsPopover.shown) {
            [weakSelfForPanel.shortcutsPopover close];
            return YES;
        }
        return NO;
    };
    [self applyWindowPinState];

    if (modern) {
        [self buildModernPanelContent];
        [self reloadAll];
        return;
    }

    NSVisualEffectView *effect = NSVisualEffectView.new;
    effect.material = NSVisualEffectMaterialHUDWindow;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateActive;
    effect.wantsLayer = YES;
    effect.layer.cornerRadius = 18;
    self.panel.contentView = effect;
    self.panelEffectView = effect;

    NSStackView *root = NSStackView.new;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.spacing = 0;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [effect addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:effect.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:effect.bottomAnchor]
    ]];

    [root addArrangedSubview:[self makeTopBar]];

    NSBox *divider = NSBox.new;
    divider.boxType = NSBoxSeparator;
    [root addArrangedSubview:divider];

    NSStackView *body = NSStackView.new;
    body.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    body.spacing = 0;
    [body setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [body setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [root addArrangedSubview:body];
    NSLayoutConstraint *bodyMinHeight = [body.heightAnchor constraintGreaterThanOrEqualToConstant:340];
    bodyMinHeight.priority = NSLayoutPriorityDefaultHigh;
    bodyMinHeight.active = YES;

    self.sidebarStack = NSStackView.new;
    self.sidebarStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.sidebarStack.spacing = 8;
    self.sidebarStack.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 10);
    [body addArrangedSubview:self.sidebarStack];
    [self.sidebarStack.widthAnchor constraintEqualToConstant:174].active = YES;

    NSBox *leftDivider = NSBox.new;
    leftDivider.boxType = NSBoxSeparator;
    [body addArrangedSubview:leftDivider];

    self.cardScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.cardScrollView.hasHorizontalScroller = YES;
    self.cardScrollView.hasVerticalScroller = NO;
    self.cardScrollView.drawsBackground = NO;
    self.cardsDocumentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 290)];
    self.cardScrollView.documentView = self.cardsDocumentView;
    [body addArrangedSubview:self.cardScrollView];

    NSBox *rightDivider = NSBox.new;
    rightDivider.boxType = NSBoxSeparator;
    [body addArrangedSubview:rightDivider];

    self.detailStack = NSStackView.new;
    self.detailStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.detailStack.spacing = 14;
    self.detailStack.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    [body addArrangedSubview:self.detailStack];
    [self.detailStack.widthAnchor constraintEqualToConstant:290].active = YES;
    [self.detailStack setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.detailStack setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    [self reloadAll];
}

- (BOOL)isModernInterface {
    return [self.currentInterfaceStyle isEqualToString:CSInterfaceStyleModern];
}

- (void)buildModernPanelContent {
    NSVisualEffectView *effect = NSVisualEffectView.new;
    effect.material = NSVisualEffectMaterialHUDWindow;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateActive;
    effect.wantsLayer = YES;
    effect.layer.cornerRadius = 22;
    self.panel.contentView = effect;
    self.panelEffectView = effect;

    NSStackView *root = NSStackView.new;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.spacing = 0;
    root.edgeInsets = NSEdgeInsetsMake(14, 18, 18, 18);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [effect addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:effect.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:effect.bottomAnchor]
    ]];

    [root addArrangedSubview:[self makeModernTopBar]];

    NSStackView *body = NSStackView.new;
    body.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    body.spacing = 18;
    [body setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [body setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [root addArrangedSubview:body];

    self.sidebarStack = NSStackView.new;
    self.sidebarStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.sidebarStack.spacing = 9;
    self.sidebarStack.edgeInsets = NSEdgeInsetsMake(18, 16, 18, 16);
    self.sidebarStack.wantsLayer = YES;
    self.sidebarStack.layer.cornerRadius = 14;
    self.sidebarStack.layer.backgroundColor = [self adjustedControlBackgroundColorWithAlpha:0.42].CGColor;
    [body addArrangedSubview:self.sidebarStack];
    [self.sidebarStack.widthAnchor constraintEqualToConstant:220].active = YES;

    self.cardScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.cardScrollView.hasHorizontalScroller = NO;
    self.cardScrollView.hasVerticalScroller = YES;
    self.cardScrollView.autohidesScrollers = YES;
    self.cardScrollView.drawsBackground = NO;
    self.cardScrollView.borderType = NSNoBorder;
    self.cardsDocumentView = [[CSFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 520, 520)];
    self.cardScrollView.documentView = self.cardsDocumentView;
    [body addArrangedSubview:self.cardScrollView];
    [self.cardScrollView.widthAnchor constraintGreaterThanOrEqualToConstant:420].active = YES;

    self.detailStack = NSStackView.new;
    self.detailStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.detailStack.spacing = 14;
    self.detailStack.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
    self.detailStack.wantsLayer = YES;
    self.detailStack.layer.cornerRadius = 14;
    self.detailStack.layer.backgroundColor = [self adjustedControlBackgroundColorWithAlpha:0.42].CGColor;
    [body addArrangedSubview:self.detailStack];
    [self.detailStack.widthAnchor constraintEqualToConstant:330].active = YES;
    [self.detailStack setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.detailStack setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
}

- (NSView *)makeModernTopBar {
    NSStackView *bar = NSStackView.new;
    bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bar.spacing = 12;
    bar.alignment = NSLayoutAttributeCenterY;
    bar.edgeInsets = NSEdgeInsetsMake(8, 0, 16, 0);
    [bar.heightAnchor constraintEqualToConstant:76].active = YES;

    NSStackView *brand = NSStackView.new;
    brand.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    brand.spacing = 10;
    brand.alignment = NSLayoutAttributeCenterY;
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.image = [NSImage imageNamed:@"CopyPasteIcon"];
    if (!icon.image) {
        icon.image = [NSImage imageWithSystemSymbolName:@"doc.on.clipboard" accessibilityDescription:@"CopyPaste"];
    }
    [icon.widthAnchor constraintEqualToConstant:34].active = YES;
    [icon.heightAnchor constraintEqualToConstant:34].active = YES;
    [brand addArrangedSubview:icon];

    NSStackView *brandText = NSStackView.new;
    brandText.orientation = NSUserInterfaceLayoutOrientationVertical;
    brandText.spacing = 0;
    [brandText addArrangedSubview:CSLabel(@"CopyPaste", [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold], NSColor.labelColor)];
    [brandText addArrangedSubview:CSLabel(@"Clipboard history", [NSFont systemFontOfSize:11 weight:NSFontWeightRegular], NSColor.secondaryLabelColor)];
    [brand addArrangedSubview:brandText];
    [brand.widthAnchor constraintEqualToConstant:246].active = YES;
    [bar addArrangedSubview:brand];

    __weak typeof(self) weakSelf = self;
    self.searchField = CSSearchField.new;
    self.searchField.placeholderString = @"搜索文本、链接、来源 App";
    self.searchField.toolTip = @"输入关键词筛选；搜索框为空时按 ⌘A 全选当前列表";
    self.searchField.target = self;
    self.searchField.action = @selector(searchChanged:);
    self.searchField.delegate = self;
    ((CSSearchField *)self.searchField).emptyCommandAHandler = ^{
        [weakSelf selectAllItems];
    };
    [self.searchField.heightAnchor constraintEqualToConstant:38].active = YES;
    [self.searchField.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;
    [self.searchField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.searchField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [bar addArrangedSubview:self.searchField];

    self.kindFilterStack = NSStackView.new;
    self.kindFilterStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.kindFilterStack.spacing = 7;
    [bar addArrangedSubview:self.kindFilterStack];

    __block CSActionButton *helpButton = nil;
    helpButton = [CSActionButton buttonWithTitle:@"" symbol:@"questionmark.circle" handler:^{
        [weakSelf showShortcutsHelpFromView:helpButton];
    }];
    helpButton.toolTip = @"查看快捷键和选择操作";
    [helpButton.widthAnchor constraintEqualToConstant:34].active = YES;
    [helpButton.heightAnchor constraintEqualToConstant:34].active = YES;
    [bar addArrangedSubview:helpButton];

    self.windowPinButton = [CSActionButton buttonWithTitle:@"" symbol:@"pin" handler:^{
        [weakSelf toggleWindowPinned];
    }];
    self.windowPinButton.toolTip = @"固定面板在最前，点击桌面或切换 App 时不隐藏";
    [self.windowPinButton.widthAnchor constraintEqualToConstant:34].active = YES;
    [self.windowPinButton.heightAnchor constraintEqualToConstant:34].active = YES;
    [bar addArrangedSubview:self.windowPinButton];
    [self updateWindowPinButton];

    CSActionButton *closeButton = [CSActionButton buttonWithTitle:@"" symbol:@"xmark" handler:^{
        [weakSelf close];
    }];
    closeButton.toolTip = @"关闭面板";
    [closeButton.widthAnchor constraintEqualToConstant:34].active = YES;
    [closeButton.heightAnchor constraintEqualToConstant:34].active = YES;
    [bar addArrangedSubview:closeButton];
    return bar;
}

- (NSView *)makeTopBar {
    NSStackView *bar = NSStackView.new;
    bar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    bar.spacing = 12;
    bar.alignment = NSLayoutAttributeCenterY;
    bar.edgeInsets = NSEdgeInsetsMake(10, 18, 10, 18);
    [bar.heightAnchor constraintEqualToConstant:52].active = YES;

    NSStackView *brand = NSStackView.new;
    brand.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    brand.spacing = 8;
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.image = [NSImage imageWithSystemSymbolName:@"doc.on.clipboard" accessibilityDescription:@"CopyPaste"];
    [icon.widthAnchor constraintEqualToConstant:22].active = YES;
    [icon.heightAnchor constraintEqualToConstant:22].active = YES;
    [brand addArrangedSubview:icon];
    [brand addArrangedSubview:CSLabel(@"CopyPaste", [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold], NSColor.labelColor)];
    [bar addArrangedSubview:brand];

    __weak typeof(self) weakSelf = self;
    self.searchField = CSSearchField.new;
    self.searchField.placeholderString = @"搜索文本、链接、来源 App";
    self.searchField.toolTip = @"输入关键词筛选；搜索框为空时按 ⌘A 全选当前列表";
    self.searchField.target = self;
    self.searchField.action = @selector(searchChanged:);
    self.searchField.delegate = self;
    ((CSSearchField *)self.searchField).emptyCommandAHandler = ^{
        [weakSelf selectAllItems];
    };
    [self.searchField.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;
    [self.searchField.heightAnchor constraintEqualToConstant:32].active = YES;
    [self.searchField setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.searchField setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [bar addArrangedSubview:self.searchField];

    __block CSActionButton *helpButton = nil;
    helpButton = [CSActionButton buttonWithTitle:@"" symbol:@"questionmark.circle" handler:^{
        [weakSelf showShortcutsHelpFromView:helpButton];
    }];
    helpButton.toolTip = @"查看快捷键和选择操作";
    [helpButton.widthAnchor constraintEqualToConstant:32].active = YES;
    [helpButton.heightAnchor constraintEqualToConstant:32].active = YES;
    [bar addArrangedSubview:helpButton];

    self.windowPinButton = [CSActionButton buttonWithTitle:@"置顶" symbol:@"pin" handler:^{
        [weakSelf toggleWindowPinned];
    }];
    self.windowPinButton.toolTip = @"固定面板在最前，点击桌面或切换 App 时不隐藏";
    [self.windowPinButton.widthAnchor constraintEqualToConstant:84].active = YES;
    [self.windowPinButton.heightAnchor constraintEqualToConstant:32].active = YES;
    [bar addArrangedSubview:self.windowPinButton];
    [self updateWindowPinButton];
    CSActionButton *closeButton = [CSActionButton buttonWithTitle:@"" symbol:@"xmark" handler:^{
        [weakSelf close];
    }];
    closeButton.toolTip = @"关闭面板";
    [closeButton.widthAnchor constraintEqualToConstant:32].active = YES;
    [closeButton.heightAnchor constraintEqualToConstant:32].active = YES;
    [bar addArrangedSubview:closeButton];
    return bar;
}

- (void)controlTextDidChange:(NSNotification *)notification {
    [self searchChanged:self.searchField];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(insertNewline:)) {
        NSEventModifierFlags flags = NSApp.currentEvent.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
        BOOL shiftPressed = (flags & NSEventModifierFlagShift) == NSEventModifierFlagShift;
        [self executeSelectedItemAsPlainText:shiftPressed];
        return YES;
    }
    if (commandSelector == @selector(moveLeft:)) {
        [self selectRelativeItem:-1];
        return YES;
    }
    if (commandSelector == @selector(moveRight:)) {
        [self selectRelativeItem:1];
        return YES;
    }
    if (commandSelector == @selector(deleteBackward:) || commandSelector == @selector(deleteForward:)) {
        if ((self.searchField.stringValue ?: @"").length == 0) {
            [self deleteSelectedItems];
            return YES;
        }
    }
    return NO;
}

- (void)searchChanged:(id)sender {
    self.store.query = self.searchField.stringValue ?: @"";
    [self ensureSelection];
    [self reloadCards];
    [self reloadDetail];
}

- (void)toggle {
    self.panel.visible ? [self close] : [self show];
}

- (void)show {
    NSRunningApplication *frontApp = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (frontApp.processIdentifier != NSRunningApplication.currentApplication.processIdentifier) {
        self.lastTargetApplication = frontApp;
    }
    self.suppressNextDeactivateClose = NO;
    [self applyWindowPinState];
    [self reloadAll];
    [self positionPanel];
    [NSApp activateIgnoringOtherApps:YES];
    [self.panel makeKeyAndOrderFront:nil];
    [self.panel makeFirstResponder:self.searchField];
}

- (void)close {
    [self.shortcutsPopover close];
    [self rememberCurrentPanelFrameIfNeeded];
    [self.panel orderOut:nil];
    if (!self.windowPinned) {
        self.suppressNextDeactivateClose = NO;
        [self applyWindowPinState];
    }
}

- (void)closeIfNotPinned {
    [self.shortcutsPopover close];
    if (self.suppressNextDeactivateClose) {
        self.suppressNextDeactivateClose = NO;
        return;
    }
    if (!self.windowPinned) {
        [self close];
    }
}

- (void)toggleWindowPinned {
    self.windowPinned = !self.windowPinned;
    [self applyWindowPinState];
    [self updateWindowPinButton];
}

- (void)applyWindowPinState {
    self.panel.floatingPanel = self.windowPinned;
    self.panel.level = self.windowPinned ? NSFloatingWindowLevel : NSNormalWindowLevel;
    self.panel.hidesOnDeactivate = !self.windowPinned;
}

- (void)updateWindowPinButton {
    self.windowPinButton.title = [self isModernInterface] ? @"" : (self.windowPinned ? @"已置顶" : @"置顶");
    self.windowPinButton.image = [NSImage imageWithSystemSymbolName:self.windowPinned ? @"pin.fill" : @"pin"
                                           accessibilityDescription:self.windowPinned ? @"已置顶" : @"置顶"];
    self.windowPinButton.contentTintColor = self.windowPinned ? NSColor.controlAccentColor : NSColor.labelColor;
}

- (void)executeSelectedItem {
    [self executeSelectedItemAsPlainText:NO];
}

- (void)executeSelectedItemAsPlainText:(BOOL)plainText {
    NSArray<NSMutableDictionary *> *items = self.store.selectedItems;
    if (items.count == 0) {
        return;
    }
    [self pasteItems:items plainText:plainText];
}

- (void)deleteSelectedItems {
    NSArray<NSMutableDictionary *> *items = self.store.selectedItems;
    if (items.count == 0) {
        return;
    }
    [self.store deleteItems:items];
}

- (void)selectAllItems {
    [self.panel makeFirstResponder:self.panel];
    [self.store selectAllFilteredItems];
    [self updateCardSelectionStyles];
    [self reloadDetail];
}

- (void)selectItem:(NSMutableDictionary *)item extendingSelection:(BOOL)extendingSelection {
    [self.panel makeFirstResponder:self.panel];
    if (extendingSelection) {
        [self.store toggleSelectionForItem:item];
    } else {
        [self.store selectItem:item];
    }
    [self updateCardSelectionStyles];
    [self reloadDetail];
}

- (void)showShortcutsHelpFromView:(NSView *)view {
    if (self.shortcutsPopover.shown) {
        [self.shortcutsPopover close];
        return;
    }

    NSPopover *popover = NSPopover.new;
    popover.behavior = NSPopoverBehaviorApplicationDefined;
    popover.animates = NO;

    NSViewController *controller = NSViewController.new;
    controller.preferredContentSize = NSMakeSize(344, 318);
    NSStackView *root = NSStackView.new;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.spacing = 8;
    root.edgeInsets = NSEdgeInsetsMake(14, 16, 14, 16);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = CSLabel(@"快捷键", [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold], NSColor.labelColor);
    [root addArrangedSubview:title];

    NSArray<NSArray<NSString *> *> *rows = @[
        @[@"唤醒面板", CSHotKeyFromPreferences(self.store.preferences)[@"display"] ?: @"⇧⌘V"],
        @[@"打开设置", @"⌘,"],
        @[@"选择候选", @"← / →"],
        @[@"多选候选", @"Shift + 单击"],
        @[@"全选当前列表", @"⌘A"],
        @[@"粘贴选中内容", @"Enter / 双击"],
        @[@"去格式粘贴文本", @"Shift + Enter / 双击"],
        @[@"删除选中内容", @"Delete"],
        @[@"搜索框全选文字", @"有搜索词时按 ⌘A"]
    ];

    for (NSArray<NSString *> *row in rows) {
        NSStackView *line = NSStackView.new;
        line.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        line.spacing = 10;
        NSTextField *name = CSLabel(row.firstObject, [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
        NSTextField *keys = CSLabel(row.lastObject, [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold], NSColor.labelColor);
        keys.alignment = NSTextAlignmentRight;
        [name.widthAnchor constraintEqualToConstant:124].active = YES;
        [keys.widthAnchor constraintEqualToConstant:178].active = YES;
        [line.heightAnchor constraintEqualToConstant:22].active = YES;
        [line addArrangedSubview:name];
        [line addArrangedSubview:keys];
        [root addArrangedSubview:line];
    }

    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 344, 318)];
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
    ]];
    controller.view = content;
    popover.contentViewController = controller;
    self.shortcutsPopover = popover;
    [popover showRelativeToRect:view.bounds ofView:view preferredEdge:NSRectEdgeMinY];
}

- (void)selectRelativeItem:(NSInteger)offset {
    NSArray<NSMutableDictionary *> *items = self.store.filteredItems;
    if (items.count == 0) {
        return;
    }

    NSInteger currentIndex = 0;
    for (NSUInteger index = 0; index < items.count; index++) {
        if ([items[index][@"id"] isEqualToString:self.store.selectedItemID]) {
            currentIndex = (NSInteger)index;
            break;
        }
    }

    NSInteger nextIndex = currentIndex + offset;
    nextIndex = MIN(MAX(nextIndex, 0), (NSInteger)items.count - 1);
    if (nextIndex == currentIndex && [items[currentIndex][@"id"] isEqualToString:self.store.selectedItemID]) {
        return;
    }

    [self.store selectItem:items[(NSUInteger)nextIndex]];
    [self updateCardSelectionStyles];
    [self reloadDetail];
    [self scrollSelectedCardIntoViewAtIndex:(NSUInteger)nextIndex];
}

- (void)scrollSelectedCardIntoViewAtIndex:(NSUInteger)index {
    if ([self isModernInterface]) {
        CGFloat cardHeight = 84.0;
        CGFloat spacing = 10.0;
        CGFloat y = 12.0 + (CGFloat)index * (cardHeight + spacing);
        NSRect targetRect = NSMakeRect(0, y, self.cardsDocumentView.bounds.size.width, cardHeight);
        [self.cardsDocumentView scrollRectToVisible:targetRect];
        return;
    }
    CGFloat cardWidth = 190.0;
    CGFloat spacing = 12.0;
    CGFloat x = 16.0 + (CGFloat)index * (cardWidth + spacing);
    NSRect targetRect = NSMakeRect(x, 0, cardWidth, self.cardsDocumentView.bounds.size.height);
    [self.cardsDocumentView scrollRectToVisible:targetRect];
}

- (NSSize)preferredPanelSizeForScreen:(NSScreen *)screen {
    NSRect visible = screen.visibleFrame;
    CGFloat width = [self isModernInterface] ? MIN(MAX(visible.size.width - 120, 980), 1240) : MIN(MAX(visible.size.width - 96, 760), 1160);
    CGFloat height = [self isModernInterface] ? MIN(MAX(visible.size.height * 0.68, 540), 720) : MIN(MAX(visible.size.height * 0.46, 420), 560);
    if ([CSPanelSizeModeFromPreferences(self.store.preferences) isEqualToString:CSPanelSizeModeSaved]) {
        NSRect savedFrame = NSZeroRect;
        if (CSRectFromFramePreference(self.store.preferences[@"panelSavedFrame"], &savedFrame)) {
            width = savedFrame.size.width;
            height = savedFrame.size.height;
        }
    }
    width = MIN(MAX(width, self.panel.minSize.width), visible.size.width);
    height = MIN(MAX(height, self.panel.minSize.height), visible.size.height);
    return NSMakeSize(width, height);
}

- (NSRect)defaultPanelFrameWithSize:(NSSize)size screen:(NSScreen *)screen {
    NSRect visible = screen.visibleFrame;
    CGFloat x = NSMidX(visible) - size.width / 2.0;
    CGFloat y = NSMinY(visible) + 34;
    return CSClampFrameToVisibleScreen(NSMakeRect(x, y, size.width, size.height), screen);
}

- (BOOL)panelFrame:(NSRect *)frame nearAnchorRect:(NSRect)anchorRect size:(NSSize)size fallbackFrame:(NSRect)fallbackFrame {
    NSScreen *screen = CSScreenForRect(anchorRect);
    NSRect visible = screen.visibleFrame;
    CGFloat margin = 10.0;
    CGFloat x = CSClampCGFloat(NSMidX(anchorRect) - size.width / 2.0,
                               NSMinX(visible),
                               NSMaxX(visible) - size.width);
    CGFloat belowY = NSMinY(anchorRect) - size.height - margin;
    CGFloat aboveY = NSMaxY(anchorRect) + margin;
    NSRect belowFrame = NSMakeRect(x, belowY, size.width, size.height);
    NSRect aboveFrame = NSMakeRect(x, aboveY, size.width, size.height);
    if (NSContainsRect(visible, belowFrame)) {
        if (frame) *frame = belowFrame;
        return YES;
    }
    if (NSContainsRect(visible, aboveFrame)) {
        if (frame) *frame = aboveFrame;
        return YES;
    }
    if (frame) *frame = fallbackFrame;
    return NO;
}

- (BOOL)focusedInputRect:(NSRect *)rect {
    if (!AXIsProcessTrusted()) {
        return NO;
    }
    AXUIElementRef focusedElement = NULL;
    AXUIElementRef systemElement = AXUIElementCreateSystemWide();
    AXError focusedError = AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute, (CFTypeRef *)&focusedElement);
    CFRelease(systemElement);
    if (focusedError != kAXErrorSuccess || !focusedElement) {
        return NO;
    }

    CFTypeRef positionValue = NULL;
    CFTypeRef sizeValue = NULL;
    AXError positionError = AXUIElementCopyAttributeValue(focusedElement, kAXPositionAttribute, &positionValue);
    AXError sizeError = AXUIElementCopyAttributeValue(focusedElement, kAXSizeAttribute, &sizeValue);
    CFRelease(focusedElement);
    if (positionError != kAXErrorSuccess || sizeError != kAXErrorSuccess || !positionValue || !sizeValue) {
        if (positionValue) CFRelease(positionValue);
        if (sizeValue) CFRelease(sizeValue);
        return NO;
    }

    CGPoint position = CGPointZero;
    CGSize size = CGSizeZero;
    BOOL ok = AXValueGetValue(positionValue, kAXValueCGPointType, &position) &&
        AXValueGetValue(sizeValue, kAXValueCGSizeType, &size);
    CFRelease(positionValue);
    CFRelease(sizeValue);
    if (!ok || size.width <= 0 || size.height <= 0) {
        return NO;
    }

    NSRect mainFrame = NSScreen.mainScreen.frame;
    CGFloat y = NSMaxY(mainFrame) - position.y - size.height;
    NSRect candidate = NSMakeRect(position.x, y, size.width, size.height);
    if (rect) {
        *rect = candidate;
    }
    return YES;
}

- (void)positionPanel {
    NSScreen *screen = NSScreen.mainScreen ?: NSScreen.screens.firstObject;
    NSSize size = [self preferredPanelSizeForScreen:screen];
    NSRect frame = [self defaultPanelFrameWithSize:size screen:screen];
    NSString *positionMode = CSPanelPositionModeFromPreferences(self.store.preferences);

    if ([positionMode isEqualToString:CSPanelPositionModeCustom]) {
        NSRect savedFrame = NSZeroRect;
        if (CSRectFromFramePreference(self.store.preferences[@"panelSavedFrame"], &savedFrame)) {
            frame = CSClampFrameToVisibleScreen(NSMakeRect(savedFrame.origin.x, savedFrame.origin.y, size.width, size.height),
                                                CSScreenForRect(savedFrame));
        }
    } else if ([positionMode isEqualToString:CSPanelPositionModeLast]) {
        NSRect lastFrame = NSZeroRect;
        if (CSRectFromFramePreference(self.store.preferences[@"panelLastFrame"], &lastFrame)) {
            frame = CSClampFrameToVisibleScreen(NSMakeRect(lastFrame.origin.x, lastFrame.origin.y, size.width, size.height),
                                                CSScreenForRect(lastFrame));
        }
    } else if ([positionMode isEqualToString:CSPanelPositionModeMouse]) {
        NSPoint mouse = NSEvent.mouseLocation;
        [self panelFrame:&frame nearAnchorRect:NSMakeRect(mouse.x, mouse.y, 1, 1) size:size fallbackFrame:frame];
    } else if ([positionMode isEqualToString:CSPanelPositionModeInput]) {
        NSRect inputRect = NSZeroRect;
        if ([self focusedInputRect:&inputRect]) {
            [self panelFrame:&frame nearAnchorRect:inputRect size:size fallbackFrame:frame];
        }
    }

    [self.panel setFrame:frame display:YES];
}

- (void)rememberCurrentPanelFrameIfNeeded {
    if (!self.panel.visible) {
        return;
    }
    if (![CSPanelPositionModeFromPreferences(self.store.preferences) isEqualToString:CSPanelPositionModeLast]) {
        return;
    }
    self.store.preferences[@"panelLastFrame"] = CSFramePreferenceFromRect(self.panel.frame);
    [self.store scheduleSave];
}

- (void)previewPanelLayout {
    if (self.panel.visible) {
        [self positionPanel];
        [self.panel orderFrontRegardless];
        return;
    }
    [self show];
}

- (void)saveCurrentPanelLayout {
    NSDictionary *framePreference = CSFramePreferenceFromRect(self.panel.frame);
    self.store.preferences[@"panelLastFrame"] = framePreference;
    self.store.preferences[@"panelSavedFrame"] = framePreference;
    [self.store save];
}

- (void)applyInterfaceAppearance {
    NSAppearance *appearance = CSAppearanceFromMode(CSAppearanceModeFromPreferences(self.store.preferences));
    self.panel.appearance = appearance;
    self.panel.alphaValue = CSPanelOpacityFromPreferences(self.store.preferences);
    if ([self isModernInterface]) {
        self.sidebarStack.layer.backgroundColor = [self adjustedControlBackgroundColorWithAlpha:0.42].CGColor;
        self.detailStack.layer.backgroundColor = [self adjustedControlBackgroundColorWithAlpha:0.42].CGColor;
    }
}

- (NSColor *)adjustedControlBackgroundColorWithAlpha:(CGFloat)alpha {
    return [NSColor.controlBackgroundColor colorWithAlphaComponent:alpha];
}

- (void)refreshInterfaceAppearance {
    [self applyInterfaceAppearance];
    [self updateCardSelectionStyles];
}

- (void)reloadAll {
    NSString *style = CSInterfaceStyleFromPreferences(self.store.preferences);
    if (![style isEqualToString:self.currentInterfaceStyle]) {
        BOOL wasVisible = self.panel.visible;
        NSRect frame = self.panel.frame;
        [self.shortcutsPopover close];
        [self.panel orderOut:nil];
        [self buildPanel];
        [self.panel setFrame:CSClampFrameToVisibleScreen(frame, CSScreenForRect(frame)) display:NO];
        if (wasVisible) {
            [self.panel makeKeyAndOrderFront:nil];
            [self.panel makeFirstResponder:self.searchField];
        }
        return;
    }
    [self applyInterfaceAppearance];
    self.searchField.stringValue = self.store.query ?: @"";
    [self ensureSelection];
    [self reloadSidebar];
    [self reloadKindFilterStack];
    [self reloadCards];
    [self reloadDetail];
}

- (void)handleDeletedItemsWithIDs:(NSSet<NSString *> *)deletedItemIDs {
    if (!self.panel.visible || deletedItemIDs.count == 0) {
        return;
    }
    if ([self isModernInterface]) {
        [self reloadAll];
        return;
    }

    [self reloadSidebar];

    NSMutableDictionary<NSString *, CSCardView *> *cardsByID = NSMutableDictionary.dictionary;
    for (NSView *subview in self.cardsDocumentView.subviews.copy) {
        if (![subview isKindOfClass:CSCardView.class]) {
            [subview removeFromSuperview];
            continue;
        }
        CSCardView *card = (CSCardView *)subview;
        if ([deletedItemIDs containsObject:card.itemID]) {
            [card removeFromSuperview];
        } else if (card.itemID.length > 0) {
            cardsByID[card.itemID] = card;
        }
    }

    NSArray<NSMutableDictionary *> *items = self.store.filteredItems;
    CGFloat x = 16;
    CGFloat y = 14;
    CGFloat width = 190;
    CGFloat height = 246;
    BOOL needsFullReload = NO;
    for (NSMutableDictionary *item in items) {
        CSCardView *card = cardsByID[item[@"id"]];
        if (!card) {
            needsFullReload = YES;
            break;
        }
        card.frame = NSMakeRect(x, y, width, height);
        x += width + 12;
    }

    if (needsFullReload) {
        [self reloadCards];
    } else {
        CGFloat documentWidth = MAX(self.cardScrollView.contentSize.width, x + 16);
        self.cardsDocumentView.frame = NSMakeRect(0, 0, documentWidth, height + 28);
        if (items.count == 0) {
            NSTextField *empty = CSLabel(@"复制一些内容后会出现在这里", [NSFont systemFontOfSize:14], NSColor.secondaryLabelColor);
            empty.alignment = NSTextAlignmentCenter;
            empty.frame = NSMakeRect(20, 130, MAX(320, self.cardScrollView.contentSize.width - 40), 30);
            [self.cardsDocumentView addSubview:empty];
        }
    }

    [self updateCardSelectionStyles];
    [self reloadDetail];
}

- (void)reloadSidebar {
    CSClearStack(self.sidebarStack);
    __weak typeof(self) weakSelf = self;
    [self.sidebarStack addArrangedSubview:[self filterButtonWithTitle:@"全部" symbol:@"tray.full" count:self.store.items.count selected:[self.store.filterMode isEqualToString:@"all"] action:^{
        weakSelf.store.filterMode = @"all";
        weakSelf.store.filterValue = @"";
        [weakSelf reloadAll];
    }]];
    NSUInteger pinnedCount = 0;
    for (NSDictionary *item in self.store.items) if ([item[@"pinned"] boolValue]) pinnedCount++;
    [self.sidebarStack addArrangedSubview:[self filterButtonWithTitle:@"置顶" symbol:@"pin" count:pinnedCount selected:[self.store.filterMode isEqualToString:@"pinned"] action:^{
        weakSelf.store.filterMode = @"pinned";
        weakSelf.store.filterValue = @"";
        [weakSelf reloadAll];
    }]];

    for (NSString *kind in @[CSKindText, CSKindLink, CSKindImage, CSKindFile]) {
        NSUInteger count = 0;
        for (NSDictionary *item in self.store.items) if ([item[@"kind"] isEqualToString:kind]) count++;
        [self.sidebarStack addArrangedSubview:[self filterButtonWithTitle:CSKindTitle(kind) symbol:CSKindSymbol(kind) count:count selected:[self.store.filterMode isEqualToString:@"kind"] && [self.store.filterValue isEqualToString:kind] action:^{
            weakSelf.store.filterMode = @"kind";
            weakSelf.store.filterValue = kind;
            [weakSelf reloadAll];
        }]];
    }

    NSTextField *pinboardTitle = CSLabel(@"PINBOARDS", [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor);
    [self.sidebarStack addArrangedSubview:pinboardTitle];

    for (NSDictionary *board in self.store.boards) {
        NSString *boardID = board[@"id"];
        NSUInteger count = 0;
        for (NSDictionary *item in self.store.items) if ([item[@"boardIDs"] containsObject:boardID]) count++;
        [self.sidebarStack addArrangedSubview:[self filterButtonWithTitle:board[@"name"] symbol:@"rectangle.stack" count:count selected:[self.store.filterMode isEqualToString:@"board"] && [self.store.filterValue isEqualToString:boardID] action:^{
            weakSelf.store.filterMode = @"board";
            weakSelf.store.filterValue = boardID;
            [weakSelf reloadAll];
        }]];
    }

    NSView *spacer = NSView.new;
    [self.sidebarStack addArrangedSubview:spacer];
    [spacer.heightAnchor constraintGreaterThanOrEqualToConstant:8].active = YES;

    NSStackView *newBoardRow = NSStackView.new;
    newBoardRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    newBoardRow.spacing = 6;
    NSTextField *field = NSTextField.new;
    field.placeholderString = @"新建";
    field.toolTip = @"输入 Pinboard 名称";
    [newBoardRow addArrangedSubview:field];
    CSActionButton *addBoardButton = [CSActionButton buttonWithTitle:@"" symbol:@"plus" handler:^{
        [weakSelf.store addBoardNamed:field.stringValue];
        field.stringValue = @"";
    }];
    addBoardButton.toolTip = @"新建 Pinboard";
    [newBoardRow addArrangedSubview:addBoardButton];
    [self.sidebarStack addArrangedSubview:newBoardRow];
}

- (void)reloadKindFilterStack {
    if (!self.kindFilterStack) {
        return;
    }
    CSClearStack(self.kindFilterStack);
    __weak typeof(self) weakSelf = self;
    NSArray<NSDictionary *> *filters = @[
        @{@"title": @"全部", @"mode": @"all", @"value": @""},
        @{@"title": @"文本", @"mode": @"kind", @"value": CSKindText},
        @{@"title": @"链接", @"mode": @"kind", @"value": CSKindLink},
        @{@"title": @"图片", @"mode": @"kind", @"value": CSKindImage},
        @{@"title": @"文件", @"mode": @"kind", @"value": CSKindFile}
    ];
    for (NSDictionary *filter in filters) {
        NSString *mode = filter[@"mode"];
        NSString *value = filter[@"value"];
        BOOL selected = [mode isEqualToString:@"all"] ? [self.store.filterMode isEqualToString:@"all"] : ([self.store.filterMode isEqualToString:mode] && [self.store.filterValue isEqualToString:value]);
        CSActionButton *button = [CSActionButton buttonWithTitle:filter[@"title"] symbol:nil handler:^{
            weakSelf.store.filterMode = mode;
            weakSelf.store.filterValue = value;
            [weakSelf reloadAll];
        }];
        button.bezelStyle = selected ? NSBezelStyleTexturedRounded : NSBezelStyleInline;
        button.contentTintColor = selected ? NSColor.controlAccentColor : NSColor.labelColor;
        button.toolTip = [NSString stringWithFormat:@"筛选：%@", filter[@"title"]];
        [button.widthAnchor constraintEqualToConstant:58].active = YES;
        [button.heightAnchor constraintEqualToConstant:32].active = YES;
        [self.kindFilterStack addArrangedSubview:button];
    }
}

- (NSButton *)filterButtonWithTitle:(NSString *)title symbol:(NSString *)symbol count:(NSUInteger)count selected:(BOOL)selected action:(void (^)(void))action {
    NSString *fullTitle = [NSString stringWithFormat:@"%@  %lu", title, (unsigned long)count];
    CSActionButton *button = [CSActionButton buttonWithTitle:fullTitle symbol:symbol handler:action];
    button.alignment = NSTextAlignmentLeft;
    button.bezelStyle = selected ? NSBezelStyleTexturedRounded : NSBezelStyleInline;
    button.contentTintColor = selected ? NSColor.controlAccentColor : NSColor.labelColor;
    button.toolTip = [NSString stringWithFormat:@"筛选：%@", title];
    button.imagePosition = NSImageLeft;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:150].active = YES;
    [button.heightAnchor constraintEqualToConstant:30].active = YES;
    return button;
}

- (void)reloadCards {
    CSClearSubviews(self.cardsDocumentView);
    NSArray<NSMutableDictionary *> *items = self.store.filteredItems;
    if ([self isModernInterface]) {
        CGFloat width = MAX(self.cardScrollView.contentSize.width - 16, 420);
        CGFloat cardHeight = 84;
        CGFloat spacing = 10;
        CGFloat y = 12;
        for (NSMutableDictionary *item in items) {
            CSCardView *card = [self modernCardViewForItem:item frame:NSMakeRect(8, y, width, cardHeight)];
            [self.cardsDocumentView addSubview:card];
            y += cardHeight + spacing;
        }

        CGFloat documentHeight = MAX(self.cardScrollView.contentSize.height, y + 12);
        self.cardsDocumentView.frame = NSMakeRect(0, 0, MAX(self.cardScrollView.contentSize.width, width + 16), documentHeight);

        if (items.count == 0) {
            NSTextField *empty = CSLabel(@"复制一些内容后会出现在这里", [NSFont systemFontOfSize:14], NSColor.secondaryLabelColor);
            empty.alignment = NSTextAlignmentCenter;
            empty.frame = NSMakeRect(16, 120, MAX(320, width - 32), 30);
            [self.cardsDocumentView addSubview:empty];
        }
        return;
    }

    CGFloat x = 16;
    CGFloat y = 14;
    CGFloat width = 190;
    CGFloat height = 246;
    for (NSMutableDictionary *item in items) {
        CSCardView *card = [self cardViewForItem:item frame:NSMakeRect(x, y, width, height)];
        [self.cardsDocumentView addSubview:card];
        x += width + 12;
    }

    CGFloat documentWidth = MAX(self.cardScrollView.contentSize.width, x + 16);
    self.cardsDocumentView.frame = NSMakeRect(0, 0, documentWidth, height + 28);

    if (items.count == 0) {
        NSTextField *empty = CSLabel(@"复制一些内容后会出现在这里", [NSFont systemFontOfSize:14], NSColor.secondaryLabelColor);
        empty.alignment = NSTextAlignmentCenter;
        empty.frame = NSMakeRect(20, 130, MAX(320, self.cardScrollView.contentSize.width - 40), 30);
        [self.cardsDocumentView addSubview:empty];
    }
}

- (CSCardView *)modernCardViewForItem:(NSMutableDictionary *)item frame:(NSRect)frame {
    BOOL selected = [self.store isItemSelected:item];
    CSCardView *card = [[CSCardView alloc] initWithFrame:frame];
    card.itemID = item[@"id"];
    card.toolTip = @"单击选择；Shift + 单击多选；双击或 Enter 粘贴；Shift + 双击/Enter 去格式粘贴文本；Delete 删除";
    card.wantsLayer = YES;
    card.layer.cornerRadius = 12;
    [self applySelectionStyleToCard:card selected:selected];

    __weak typeof(self) weakSelf = self;
    card.singleClick = ^(NSEvent *event) {
        BOOL shiftPressed = (event.modifierFlags & NSEventModifierFlagShift) == NSEventModifierFlagShift;
        [weakSelf selectItem:item extendingSelection:shiftPressed];
    };
    card.doubleClick = ^(NSEvent *event) {
        BOOL shiftPressed = (event.modifierFlags & NSEventModifierFlagShift) == NSEventModifierFlagShift;
        [weakSelf pasteItems:@[item] plainText:shiftPressed];
    };

    NSImageView *symbol = [[NSImageView alloc] initWithFrame:NSMakeRect(16, 50, 18, 18)];
    symbol.image = [NSImage imageWithSystemSymbolName:CSKindSymbol(item[@"kind"]) accessibilityDescription:CSKindTitle(item[@"kind"])];
    symbol.contentTintColor = selected ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
    [card addSubview:symbol];

    NSTextField *title = CSLabel(item[@"title"], [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold], NSColor.labelColor);
    title.frame = NSMakeRect(44, 48, frame.size.width - 132, 22);
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:title];

    NSString *bodyText = CSTruncate(CSCondense(item[@"body"] ?: @""), 140);
    NSTextField *body = CSLabel(bodyText.length > 0 ? bodyText : CSKindTitle(item[@"kind"]), [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    body.frame = NSMakeRect(44, 28, frame.size.width - 96, 18);
    body.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:body];

    NSString *meta = [NSString stringWithFormat:@"%@ · %@", CSKindTitle(item[@"kind"]), CSRelativeDate(item[@"date"])];
    NSTextField *source = CSLabel(meta, [NSFont systemFontOfSize:11], NSColor.tertiaryLabelColor);
    source.frame = NSMakeRect(44, 10, frame.size.width - 120, 16);
    [card addSubview:source];

    if ([item[@"pinned"] boolValue]) {
        NSImageView *pin = [[NSImageView alloc] initWithFrame:NSMakeRect(frame.size.width - 34, 52, 16, 16)];
        pin.image = [NSImage imageWithSystemSymbolName:@"pin.fill" accessibilityDescription:@"Pinned"];
        pin.contentTintColor = NSColor.systemOrangeColor;
        [card addSubview:pin];
    }

    NSTextField *app = CSLabel((item[@"sourceAppName"] ?: @""), [NSFont systemFontOfSize:10], NSColor.tertiaryLabelColor);
    app.alignment = NSTextAlignmentRight;
    app.frame = NSMakeRect(frame.size.width - 118, 10, 98, 16);
    [card addSubview:app];
    return card;
}

- (CSCardView *)cardViewForItem:(NSMutableDictionary *)item frame:(NSRect)frame {
    BOOL selected = [self.store isItemSelected:item];
    CSCardView *card = [[CSCardView alloc] initWithFrame:frame];
    card.itemID = item[@"id"];
    card.toolTip = @"单击选择；Shift + 单击多选；双击或 Enter 粘贴；Shift + 双击/Enter 去格式粘贴文本；Delete 删除";
    card.wantsLayer = YES;
    card.layer.cornerRadius = 10;
    [self applySelectionStyleToCard:card selected:selected];

    __weak typeof(self) weakSelf = self;
    card.singleClick = ^(NSEvent *event) {
        BOOL shiftPressed = (event.modifierFlags & NSEventModifierFlagShift) == NSEventModifierFlagShift;
        [weakSelf selectItem:item extendingSelection:shiftPressed];
    };
    card.doubleClick = ^(NSEvent *event) {
        BOOL shiftPressed = (event.modifierFlags & NSEventModifierFlagShift) == NSEventModifierFlagShift;
        [weakSelf pasteItems:@[item] plainText:shiftPressed];
    };

    NSImageView *symbol = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 216, 16, 16)];
    symbol.image = [NSImage imageWithSystemSymbolName:CSKindSymbol(item[@"kind"]) accessibilityDescription:CSKindTitle(item[@"kind"])];
    [card addSubview:symbol];

    NSTextField *kindLabel = CSLabel(CSKindTitle(item[@"kind"]), [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor);
    kindLabel.frame = NSMakeRect(34, 213, 90, 20);
    [card addSubview:kindLabel];

    if ([item[@"pinned"] boolValue]) {
        NSImageView *pin = [[NSImageView alloc] initWithFrame:NSMakeRect(162, 216, 16, 16)];
        pin.image = [NSImage imageWithSystemSymbolName:@"pin.fill" accessibilityDescription:@"Pinned"];
        pin.contentTintColor = NSColor.systemOrangeColor;
        [card addSubview:pin];
    }

    NSView *preview = [self previewViewForItem:item frame:NSMakeRect(12, 118, 166, 86) compact:YES];
    preview.wantsLayer = YES;
    preview.layer.cornerRadius = 8;
    preview.layer.masksToBounds = YES;
    [card addSubview:preview];

    NSTextField *title = CSLabel(item[@"title"], [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold], NSColor.labelColor);
    title.frame = NSMakeRect(12, 76, 166, 38);
    title.maximumNumberOfLines = 2;
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    [card addSubview:title];

    NSTextField *body = CSLabel(CSTruncate(CSCondense(item[@"body"] ?: @""), 80), [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor);
    body.frame = NSMakeRect(12, 44, 166, 32);
    body.maximumNumberOfLines = 2;
    [card addSubview:body];

    NSTextField *source = CSLabel((item[@"sourceAppName"] ?: @"未知来源"), [NSFont systemFontOfSize:10], NSColor.tertiaryLabelColor);
    source.frame = NSMakeRect(12, 14, 96, 16);
    [card addSubview:source];

    NSTextField *date = CSLabel(CSRelativeDate(item[@"date"]), [NSFont systemFontOfSize:10], NSColor.tertiaryLabelColor);
    date.alignment = NSTextAlignmentRight;
    date.frame = NSMakeRect(112, 14, 66, 16);
    [card addSubview:date];
    return card;
}

- (void)updateCardSelectionStyles {
    NSMutableSet<NSString *> *selectedIDs = NSMutableSet.set;
    for (NSString *itemID in self.store.selectedItemIDs) {
        [selectedIDs addObject:itemID];
    }
    for (NSView *subview in self.cardsDocumentView.subviews) {
        if (![subview isKindOfClass:CSCardView.class]) {
            continue;
        }
        CSCardView *card = (CSCardView *)subview;
        [self applySelectionStyleToCard:card selected:[selectedIDs containsObject:card.itemID]];
    }
}

- (void)applySelectionStyleToCard:(CSCardView *)card selected:(BOOL)selected {
    card.layer.borderWidth = selected ? 1.5 : 1.0;
    card.layer.borderColor = (selected ? NSColor.controlAccentColor : [NSColor.separatorColor colorWithAlphaComponent:0.55]).CGColor;
    CGFloat baseAlpha = [self isModernInterface] ? 0.46 : 0.72;
    CGFloat selectedAlpha = [self isModernInterface] ? 0.22 : 0.16;
    card.layer.backgroundColor = (selected ? [NSColor.controlAccentColor colorWithAlphaComponent:selectedAlpha] : [self adjustedControlBackgroundColorWithAlpha:baseAlpha]).CGColor;
}

- (NSView *)previewViewForItem:(NSDictionary *)item frame:(NSRect)frame compact:(BOOL)compact {
    NSString *kind = item[@"kind"];
    if ([kind isEqualToString:CSKindImage]) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:item[@"imageBase64"] ?: @"" options:0];
        NSImageView *imageView = [[NSImageView alloc] initWithFrame:frame];
        imageView.image = [[NSImage alloc] initWithData:data];
        imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        imageView.wantsLayer = YES;
        imageView.layer.backgroundColor = [self adjustedControlBackgroundColorWithAlpha:0.8].CGColor;
        return imageView;
    }

    if ([kind isEqualToString:CSKindFile]) {
        NSTextField *files = CSLabel(CSTruncate([item[@"body"] ?: @"" lastPathComponent], compact ? 120 : 400), [NSFont systemFontOfSize:compact ? 11 : 13], NSColor.secondaryLabelColor);
        files.frame = frame;
        files.maximumNumberOfLines = compact ? 4 : 8;
        files.wantsLayer = YES;
        files.layer.backgroundColor = [self adjustedControlBackgroundColorWithAlpha:0.8].CGColor;
        return files;
    }

    NSTextField *text = CSLabel(CSTruncate(CSTrim(item[@"body"] ?: @""), compact ? 110 : 1000), [NSFont monospacedSystemFontOfSize:compact ? 11 : 12 weight:NSFontWeightRegular], NSColor.secondaryLabelColor);
    text.frame = frame;
    text.maximumNumberOfLines = compact ? 4 : 0;
    text.wantsLayer = YES;
    text.layer.backgroundColor = [self adjustedControlBackgroundColorWithAlpha:0.8].CGColor;
    return text;
}

- (NSView *)detailPreviewContainerForItem:(NSDictionary *)item {
    CGFloat viewportWidth = [self isModernInterface] ? 294.0 : 258.0;
    CGFloat viewportHeight = [self isModernInterface] ? 180.0 : 168.0;

    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, viewportWidth, viewportHeight)];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.wantsLayer = YES;
    container.layer.cornerRadius = 8;
    container.layer.borderWidth = 1;
    container.layer.borderColor = [NSColor.separatorColor colorWithAlphaComponent:0.55].CGColor;
    container.layer.backgroundColor = [self adjustedControlBackgroundColorWithAlpha:0.72].CGColor;
    [container.widthAnchor constraintEqualToConstant:viewportWidth].active = YES;
    [container.heightAnchor constraintEqualToConstant:viewportHeight].active = YES;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.drawsBackground = NO;
    [container addSubview:scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:container.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
    ]];

    NSString *kind = item[@"kind"];
    if ([kind isEqualToString:CSKindImage]) {
        NSData *data = [[NSData alloc] initWithBase64EncodedString:item[@"imageBase64"] ?: @"" options:0];
        NSImage *image = [[NSImage alloc] initWithData:data];
        if (image) {
            CGFloat documentWidth = MIN(MAX(image.size.width, viewportWidth), 4096.0);
            CGFloat documentHeight = MIN(MAX(image.size.height, viewportHeight), 4096.0);
            NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, documentWidth, documentHeight)];
            imageView.image = image;
            imageView.imageAlignment = NSImageAlignTopLeft;
            imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
            imageView.wantsLayer = YES;
            imageView.layer.backgroundColor = NSColor.clearColor.CGColor;
            scrollView.documentView = imageView;
            return container;
        }
    }

    NSString *text = item[@"body"] ?: @"";
    NSTextView *textView = [self textDocumentViewForPreview:text viewportWidth:viewportWidth viewportHeight:viewportHeight];
    scrollView.documentView = textView;
    return container;
}

- (NSTextView *)textDocumentViewForPreview:(NSString *)text viewportWidth:(CGFloat)viewportWidth viewportHeight:(CGFloat)viewportHeight {
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSUInteger longestLineLength = 0;
    for (NSString *line in lines) {
        longestLineLength = MAX(longestLineLength, line.length);
    }

    CGFloat documentWidth = MIN(MAX(viewportWidth, (CGFloat)longestLineLength * 7.4 + 28.0), 4096.0);
    CGFloat documentHeight = MIN(MAX(viewportHeight, (CGFloat)MAX(lines.count, 1) * 18.0 + 28.0), 4096.0);

    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, documentWidth, documentHeight)];
    textView.string = text ?: @"";
    textView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    textView.textColor = NSColor.secondaryLabelColor;
    textView.editable = NO;
    textView.selectable = YES;
    textView.drawsBackground = NO;
    textView.textContainerInset = NSMakeSize(10, 10);
    textView.horizontallyResizable = YES;
    textView.verticallyResizable = YES;
    textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    textView.textContainer.widthTracksTextView = NO;
    textView.textContainer.containerSize = NSMakeSize(documentWidth, CGFLOAT_MAX);
    return textView;
}

- (void)reloadDetail {
    CSClearStack(self.detailStack);
    NSMutableDictionary *item = self.store.selectedItem;
    if (!item) {
        NSTextField *empty = CSLabel(@"复制一些内容后会出现在这里", [NSFont systemFontOfSize:14], NSColor.secondaryLabelColor);
        empty.alignment = NSTextAlignmentCenter;
        [self.detailStack addArrangedSubview:empty];
        return;
    }
    NSArray<NSMutableDictionary *> *selectedItems = self.store.selectedItems;
    if (selectedItems.count > 1) {
        NSTextField *multiLabel = CSLabel([NSString stringWithFormat:@"已选择 %lu 项", (unsigned long)selectedItems.count],
                                          [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
                                          NSColor.controlAccentColor);
        [self.detailStack addArrangedSubview:multiLabel];
    }

    NSStackView *header = NSStackView.new;
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.spacing = 8;
    [header addArrangedSubview:CSLabel(CSKindTitle(item[@"kind"]), [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor)];
    NSView *spacer = NSView.new;
    [header addArrangedSubview:spacer];
    [header addArrangedSubview:CSLabel(CSRelativeDate(item[@"date"]), [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor)];
    [self.detailStack addArrangedSubview:header];

    if ([self.store.preferences[@"showDetailPreview"] boolValue]) {
        NSView *preview = [self detailPreviewContainerForItem:item];
        [self.detailStack addArrangedSubview:preview];
    }

    NSTextField *title = CSLabel(item[@"title"], [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold], NSColor.labelColor);
    title.maximumNumberOfLines = 2;
    [self.detailStack addArrangedSubview:title];

    if ([item[@"sourceAppName"] length] > 0) {
        [self.detailStack addArrangedSubview:CSLabel(item[@"sourceAppName"], [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor)];
    }

    [self.detailStack addArrangedSubview:[self boardChipsForItem:item]];

    NSView *fill = NSView.new;
    [fill.heightAnchor constraintGreaterThanOrEqualToConstant:20].active = YES;
    [self.detailStack addArrangedSubview:fill];

    __weak typeof(self) weakSelf = self;
    NSStackView *actions = NSStackView.new;
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 8;
    CSActionButton *pasteButton = [CSActionButton buttonWithTitle:@"粘贴" symbol:@"paperplane.fill" handler:^{
        [weakSelf pasteItems:weakSelf.store.selectedItems plainText:NO];
    }];
    pasteButton.toolTip = @"把选中内容写入剪贴板，并在允许时自动粘贴到目标 App；Shift + Enter 可去格式粘贴文本";
    [actions addArrangedSubview:pasteButton];
    CSActionButton *pinButton = [CSActionButton buttonWithTitle:@"" symbol:[item[@"pinned"] boolValue] ? @"pin.fill" : @"pin" handler:^{
        [weakSelf.store togglePin:item];
    }];
    pinButton.toolTip = [item[@"pinned"] boolValue] ? @"取消置顶当前记录" : @"置顶当前记录";
    [actions addArrangedSubview:pinButton];
    CSActionButton *copyPlainTextButton = [CSActionButton buttonWithTitle:@"" symbol:@"doc.on.doc" handler:^{
        [weakSelf.store restoreItemToPasteboard:item asPlainText:YES];
    }];
    copyPlainTextButton.toolTip = @"复制到剪贴板但不自动粘贴；文本会去格式，图片和文件保持原内容";
    [actions addArrangedSubview:copyPlainTextButton];
    [self.detailStack addArrangedSubview:actions];

    if (self.store.lastNotice.length > 0) {
        [self.detailStack addArrangedSubview:CSLabel(self.store.lastNotice, [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor)];
    }
}

- (NSView *)boardChipsForItem:(NSMutableDictionary *)item {
    NSStackView *chips = NSStackView.new;
    chips.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    chips.spacing = 6;
    __weak typeof(self) weakSelf = self;
    for (NSDictionary *board in self.store.boards) {
        BOOL active = [item[@"boardIDs"] containsObject:board[@"id"]];
        CSActionButton *chip = [CSActionButton buttonWithTitle:board[@"name"] symbol:nil handler:^{
            [weakSelf.store toggleBoard:board forItem:item];
        }];
        chip.bezelStyle = active ? NSBezelStyleRegularSquare : NSBezelStyleInline;
        chip.contentTintColor = active ? CSColorFromHex(board[@"color"], 1) : NSColor.labelColor;
        chip.toolTip = active ? @"从这个 Pinboard 移除当前记录" : @"把当前记录加入这个 Pinboard";
        [chips addArrangedSubview:chip];
    }
    return chips;
}

- (void)ensureSelection {
    NSArray *items = self.store.filteredItems;
    NSMutableSet<NSString *> *visibleIDs = NSMutableSet.set;
    BOOL foundPrimary = NO;
    for (NSDictionary *item in items) {
        NSString *itemID = item[@"id"];
        if (itemID.length > 0) {
            [visibleIDs addObject:itemID];
        }
        if ([item[@"id"] isEqualToString:self.store.selectedItemID]) {
            foundPrimary = YES;
        }
    }

    for (NSString *itemID in self.store.selectedItemIDs.array.copy) {
        if (![visibleIDs containsObject:itemID]) {
            [self.store.selectedItemIDs removeObject:itemID];
        }
    }

    if (!foundPrimary) {
        self.store.selectedItemID = items.firstObject[@"id"];
    }
    if (self.store.selectedItemIDs.count == 0 && self.store.selectedItemID.length > 0) {
        [self.store.selectedItemIDs addObject:self.store.selectedItemID];
    }
}

- (void)pasteItem:(NSMutableDictionary *)item plainText:(BOOL)plainText {
    if (item) {
        [self pasteItems:@[item] plainText:plainText];
    }
}

- (void)pasteItems:(NSArray<NSMutableDictionary *> *)items plainText:(BOOL)plainText {
    if (items.count == 0) {
        return;
    }
    NSRunningApplication *targetApplication = self.lastTargetApplication;
    BOOL hasTextLikeItem = NO;
    for (NSDictionary *item in items) {
        NSString *kind = item[@"kind"];
        if ([kind isEqualToString:CSKindText] || [kind isEqualToString:CSKindLink]) {
            hasTextLikeItem = YES;
            break;
        }
    }
    BOOL effectivePlainText = plainText && hasTextLikeItem;
    [self.store writeItemsToPasteboard:items asPlainText:effectivePlainText];
    if (effectivePlainText) {
        self.store.lastNotice = items.count > 1 ? [NSString stringWithFormat:@"已去格式放回剪贴板 %lu 项", (unsigned long)items.count] : @"已去格式放回剪贴板";
    } else {
        self.store.lastNotice = items.count > 1 ? [NSString stringWithFormat:@"已放回剪贴板 %lu 项", (unsigned long)items.count] : @"已放回剪贴板";
    }
    BOOL shouldHide = [self.store.preferences[@"hideAfterSelection"] boolValue];

    if (![self.store.preferences[@"autoPaste"] boolValue]) {
        if (shouldHide) {
            [self close];
        }
        return;
    }

    if (!AXIsProcessTrusted()) {
        NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        self.store.lastNotice = @"已复制。授权无障碍后可自动粘贴。";
        if (shouldHide) {
            [self close];
        } else {
            [self reloadDetail];
        }
        return;
    }

    if (!targetApplication || targetApplication.terminated) {
        self.store.lastNotice = @"已复制。未找到可粘贴的目标 App。";
        if (shouldHide) {
            [self close];
        } else {
            [self reloadDetail];
        }
        return;
    }

    self.suppressNextDeactivateClose = YES;
    self.panel.hidesOnDeactivate = NO;
    self.panel.floatingPanel = YES;
    self.panel.level = NSFloatingWindowLevel;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!targetApplication.terminated) {
            [targetApplication unhide];
            [targetApplication activateWithOptions:NSApplicationActivateIgnoringOtherApps | NSApplicationActivateAllWindows];
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.07 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (targetApplication.terminated) {
                if (shouldHide) {
                    [self close];
                }
                return;
            }
            CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
            CGEventRef down = CGEventCreateKeyboardEvent(source, (CGKeyCode)kVK_ANSI_V, true);
            CGEventRef up = CGEventCreateKeyboardEvent(source, (CGKeyCode)kVK_ANSI_V, false);
            CGEventSetFlags(down, kCGEventFlagMaskCommand);
            CGEventSetFlags(up, kCGEventFlagMaskCommand);
            CGEventPost(kCGHIDEventTap, down);
            CGEventPost(kCGHIDEventTap, up);
            CFRelease(down);
            CFRelease(up);
            CFRelease(source);
            if (shouldHide) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self close];
                });
            }
        });
    });
}
@end

@interface CSSettingsController : NSObject
@property (nonatomic, strong) CSStore *store;
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTextView *ignoredTextView;
@property (nonatomic, copy) NSString *currentInterfaceStyle;
@property (nonatomic, strong) NSSegmentedControl *interfaceStyleControl;
@property (nonatomic, strong) NSSegmentedControl *modernSectionControl;
@property (nonatomic, strong) NSStackView *modernContentStack;
@property (nonatomic, strong) NSArray<CSActionButton *> *modernNavigationButtons;
@property (nonatomic, strong) NSView *settingsContentBackgroundView;
@property (nonatomic, strong) NSView *modernSidebarView;
@property (nonatomic, strong) NSView *modernPanelSurfaceView;
@property (nonatomic, assign) NSInteger modernSelectedSection;
@property (nonatomic, strong) NSTextField *maxItemsLabel;
@property (nonatomic, strong) NSSegmentedControl *appearanceControl;
@property (nonatomic, strong) NSTextField *transparencyLabel;
@property (nonatomic, strong) NSSlider *transparencySlider;
@property (nonatomic, strong) NSSegmentedControl *panelSizeModeControl;
@property (nonatomic, strong) NSPopUpButton *panelPositionModePopup;
@property (nonatomic, strong) NSTextField *panelLayoutStatusLabel;
@property (nonatomic, strong) CSHotKeyRecorder *hotKeyRecorder;
@property (nonatomic, strong) NSTextField *hotKeyStatusLabel;
@property (nonatomic, strong) NSView *hotKeyStatusRow;
@property (nonatomic, copy) void (^hotKeyRecordingChanged)(BOOL recording);
@property (nonatomic, copy) void (^panelLayoutPreviewRequested)(void);
@property (nonatomic, copy) void (^panelLayoutSaveRequested)(void);
- (instancetype)initWithStore:(CSStore *)store;
- (void)show;
- (void)refresh;
@end

@implementation CSSettingsController

- (instancetype)initWithStore:(CSStore *)store {
    self = [super init];
    if (!self) return nil;
    _store = store;
    [self buildWindow];
    return self;
}

- (NSView *)modernPanelView {
    NSView *view = NSView.new;
    view.wantsLayer = YES;
    view.layer.cornerRadius = 12;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    return view;
}

- (BOOL)settingsUseDarkAppearance {
    NSString *match = [self.window.effectiveAppearance bestMatchFromAppearancesWithNames:@[
        NSAppearanceNameAqua,
        NSAppearanceNameDarkAqua
    ]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

- (NSColor *)settingsWindowBackgroundColor {
    return [self settingsUseDarkAppearance] ? CSColorFromHex(@"1F2023", 1.0) : CSColorFromHex(@"F5F6F8", 1.0);
}

- (NSColor *)settingsSurfaceColor {
    return [self settingsUseDarkAppearance] ? CSColorFromHex(@"2A2C30", 1.0) : CSColorFromHex(@"FFFFFF", 1.0);
}

- (NSColor *)settingsSelectedNavigationColor {
    return [self settingsUseDarkAppearance] ? [NSColor.controlAccentColor colorWithAlphaComponent:0.26] : [NSColor.controlAccentColor colorWithAlphaComponent:0.14];
}

- (void)applySettingsSurfaceColors {
    self.window.backgroundColor = [self settingsWindowBackgroundColor];
    self.settingsContentBackgroundView.wantsLayer = YES;
    self.settingsContentBackgroundView.layer.backgroundColor = [self settingsWindowBackgroundColor].CGColor;
    self.modernSidebarView.layer.backgroundColor = [self settingsSurfaceColor].CGColor;
    self.modernPanelSurfaceView.layer.backgroundColor = [self settingsSurfaceColor].CGColor;
    [self refreshModernNavigationSelection];
}

- (NSTextField *)settingsTitleLabel:(NSString *)text {
    NSTextField *label = CSLabel(text, [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold], NSColor.labelColor);
    label.maximumNumberOfLines = 1;
    return label;
}

- (NSStackView *)settingsRowWithTitle:(NSString *)title control:(NSView *)control subtitle:(NSString *)subtitle {
    NSStackView *row = NSStackView.new;
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 14;
    row.alignment = NSLayoutAttributeTop;

    NSTextField *label = CSLabel(title ?: @"", [NSFont systemFontOfSize:14 weight:NSFontWeightMedium], NSColor.labelColor);
    label.alignment = NSTextAlignmentRight;
    [label.widthAnchor constraintEqualToConstant:118].active = YES;
    [row addArrangedSubview:label];

    NSStackView *content = NSStackView.new;
    content.orientation = NSUserInterfaceLayoutOrientationVertical;
    content.spacing = 5;
    content.alignment = NSLayoutAttributeLeading;
    [content addArrangedSubview:control];
    if (subtitle.length > 0) {
        NSTextField *subtitleLabel = CSLabel(subtitle, [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
        subtitleLabel.maximumNumberOfLines = 2;
        [content addArrangedSubview:subtitleLabel];
    }
    [row addArrangedSubview:content];
    return row;
}

- (NSStackView *)settingsIndentedRowWithControl:(NSView *)control subtitle:(NSString *)subtitle {
    return [self settingsRowWithTitle:@"" control:control subtitle:subtitle];
}

- (NSStackView *)settingsCheckboxStackWithKeys:(NSArray<NSString *> *)keys titles:(NSArray<NSString *> *)titles {
    NSStackView *stack = NSStackView.new;
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 9;
    stack.alignment = NSLayoutAttributeLeading;
    for (NSUInteger index = 0; index < keys.count && index < titles.count; index++) {
        [stack addArrangedSubview:[self checkboxWithTitle:titles[index] key:keys[index]]];
    }
    return stack;
}

- (NSBox *)settingsDivider {
    NSBox *divider = NSBox.new;
    divider.boxType = NSBoxSeparator;
    return divider;
}

- (void)styleNavigationButton:(CSActionButton *)button selected:(BOOL)selected {
    NSString *title = button.title.length > 0 ? button.title : button.attributedTitle.string;
    NSColor *textColor = selected ? NSColor.controlAccentColor : NSColor.labelColor;
    NSFont *font = [NSFont systemFontOfSize:14 weight:selected ? NSFontWeightSemibold : NSFontWeightMedium];
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title ?: @""
                                                              attributes:@{NSForegroundColorAttributeName: textColor,
                                                                           NSFontAttributeName: font}];
    button.contentTintColor = textColor;
    button.layer.backgroundColor = (selected ? [self settingsSelectedNavigationColor] : NSColor.clearColor).CGColor;
}

- (void)refreshModernNavigationSelection {
    for (CSActionButton *button in self.modernNavigationButtons) {
        [self styleNavigationButton:button selected:(button.tag == self.modernSelectedSection)];
    }
}

- (CSActionButton *)modernNavigationButtonWithTitle:(NSString *)title symbol:(NSString *)symbol index:(NSInteger)index {
    __weak typeof(self) weakSelf = self;
    CSActionButton *button = [CSActionButton buttonWithTitle:title symbol:symbol handler:^{
        [weakSelf showModernSection:index];
    }];
    button.alignment = NSTextAlignmentLeft;
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.bordered = NO;
    button.wantsLayer = YES;
    button.layer.cornerRadius = 8;
    button.tag = index;
    button.imagePosition = NSImageLeft;
    button.toolTip = title;
    [button.heightAnchor constraintEqualToConstant:36].active = YES;
    [self styleNavigationButton:button selected:NO];
    return button;
}

- (NSStackView *)modernLabeledRowWithTitle:(NSString *)title control:(NSView *)control subtitle:(NSString *)subtitle {
    return [self settingsRowWithTitle:title control:control subtitle:subtitle];
}

- (void)buildModernWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 740, 520)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"CopyPaste 设置";
    self.window.minSize = NSMakeSize(700, 480);
    self.window.releasedWhenClosed = NO;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorTransient;

    NSView *content = NSView.new;
    self.settingsContentBackgroundView = content;
    content.wantsLayer = YES;
    self.window.contentView = content;

    NSStackView *root = NSStackView.new;
    root.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    root.spacing = 14;
    root.edgeInsets = NSEdgeInsetsMake(16, 16, 16, 16);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
    ]];

    NSStackView *sidebar = NSStackView.new;
    sidebar.orientation = NSUserInterfaceLayoutOrientationVertical;
    sidebar.spacing = 10;
    sidebar.edgeInsets = NSEdgeInsetsMake(18, 14, 18, 14);
    sidebar.wantsLayer = YES;
    sidebar.layer.cornerRadius = 12;
    self.modernSidebarView = sidebar;
    [root addArrangedSubview:sidebar];
    [sidebar.widthAnchor constraintEqualToConstant:168].active = YES;

    [sidebar addArrangedSubview:CSLabel(@"CopyPaste", [NSFont systemFontOfSize:19 weight:NSFontWeightSemibold], NSColor.labelColor)];
    NSTextField *subtitle = CSLabel(@"偏好设置", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    subtitle.maximumNumberOfLines = 2;
    [sidebar addArrangedSubview:subtitle];

    self.interfaceStyleControl = [NSSegmentedControl segmentedControlWithLabels:@[@"经典", @"现代"]
                                                                    trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                          target:self
                                                                          action:@selector(interfaceStyleChanged:)];
    self.interfaceStyleControl.segmentStyle = NSSegmentStyleRounded;
    self.interfaceStyleControl.toolTip = @"切换 CopyPaste 的界面布局";
    [self.interfaceStyleControl.heightAnchor constraintEqualToConstant:30].active = YES;
    [sidebar addArrangedSubview:self.interfaceStyleControl];

    NSBox *divider = NSBox.new;
    divider.boxType = NSBoxSeparator;
    [sidebar addArrangedSubview:divider];

    CSActionButton *generalButton = [self modernNavigationButtonWithTitle:@"通用" symbol:@"gearshape" index:0];
    CSActionButton *shortcutButton = [self modernNavigationButtonWithTitle:@"快捷键" symbol:@"keyboard" index:1];
    CSActionButton *appearanceButton = [self modernNavigationButtonWithTitle:@"外观" symbol:@"paintbrush" index:2];
    CSActionButton *ignoredButton = [self modernNavigationButtonWithTitle:@"忽略应用" symbol:@"nosign" index:3];
    self.modernNavigationButtons = @[generalButton, shortcutButton, appearanceButton, ignoredButton];
    for (CSActionButton *button in self.modernNavigationButtons) {
        [sidebar addArrangedSubview:button];
    }
    NSView *sidebarFill = NSView.new;
    [sidebar addArrangedSubview:sidebarFill];

    NSView *panel = [self modernPanelView];
    self.modernPanelSurfaceView = panel;
    [root addArrangedSubview:panel];
    [panel.widthAnchor constraintGreaterThanOrEqualToConstant:440].active = YES;

    self.modernContentStack = NSStackView.new;
    self.modernContentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.modernContentStack.spacing = 13;
    self.modernContentStack.edgeInsets = NSEdgeInsetsMake(22, 24, 22, 24);
    self.modernContentStack.alignment = NSLayoutAttributeLeading;
    self.modernContentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:self.modernContentStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.modernContentStack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [self.modernContentStack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [self.modernContentStack.topAnchor constraintEqualToAnchor:panel.topAnchor],
        [self.modernContentStack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor]
    ]];

    [self showModernSection:0];
    [self applySettingsSurfaceColors];
}

- (void)showModernSection:(NSInteger)section {
    CSClearStack(self.modernContentStack);
    __weak typeof(self) weakSelf = self;
    self.modernSelectedSection = MIN(MAX(section, 0), 3);
    [self refreshModernNavigationSelection];
    NSArray<NSString *> *titles = @[@"通用", @"快捷键", @"外观", @"忽略应用"];
    NSString *title = titles[(NSUInteger)self.modernSelectedSection];
    [self.modernContentStack addArrangedSubview:[self settingsTitleLabel:title]];

    if (self.modernSelectedSection == 0) {
        NSStackView *checks = [self settingsCheckboxStackWithKeys:@[@"autoPaste", @"hideAfterSelection", @"showDetailPreview", @"captureImages", @"showDock"]
                                                           titles:@[@"复制后自动粘贴", @"选择后自动隐藏", @"显示内容预览", @"记录图片内容", @"在 Dock 中显示图标"]];
        [self.modernContentStack addArrangedSubview:[self settingsRowWithTitle:@"基础选项" control:checks subtitle:@"这些选项控制 CopyPaste 日常使用时的默认行为。"]];
    } else if (self.modernSelectedSection == 1) {
        self.hotKeyRecorder = [[CSHotKeyRecorder alloc] initWithFrame:NSZeroRect];
        [self.hotKeyRecorder.widthAnchor constraintEqualToConstant:190].active = YES;
        self.hotKeyRecorder.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        self.hotKeyRecorder.hotKeyChanged = ^(UInt32 keyCode, UInt32 modifiers, NSString *displayName) {
            [weakSelf.store updatePreferenceKey:@"hotKey" value:CSHotKeyPreference(keyCode, modifiers, displayName)];
        };
        self.hotKeyRecorder.recordingChanged = ^(BOOL recording) {
            if (weakSelf.hotKeyRecordingChanged) {
                weakSelf.hotKeyRecordingChanged(recording);
            }
        };
        [self.modernContentStack addArrangedSubview:[self modernLabeledRowWithTitle:@"唤醒快捷键" control:self.hotKeyRecorder subtitle:@"录制用于打开 CopyPaste 面板的全局快捷键。"]];
        self.hotKeyStatusLabel = CSLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
        self.hotKeyStatusLabel.maximumNumberOfLines = 2;
        self.hotKeyStatusRow = [self settingsIndentedRowWithControl:self.hotKeyStatusLabel subtitle:nil];
        [self.modernContentStack addArrangedSubview:self.hotKeyStatusRow];
        CSActionButton *accessibilityButton = [CSActionButton buttonWithTitle:@"请求无障碍权限" symbol:@"hand.raised" handler:^{
            NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
        }];
        accessibilityButton.toolTip = @"打开系统授权提示；授权后可自动粘贴到目标 App";
        [self.modernContentStack addArrangedSubview:[self modernLabeledRowWithTitle:@"无障碍权限" control:accessibilityButton subtitle:@"自动粘贴需要此权限；未授权时仍可手动粘贴。"]];
    } else if (self.modernSelectedSection == 2) {
        self.appearanceControl = [NSSegmentedControl segmentedControlWithLabels:@[@"浅色", @"深色", @"系统"]
                                                                    trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                          target:self
                                                                          action:@selector(appearanceChanged:)];
        self.appearanceControl.segmentStyle = NSSegmentStyleRounded;
        [self.modernContentStack addArrangedSubview:[self modernLabeledRowWithTitle:@"外观" control:self.appearanceControl subtitle:@"选择 CopyPaste 使用浅色、深色或跟随系统。"]];

        NSStackView *transparencyControl = NSStackView.new;
        transparencyControl.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        transparencyControl.spacing = 10;
        transparencyControl.alignment = NSLayoutAttributeCenterY;
        self.transparencySlider = NSSlider.new;
        self.transparencySlider.minValue = 0;
        self.transparencySlider.maxValue = 45;
        self.transparencySlider.continuous = YES;
        self.transparencySlider.target = self;
        self.transparencySlider.action = @selector(transparencyChanged:);
        [self.transparencySlider.widthAnchor constraintEqualToConstant:230].active = YES;
        [transparencyControl addArrangedSubview:self.transparencySlider];
        self.transparencyLabel = CSLabel(@"", [NSFont systemFontOfSize:14 weight:NSFontWeightMedium], NSColor.labelColor);
        [self.transparencyLabel.widthAnchor constraintEqualToConstant:52].active = YES;
        [transparencyControl addArrangedSubview:self.transparencyLabel];
        [self.modernContentStack addArrangedSubview:[self modernLabeledRowWithTitle:@"界面透明度" control:transparencyControl subtitle:@"控制面板背景透出背后窗口的程度。"]];

        self.panelSizeModeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"临时拖拽", @"固定保存"]
                                                                       trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                             target:self
                                                                             action:@selector(panelSizeModeChanged:)];
        self.panelSizeModeControl.segmentStyle = NSSegmentStyleRounded;
        [self.modernContentStack addArrangedSubview:[self modernLabeledRowWithTitle:@"窗口大小" control:self.panelSizeModeControl subtitle:@"临时拖拽只影响本次；固定保存会长期使用保存尺寸。"]];

        self.panelPositionModePopup = NSPopUpButton.new;
        [self.panelPositionModePopup addItemsWithTitles:@[@"默认位置", @"固定位置", @"记录上次", @"鼠标附近", @"输入框附近"]];
        self.panelPositionModePopup.target = self;
        self.panelPositionModePopup.action = @selector(panelPositionModeChanged:);
        [self.modernContentStack addArrangedSubview:[self modernLabeledRowWithTitle:@"窗口位置" control:self.panelPositionModePopup subtitle:@"选择面板唤醒时的位置策略。"]];

        NSStackView *actions = NSStackView.new;
        actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        actions.spacing = 10;
        CSActionButton *showPanelButton = [CSActionButton buttonWithTitle:@"显示窗口" symbol:@"macwindow" handler:^{
            if (weakSelf.panelLayoutPreviewRequested) {
                weakSelf.panelLayoutPreviewRequested();
            }
        }];
        [actions addArrangedSubview:showPanelButton];
        CSActionButton *savePanelButton = [CSActionButton buttonWithTitle:@"保存当前窗口" symbol:@"checkmark" handler:^{
            if (weakSelf.panelLayoutSaveRequested) {
                weakSelf.panelLayoutSaveRequested();
            }
            weakSelf.panelLayoutStatusLabel.stringValue = @"已保存当前窗口大小和位置";
        }];
        [actions addArrangedSubview:savePanelButton];
        [self.modernContentStack addArrangedSubview:[self modernLabeledRowWithTitle:@"布局操作" control:actions subtitle:@"打开面板调整位置和尺寸，再保存为固定布局。"]];
        self.panelLayoutStatusLabel = CSLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
        self.panelLayoutStatusLabel.maximumNumberOfLines = 2;
        [self.modernContentStack addArrangedSubview:[self settingsIndentedRowWithControl:self.panelLayoutStatusLabel subtitle:nil]];
    } else {
        NSStackView *maxRow = NSStackView.new;
        maxRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        maxRow.spacing = 10;
        maxRow.alignment = NSLayoutAttributeCenterY;
        self.maxItemsLabel = CSLabel(@"", [NSFont systemFontOfSize:14 weight:NSFontWeightMedium], NSColor.labelColor);
        [self.maxItemsLabel.widthAnchor constraintEqualToConstant:92].active = YES;
        [maxRow addArrangedSubview:self.maxItemsLabel];
        NSStepper *stepper = NSStepper.new;
        stepper.minValue = 50;
        stepper.maxValue = 2000;
        stepper.increment = 50;
        stepper.integerValue = [self.store.preferences[@"maxItems"] integerValue];
        stepper.target = self;
        stepper.action = @selector(maxItemsChanged:);
        [maxRow addArrangedSubview:stepper];
        [self.modernContentStack addArrangedSubview:[self modernLabeledRowWithTitle:@"历史数量" control:maxRow subtitle:@"限制本地剪贴板历史保存条数。"]];

        [self.modernContentStack addArrangedSubview:CSLabel(@"忽略的 Bundle ID", [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold], NSColor.labelColor)];
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        scroll.hasVerticalScroller = YES;
        self.ignoredTextView = NSTextView.new;
        self.ignoredTextView.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
        scroll.documentView = self.ignoredTextView;
        [scroll.widthAnchor constraintEqualToConstant:430].active = YES;
        [scroll.heightAnchor constraintEqualToConstant:134].active = YES;
        [self.modernContentStack addArrangedSubview:scroll];

        CSActionButton *saveIgnoredButton = [CSActionButton buttonWithTitle:@"保存忽略列表" symbol:@"checkmark" handler:^{
            NSArray *lines = [weakSelf.ignoredTextView.string componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
            NSMutableArray *ids = NSMutableArray.array;
            for (NSString *line in lines) {
                NSString *trimmed = CSTrim(line);
                if (trimmed.length > 0) [ids addObject:trimmed];
            }
            [weakSelf.store updatePreferenceKey:@"ignoredBundleIDs" value:ids];
        }];
        [self.modernContentStack addArrangedSubview:saveIgnoredButton];
    }

    NSView *fill = NSView.new;
    [fill.heightAnchor constraintGreaterThanOrEqualToConstant:20].active = YES;
    [self.modernContentStack addArrangedSubview:fill];
    [self refresh];
}

- (void)buildWindow {
    self.currentInterfaceStyle = CSInterfaceStyleFromPreferences(self.store.preferences);
    if ([self.currentInterfaceStyle isEqualToString:CSInterfaceStyleModern]) {
        [self buildModernWindow];
        return;
    }

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 680)
                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"CopyPaste 设置";
    self.window.minSize = NSMakeSize(600, 620);
    self.window.releasedWhenClosed = NO;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorTransient;

    NSView *content = NSView.new;
    self.settingsContentBackgroundView = content;
    content.wantsLayer = YES;
    self.window.contentView = content;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.drawsBackground = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [scrollView.topAnchor constraintEqualToAnchor:content.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
    ]];

    CSFlippedView *document = CSFlippedView.new;
    document.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.documentView = document;

    NSStackView *root = NSStackView.new;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.spacing = 13;
    root.alignment = NSLayoutAttributeLeading;
    root.edgeInsets = NSEdgeInsetsMake(22, 24, 22, 24);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [document.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor],
        [document.heightAnchor constraintGreaterThanOrEqualToAnchor:scrollView.contentView.heightAnchor],
        [root.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:document.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:document.bottomAnchor]
    ]];

    NSStackView *header = NSStackView.new;
    header.orientation = NSUserInterfaceLayoutOrientationVertical;
    header.spacing = 3;
    header.alignment = NSLayoutAttributeLeading;
    [header addArrangedSubview:CSLabel(@"CopyPaste 设置", [NSFont systemFontOfSize:20 weight:NSFontWeightSemibold], NSColor.labelColor)];
    [header addArrangedSubview:CSLabel(@"管理剪贴板记录、面板行为与快捷键", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor)];
    [root addArrangedSubview:header];

    self.interfaceStyleControl = [NSSegmentedControl segmentedControlWithLabels:@[@"经典", @"现代"]
                                                                    trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                          target:self
                                                                          action:@selector(interfaceStyleChanged:)];
    self.interfaceStyleControl.segmentStyle = NSSegmentStyleRounded;
    self.interfaceStyleControl.toolTip = @"切换 CopyPaste 的界面布局；经典保持当前交互，现代使用新的分栏界面";
    [root addArrangedSubview:[self settingsRowWithTitle:@"界面风格" control:self.interfaceStyleControl subtitle:@"经典保留当前交互；现代使用新的分栏界面。"]];

    NSBox *generalDivider = [self settingsDivider];
    [generalDivider.widthAnchor constraintEqualToConstant:592].active = YES;
    [root addArrangedSubview:generalDivider];

    [root addArrangedSubview:CSLabel(@"通用", [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold], NSColor.labelColor)];
    NSStackView *checks = [self settingsCheckboxStackWithKeys:@[@"autoPaste", @"hideAfterSelection", @"showDetailPreview", @"captureImages", @"showDock"]
                                                       titles:@[@"复制后自动粘贴", @"选择后自动隐藏", @"显示内容预览", @"记录图片内容", @"在 Dock 中显示图标"]];
    [root addArrangedSubview:[self settingsRowWithTitle:@"基础选项" control:checks subtitle:nil]];

    NSBox *shortcutDivider = [self settingsDivider];
    [shortcutDivider.widthAnchor constraintEqualToConstant:592].active = YES;
    [root addArrangedSubview:shortcutDivider];

    [root addArrangedSubview:CSLabel(@"快捷键", [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold], NSColor.labelColor)];
    self.hotKeyRecorder = [[CSHotKeyRecorder alloc] initWithFrame:NSZeroRect];
    [self.hotKeyRecorder.widthAnchor constraintEqualToConstant:190].active = YES;
    self.hotKeyRecorder.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    __weak typeof(self) weakSelf = self;
    self.hotKeyRecorder.hotKeyChanged = ^(UInt32 keyCode, UInt32 modifiers, NSString *displayName) {
        [weakSelf.store updatePreferenceKey:@"hotKey" value:CSHotKeyPreference(keyCode, modifiers, displayName)];
    };
    self.hotKeyRecorder.recordingChanged = ^(BOOL recording) {
        if (weakSelf.hotKeyRecordingChanged) {
            weakSelf.hotKeyRecordingChanged(recording);
        }
    };
    [root addArrangedSubview:[self settingsRowWithTitle:@"唤醒快捷键" control:self.hotKeyRecorder subtitle:@"录制用于打开 CopyPaste 面板的全局快捷键。"]];
    self.hotKeyStatusLabel = CSLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    self.hotKeyStatusLabel.maximumNumberOfLines = 2;
    self.hotKeyStatusRow = [self settingsIndentedRowWithControl:self.hotKeyStatusLabel subtitle:nil];
    [root addArrangedSubview:self.hotKeyStatusRow];

    CSActionButton *accessibilityButton = [CSActionButton buttonWithTitle:@"请求无障碍权限" symbol:@"hand.raised" handler:^{
        NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
        AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    }];
    accessibilityButton.toolTip = @"打开系统授权提示；授权后可自动粘贴到目标 App";
    [root addArrangedSubview:[self settingsRowWithTitle:@"无障碍权限" control:accessibilityButton subtitle:@"自动粘贴需要此权限；未授权时仍可手动粘贴。"]];

    NSBox *appearanceDivider = [self settingsDivider];
    [appearanceDivider.widthAnchor constraintEqualToConstant:592].active = YES;
    [root addArrangedSubview:appearanceDivider];

    [root addArrangedSubview:CSLabel(@"外观与布局", [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold], NSColor.labelColor)];
    self.appearanceControl = [NSSegmentedControl segmentedControlWithLabels:@[@"浅色", @"深色", @"系统"]
                                                                trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                      target:self
                                                                      action:@selector(appearanceChanged:)];
    self.appearanceControl.segmentStyle = NSSegmentStyleRounded;
    [root addArrangedSubview:[self settingsRowWithTitle:@"外观" control:self.appearanceControl subtitle:nil]];

    NSStackView *transparencyControl = NSStackView.new;
    transparencyControl.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    transparencyControl.spacing = 10;
    transparencyControl.alignment = NSLayoutAttributeCenterY;
    self.transparencySlider = NSSlider.new;
    self.transparencySlider.minValue = 0;
    self.transparencySlider.maxValue = 45;
    self.transparencySlider.continuous = YES;
    self.transparencySlider.target = self;
    self.transparencySlider.action = @selector(transparencyChanged:);
    self.transparencySlider.toolTip = @"调整 CopyPaste 面板透出背后窗口的程度";
    [self.transparencySlider.widthAnchor constraintEqualToConstant:300].active = YES;
    [transparencyControl addArrangedSubview:self.transparencySlider];
    self.transparencyLabel = CSLabel(@"", [NSFont systemFontOfSize:14 weight:NSFontWeightMedium], NSColor.labelColor);
    [self.transparencyLabel.widthAnchor constraintEqualToConstant:52].active = YES;
    [transparencyControl addArrangedSubview:self.transparencyLabel];
    [root addArrangedSubview:[self settingsRowWithTitle:@"界面透明度" control:transparencyControl subtitle:nil]];

    self.panelSizeModeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"临时拖拽", @"固定保存"]
                                                                   trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                         target:self
                                                                         action:@selector(panelSizeModeChanged:)];
    self.panelSizeModeControl.segmentStyle = NSSegmentStyleRounded;
    self.panelSizeModeControl.toolTip = @"临时拖拽只影响本次；固定保存会长期使用保存的窗口大小";
    [root addArrangedSubview:[self settingsRowWithTitle:@"窗口大小" control:self.panelSizeModeControl subtitle:nil]];

    self.panelPositionModePopup = NSPopUpButton.new;
    [self.panelPositionModePopup addItemsWithTitles:@[@"默认位置", @"固定位置", @"记录上次", @"鼠标附近", @"输入框附近"]];
    self.panelPositionModePopup.target = self;
    self.panelPositionModePopup.action = @selector(panelPositionModeChanged:);
    self.panelPositionModePopup.toolTip = @"选择面板唤醒时出现的位置策略";
    [root addArrangedSubview:[self settingsRowWithTitle:@"窗口位置" control:self.panelPositionModePopup subtitle:nil]];

    NSStackView *panelLayoutActions = NSStackView.new;
    panelLayoutActions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    panelLayoutActions.spacing = 10;
    CSActionButton *showPanelButton = [CSActionButton buttonWithTitle:@"显示窗口" symbol:@"macwindow" handler:^{
        if (weakSelf.panelLayoutPreviewRequested) {
            weakSelf.panelLayoutPreviewRequested();
        }
    }];
    showPanelButton.toolTip = @"打开 CopyPaste 面板，方便拖动调整大小和位置";
    [panelLayoutActions addArrangedSubview:showPanelButton];
    CSActionButton *savePanelButton = [CSActionButton buttonWithTitle:@"保存当前窗口" symbol:@"checkmark" handler:^{
        if (weakSelf.panelLayoutSaveRequested) {
            weakSelf.panelLayoutSaveRequested();
        }
        weakSelf.panelLayoutStatusLabel.stringValue = @"已保存当前窗口大小和位置";
    }];
    savePanelButton.toolTip = @"保存当前面板大小和位置，用于固定大小或固定位置模式";
    [panelLayoutActions addArrangedSubview:savePanelButton];
    [root addArrangedSubview:[self settingsRowWithTitle:@"布局操作" control:panelLayoutActions subtitle:nil]];
    self.panelLayoutStatusLabel = CSLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    self.panelLayoutStatusLabel.maximumNumberOfLines = 2;
    [root addArrangedSubview:[self settingsIndentedRowWithControl:self.panelLayoutStatusLabel subtitle:nil]];

    NSBox *historyDivider = [self settingsDivider];
    [historyDivider.widthAnchor constraintEqualToConstant:592].active = YES;
    [root addArrangedSubview:historyDivider];

    [root addArrangedSubview:CSLabel(@"历史与忽略应用", [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold], NSColor.labelColor)];
    NSStackView *maxRow = NSStackView.new;
    maxRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    maxRow.spacing = 10;
    maxRow.alignment = NSLayoutAttributeCenterY;
    self.maxItemsLabel = CSLabel(@"", [NSFont systemFontOfSize:14 weight:NSFontWeightMedium], NSColor.labelColor);
    [self.maxItemsLabel.widthAnchor constraintEqualToConstant:92].active = YES;
    [maxRow addArrangedSubview:self.maxItemsLabel];
    NSStepper *stepper = NSStepper.new;
    stepper.minValue = 50;
    stepper.maxValue = 2000;
    stepper.increment = 50;
    stepper.integerValue = [self.store.preferences[@"maxItems"] integerValue];
    stepper.target = self;
    stepper.action = @selector(maxItemsChanged:);
    [maxRow addArrangedSubview:stepper];
    [root addArrangedSubview:[self settingsRowWithTitle:@"历史数量" control:maxRow subtitle:nil]];

    [root addArrangedSubview:CSLabel(@"忽略的 Bundle ID", [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold], NSColor.labelColor)];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES;
    self.ignoredTextView = NSTextView.new;
    self.ignoredTextView.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    scroll.documentView = self.ignoredTextView;
    [scroll.widthAnchor constraintEqualToConstant:560].active = YES;
    [scroll.heightAnchor constraintEqualToConstant:78].active = YES;
    [root addArrangedSubview:scroll];

    NSStackView *actions = NSStackView.new;
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 10;
    CSActionButton *saveIgnoredButton = [CSActionButton buttonWithTitle:@"保存忽略列表" symbol:@"checkmark" handler:^{
        NSArray *lines = [weakSelf.ignoredTextView.string componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
        NSMutableArray *ids = NSMutableArray.array;
        for (NSString *line in lines) {
            NSString *trimmed = CSTrim(line);
            if (trimmed.length > 0) [ids addObject:trimmed];
        }
        [weakSelf.store updatePreferenceKey:@"ignoredBundleIDs" value:ids];
    }];
    saveIgnoredButton.toolTip = @"保存不记录剪贴板的 App Bundle ID 列表";
    [actions addArrangedSubview:saveIgnoredButton];
    [root addArrangedSubview:actions];

    [self refresh];
}

- (NSButton *)checkboxWithTitle:(NSString *)title key:(NSString *)key {
    NSButton *button = [NSButton checkboxWithTitle:title target:self action:@selector(checkboxChanged:)];
    button.identifier = key;
    button.state = [self.store.preferences[key] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    button.font = [NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    if ([key isEqualToString:@"autoPaste"]) {
        button.toolTip = @"开启后，选择记录会自动切回目标 App 并发送粘贴命令";
    } else if ([key isEqualToString:@"hideAfterSelection"]) {
        button.toolTip = @"开启后，双击或回车粘贴后会隐藏 CopyPaste 面板";
    } else if ([key isEqualToString:@"showDetailPreview"]) {
        button.toolTip = @"控制右侧是否显示内容预览，关闭后选择候选更轻快";
    } else if ([key isEqualToString:@"captureImages"]) {
        button.toolTip = @"开启后会记录图片内容，历史库体积也会变大";
    } else if ([key isEqualToString:@"showDock"]) {
        button.toolTip = @"控制 CopyPaste 是否出现在 Dock 和应用切换器中";
    }
    return button;
}

- (void)interfaceStyleChanged:(NSSegmentedControl *)sender {
    NSString *style = sender.selectedSegment == 1 ? CSInterfaceStyleModern : CSInterfaceStyleClassic;
    [self.store updatePreferenceKey:@"interfaceStyle" value:style];
}

- (void)checkboxChanged:(NSButton *)sender {
    [self.store updatePreferenceKey:sender.identifier value:@(sender.state == NSControlStateValueOn)];
}

- (void)maxItemsChanged:(NSStepper *)sender {
    [self.store updatePreferenceKey:@"maxItems" value:@(sender.integerValue)];
    [self refresh];
}

- (void)appearanceChanged:(NSSegmentedControl *)sender {
    NSString *mode = CSAppearanceModeSystem;
    if (sender.selectedSegment == 0) {
        mode = CSAppearanceModeLight;
    } else if (sender.selectedSegment == 1) {
        mode = CSAppearanceModeDark;
    }
    [self.store updatePreferenceKey:@"appearanceMode" value:mode];
}

- (void)transparencyChanged:(NSSlider *)sender {
    CGFloat transparency = CSClampCGFloat(sender.doubleValue, 0.0, 45.0);
    CGFloat opacity = 1.0 - transparency / 100.0;
    self.transparencyLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", transparency];
    [self.store updatePreferenceKey:@"panelOpacity" value:@(opacity)];
}

- (void)panelSizeModeChanged:(NSSegmentedControl *)sender {
    NSString *mode = sender.selectedSegment == 1 ? CSPanelSizeModeSaved : CSPanelSizeModeTemporary;
    [self.store updatePreferenceKey:@"panelSizeMode" value:mode];
    if (self.panelLayoutPreviewRequested) {
        self.panelLayoutPreviewRequested();
    }
}

- (NSString *)panelPositionModeForSelectedIndex:(NSInteger)index {
    switch (index) {
        case 1: return CSPanelPositionModeCustom;
        case 2: return CSPanelPositionModeLast;
        case 3: return CSPanelPositionModeMouse;
        case 4: return CSPanelPositionModeInput;
        default: return CSPanelPositionModeDefault;
    }
}

- (NSInteger)selectedIndexForPanelPositionMode:(NSString *)mode {
    if ([mode isEqualToString:CSPanelPositionModeCustom]) return 1;
    if ([mode isEqualToString:CSPanelPositionModeLast]) return 2;
    if ([mode isEqualToString:CSPanelPositionModeMouse]) return 3;
    if ([mode isEqualToString:CSPanelPositionModeInput]) return 4;
    return 0;
}

- (void)panelPositionModeChanged:(NSPopUpButton *)sender {
    NSString *mode = [self panelPositionModeForSelectedIndex:sender.indexOfSelectedItem];
    [self.store updatePreferenceKey:@"panelPositionMode" value:mode];
    if (self.panelLayoutPreviewRequested) {
        self.panelLayoutPreviewRequested();
    }
}

- (void)refresh {
    NSString *style = CSInterfaceStyleFromPreferences(self.store.preferences);
    if (self.currentInterfaceStyle.length > 0 && ![style isEqualToString:self.currentInterfaceStyle]) {
        BOOL wasVisible = self.window.visible;
        [self.window orderOut:nil];
        self.window = nil;
        [self buildWindow];
        if (wasVisible) {
            [self.window center];
            [self.window makeKeyAndOrderFront:nil];
            [self.window orderFrontRegardless];
        }
        return;
    }
    [self applySettingsSurfaceColors];
    self.interfaceStyleControl.selectedSegment = [style isEqualToString:CSInterfaceStyleModern] ? 1 : 0;
    [self refreshModernNavigationSelection];
    self.maxItemsLabel.stringValue = [NSString stringWithFormat:@"%@ 条", self.store.preferences[@"maxItems"]];
    NSDictionary *hotKey = CSHotKeyFromPreferences(self.store.preferences);
    [self.hotKeyRecorder setHotKeyDisplayValue:hotKey[@"display"]];
    BOOL hasHotKeyNotice = [self.store.lastNotice containsString:@"快捷键"];
    self.hotKeyStatusLabel.hidden = !hasHotKeyNotice;
    self.hotKeyStatusRow.hidden = !hasHotKeyNotice;
    self.hotKeyStatusLabel.stringValue = hasHotKeyNotice ? self.store.lastNotice : @"";
    NSString *mode = CSAppearanceModeFromPreferences(self.store.preferences);
    if ([mode isEqualToString:CSAppearanceModeLight]) {
        self.appearanceControl.selectedSegment = 0;
    } else if ([mode isEqualToString:CSAppearanceModeDark]) {
        self.appearanceControl.selectedSegment = 1;
    } else {
        self.appearanceControl.selectedSegment = 2;
    }
    CGFloat transparency = CSTransparencyPercentFromPreferences(self.store.preferences);
    self.transparencyLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", transparency];
    self.transparencySlider.doubleValue = transparency;
    self.panelSizeModeControl.selectedSegment = [CSPanelSizeModeFromPreferences(self.store.preferences) isEqualToString:CSPanelSizeModeSaved] ? 1 : 0;
    NSString *positionMode = CSPanelPositionModeFromPreferences(self.store.preferences);
    [self.panelPositionModePopup selectItemAtIndex:[self selectedIndexForPanelPositionMode:positionMode]];
    if ([CSPanelSizeModeFromPreferences(self.store.preferences) isEqualToString:CSPanelSizeModeSaved] ||
        [positionMode isEqualToString:CSPanelPositionModeCustom]) {
        self.panelLayoutStatusLabel.stringValue = @"显示窗口并拖动调整，点击保存当前窗口后长期保持。";
    } else if ([positionMode isEqualToString:CSPanelPositionModeInput]) {
        self.panelLayoutStatusLabel.stringValue = @"输入框附近依赖目标 App 的辅助功能信息，失败会退回默认位置。";
    } else {
        self.panelLayoutStatusLabel.stringValue = @"临时拖拽不会持久保存；记录上次会在关闭面板时保存位置。";
    }
    self.ignoredTextView.string = [self.store.preferences[@"ignoredBundleIDs"] componentsJoinedByString:@"\n"] ?: @"";
}

- (void)show {
    if (!self.window) {
        [self buildWindow];
    }
    [self refresh];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
}
@end

@interface CSAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) CSStore *store;
@property (nonatomic, strong) CSClipboardMonitor *monitor;
@property (nonatomic, strong) CSPanelController *panelController;
@property (nonatomic, strong) CSSettingsController *settingsController;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSRunningApplication *lastExternalApplication;
- (void)rememberCurrentTargetApplication;
- (void)applyAppearancePreference;
- (void)registerHotKey;
- (void)unregisterHotKey;
- (void)updateStatusItemTooltip;
@end

static OSStatus CSHotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    EventHotKeyID hotKeyID;
    OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID), NULL, &hotKeyID);
    if (status == noErr && hotKeyID.signature == CSHotKeySignature && userData != NULL) {
        CSAppDelegate *delegate = (__bridge CSAppDelegate *)userData;
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate rememberCurrentTargetApplication];
            [delegate.panelController toggle];
        });
    }
    return noErr;
}

@implementation CSAppDelegate {
    EventHotKeyRef _hotKeyRef;
    EventHandlerRef _hotKeyHandlerRef;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.store = CSStore.new;
    [self applyAppearancePreference];
    self.panelController = [[CSPanelController alloc] initWithStore:self.store];
    self.settingsController = [[CSSettingsController alloc] initWithStore:self.store];
    self.monitor = [[CSClipboardMonitor alloc] initWithStore:self.store];

    __weak typeof(self) weakSelf = self;
    self.store.didChange = ^{
        [weakSelf applyAppearancePreference];
        [weakSelf configureActivationPolicy];
        [weakSelf.panelController reloadAll];
        [weakSelf.settingsController refresh];
    };
    self.store.didDeleteItems = ^(NSSet<NSString *> *deletedItemIDs) {
        [weakSelf.panelController handleDeletedItemsWithIDs:deletedItemIDs];
        [weakSelf.settingsController refresh];
    };
    self.store.didChangeAppearance = ^(NSString *key) {
        [weakSelf applyAppearancePreference];
        if ([key isEqualToString:@"appearanceMode"]) {
            [weakSelf.panelController reloadAll];
        } else {
            [weakSelf.panelController refreshInterfaceAppearance];
        }
        [weakSelf.settingsController refresh];
    };
    self.store.didChangeHotKey = ^{
        [weakSelf registerHotKey];
        [weakSelf updateStatusItemTooltip];
        [weakSelf.settingsController refresh];
    };
    self.settingsController.hotKeyRecordingChanged = ^(BOOL recording) {
        if (recording) {
            [weakSelf unregisterHotKey];
        } else {
            [weakSelf registerHotKey];
        }
    };
    self.settingsController.panelLayoutPreviewRequested = ^{
        [weakSelf.panelController previewPanelLayout];
    };
    self.settingsController.panelLayoutSaveRequested = ^{
        [weakSelf.panelController saveCurrentPanelLayout];
        [weakSelf.settingsController refresh];
    };

    [self configureActivationPolicy];
    [self configureMainMenu];
    [self configureStatusItem];
    [self registerHotKey];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                       selector:@selector(workspaceDidActivateApplication:)
                                                           name:NSWorkspaceDidActivateApplicationNotification
                                                         object:nil];
    [self rememberCurrentTargetApplication];
    [self.monitor start];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.monitor stop];
    [self.store flushPendingSave];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    if (_hotKeyRef) UnregisterEventHotKey(_hotKeyRef);
    if (_hotKeyHandlerRef) RemoveEventHandler(_hotKeyHandlerRef);
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self rememberCurrentTargetApplication];
    [self.panelController show];
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (void)workspaceDidActivateApplication:(NSNotification *)notification {
    NSRunningApplication *application = notification.userInfo[NSWorkspaceApplicationKey];
    [self rememberTargetApplication:application];
}

- (void)rememberCurrentTargetApplication {
    [self rememberTargetApplication:NSWorkspace.sharedWorkspace.frontmostApplication];
}

- (void)rememberTargetApplication:(NSRunningApplication *)application {
    if (!application || application.terminated) {
        return;
    }
    if (application.processIdentifier == NSRunningApplication.currentApplication.processIdentifier) {
        return;
    }
    self.lastExternalApplication = application;
    self.panelController.lastTargetApplication = application;
}

- (void)applicationDidResignActive:(NSNotification *)notification {
    [self.panelController closeIfNotPinned];
}

- (void)configureActivationPolicy {
    [NSApp setActivationPolicy:[self.store.preferences[@"showDock"] boolValue] ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
}

- (void)applyAppearancePreference {
    NSApp.appearance = CSAppearanceFromMode(CSAppearanceModeFromPreferences(self.store.preferences));
}

- (void)configureMainMenu {
    NSMenu *mainMenu = NSMenu.new;
    NSMenuItem *appMenuItem = NSMenuItem.new;
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"CopyPaste"];

    NSMenuItem *settingsItem = [[NSMenuItem alloc] initWithTitle:@"设置..." action:@selector(openSettings:) keyEquivalent:@","];
    settingsItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    settingsItem.target = self;
    [appMenu addItem:settingsItem];

    [appMenu addItem:NSMenuItem.separatorItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出 CopyPaste" action:@selector(quit:) keyEquivalent:@"q"];
    quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    quitItem.target = self;
    [appMenu addItem:quitItem];

    appMenuItem.submenu = appMenu;
    [mainMenu addItem:appMenuItem];
    NSApp.mainMenu = mainMenu;
}

- (void)configureStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSStatusBarButton *button = self.statusItem.button;
    button.image = [NSImage imageWithSystemSymbolName:@"doc.on.clipboard" accessibilityDescription:@"CopyPaste"];
    button.imagePosition = NSImageOnly;
    button.target = self;
    button.action = @selector(statusItemClicked:);
    [button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    [self updateStatusItemTooltip];
}

- (void)updateStatusItemTooltip {
    NSString *display = CSHotKeyFromPreferences(self.store.preferences)[@"display"] ?: @"";
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"CopyPaste - %@", display];
}

- (void)statusItemClicked:(NSStatusBarButton *)sender {
    if (NSApp.currentEvent.type == NSEventTypeRightMouseUp) {
        self.statusItem.menu = [self makeStatusMenu];
        [sender performClick:nil];
        self.statusItem.menu = nil;
    } else {
        [self rememberCurrentTargetApplication];
        [self.panelController toggle];
    }
}

- (NSMenu *)makeStatusMenu {
    NSMenu *menu = NSMenu.new;
    [menu addItem:[self menuItem:@"打开 CopyPaste" action:@selector(openPanel:)]];
    NSMenuItem *settingsItem = [self menuItem:@"设置..." action:@selector(openSettings:)];
    settingsItem.keyEquivalent = @",";
    settingsItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItem:settingsItem];
    [menu addItem:[self menuItem:@"请求无障碍权限" action:@selector(requestAccessibility:)]];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:[self menuItem:@"清除未置顶历史" action:@selector(clearHistory:)]];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItem:[self menuItem:@"退出" action:@selector(quit:)]];
    return menu;
}

- (NSMenuItem *)menuItem:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    return item;
}

- (void)openPanel:(id)sender {
    [self rememberCurrentTargetApplication];
    if (self.lastExternalApplication) {
        self.panelController.lastTargetApplication = self.lastExternalApplication;
    }
    [self.panelController show];
}

- (void)openSettings:(id)sender {
    [self.settingsController show];
}

- (void)requestAccessibility:(id)sender {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (void)clearHistory:(id)sender {
    [self.store clearHistoryKeepingPinned:YES];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

- (void)unregisterHotKey {
    if (_hotKeyRef) {
        UnregisterEventHotKey(_hotKeyRef);
        _hotKeyRef = NULL;
    }
}

- (void)registerHotKey {
    if (!_hotKeyHandlerRef) {
        EventTypeSpec eventType = { kEventClassKeyboard, kEventHotKeyPressed };
        OSStatus handlerStatus = InstallEventHandler(GetApplicationEventTarget(), CSHotKeyHandler, 1, &eventType, (__bridge void *)self, &_hotKeyHandlerRef);
        if (handlerStatus != noErr) {
            self.store.lastNotice = @"快捷键监听失败，可从菜单栏打开。";
            return;
        }
    }

    [self unregisterHotKey];
    NSDictionary *hotKey = CSHotKeyFromPreferences(self.store.preferences);
    UInt32 keyCode = [hotKey[@"keyCode"] unsignedIntValue];
    UInt32 modifiers = [hotKey[@"modifiers"] unsignedIntValue];
    EventHotKeyID hotKeyID = { CSHotKeySignature, 1 };
    OSStatus hotKeyStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &_hotKeyRef);
    if (hotKeyStatus != noErr) {
        self.store.lastNotice = @"快捷键注册失败，可能已被其他 App 占用，可从菜单栏打开。";
    } else if ([self.store.lastNotice containsString:@"快捷键"]) {
        self.store.lastNotice = @"";
    }
}
@end

@protocol CSSettingsOpening <NSObject>
- (void)openSettings:(id)sender;
@end

@interface CSApplication : NSApplication
@end

@implementation CSApplication
- (void)sendEvent:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    BOOL commandOnly = (flags & NSEventModifierFlagCommand) &&
        !(flags & (NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl));
    if (event.type == NSEventTypeKeyDown && event.keyCode == kVK_ANSI_Comma && commandOnly) {
        if ([self.keyWindow.firstResponder isKindOfClass:CSHotKeyRecorder.class]) {
            [super sendEvent:event];
            return;
        }
        id delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(openSettings:)]) {
            [(id<CSSettingsOpening>)delegate openSettings:self];
            return;
        }
    }
    [super sendEvent:event];
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = [CSApplication sharedApplication];
        CSAppDelegate *delegate = CSAppDelegate.new;
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
