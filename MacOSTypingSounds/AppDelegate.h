//
//  AppDelegate.h
//  MacOSTypingSounds
//
//  Created by Hugo Gonzalez on 2/28/15.
//

#import <Cocoa/Cocoa.h>

NS_INLINE BOOL FTMShouldShowRouteLineForModifierFlags(NSEventModifierFlags flags) {
    return (flags & NSEventModifierFlagOption) != 0;
}

NS_INLINE BOOL FTMShouldShowPermissionsWarningItem(BOOL accessibilityGranted, BOOL inputMonitoringGranted) {
    return !(accessibilityGranted && inputMonitoringGranted);
}

NS_INLINE BOOL FTMShouldPresentFirstLaunchSetupPrompt(BOOL alreadyPrompted, BOOL accessibilityGranted, BOOL inputMonitoringGranted) {
    return (!alreadyPrompted && FTMShouldShowPermissionsWarningItem(accessibilityGranted, inputMonitoringGranted));
}

@interface AppDelegate : NSObject <NSApplicationDelegate>


@end
