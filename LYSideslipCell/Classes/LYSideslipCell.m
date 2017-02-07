//
//  LYSideslipCell.m
//  LYSideslipCellDemo
//
//  Created by Louis on 16/7/5.
//  Copyright © 2016年 Louis. All rights reserved.
//

#import "LYSideslipCell.h"
#import <objc/runtime.h>

#define LYSideslipCellButtonMargin 15
#define LYSideslipCellLeftLimitScrollMargin 15
#define LYSideslipCellRightLimitScrollMargin 30

@interface LYSideslipCellAction ()
@property (nonatomic, copy) void (^handler)(LYSideslipCellAction *action, NSIndexPath *indexPath);
@property (nonatomic, assign) LYSideslipCellActionStyle style;
@end
@implementation LYSideslipCellAction
+ (instancetype)rowActionWithStyle:(LYSideslipCellActionStyle)style title:(NSString *)title handler:(void (^)(LYSideslipCellAction *action, NSIndexPath *indexPath))handler {
    LYSideslipCellAction *action = [LYSideslipCellAction new];
    action.title = title;
    action.handler = handler;
    action.style = style;
    return action;
}
@end

@interface LYSideslipCell () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;
//@property (nonatomic, assign) BOOL sideslip;
@end

static BOOL _sideslip;
@implementation LYSideslipCell {
    UITableView *_tableView;
    UIView *_btnContainView;
    NSIndexPath *_indexPath;
    NSArray <LYSideslipCellAction *>* _actions;
    BOOL _discardTouchDown;
}

#pragma mark - Life Cycle
+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        SEL originalSelector = @selector(addSubview:);
        SEL swizzledSelector = @selector(ly_addSubview:);
        
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        
        BOOL didAddMethod =
        class_addMethod(class,
                        originalSelector,
                        method_getImplementation(swizzledMethod),
                        method_getTypeEncoding(swizzledMethod));
        
        if (didAddMethod) {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

- (void)ly_addSubview:(UIView *)view {
    if ([view isKindOfClass:NSClassFromString(@"UITableViewCellContentView")] || [view isKindOfClass:NSClassFromString(@"_UITableViewCellSeparatorView")]) {
        [self ly_addSubview:view];
    } else {
        [self.contentView addSubview:view];
    }
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        [self setupSideslipCell];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        [self setupSideslipCell];
    }
    return self;
}

- (void)setupSideslipCell {
    self.contentView.backgroundColor = [UIColor whiteColor];
    
    _panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(contentViewPan:)];
    _panGesture.delegate = self;
    [self.contentView addGestureRecognizer:_panGesture];
}

#pragma mark - UIGestureRecognizerDelegate
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == _panGesture) {
        if (!self.tableView.scrollEnabled) return YES;
        UIPanGestureRecognizer *gesture = (UIPanGestureRecognizer *)gestureRecognizer;
        CGPoint translation = [gesture translationInView:gesture.view];
        BOOL shouldBegin = fabs(translation.y) <= fabs(translation.x);
        if (!shouldBegin) return NO;
        if ([_delegate respondsToSelector:@selector(sideslipCell:canSideslipRowAtIndexPath:)])
            shouldBegin = [_delegate sideslipCell:self canSideslipRowAtIndexPath:[self.tableView indexPathForCell:self]] || _sideslip;
        if (shouldBegin) {
            if ([_delegate respondsToSelector:@selector(sideslipCell:editActionsForRowAtIndexPath:)]) {
                NSArray <LYSideslipCellAction*> *actions = [_delegate sideslipCell:self editActionsForRowAtIndexPath:self.indexPath];
                if (!actions || actions.count == 0) return NO;
                [self setActions:actions];
            } else {
                return NO;
            }
        }
        return shouldBegin;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return ![touch.view isKindOfClass:UIControl.class];
}

#pragma mark - Response Events
- (void)contentViewPan:(UIPanGestureRecognizer *)pan {
    CGPoint point = [pan translationInView:pan.view];
    UIGestureRecognizerState state = pan.state;
    [pan setTranslation:CGPointZero inView:pan.view];
    
    if (state == UIGestureRecognizerStateBegan) {
        if (_sideslip) {
            _discardTouchDown = YES;
            self.userInteractionEnabled = NO;
            [self hiddenAllSideslipButton];
        }
    } else if (state == UIGestureRecognizerStateChanged) {
        
        if (_discardTouchDown) return;
        if (CGRectGetWidth(_btnContainView.frame) == 0) return;
        
        CGRect frame = self.contentView.frame;
        frame.origin.x += point.x;
        if (frame.origin.x > LYSideslipCellLeftLimitScrollMargin) {
            frame.origin.x = LYSideslipCellLeftLimitScrollMargin;
        } else if (frame.origin.x < -LYSideslipCellRightLimitScrollMargin - CGRectGetWidth(_btnContainView.frame)) {
            frame.origin.x = -LYSideslipCellRightLimitScrollMargin - CGRectGetWidth(_btnContainView.frame);
        }
        
        self.contentView.frame = frame;
        
    } else if (state == UIGestureRecognizerStateEnded) {
        
        if (_discardTouchDown) {
            _discardTouchDown = NO;
            self.userInteractionEnabled = YES;
            return;
        }
        
        if (self.contentView.frame.origin.x == 0) return;
        
        if (self.contentView.frame.origin.x > 5) {
            [self hiddenWithBounceAnimation];
        } else {
            if (fabs(self.contentView.frame.origin.x) >= 40 && point.x <= 0) {
                [self showSideslipButton];
            } else {
                [self hiddenSideslipButton];
            }
        }
    } else {
        _discardTouchDown = NO;
        self.userInteractionEnabled = YES;
        [self hiddenAllSideslipButton];
    }
}

- (void)actionBtnDidClicked:(UIButton *)btn {
    if ([self.delegate respondsToSelector:@selector(sideslipCell:rowAtIndexPath:didSelectedAtIndex:)]) {
        [self.delegate sideslipCell:self rowAtIndexPath:self.indexPath didSelectedAtIndex:btn.tag];
    }
    if (btn.tag < _actions.count) {
        LYSideslipCellAction *action = _actions[btn.tag];
        if (action.handler) action.handler(action, self.indexPath);
    }
}

#pragma mark - Public Methods
- (void)hideSideslip {
    for (LYSideslipCell *cell in self.tableView.visibleCells)
        if ([cell isKindOfClass:LYSideslipCell.class])
            [cell hiddenSideslipButton];
}

#pragma mark - Private Methods
- (void)closeAllOperation {
    _sideslip = YES;
    self.tableView.scrollEnabled = NO;
    self.tableView.allowsSelection = NO;
    for (LYSideslipCell *cell in self.tableView.visibleCells)
        if ([cell isKindOfClass:LYSideslipCell.class]) {
            cell.userInteractionEnabled = NO;
        }
}

- (void)openAllOperation {
    _sideslip = NO;
    self.tableView.scrollEnabled = YES;
    self.tableView.allowsSelection = YES;
    for (LYSideslipCell *cell in self.tableView.visibleCells)
        if ([cell isKindOfClass:LYSideslipCell.class]) {
            cell.userInteractionEnabled = YES;
        }
}

- (void)hiddenWithBounceAnimation {
    if (self.contentView.frame.origin.x == 0) return;
    
    [self closeAllOperation];

    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        CGRect frame = self.contentView.frame;
        frame.origin.x = -10;
        self.contentView.frame = frame;
    } completion:^(BOOL finished) {
        [self hiddenSideslipButton];
    }];
}

- (void)hiddenAllSideslipButton {
    if (self.contentView.frame.origin.x == 0) {
        for (LYSideslipCell *cell in self.tableView.visibleCells)
            if ([cell isKindOfClass:LYSideslipCell.class])
                [cell hiddenSideslipButton];
    } else {
        [self hiddenSideslipButton];
    }
}

- (void)hiddenSideslipButton {
    if (self.contentView.frame.origin.x == 0) return;
    
    [self closeAllOperation];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        CGRect frame = self.contentView.frame;
        frame.origin.x = 0;
        self.contentView.frame = frame;
    } completion:^(BOOL finished) {
        [_btnContainView removeFromSuperview];
        _btnContainView = nil;
        [self openAllOperation];
    }];
}

- (void)showSideslipButton {
    [self closeAllOperation];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        CGRect frame = self.contentView.frame;
        frame.origin.x = -CGRectGetWidth(_btnContainView.frame);
        self.contentView.frame = frame;
    } completion:^(BOOL finished) {
        for (LYSideslipCell *cell in self.tableView.visibleCells)
            if ([cell isKindOfClass:LYSideslipCell.class]) {
                cell.userInteractionEnabled = YES;
            }
    }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat totalWidth = 0;
    for (UIButton *btn in _btnContainView.subviews) {
        btn.frame = CGRectMake(totalWidth, 0, btn.frame.size.width, self.frame.size.height);
        totalWidth += btn.frame.size.width;
    }
    _btnContainView.frame = CGRectMake(self.frame.size.width - totalWidth, 0, totalWidth, self.frame.size.height);
}

#pragma mark - Public Methods
- (void)setActions:(NSArray <LYSideslipCellAction *>*)actions {
    _actions = actions;

    if (_btnContainView) {
        [_btnContainView removeFromSuperview];
        _btnContainView = nil;
    } else {
        _btnContainView = [UIView new];
        [self insertSubview:_btnContainView belowSubview:self.contentView];
    }
    
    for (int i = 0; i < actions.count; i++) {
        LYSideslipCellAction *action = actions[i];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
        [btn setTitle:action.title forState:UIControlStateNormal];
    
        if (action.backgroundColor) {
            btn.backgroundColor = action.backgroundColor;
        } else {
            btn.backgroundColor = action.style == LYSideslipCellActionStyleNormal? [UIColor colorWithRed:200/255.0 green:199/255.0 blue:205/255.0 alpha:1] : [UIColor redColor];
        }
        
        if (action.image) {
            [btn setImage:action.image forState:UIControlStateNormal];
        }
        
        CGFloat width = [action.title boundingRectWithSize:CGSizeMake(MAXFLOAT, MAXFLOAT) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName : btn.titleLabel.font} context:nil].size.width;
        width += (action.image ? action.image.size.width : 0);
        btn.frame = CGRectMake(0, 0, width + LYSideslipCellButtonMargin*2, self.frame.size.height);
        
        btn.contentEdgeInsets = UIEdgeInsetsMake(0, LYSideslipCellButtonMargin, 0, LYSideslipCellButtonMargin);
        btn.tag = i;
        [btn addTarget:self action:@selector(actionBtnDidClicked:) forControlEvents:UIControlEventTouchUpInside];
        [_btnContainView addSubview:btn];
    }
}


#pragma mark - Getter/Setter
- (UITableView *)tableView {
    if (!_tableView) {
        id view = self.superview;
        while (view && [view isKindOfClass:[UITableView class]] == NO) {
            view = [view superview];
        }
        _tableView = (UITableView *)view;
    }
    return _tableView;
}

- (NSIndexPath *)indexPath {
    if (!_indexPath) {
        _indexPath = [self.tableView indexPathForCell:self];
    }
    return _indexPath;
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    [super setHighlighted:highlighted animated:animated];
    [self modifyBgColor:highlighted];
}


- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    if (_sideslip) return;
    [super setSelected:selected animated:animated];
    [self modifyBgColor:selected];
}

- (void)modifyBgColor:(BOOL)selected {
    if (selected) {
        _btnContainView.hidden = YES;
    } else {
        _btnContainView.hidden = NO;
    }
}



- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    if (_sideslip) [self hiddenAllSideslipButton];
}

//- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    [super touchesBegan:touches withEvent:event];
//    NSLog(@"%s", __func__);
//    if (_sideslip) {
//        _discardTouchDown = YES;
//        self.userInteractionEnabled = NO;
//        [self hiddenAllSideslipButton];
//    }
//}
//
//- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    [super touchesMoved:touches withEvent:event];
//
//    
//    
//    UITouch *touch = touches.anyObject;
//    CGPoint previouPoint = [touch previousLocationInView:touch.view];
//    CGPoint point = [touch locationInView:touch.view];
//    CGFloat x = point.x - previouPoint.x;
//    CGFloat y = point.y - previouPoint.y;
//    if (x == 0) return;
//    
//    // 防止选中高亮后, 滚不动tableView
////    if (y != 0 && !_sideslip) {
////        return [super touchesCancelled:touches withEvent:event];
////    }
//
//    if (_discardTouchDown) return;
//    if (CGRectGetWidth(_btnContainView.frame) == 0) return;
//    
//    
//    CGRect frame = self.contentView.frame;
//    frame.origin.x += (point.x - previouPoint.x);
//    if (frame.origin.x > LYSideslipCellLeftLimitScrollMargin) {
//        frame.origin.x = LYSideslipCellLeftLimitScrollMargin;
//    } else if (frame.origin.x < -LYSideslipCellRightLimitScrollMargin - CGRectGetWidth(_btnContainView.frame)) {
//        frame.origin.x = -LYSideslipCellRightLimitScrollMargin - CGRectGetWidth(_btnContainView.frame);
//    }
//    
//    self.contentView.frame = frame;
//    if (!_sideslip) {
//        self.tableView.scrollEnabled = NO;
//        _sideslip = YES;
//        [self setHighlighted:NO animated:NO];
//    }
//}
//
//- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    NSLog(@"%s", __func__);
//    [super touchesEnded:touches withEvent:event];
//    self.tableView.scrollEnabled = YES;
//    if (_discardTouchDown) {
//        _discardTouchDown = NO;
//        self.userInteractionEnabled = YES;
//        return;
//    }
//
//    if (self.contentView.frame.origin.x == 0) return;
//
//    if (self.contentView.frame.origin.x > 5) {
//        [self hiddenWithBounceAnimation];
//    } else {
//        UITouch *touch = touches.anyObject;
//        CGPoint previouPoint = [touch previousLocationInView:touch.view];
//        CGPoint point = [touch locationInView:touch.view];
//        CGFloat x = point.x - previouPoint.x;
//        if (fabs(self.contentView.frame.origin.x) >= 40 && x <= 0) {
//            [self showSideslipButton];
//        } else {
//            [self hiddenSideslipButton];
//        }
//    }
//}
//
//- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
//    NSLog(@"%s", __func__);
//    [super touchesCancelled:touches withEvent:event];
//    self.tableView.scrollEnabled = YES;
//    _discardTouchDown = NO;
//    self.userInteractionEnabled = YES;
//    [self hiddenAllSideslipButton];
//}
//
//- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
//    UIView *view = [super hitTest:point withEvent:event];
//    NSLog(@"%@ %@", [NSString stringWithFormat:@"%p", self], NSStringFromClass(view.class));
//    return view;
//}
//
//- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
//    BOOL bo = [super pointInside:point withEvent:event];
//    return bo;
//}
@end
