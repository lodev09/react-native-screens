#if !RCT_NEW_ARCH_ENABLED
#import "RCTConvert+RNSBottomTabs.h"

@implementation RCTConvert (RNSBottomTabs)

+ (UIOffset)UIOffset:(id)json;
{
  json = [self NSDictionary:json];
  return UIOffsetMake([json[@"horizontal"] floatValue], [json[@"vertical"] floatValue]);
}

RCT_ENUM_CONVERTER(
    RNSBottomTabsIconType,
    (@{
      @"image" : @(RNSBottomTabsIconTypeImage),
      @"template" : @(RNSBottomTabsIconTypeTemplate),
      @"sfSymbol" : @(RNSBottomTabsIconTypeSfSymbol),
    }),
    RNSBottomTabsIconTypeSfSymbol,
    integerValue)

RCT_ENUM_CONVERTER(
    RNSTabBarMinimizeBehavior,
    (@{
      @"automatic" : @(RNSTabBarMinimizeBehaviorAutomatic),
      @"never" : @(RNSTabBarMinimizeBehaviorNever),
      @"onScrollDown" : @(RNSTabBarMinimizeBehaviorOnScrollDown),
      @"onScrollUp" : @(RNSTabBarMinimizeBehaviorOnScrollUp),
    }),
    RNSTabBarMinimizeBehaviorAutomatic,
    integerValue)

@end

#endif // !RCT_NEW_ARCH_ENABLED
