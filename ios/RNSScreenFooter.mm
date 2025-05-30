#import "RNSScreenFooter.h"
#import "RNSScreen.h"
#import "UIView+Pinning.h"

#ifdef RCT_NEW_ARCH_ENABLED
#import <React/RCTConversions.h>
#import <react/renderer/components/rnscreens/ComponentDescriptors.h>
#import <react/renderer/components/rnscreens/EventEmitters.h>
#import <react/renderer/components/rnscreens/Props.h>
#import <react/renderer/components/rnscreens/RCTComponentViewHelpers.h>

#endif // RCT_NEW_ARCH_ENABLED

@implementation RNSScreenFooter {
  NSLayoutConstraint *_heightConstraint;
  NSLayoutConstraint *_bottomConstraint;
  RNSScreenView *_screenView;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didMoveToSuperview
{
  [super didMoveToSuperview];
  if ([self.superview isKindOfClass:RNSScreenView.class]) {
    _screenView = (RNSScreenView *)self.superview;
    [self pinToView:_screenView.controller.view
          fromEdges:UIRectEdgeLeft | UIRectEdgeRight | UIRectEdgeBottom
         withHeight:@0
        constraints:^(
            NSLayoutConstraint *top,
            NSLayoutConstraint *bottom,
            NSLayoutConstraint *left,
            NSLayoutConstraint *right,
            NSLayoutConstraint *height) {
          self->_heightConstraint = height;
          self->_bottomConstraint = bottom;
        }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
  }
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  if (self.onLayout != nil) {
    self.onLayout(self.frame);
  }
}

- (void)keyboardWillShow:(NSNotification *)notification
{
  NSDictionary *userInfo = notification.userInfo;
  NSValue *keyboardFrameValue = userInfo[UIKeyboardFrameEndUserInfoKey];

  if (keyboardFrameValue && [keyboardFrameValue isKindOfClass:[NSValue class]]) {
    CGRect keyboardFrame = [keyboardFrameValue CGRectValue];
    _bottomConstraint.constant = -keyboardFrame.size.height;

    [UIView animateWithDuration:0.3
                     animations:^{
                       [self->_screenView.controller.view layoutIfNeeded];
                     }];
  }
}

- (void)keyboardWillHide:(NSNotification *)notification
{
  _bottomConstraint.constant = 0;

  [UIView animateWithDuration:0.3
                   animations:^{
                     [self->_screenView.controller.view layoutIfNeeded];
                   }];
}

#ifdef RCT_NEW_ARCH_ENABLED

#pragma Fabric specific

// Needed because of this: https://github.com/facebook/react-native/pull/37274
+ (void)load
{
  [super load];
}

+ (react::ComponentDescriptorProvider)componentDescriptorProvider
{
  return react::concreteComponentDescriptorProvider<react::RNSScreenFooterComponentDescriptor>();
}

Class<RCTComponentViewProtocol> RNSScreenFooterCls(void)
{
  return RNSScreenFooter.class;
}

RNS_IGNORE_SUPER_CALL_BEGIN
- (void)updateLayoutMetrics:(react::LayoutMetrics const &)layoutMetrics
           oldLayoutMetrics:(react::LayoutMetrics const &)oldLayoutMetrics
{
  CGRect frame = RCTCGRectFromRect(layoutMetrics.frame);
  _heightConstraint.constant = frame.size.height;
}
RNS_IGNORE_SUPER_CALL_END

#else

#pragma Paper specific

- (void)reactSetFrame:(CGRect)frame
{
  [super reactSetFrame:frame];
  _heightConstraint.constant = frame.size.height;
}

#endif // RCT_NEW_ARCH_ENABLED

@end

@implementation RNSScreenFooterManager

RCT_EXPORT_MODULE()

- (UIView *)view
{
  return [RNSScreenFooter new];
}

@end
