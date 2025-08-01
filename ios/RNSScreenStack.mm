#ifdef RCT_NEW_ARCH_ENABLED
#import <React/RCTFabricComponentsPlugins.h>
#import <React/RCTFabricSurface.h>
#import <React/RCTMountingTransactionObserving.h>
#import <React/RCTSurfaceTouchHandler.h>
#import <React/RCTSurfaceView.h>
#import <React/UIView+React.h>
#import <react/renderer/components/rnscreens/ComponentDescriptors.h>
#import <react/renderer/components/rnscreens/EventEmitters.h>
#import <react/renderer/components/rnscreens/Props.h>
#import <react/renderer/components/rnscreens/RCTComponentViewHelpers.h>
#import "RCTSurfaceTouchHandler+RNSUtility.h"
#else
#import <React/RCTBridge.h>
#import <React/RCTRootContentView.h>
#import <React/RCTShadowView.h>
#import <React/RCTTouchHandler.h>
#import <React/RCTUIManager.h>
#import <React/RCTUIManagerUtils.h>
#import "RCTTouchHandler+RNSUtility.h"
#endif // RCT_NEW_ARCH_ENABLED

#import "RNSDefines.h"
#import "RNSPercentDrivenInteractiveTransition.h"
#import "RNSScreen.h"
#import "RNSScreenStack.h"
#import "RNSScreenStackAnimator.h"
#import "RNSScreenStackHeaderConfig.h"
#import "RNSScreenWindowTraits.h"
#import "RNSScrollViewFinder.h"
#import "RNSTabsScreenViewController.h"
#import "UIScrollView+RNScreens.h"
#import "UIView+RNSUtility.h"
#import "utils/UINavigationBar+RNSUtility.h"
#import "integrations/RNSDismissibleModalProtocol.h"

#ifdef RCT_NEW_ARCH_ENABLED
namespace react = facebook::react;
#endif // RCT_NEW_ARCH_ENABLED

@interface RNSScreenStackView () <
    UINavigationControllerDelegate,
    UIAdaptivePresentationControllerDelegate,
    UIGestureRecognizerDelegate,
    UIViewControllerTransitioningDelegate
#ifdef RCT_NEW_ARCH_ENABLED
    ,
    RCTMountingTransactionObserving
#endif
    >

@property (nonatomic) NSMutableArray<UIViewController *> *presentedModals;
@property (nonatomic) BOOL updatingModals;
@property (nonatomic) BOOL scheduleModalsUpdate;

@end

@implementation RNSNavigationController

#if !TARGET_OS_TV
- (UIViewController *)childViewControllerForStatusBarStyle
{
  return [self topViewController];
}

- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation
{
  return [self topViewController].preferredStatusBarUpdateAnimation;
}

- (UIViewController *)childViewControllerForStatusBarHidden
{
  return [self topViewController];
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  if ([self.topViewController isKindOfClass:[RNSScreen class]]) {
    RNSScreen *screenController = (RNSScreen *)self.topViewController;
    BOOL isNotDismissingModal = screenController.presentedViewController == nil ||
        (screenController.presentedViewController != nil &&
         ![screenController.presentedViewController isBeingDismissed]);
    BOOL isPresentingSearchController =
        [screenController.presentedViewController isKindOfClass:UISearchController.class];

    // Calculate header height during simple transition from one screen to another.
    // If RNSScreen includes a navigation controller of type RNSNavigationController, it should not calculate
    // header height, as it could have nested stack.
    if (![screenController hasNestedStack] && (isPresentingSearchController || isNotDismissingModal)) {
      [screenController calculateAndNotifyHeaderHeightChangeIsModal:NO];
    }

    [self maybeUpdateHeaderLayoutInfoInShadowTree:screenController];
  }
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
  return [self topViewController].supportedInterfaceOrientations;
}

- (UIViewController *)childViewControllerForHomeIndicatorAutoHidden
{
  return [self topViewController];
}

- (void)maybeUpdateHeaderLayoutInfoInShadowTree:(RNSScreen *)screenController
{
  // This might happen e.g. if there is only native title present in navigation bar.
  if (self.navigationBar.subviews.count < 2) {
    return;
  }

  auto headerConfig = screenController.screenView.findHeaderConfig;
  if (headerConfig == nil || !headerConfig.shouldHeaderBeVisible) {
    return;
  }

#ifdef RCT_NEW_ARCH_ENABLED
  [headerConfig updateHeaderStateInShadowTreeInContextOfNavigationBar:self.navigationBar];
#else
  NSDirectionalEdgeInsets navBarMargins = [self.navigationBar directionalLayoutMargins];
  NSDirectionalEdgeInsets navBarContentMargins =
      [self.navigationBar.rnscreens_findContentView directionalLayoutMargins];

  BOOL isDisplayingBackButton = [headerConfig shouldBackButtonBeVisibleInNavigationBar:self.navigationBar];

  // 44.0 is just "closed eyes default". It is so on device I've tested with, nothing more.
  UIView *barButtonView = isDisplayingBackButton ? self.navigationBar.rnscreens_findBackButtonWrapperView : nil;
  CGFloat platformBackButtonWidth = barButtonView != nil ? barButtonView.frame.size.width : 44.0f;

  [headerConfig updateHeaderConfigState:NSDirectionalEdgeInsets{
                                            .leading = navBarMargins.leading + navBarContentMargins.leading +
                                                (isDisplayingBackButton ? platformBackButtonWidth : 0),
                                            .trailing = navBarMargins.trailing + navBarContentMargins.trailing,
                                        }];
#endif // RCT_NEW_ARCH_ENABLED
}
#endif

- (void)willMoveToParentViewController:(UIViewController *)parent
{
  [super willMoveToParentViewController:parent];
  if ([self.parentViewController isKindOfClass:RNSTabsScreenViewController.class]) {
    RNSTabsScreenViewController *previousParentTabsScreenVC =
        static_cast<RNSTabsScreenViewController *>(self.parentViewController);
    [previousParentTabsScreenVC clearTabsSpecialEffectsDelegateIfNeeded:self];
  }
}

- (void)didMoveToParentViewController:(UIViewController *)parent
{
  [super didMoveToParentViewController:parent];
  if ([parent isKindOfClass:RNSTabsScreenViewController.class]) {
    RNSTabsScreenViewController *parentTabsScreenVC = static_cast<RNSTabsScreenViewController *>(parent);
    [parentTabsScreenVC setTabsSpecialEffectsDelegate:self];
  }
}

- (bool)onRepeatedTabSelectionOfTabScreenController:(RNSTabsScreenViewController *)tabScreenController
{
  if ([[self viewControllers] count] > 1 &&
      tabScreenController.tabScreenComponentView.shouldUseRepeatedTabSelectionPopToRootSpecialEffect) {
    return [[self popToRootViewControllerAnimated:true] count] > 0;
  } else if (tabScreenController.tabScreenComponentView.shouldUseRepeatedTabSelectionScrollToTopSpecialEffect) {
    UIScrollView *scrollView =
        [RNSScrollViewFinder findScrollViewInFirstDescendantChainFrom:[[self topViewController] view]];
    return [scrollView rnscreens_scrollToTop];
  }

  return false;
}

@end

#if !TARGET_OS_TV && !TARGET_OS_VISION
@interface RNSScreenEdgeGestureRecognizer : UIScreenEdgePanGestureRecognizer
@end

@implementation RNSScreenEdgeGestureRecognizer
@end

@interface RNSPanGestureRecognizer : UIPanGestureRecognizer
@end

@implementation RNSPanGestureRecognizer
@end
#endif

@implementation RNSScreenStackView {
  UINavigationController *_controller;
  NSMutableArray<RNSScreenView *> *_reactSubviews;
  BOOL _invalidated;
  BOOL _isFullWidthSwiping;
  RNSPercentDrivenInteractiveTransition *_interactionController;
  __weak RNSScreenStackManager *_manager;
  BOOL _updateScheduled;
#ifdef RCT_NEW_ARCH_ENABLED
  /// Screens that are subject of `ShadowViewMutation::Type::Delete` mutation
  /// in current transaction. This vector should be populated when we receive notification via
  /// `RCTMountingObserving` protocol, that a transaction will be performed, and should
  /// be cleaned up when we're notified that the transaction has been completed.
  std::vector<__strong RNSScreenView *> _toBeDeletedScreens;
#endif // RCT_NEW_ARCH_ENABLED
}

#ifdef RCT_NEW_ARCH_ENABLED

// Needed because of this: https://github.com/facebook/react-native/pull/37274
+ (void)load
{
  [super load];
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const react::RNSScreenStackProps>();
    _props = defaultProps;
    [self initCommonProps];
  }

  return self;
}
#endif // RCT_NEW_ARCH_ENABLED

- (instancetype)initWithManager:(RNSScreenStackManager *)manager
{
  if (self = [super init]) {
    _invalidated = NO;
    _manager = manager;
    [self initCommonProps];
  }
  return self;
}

- (void)initCommonProps
{
  _reactSubviews = [NSMutableArray new];
  _presentedModals = [NSMutableArray new];
  _controller = [RNSNavigationController new];
  _controller.delegate = self;
#if !TARGET_OS_TV && !TARGET_OS_VISION
  [self setupGestureHandlers];
#endif
  // we have to initialize viewControllers with a non empty array for
  // largeTitle header to render in the opened state. If it is empty
  // the header will render in collapsed state which is perhaps a bug
  // in UIKit but ¯\_(ツ)_/¯
  [_controller setViewControllers:@[ [UIViewController new] ]];
}

#pragma mark - helper methods

- (BOOL)shouldCancelDismissFromView:(RNSScreenView *)fromView toView:(RNSScreenView *)toView
{
  int fromIndex = (int)[_reactSubviews indexOfObject:fromView];
  int toIndex = (int)[_reactSubviews indexOfObject:toView];
  for (int i = fromIndex; i > toIndex; i--) {
    if (_reactSubviews[i].preventNativeDismiss) {
      return YES;
      break;
    }
  }
  return NO;
}

#pragma mark - Common

- (void)emitOnFinishTransitioningEvent
{
#ifdef RCT_NEW_ARCH_ENABLED
  if (_eventEmitter != nullptr) {
    std::dynamic_pointer_cast<const react::RNSScreenStackEventEmitter>(_eventEmitter)
        ->onFinishTransitioning(react::RNSScreenStackEventEmitter::OnFinishTransitioning{});
  }
#else
  if (self.onFinishTransitioning) {
    self.onFinishTransitioning(nil);
  }
#endif
}

- (void)navigationController:(UINavigationController *)navigationController
      willShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated
{
#ifdef RCT_NEW_ARCH_ENABLED
  if (![viewController.view isKindOfClass:[RNSScreenView class]]) {
    // if the current view is a snapshot, config was already removed so we don't trigger the method
    return;
  }
#endif
  auto *screenView = static_cast<RNSScreenView *>(viewController.view);
  [RNSScreenStackHeaderConfig willShowViewController:viewController
                                            animated:animated
                                          withConfig:screenView.findHeaderConfig];
}

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController
{
  // We don't directly set presentation delegate but instead rely on the ScreenView's delegate to
  // forward certain calls to the container (Stack).
  if ([presentationController.presentedViewController isKindOfClass:[RNSScreen class]]) {
    // we trigger the update of status bar's appearance here because there is no other lifecycle method
    // that can handle it when dismissing a modal, the same for orientation
    [RNSScreenWindowTraits updateWindowTraits];
    [_presentedModals removeObject:presentationController.presentedViewController];

    _updatingModals = NO;
#ifdef RCT_NEW_ARCH_ENABLED
    [self emitOnFinishTransitioningEvent];
#else
    // we double check if there are no new controllers pending to be presented since someone could
    // have tried to push another one during the transition.
    // We don't do it on Fabric since update of container will be triggered from "unmount" method afterwards
    [self updateContainer];
    if (self.onFinishTransitioning) {
      // instead of directly triggering onFinishTransitioning this time we enqueue the event on the
      // main queue. We do that because onDismiss event is also enqueued and we want for the transition
      // finish event to arrive later than onDismiss (see RNSScreen#notifyDismiss)
      dispatch_async(dispatch_get_main_queue(), ^{
        [self emitOnFinishTransitioningEvent];
      });
    }
#endif
  }
}

RNS_IGNORE_SUPER_CALL_BEGIN
- (NSArray<UIView *> *)reactSubviews
{
  return _reactSubviews;
}
RNS_IGNORE_SUPER_CALL_END

- (void)didMoveToWindow
{
  [super didMoveToWindow];
#ifdef RCT_NEW_ARCH_ENABLED
  // for handling nested stacks
  [self maybeAddToParentAndUpdateContainer];
#else
  if (!_invalidated) {
    // We check whether the view has been invalidated before running side-effects in didMoveToWindow
    // This is needed because when LayoutAnimations are used it is possible for view to be re-attached
    // to a window despite the fact it has been removed from the React Native view hierarchy.
    [self maybeAddToParentAndUpdateContainer];
  }
#endif
}

- (void)maybeAddToParentAndUpdateContainer
{
  BOOL wasScreenMounted = _controller.parentViewController != nil;
  if (!self.window && !wasScreenMounted) {
    // We wait with adding to parent controller until the stack is mounted.
    // If we add it when window is not attached, some of the view transitions will be blocked (i.e.
    // modal transitions) and the internal view controler's state will get out of sync with what's
    // on screen without us knowing.
    return;
  }
  [self updateContainer];
  if (!wasScreenMounted) {
    // when stack hasn't been added to parent VC yet we do two things:
    // 1) we run updateContainer (the one above) – we do this because we want push view controllers to
    // be installed before the VC is mounted. If we do that after it is added to parent the push
    // updates operations are going to be blocked by UIKit.
    // 2) we add navigation VS to parent – this is needed for the VC lifecycle events to be dispatched
    // properly
    // 3) we again call updateContainer – this time we do this to open modal controllers. Modals
    // won't open in (1) because they require navigator to be added to parent. We handle that case
    // gracefully in setModalViewControllers and can retry opening at any point.
    [self reactAddControllerToClosestParent:_controller];
    [self updateContainer];
  }
}

- (void)reactAddControllerToClosestParent:(UIViewController *)controller
{
  if (!controller.parentViewController) {
    UIView *parentView = (UIView *)self.reactSuperview;
    while (parentView) {
      if (parentView.reactViewController) {
        [parentView.reactViewController addChildViewController:controller];
        [self addSubview:controller.view];
#if !TARGET_OS_TV
        _controller.interactivePopGestureRecognizer.delegate = self;
#endif
        [controller didMoveToParentViewController:parentView.reactViewController];
        // On iOS pre 12 we observed that `willShowViewController` delegate method does not always
        // get triggered when the navigation controller is instantiated. As the only thing we do in
        // that delegate method is ask nav header to update to the current state it does not hurt to
        // trigger that logic from here too such that we can be sure the header is properly updated.
        [self navigationController:_controller willShowViewController:_controller.topViewController animated:NO];
        break;
      }
      parentView = (UIView *)parentView.reactSuperview;
    }
    return;
  }
}

+ (UIViewController *)findTopMostPresentedViewControllerFromViewController:(UIViewController *)controller
{
  auto presentedVc = controller;
  while (presentedVc.presentedViewController != nil) {
    presentedVc = presentedVc.presentedViewController;
  }
  return presentedVc;
}

- (UIViewController *)findReactRootViewController
{
  UIView *parent = self;
  while (parent) {
    parent = parent.reactSuperview;
    if (parent.isReactRootView) {
      return parent.reactViewController;
    }
  }
  return nil;
}

- (UIViewController *)lastFromPresentedViewControllerChainStartingFrom:(UIViewController *)vc
{
  UIViewController *lastNonNullVc = vc;
  UIViewController *lastVc = vc.presentedViewController;
  while (lastVc != nil) {
    lastNonNullVc = lastVc;
    lastVc = lastVc.presentedViewController;
  }
  return lastNonNullVc;
}

- (void)setModalViewControllers:(NSArray<UIViewController *> *)controllers
{
  // prevent re-entry
  if (_updatingModals) {
    _scheduleModalsUpdate = YES;
    return;
  }

  // when there is no change we return immediately. This check is important because sometime we may
  // accidently trigger modal dismiss if we don't verify to run the below code only when an actual
  // change in the list of presented modal was made.
  if ([_presentedModals isEqualToArray:controllers]) {
    return;
  }

  // if view controller is not yet attached to window we skip updates now and run them when view
  // is attached
  if (self.window == nil && _presentedModals.lastObject.view.window == nil) {
    return;
  }

  _updatingModals = YES;

  // We need to find bottom-most view controller that should stay on the stack
  // for the duration of transition.

  // There are couple of scenarios:
  // (1) no modals are presented or all modals were presented by this RNSNavigationController,
  // (2) there are modals presented by other RNSNavigationControllers (nested/outer),
  // (3) there are modals presented by other controllers (e.g. React Native's Modal view).

  // Last controller that is common for both _presentedModals & controllers or this RNSNavigationController in case
  // there is no common part.
  __block UIViewController *changeRootController = _controller;

  // Last common controller index + 1
  NSUInteger changeRootIndex = 0;
  for (NSUInteger i = 0; i < MIN(_presentedModals.count, controllers.count); i++) {
    if (_presentedModals[i] == controllers[i]) {
      changeRootController = controllers[i];
      changeRootIndex = i + 1;
    } else {
      break;
    }
  }

  // we verify that controllers added on top of changeRootIndex are all new. Unfortunately modal
  // VCs cannot be reshuffled (there are some visual glitches when we try to dismiss then show as
  // even non-animated dismissal has delay and updates the screen several times)
  for (NSUInteger i = changeRootIndex; i < controllers.count; i++) {
    if ([_presentedModals containsObject:controllers[i]]) {
      RCTAssert(false, @"Modally presented controllers are being reshuffled, this is not allowed");
    }
  }

  __weak RNSScreenStackView *weakSelf = self;

  void (^afterTransitions)(void) = ^{
    [weakSelf emitOnFinishTransitioningEvent];
    weakSelf.updatingModals = NO;
    if (weakSelf.scheduleModalsUpdate) {
      // if modals update was requested during setModalViewControllers we set scheduleModalsUpdate
      // flag in order to perform updates at a later point. Here we are done with all modals
      // transitions and check this flag again. If it was set, we reset the flag and execute updates.
      weakSelf.scheduleModalsUpdate = NO;
      [weakSelf updateContainer];
    }
    // we trigger the update of orientation here because, when dismissing the modal from JS,
    // neither `viewWillAppear` nor `presentationControllerDidDismiss` are called, same for status bar.
    [RNSScreenWindowTraits updateWindowTraits];
  };

  void (^finish)(void) = ^{
    NSUInteger oldCount = weakSelf.presentedModals.count;
    if (changeRootIndex < oldCount) {
      [weakSelf.presentedModals removeObjectsInRange:NSMakeRange(changeRootIndex, oldCount - changeRootIndex)];
    }
    BOOL isAttached =
        changeRootController.parentViewController != nil || changeRootController.presentingViewController != nil;

    if (!isAttached || changeRootIndex >= controllers.count) {
      // if change controller view is not attached, presenting modals will silently fail on iOS.
      // In such a case we trigger controllers update from didMoveToWindow.
      // We also don't run any present transitions if changeRootIndex is greater or equal to the size
      // of new controllers array. This means that no new controllers should be presented.
      afterTransitions();
      return;
    }

    UIViewController *previous = changeRootController;

    for (NSUInteger i = changeRootIndex; i < controllers.count; i++) {
      UIViewController *next = controllers[i];
      BOOL lastModal = (i == controllers.count - 1);

      // Inherit UI style from its parent - solves an issue with incorrect style being applied to some UIKit views
      // like date picker or segmented control.
      next.overrideUserInterfaceStyle = self->_controller.overrideUserInterfaceStyle;

      BOOL shouldAnimate = lastModal && [next isKindOfClass:[RNSScreen class]] &&
          ((RNSScreen *)next).screenView.stackAnimation != RNSScreenStackAnimationNone;

      // if you want to present another modal quick enough after dismissing the previous one,
      // it will result in wrong changeRootController, see repro in
      // https://github.com/software-mansion/react-native-screens/issues/1299 We call `updateContainer` again in
      // `presentationControllerDidDismiss` to cover this case and present new controller
      if (previous.beingDismissed) {
        return;
      }

      [previous presentViewController:next
                             animated:shouldAnimate
                           completion:^{
                             [weakSelf.presentedModals addObject:next];
                             if (lastModal) {
                               afterTransitions();
                             };
                           }];
      previous = next;
    }
  };

  // changeRootController is the last controller that *is owned by this stack*, and should stay unchanged after this
  // batch of transitions. Therefore changeRootController.presentedViewController is the first constroller to be
  // dismissed (implying also all controllers above). Notice here, that firstModalToBeDismissed could have been
  // RNSScreen modal presented from *this* stack, another stack, or any other view controller with modal presentation
  // provided by third-party libraries (e.g. React Native's Modal view). In case of presence of other (not managed by
  // us) modal controllers, weird interactions might arise. The code below, besides handling our presentation /
  // dismissal logic also attempts to handle possible wide gamut of cases of interactions with third-party modal
  // controllers, however it's not perfect.
  // TODO: Find general way to manage owned and foreign modal view controllers and refactor this code. Consider building
  // model first (data structue, attempting to be aware of all modals in presentation and some text-like algorithm for
  // computing required operations).

  UIViewController *firstModalToBeDismissed = changeRootController.presentedViewController;

  // This check is for external modals that are not owned by this stack. They can prevent the dismissal of the modal by
  // extending RNSDismissibleModalProtocol and returning NO from isDismissible method.
  if (![firstModalToBeDismissed conformsToProtocol:@protocol(RNSDismissibleModalProtocol)] ||
      [(id<RNSDismissibleModalProtocol>)firstModalToBeDismissed isDismissible]) {
    if (firstModalToBeDismissed != nil) {
      const BOOL firstModalToBeDismissedIsOwned = [firstModalToBeDismissed isKindOfClass:RNSScreen.class];
      const BOOL firstModalToBeDismissedIsOwnedByThisStack =
          firstModalToBeDismissedIsOwned && [_presentedModals containsObject:firstModalToBeDismissed];

      if (firstModalToBeDismissedIsOwnedByThisStack || !firstModalToBeDismissedIsOwned) {
        // We dismiss every VC that was presented by changeRootController VC or its descendant.
        // After the series of dismissals is completed we run completion block in which
        // we present modals on top of changeRootController (which may be the this stack VC)
        //
        // There also might the second case, where the firstModalToBeDismissed is foreign.
        // See: https://github.com/software-mansion/react-native-screens/issues/2048
        // For now, to mitigate the issue, we also decide to trigger its dismissal before
        // starting the presentation chain down below in finish() callback.
        if (!firstModalToBeDismissed.isBeingDismissed) {
          // If the modal is owned we let it control whether the dismissal is animated or not. For foreign controllers
          // we just assume animation.
          const BOOL firstModalToBeDismissedPrefersAnimation = firstModalToBeDismissedIsOwned
              ? static_cast<RNSScreen *>(firstModalToBeDismissed).screenView.stackAnimation !=
                  RNSScreenStackAnimationNone
              : YES;
          [changeRootController dismissViewControllerAnimated:firstModalToBeDismissedPrefersAnimation
                                                   completion:finish];
        } else {
          // We need to wait for its dismissal and then run our presentation code.
          // This happens, e.g. when we have foreign modal presented on top of owned one & we dismiss foreign one and
          // immediately present another owned one. Dismissal of the foreign one will be triggered by foreign
          // controller.
          [[firstModalToBeDismissed transitionCoordinator]
              animateAlongsideTransition:nil
                              completion:^(id<UIViewControllerTransitionCoordinatorContext> _) {
                                finish();
                              }];
        }
        return;
      }
    }

    // changeRootController does not have presentedViewController but it does not mean that no modals are in
    // presentation; modals could be presented by another stack (nested / outer), third-party view controller or they
    // could be using UIModalPresentationCurrentContext / UIModalPresentationOverCurrentContext presentation styles; in
    // the last case for some reason system asks top-level (react root) vc to present instead of our stack, despite the
    // fact that `definesPresentationContext` returns `YES` for UINavigationController. So we first need to find
    // top-level controller manually:
    UIViewController *reactRootVc = [self findReactRootViewController];
    UIViewController *topMostVc = [RNSScreenStackView findTopMostPresentedViewControllerFromViewController:reactRootVc];

    if (topMostVc != reactRootVc) {
      changeRootController = topMostVc;

      // Here we handle just the simplest case where the top level VC was dismissed. In any more complex
      // scenario we will still have problems, see: https://github.com/software-mansion/react-native-screens/issues/1813
      if ([_presentedModals containsObject:topMostVc] && ![controllers containsObject:topMostVc]) {
        [changeRootController dismissViewControllerAnimated:YES completion:finish];
        return;
      }
    }
  }

  // We didn't detect any controllers for dismissal, thus we start presenting new VCs
  finish();
}

- (void)setPushViewControllers:(NSArray<UIViewController *> *)controllers
{
  // when there is no change we return immediately
  if ([_controller.viewControllers isEqualToArray:controllers]) {
    return;
  }

  // if view controller is not yet attached to window we skip updates now and run them when view
  // is attached
  if (self.window == nil) {
    return;
  }
  // when transition is ongoing, any updates made to the controller will not be reflected until the
  // transition is complete. In particular, when we push/pop view controllers we expect viewControllers
  // property to be updated immediately. Based on that property we then calculate future updates.
  // When the transition is ongoing the property won't be updated immediatly. We therefore avoid
  // making any updated when transition is ongoing and schedule updates for when the transition
  // is complete.
  if (_controller.transitionCoordinator != nil) {
    if (!_updateScheduled) {
      _updateScheduled = YES;
      __weak RNSScreenStackView *weakSelf = self;
      [_controller.transitionCoordinator
          animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
            // do nothing here, we only want to be notified when transition is complete
          }
          completion:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context) {
            self->_updateScheduled = NO;
            [weakSelf updateContainer];
          }];
    }
    return;
  }

  UIViewController *top = controllers.lastObject;
#ifdef RCT_NEW_ARCH_ENABLED
  UIViewController *previousTop = _controller.topViewController;
#else
  UIViewController *previousTop = _controller.viewControllers.lastObject;
#endif

  // At the start we set viewControllers to contain a single UIViewController
  // instance. This is a workaround for header height adjustment bug (see comment
  // in the init function). Here, we need to detect if the initial empty
  // controller is still there
  BOOL firstTimePush = ![previousTop isKindOfClass:[RNSScreen class]];

  if (firstTimePush) {
    // nothing pushed yet
    [_controller setViewControllers:controllers animated:NO];
  } else if (top != previousTop) {
    if (![controllers containsObject:previousTop]) {
      // if the previous top screen does not exist anymore and the new top was not on the stack before, probably replace
      // was called, so we check the animation
      if (![_controller.viewControllers containsObject:top] &&
          ((RNSScreenView *)top.view).replaceAnimation == RNSScreenReplaceAnimationPush) {
        // setting new controllers with animation does `push` animation by default
#ifdef RCT_NEW_ARCH_ENABLED
        // This is a workaround for the case, when in the app we're trying to do `replace` action on screens, when
        // there's already ongoing transition to some screen. In such case, we're making the snapshot, but we're trying
        // to add it to the wrong superview (where it should be UIViewControllerWrapperView, but it's
        // _UIParallaxDimmingView instead). At the moment of RN 0.74 we can't queue the unmounts for such situation
        // either, so we need to turn off animations, when the view is not yet mounted, but it will appear after the
        // transition of previous replacement.
        [_controller setViewControllers:controllers animated:previousTop.view.window != nil];
#else
        [_controller setViewControllers:controllers animated:YES];
#endif // RCT_NEW_ARCH_ENABLED
      } else {
        // last top controller is no longer on stack
        // in this case we set the controllers stack to the new list with
        // added the last top element to it and perform (animated) pop
        NSMutableArray *newControllers = [NSMutableArray arrayWithArray:controllers];
        [newControllers addObject:previousTop];
        [_controller setViewControllers:newControllers animated:NO];
        [_controller popViewControllerAnimated:YES];
      }
    } else if (![_controller.viewControllers containsObject:top]) {
      // new top controller is not on the stack
      // in such case we update the stack except from the last element with
      // no animation and do animated push of the last item
      NSMutableArray *newControllers = [NSMutableArray arrayWithArray:controllers];
      [newControllers removeLastObject];

      [_controller setViewControllers:newControllers animated:NO];
      [_controller pushViewController:top animated:YES];
    } else {
      // don't really know what this case could be, but may need to handle it
      // somehow
      [_controller setViewControllers:controllers animated:NO];
    }
  } else {
    // change wasn't on the top of the stack. We don't need animation.
    [_controller setViewControllers:controllers animated:NO];
  }
}

- (void)updateContainer
{
  NSMutableArray<UIViewController *> *pushControllers = [NSMutableArray new];
  NSMutableArray<UIViewController *> *modalControllers = [NSMutableArray new];
  for (RNSScreenView *screen in _reactSubviews) {
    if (!screen.dismissed && screen.controller != nil && screen.activityState != RNSActivityStateInactive) {
      if (pushControllers.count == 0) {
        // first screen on the list needs to be places as "push controller"
        [pushControllers addObject:screen.controller];
      } else {
        if (screen.stackPresentation == RNSScreenStackPresentationPush) {
          [pushControllers addObject:screen.controller];
        } else {
          [modalControllers addObject:screen.controller];
        }
      }
    }
  }

  [self setPushViewControllers:pushControllers];
  [self setModalViewControllers:modalControllers];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  _controller.view.frame = self.bounds;

  // We need to update the bounds of the modal views here, since
  // for contained modals they are not updated by modals themselves.
  for (UIViewController *modal in _presentedModals) {
    // Because `layoutSubviews` method is also called on grabbing the modal,
    // we don't want to update the frame when modal is being dismissed.
    // We also want to get the frame in correct position. In the best case, it
    // should be modal's superview (UITransitionView), which frame is being changed correctly.
    // Otherwise, when superview is nil, we will fallback to the bounds of the ScreenStack.
    BOOL isModalBeingDismissed = [modal isKindOfClass:[RNSScreen class]] && ((RNSScreen *)modal).isBeingDismissed;
    CGRect correctFrame = modal.view.superview != nil ? modal.view.superview.frame : self.bounds;

    if (!CGRectEqualToRect(modal.view.frame, correctFrame) && !isModalBeingDismissed) {
      modal.view.frame = correctFrame;
    }
  }
}

- (void)dismissOnReload
{
#ifdef RCT_NEW_ARCH_ENABLED
#else
  dispatch_async(dispatch_get_main_queue(), ^{
    [self invalidate];
  });
#endif // RCT_NEW_ARCH_ENABLED
}

#pragma mark methods connected to transitioning

- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)navigationController
                                  animationControllerForOperation:(UINavigationControllerOperation)operation
                                               fromViewController:(UIViewController *)fromVC
                                                 toViewController:(UIViewController *)toVC
{
  RNSScreenView *screen;
  if (operation == UINavigationControllerOperationPush) {
    screen = ((RNSScreen *)toVC).screenView;
  } else if (operation == UINavigationControllerOperationPop) {
    screen = ((RNSScreen *)fromVC).screenView;
  }
  BOOL shouldCancelDismiss = [self shouldCancelDismissFromView:(RNSScreenView *)fromVC.view
                                                        toView:(RNSScreenView *)toVC.view];
  if (screen != nil &&
      // when preventing the native dismiss with back button, we have to return the animator.
      // Also, we need to return the animator when full width swiping even if the animation is not custom,
      // otherwise the screen will be just popped immediately due to no animation
      ((operation == UINavigationControllerOperationPop && shouldCancelDismiss) || _isFullWidthSwiping ||
       [RNSScreenStackAnimator isCustomAnimation:screen.stackAnimation] || _customAnimation)) {
    return [[RNSScreenStackAnimator alloc] initWithOperation:operation];
  }
  return nil;
}

- (void)cancelTouchesInParent
{
  // cancel touches in parent, this is needed to cancel RN touch events. For example when Touchable
  // item is close to an edge and we start pulling from edge we want the Touchable to be cancelled.
  // Without the below code the Touchable will remain active (highlighted) for the duration of back
  // gesture and onPress may fire when we release the finger.

  [[self rnscreens_findTouchHandlerInAncestorChain] rnscreens_cancelTouches];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
  if (_disableSwipeBack) {
    return NO;
  }
  RNSScreenView *topScreen = _reactSubviews.lastObject;

#if TARGET_OS_TV || TARGET_OS_VISION
  [self cancelTouchesInParent];
  return YES;
#else
  // RNSPanGestureRecognizer will receive events iff topScreen.fullScreenSwipeEnabled == YES;
  // Events are filtered in gestureRecognizer:shouldReceivePressOrTouchEvent: method
  if ([gestureRecognizer isKindOfClass:[RNSPanGestureRecognizer class]]) {
    if ([self isInGestureResponseDistance:gestureRecognizer topScreen:topScreen]) {
      _isFullWidthSwiping = YES;
      [self cancelTouchesInParent];
      return YES;
    }
    return NO;
  }

  // Now we're dealing with RNSScreenEdgeGestureRecognizer (or _UIParallaxTransitionPanGestureRecognizer)
  if (topScreen.customAnimationOnSwipe && [RNSScreenStackAnimator isCustomAnimation:topScreen.stackAnimation]) {
    if ([gestureRecognizer isKindOfClass:[RNSScreenEdgeGestureRecognizer class]]) {
      UIRectEdge edges = ((RNSScreenEdgeGestureRecognizer *)gestureRecognizer).edges;
      BOOL isRTL = _controller.view.semanticContentAttribute == UISemanticContentAttributeForceRightToLeft;
      BOOL isSlideFromLeft = topScreen.stackAnimation == RNSScreenStackAnimationSlideFromLeft;
      // if we do not set any explicit `semanticContentAttribute`, it is `UISemanticContentAttributeUnspecified` instead
      // of `UISemanticContentAttributeForceLeftToRight`, so we just check if it is RTL or not
      BOOL isCorrectEdge = (isRTL && edges == UIRectEdgeRight) ||
          (!isRTL && isSlideFromLeft && edges == UIRectEdgeRight) ||
          (isRTL && isSlideFromLeft && edges == UIRectEdgeLeft) || (!isRTL && edges == UIRectEdgeLeft);
      if (isCorrectEdge) {
        [self cancelTouchesInParent];
        return YES;
      }
    }
    return NO;
  } else {
    if ([gestureRecognizer isKindOfClass:[RNSScreenEdgeGestureRecognizer class]]) {
      // it should only recognize with `customAnimationOnSwipe` set
      return NO;
    }
    // _UIParallaxTransitionPanGestureRecognizer (other...)
    [self cancelTouchesInParent];
    return YES;
  }

#endif // TARGET_OS_TV
}

#if !TARGET_OS_TV && !TARGET_OS_VISION
- (void)setupGestureHandlers
{
  // gesture recognizers for custom stack animations
  RNSScreenEdgeGestureRecognizer *leftEdgeSwipeGestureRecognizer =
      [[RNSScreenEdgeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
  leftEdgeSwipeGestureRecognizer.edges = UIRectEdgeLeft;
  leftEdgeSwipeGestureRecognizer.delegate = self;
  [self addGestureRecognizer:leftEdgeSwipeGestureRecognizer];

  RNSScreenEdgeGestureRecognizer *rightEdgeSwipeGestureRecognizer =
      [[RNSScreenEdgeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipe:)];
  rightEdgeSwipeGestureRecognizer.edges = UIRectEdgeRight;
  rightEdgeSwipeGestureRecognizer.delegate = self;
  [self addGestureRecognizer:rightEdgeSwipeGestureRecognizer];

  // gesture recognizer for full width swipe gesture
  RNSPanGestureRecognizer *panRecognizer = [[RNSPanGestureRecognizer alloc] initWithTarget:self
                                                                                    action:@selector(handleSwipe:)];
  panRecognizer.delegate = self;
  [self addGestureRecognizer:panRecognizer];
}

- (void)handleSwipe:(UIPanGestureRecognizer *)gestureRecognizer
{
  RNSScreenView *topScreen = _reactSubviews.lastObject;
  float translation;
  float velocity;
  float distance;
  if (topScreen.swipeDirection == RNSScreenSwipeDirectionVertical) {
    translation = [gestureRecognizer translationInView:gestureRecognizer.view].y;
    velocity = [gestureRecognizer velocityInView:gestureRecognizer.view].y;
    distance = gestureRecognizer.view.bounds.size.height;
  } else {
    translation = [gestureRecognizer translationInView:gestureRecognizer.view].x;
    velocity = [gestureRecognizer velocityInView:gestureRecognizer.view].x;
    distance = gestureRecognizer.view.bounds.size.width;
    BOOL isRTL = _controller.view.semanticContentAttribute == UISemanticContentAttributeForceRightToLeft;
    if (isRTL) {
      translation = -translation;
      velocity = -velocity;
    }
  }

  bool isInverted = topScreen.stackAnimation == RNSScreenStackAnimationSlideFromLeft;

  float transitionProgress = (translation / distance);
  transitionProgress = isInverted ? transitionProgress * -1 : transitionProgress;

  switch (gestureRecognizer.state) {
    case UIGestureRecognizerStateBegan: {
      _interactionController = [RNSPercentDrivenInteractiveTransition new];
      [_controller popViewControllerAnimated:YES];
      break;
    }

    case UIGestureRecognizerStateChanged: {
      [_interactionController updateInteractiveTransition:transitionProgress];
      break;
    }

    case UIGestureRecognizerStateCancelled: {
      [_interactionController cancelInteractiveTransition];
      break;
    }

    case UIGestureRecognizerStateEnded: {
      // values taken from
      // https://github.com/react-navigation/react-navigation/blob/54739828598d7072c1bf7b369659e3682db3edc5/packages/stack/src/views/Stack/Card.tsx#L316
      float snapPoint = distance / 2;
      float gestureDistance = translation + velocity * 0.3;
      gestureDistance = isInverted ? gestureDistance * -1 : gestureDistance;
      BOOL shouldFinishTransition = gestureDistance > snapPoint;
      if (shouldFinishTransition) {
        [_interactionController finishInteractiveTransition];
      } else {
        [_interactionController cancelInteractiveTransition];
      }
      _interactionController = nil;
      _isFullWidthSwiping = NO;
    }
    default: {
      break;
    }
  }
}

- (id<UIViewControllerInteractiveTransitioning>)navigationController:(UINavigationController *)navigationController
                         interactionControllerForAnimationController:
                             (id<UIViewControllerAnimatedTransitioning>)animationController
{
  RNSScreenView *fromView = [_controller.transitionCoordinator viewForKey:UITransitionContextFromViewKey];
  RNSScreenView *toView = [_controller.transitionCoordinator viewForKey:UITransitionContextToViewKey];
  // we can intercept clicking back button here, we check reactSuperview since this method also fires when
  // navigating back from JS
  if (_interactionController == nil && fromView.reactSuperview) {
    BOOL shouldCancelDismiss = [self shouldCancelDismissFromView:fromView toView:toView];
    if (shouldCancelDismiss) {
      _interactionController = [RNSPercentDrivenInteractiveTransition new];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self->_interactionController cancelInteractiveTransition];
        self->_interactionController = nil;
        int fromIndex = (int)[self->_reactSubviews indexOfObject:fromView];
        int toIndex = (int)[self->_reactSubviews indexOfObject:toView];
        int indexDiff = fromIndex - toIndex;
        int dismissCount = indexDiff > 0 ? indexDiff : 1;
        [self updateContainer];
        [fromView notifyDismissCancelledWithDismissCount:dismissCount];
      });
    }
  }

  if (_interactionController != nil) {
    [_interactionController setAnimationController:animationController];
  }
  return _interactionController;
}

- (id<UIViewControllerInteractiveTransitioning>)interactionControllerForDismissal:
    (id<UIViewControllerAnimatedTransitioning>)animator
{
  return _interactionController;
}

- (void)navigationController:(UINavigationController *)navigationController
       didShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated
{
  [self emitOnFinishTransitioningEvent];
  [RNSScreenWindowTraits updateWindowTraits];
  // Because of the bug that caused view to have incorrect dimensions while changing the orientation,
  // we need to signalize that it needs to be layouted.
  // see https://github.com/software-mansion/react-native-screens/pull/1970
  [_controller.view setNeedsLayout];
}
#endif

- (void)markChildUpdated
{
  // In native stack this should be called only for `preload` purposes.
  [self updateContainer];
}

- (void)didUpdateChildren
{
  // do nothing
}

- (UIViewController *)reactViewController
{
  return _controller;
}

- (BOOL)isInGestureResponseDistance:(UIGestureRecognizer *)gestureRecognizer topScreen:(RNSScreenView *)topScreen
{
  NSDictionary *gestureResponseDistanceValues = topScreen.gestureResponseDistance;
  float x = [gestureRecognizer locationInView:gestureRecognizer.view].x;
  float y = [gestureRecognizer locationInView:gestureRecognizer.view].y;
  BOOL isRTL = _controller.view.semanticContentAttribute == UISemanticContentAttributeForceRightToLeft;
  if (isRTL) {
    x = _controller.view.frame.size.width - x;
  }

  // see:
  // https://github.com/software-mansion/react-native-screens/pull/1442/commits/74d4bae321875d8305ad021b3d448ebf713e7d56
  // this prop is always default initialized so we do not expect any nils
  float start = [gestureResponseDistanceValues[@"start"] floatValue];
  float end = [gestureResponseDistanceValues[@"end"] floatValue];
  float top = [gestureResponseDistanceValues[@"top"] floatValue];
  float bottom = [gestureResponseDistanceValues[@"bottom"] floatValue];

  // we check if any of the constraints are violated and return NO if so
  return !(
      (start != -1 && x < start) || (end != -1 && x > end) || (top != -1 && y < top) || (bottom != -1 && y > bottom));
}

// By default, the header buttons that are not inside the native hit area
// cannot be clicked, so we check it by ourselves
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
  if (CGRectContainsPoint(_controller.navigationBar.frame, point)) {
    RNSScreenView *topMostScreen = (RNSScreenView *)_reactSubviews.lastObject;
    UIView *headerConfig = topMostScreen.findHeaderConfig;
    if ([headerConfig isKindOfClass:[RNSScreenStackHeaderConfig class]]) {
      UIView *headerHitTestResult = [headerConfig hitTest:point withEvent:event];
      if (headerHitTestResult != nil) {
        return headerHitTestResult;
      }
    }
  }
  return [super hitTest:point withEvent:event];
}

#if !TARGET_OS_TV && !TARGET_OS_VISION

- (BOOL)isScrollViewPanGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
{
  // NOTE: This hack is required to restore native behavior of edge swipe (interactive pop gesture)
  // without this, on a screen with a scroll view, it's only possible to pop view by panning horizontally
  // if even slightly diagonal (or if in motion), scroll view will scroll, and edge swipe will be cancelled
  if (![[gestureRecognizer view] isKindOfClass:[UIScrollView class]]) {
    return NO;
  }
  UIScrollView *scrollView = (UIScrollView *)gestureRecognizer.view;
  return scrollView.panGestureRecognizer == gestureRecognizer;
}

// Custom method for compatibility with iOS < 13.4
// RNSScreenStackView is a UIGestureRecognizerDelegate for three types of gesture recognizers:
// RNSPanGestureRecognizer, RNSScreenEdgeGestureRecognizer, _UIParallaxTransitionPanGestureRecognizer
// Be careful when adding another type of gesture recognizer.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceivePressOrTouchEvent:(NSObject *)event
{
  RNSScreenView *topScreen = _reactSubviews.lastObject;

  for (RNSScreenView *s in _reactSubviews.reverseObjectEnumerator) {
    // Skip preloaded screens (state=RNSActivityStateInactive) that are on top and not yet navigated to
    // The "real" top screen is the one with state=RNSActivityStateOnTop
    if (s.activityState == RNSActivityStateOnTop) {
      topScreen = s;
      break;
    }
  }

  if (![topScreen isKindOfClass:[RNSScreenView class]] || !topScreen.gestureEnabled ||
      _controller.viewControllers.count < 2 || [topScreen isModal]) {
    return NO;
  }

  // We want to pass events to RNSPanGestureRecognizer iff full screen swipe is enabled.
  if ([gestureRecognizer isKindOfClass:[RNSPanGestureRecognizer class]]) {
    return topScreen.fullScreenSwipeEnabled;
  }

  // RNSScreenEdgeGestureRecognizer || _UIParallaxTransitionPanGestureRecognizer
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceivePress:(UIPress *)press;
{
  return [self gestureRecognizer:gestureRecognizer shouldReceivePressOrTouchEvent:press];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch;
{
  return [self gestureRecognizer:gestureRecognizer shouldReceivePressOrTouchEvent:touch];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  if ([gestureRecognizer isKindOfClass:[RNSPanGestureRecognizer class]] &&
      [self isScrollViewPanGestureRecognizer:otherGestureRecognizer]) {
    RNSPanGestureRecognizer *panGestureRecognizer = (RNSPanGestureRecognizer *)gestureRecognizer;
    BOOL isBackGesture = [panGestureRecognizer translationInView:panGestureRecognizer.view].x > 0 &&
        _controller.viewControllers.count > 1;

    if (gestureRecognizer.state == UIGestureRecognizerStateBegan || isBackGesture) {
      return NO;
    }

    return YES;
  }
  return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
  return (
      [gestureRecognizer isKindOfClass:[UIScreenEdgePanGestureRecognizer class]] &&
      [self isScrollViewPanGestureRecognizer:otherGestureRecognizer]);
}

#endif // !TARGET_OS_TV

RNS_IGNORE_SUPER_CALL_BEGIN
// We hijack the udpates as we don't want to update UIKit model yet.
// This is done after all mutations are processed.
- (void)insertReactSubview:(RNSScreenView *)subview atIndex:(NSInteger)atIndex
{
  if (![subview isKindOfClass:[RNSScreenView class]]) {
    RCTLogError(@"ScreenStack only accepts children of type Screen");
    return;
  }
  subview.reactSuperview = self;
  [_reactSubviews insertObject:subview atIndex:atIndex];
}

- (void)removeReactSubview:(RNSScreenView *)subview
{
  subview.reactSuperview = nil;
  [_reactSubviews removeObject:subview];
}
RNS_IGNORE_SUPER_CALL_END

- (void)didUpdateReactSubviews
{
  // we need to wait until children have their layout set. At this point they don't have the layout
  // set yet, however the layout call is already enqueued on ui thread. Enqueuing update call on the
  // ui queue will guarantee that the update will run after layout.
  dispatch_async(dispatch_get_main_queue(), ^{
    [self maybeAddToParentAndUpdateContainer];
  });
}

- (void)startScreenTransition
{
  if (_interactionController == nil) {
    _customAnimation = YES;
    _interactionController = [RNSPercentDrivenInteractiveTransition new];
    [_controller popViewControllerAnimated:YES];
  }
}

- (void)updateScreenTransition:(double)progress
{
  [_interactionController updateInteractiveTransition:progress];
}

- (void)finishScreenTransition:(BOOL)canceled
{
  _customAnimation = NO;
  if (canceled) {
    [_interactionController updateInteractiveTransition:0.0];
    [_interactionController cancelInteractiveTransition];
  } else {
    [_interactionController updateInteractiveTransition:1.0];
    [_interactionController finishInteractiveTransition];
  }
  _interactionController = nil;
}

- (nonnull NSArray<NSString *> *)screenIds
{
  NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:_reactSubviews.count];
  for (RNSScreenView *childScreenView in _reactSubviews) {
    [ids addObject:childScreenView.screenId];
  }
  return ids;
}

#ifdef RCT_NEW_ARCH_ENABLED
#pragma mark - Fabric specific

- (void)mountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index
{
  if (![childComponentView isKindOfClass:[RNSScreenView class]]) {
    RCTLogError(@"ScreenStack only accepts children of type Screen");
    return;
  }

  RCTAssert(
      childComponentView.reactSuperview == nil,
      @"Attempt to mount already mounted component view. (parent: %@, child: %@, index: %@, existing parent: %@)",
      self,
      childComponentView,
      @(index),
      @([childComponentView.superview tag]));

  [_reactSubviews insertObject:(RNSScreenView *)childComponentView atIndex:index];
  ((RNSScreenView *)childComponentView).reactSuperview = self;
  // Container update is done after all mount operations are executed in
  // `- [RNSScreenStackView mountingTransactionDidMount: withSurfaceTelemetry:]`
}

- (nullable RNSScreenView *)childScreenForTag:(react::Tag)tag
{
  for (RNSScreenView *child in _reactSubviews) {
    if (child.tag == tag) {
      return child;
    }
  }
  return nil;
}

- (void)unmountChildComponentView:(UIView<RCTComponentViewProtocol> *)childComponentView index:(NSInteger)index
{
  RNSScreenView *screenChildComponent = (RNSScreenView *)childComponentView;
  [screenChildComponent.controller setViewToSnapshot];

  RCTAssert(
      screenChildComponent.reactSuperview == self,
      @"Attempt to unmount a view which is mounted inside different view. (parent: %@, child: %@, index: %@)",
      self,
      screenChildComponent,
      @(index));
  RCTAssert(
      (_reactSubviews.count > index) && [_reactSubviews objectAtIndex:index] == childComponentView,
      @"Attempt to unmount a view which has a different index. (parent: %@, child: %@, index: %@, actual index: %@, tag at index: %@)",
      self,
      screenChildComponent,
      @(index),
      @([_reactSubviews indexOfObject:screenChildComponent]),
      @([[_reactSubviews objectAtIndex:index] tag]));
  screenChildComponent.reactSuperview = nil;
  [_reactSubviews removeObject:screenChildComponent];
  [screenChildComponent removeFromSuperview];
}

- (void)mountingTransactionWillMount:(const facebook::react::MountingTransaction &)transaction
                withSurfaceTelemetry:(const facebook::react::SurfaceTelemetry &)surfaceTelemetry
{
  for (const auto &mutation : transaction.getMutations()) {
    if (mutation.type == react::ShadowViewMutation::Delete) {
      RNSScreenView *_Nullable toBeRemovedChild = [self childScreenForTag:mutation.oldChildShadowView.tag];
      if (toBeRemovedChild != nil) {
        [toBeRemovedChild willBeUnmountedInUpcomingTransaction];
        _toBeDeletedScreens.push_back(toBeRemovedChild);
      }
    }
  }
}

- (void)mountingTransactionDidMount:(const facebook::react::MountingTransaction &)transaction
               withSurfaceTelemetry:(const facebook::react::SurfaceTelemetry &)surfaceTelemetry
{
  for (const auto &mutation : transaction.getMutations()) {
    // Note that self.tag might be invalid in cases this stack is removed.
    // This mostlikely does not cause any problems now, but it is something
    // worth to be aware of.
    if (MUTATION_PARENT_TAG(mutation) == self.tag &&
        (mutation.type == react::ShadowViewMutation::Type::Insert ||
         mutation.type == react::ShadowViewMutation::Type::Remove)) {
      // we need to wait until children have their layout set. At this point they don't have the layout
      // set yet, however the layout call is already enqueued on ui thread. Enqueuing update call on the
      // ui queue will guarantee that the update will run after layout.
      dispatch_async(dispatch_get_main_queue(), ^{
        [self maybeAddToParentAndUpdateContainer];
      });
      break;
    }
  }

  if (!self->_toBeDeletedScreens.empty()) {
    __weak RNSScreenStackView *weakSelf = self;
    // We want to run after container updates are performed (transitions etc.)
    dispatch_async(dispatch_get_main_queue(), ^{
      RNSScreenStackView *_Nullable strongSelf = weakSelf;
      if (strongSelf == nil) {
        return;
      }
      for (RNSScreenView *screenRef : strongSelf->_toBeDeletedScreens) {
        [screenRef invalidate];
      }
      strongSelf->_toBeDeletedScreens.clear();
    });
  }
}

- (void)prepareForRecycle
{
  [super prepareForRecycle];
  _reactSubviews = [NSMutableArray new];

  for (UIViewController *controller in _presentedModals) {
    [controller dismissViewControllerAnimated:NO completion:nil];
  }

  [_presentedModals removeAllObjects];
  [_controller willMoveToParentViewController:nil];
  [_controller removeFromParentViewController];
  [_controller setViewControllers:@[ [UIViewController new] ]];
}

+ (react::ComponentDescriptorProvider)componentDescriptorProvider
{
  return react::concreteComponentDescriptorProvider<react::RNSScreenStackComponentDescriptor>();
}
#else
#pragma mark - Paper specific

- (void)invalidate
{
  _invalidated = YES;
  [self dismissAllRelatedModals];
  [_controller willMoveToParentViewController:nil];
  [_controller removeFromParentViewController];
}

// This method aims to dismiss all modals for which presentation process
// has been initiated in this navigation controller, i. e. either a Screen
// with modal presentation or foreign modal presented from inside a Screen.
- (void)dismissAllRelatedModals
{
  [_controller.presentedViewController dismissViewControllerAnimated:YES completion:nil];

  // This loop seems to be excessive. Above message send to `_controller` should
  // be enough, because system dismisses the controllers recursively,
  // however better safe than sorry & introduce a regression, thus it is left here.
  for (UIViewController *controller in [_presentedModals reverseObjectEnumerator]) {
    [controller dismissViewControllerAnimated:NO completion:nil];
  }
  [_presentedModals removeAllObjects];
}

#endif // RCT_NEW_ARCH_ENABLED

@end

#ifdef RCT_NEW_ARCH_ENABLED
Class<RCTComponentViewProtocol> RNSScreenStackCls(void)
{
  return RNSScreenStackView.class;
}
#endif

@implementation RNSScreenStackManager {
  NSPointerArray *_stacks;
}

RCT_EXPORT_MODULE()

RCT_EXPORT_VIEW_PROPERTY(onFinishTransitioning, RCTDirectEventBlock);

#ifdef RCT_NEW_ARCH_ENABLED
#else
- (UIView *)view
{
  RNSScreenStackView *view = [[RNSScreenStackView alloc] initWithManager:self];
  if (!_stacks) {
    _stacks = [NSPointerArray weakObjectsPointerArray];
  }
  [_stacks addPointer:(__bridge void *)view];
  return view;
}
#endif // RCT_NEW_ARCH_ENABLED

- (void)invalidate
{
  for (RNSScreenStackView *stack in _stacks) {
    [stack dismissOnReload];
  }
  _stacks = nil;
}

@end
