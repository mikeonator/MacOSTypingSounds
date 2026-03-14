//
//  AppDelegate.m
//  MacOSTypingSounds
//
//  Created by Hugo Gonzalez on 2/28/15.
//

#import "AppDelegate.h"

#import <ApplicationServices/ApplicationServices.h>

#import "FTMPreferencesWindowController.h"
#import "FTMProfileSystem.h"

static NSString * const FTMDefaultsKeyDidShowPermissionsSetupPrompt = @"didShowPermissionsSetupPrompt";

@interface AppDelegate () <NSMenuDelegate, FTMPreferencesPermissionProviding>
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (assign, nonatomic) BOOL isMuted;
@property (strong, nonatomic) id globalKeyMonitor;
@property (strong, nonatomic) FTMProfileStore *profileStore;
@property (strong, nonatomic) FTMSoundPackImporter *soundPackImporter;
@property (strong, nonatomic) FTMSoundResolver *soundResolver;
@property (strong, nonatomic) FTMSoundPlayer *soundPlayer;
@property (strong, nonatomic) FTMPreferencesWindowController *preferencesWindowController;
@end

@implementation AppDelegate

#pragma mark - App Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{
        FTMDefaultsKeyMuted: @NO,
        FTMDefaultsKeyDidShowPermissionsSetupPrompt: @NO,
    }];

    self.isMuted = [defaults boolForKey:FTMDefaultsKeyMuted];

    self.soundPackImporter = [[FTMSoundPackImporter alloc] init];
    self.profileStore = [[FTMProfileStore alloc] initWithDefaults:defaults bundle:[NSBundle mainBundle]];
    self.soundPlayer = [[FTMSoundPlayer alloc] init];
    self.soundResolver = [[FTMSoundResolver alloc] initWithProfileStore:self.profileStore bundle:[NSBundle mainBundle]];

    NSError *loadError = nil;
    if (![self.profileStore loadOrInitialize:&loadError]) {
        [self presentStartupError:loadError];
    }

    [self refreshGlobalKeyMonitor];
    [self installWorkspaceObservers];
    [self setupStatusItem];
    [self setMenuItemsShowingRouteLine:NO];
    [self maybePresentFirstLaunchSetupPrompt];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    if (self.globalKeyMonitor) {
        [NSEvent removeMonitor:self.globalKeyMonitor];
        self.globalKeyMonitor = nil;
    }
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

#pragma mark - Setup

- (void)installWorkspaceObservers {
    NSNotificationCenter *workspaceCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [workspaceCenter addObserver:self
                        selector:@selector(applicationLaunched:)
                            name:NSWorkspaceDidLaunchApplicationNotification
                          object:nil];
    [workspaceCenter addObserver:self
                        selector:@selector(applicationTerminated:)
                            name:NSWorkspaceDidTerminateApplicationNotification
                          object:nil];
    [workspaceCenter addObserver:self
                        selector:@selector(applicationActivated:)
                            name:NSWorkspaceDidActivateApplicationNotification
                          object:nil];
}

- (void)setupStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    if (self.statusItem.button) {
        NSString *menuIconPNGPath = [[NSBundle mainBundle] pathForResource:@"MenuBarIconTemplate" ofType:@"png"];
        NSImage *menuIcon = menuIconPNGPath.length ? [[NSImage alloc] initWithContentsOfFile:menuIconPNGPath] : nil;
        if (!menuIcon) {
            menuIcon = [NSImage imageNamed:@"MenuBarIconTemplate"];
        }
        if (!menuIcon) {
            menuIcon = [NSImage imageNamed:@"MenuBarIconTemplate.pdf"];
        }
        if (menuIcon) {
            menuIcon = [menuIcon copy];
            menuIcon.template = YES;
            menuIcon.size = NSMakeSize(24, 24);
            self.statusItem.button.image = menuIcon;
            self.statusItem.button.imageScaling = NSImageScaleProportionallyDown;
            self.statusItem.button.imagePosition = NSImageOnly;
        }
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"MacOSTypingSounds"];
    menu.delegate = self;
    self.statusItem.menu = menu;
}

- (void)refreshGlobalKeyMonitor {
    if (self.globalKeyMonitor) {
        [NSEvent removeMonitor:self.globalKeyMonitor];
        self.globalKeyMonitor = nil;
    }

    __weak typeof(self) weakSelf = self;
    self.globalKeyMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                    handler:^(NSEvent *event) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        [self handleGlobalKeyDown:event];
    }];
}

#pragma mark - Event Handling

- (void)handleGlobalKeyDown:(NSEvent *)event {
    if ([self handleShortcutIfNeeded:event]) {
        return;
    }

    FTMProfile *effectiveProfile = [self effectiveTypingProfileForFrontmostApp];
    if (!self.isMuted && effectiveProfile) {
        NSString *path = [self.soundResolver soundPathForKeyCode:event.keyCode profile:effectiveProfile];
        [self.soundPlayer playSoundAtPath:path];
    }
}

- (BOOL)handleShortcutIfNeeded:(NSEvent *)event {
    NSEventModifierFlags flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
    BOOL hasShortcutModifiers = ((flags & NSEventModifierFlagCommand) &&
                                 (flags & NSEventModifierFlagShift) &&
                                 (flags & NSEventModifierFlagControl));
    if (!hasShortcutModifiers) {
        return NO;
    }

    if (event.keyCode == kVK_ANSI_K) {
        [self toggleMute];
        return YES;
    }
    if (event.keyCode == kVK_ANSI_L) {
        [self toggleAssignedAppsOnlyMode];
        return YES;
    }
    return NO;
}

#pragma mark - Status Menu

- (NSArray<NSString *> *)missingKeyboardAccessComponents {
    NSMutableArray<NSString *> *components = [NSMutableArray array];
    if (![self hasAccessibilityAccess]) {
        [components addObject:@"Accessibility"];
    }
    if (@available(macOS 10.15, *)) {
        if (![self hasInputMonitoringAccess]) {
            [components addObject:@"Input Monitoring"];
        }
    }
    return [components copy];
}

- (NSString *)permissionSetupWarningTitle {
    NSArray<NSString *> *missing = [self missingKeyboardAccessComponents];
    if (missing.count == 0) {
        return @"";
    }
    if (missing.count == 1) {
        return [NSString stringWithFormat:@"Setup Required: Grant %@…", missing.firstObject];
    }
    return @"Setup Required: Grant Accessibility + Input Monitoring…";
}

- (void)setMenuItemsShowingRouteLine:(BOOL)showRouteLine {
    NSMenu *menu = self.statusItem.menu;
    if (!menu) {
        menu = [[NSMenu alloc] initWithTitle:@"MacOSTypingSounds"];
        menu.delegate = self;
        self.statusItem.menu = menu;
    }

    [menu removeAllItems];

    NSMenuItem *muteItem = [[NSMenuItem alloc] initWithTitle:(self.isMuted ? @"Unmute SFX" : @"Mute SFX")
                                                      action:@selector(toggleMute)
                                               keyEquivalent:@"k"];
    muteItem.target = self;
    [muteItem setKeyEquivalentModifierMask:(NSEventModifierFlagShift | NSEventModifierFlagCommand | NSEventModifierFlagControl)];
    [menu addItem:muteItem];

    BOOL assignedAppsOnly = FTMReadAssignedAppsOnlyFromDefaults([NSUserDefaults standardUserDefaults]);
    NSMenuItem *playModeItem = [[NSMenuItem alloc] initWithTitle:(assignedAppsOnly ? @"Play SFX in all apps (use default profile for unassigned apps)" : @"Play SFX in assigned apps only")
                                                          action:@selector(toggleAssignedAppsOnlyMode)
                                                   keyEquivalent:@"l"];
    playModeItem.target = self;
    [playModeItem setKeyEquivalentModifierMask:(NSEventModifierFlagShift | NSEventModifierFlagCommand | NSEventModifierFlagControl)];
    [menu addItem:playModeItem];

    [menu addItem:[NSMenuItem separatorItem]];

    BOOL hasPermissions = [self hasKeyboardMonitoringAccess];
    if (FTMShouldShowPermissionsWarningItem([self hasAccessibilityAccess], [self hasInputMonitoringAccess])) {
        NSMenuItem *warningItem = [[NSMenuItem alloc] initWithTitle:[self permissionSetupWarningTitle]
                                                             action:@selector(openPermissionSetupFromMenu:)
                                                      keyEquivalent:@""];
        warningItem.target = self;
        warningItem.enabled = !hasPermissions;
        [menu addItem:warningItem];
        [menu addItem:[NSMenuItem separatorItem]];
    }

    if (showRouteLine) {
        NSString *routeTitle = [self currentRouteStatusTitle];
        if (routeTitle.length > 0) {
            NSMenuItem *routeItem = [[NSMenuItem alloc] initWithTitle:routeTitle action:nil keyEquivalent:@""];
            routeItem.enabled = NO;
            [menu addItem:routeItem];
            [menu addItem:[NSMenuItem separatorItem]];
        }
    }

    [menu addItem:[self profilesMenuItem]];

    NSMenuItem *preferencesItem = [[NSMenuItem alloc] initWithTitle:@"Preferences…"
                                                             action:@selector(showPreferencesWindow:)
                                                      keyEquivalent:@","];
    preferencesItem.target = self;
    [menu addItem:preferencesItem];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit MacOSTypingSounds" action:@selector(terminate:) keyEquivalent:@"q"];
}

- (NSMenuItem *)profilesMenuItem {
    NSMenu *profilesSubmenu = [[NSMenu alloc] initWithTitle:@"Default Profile (Unassigned Apps)"];
    FTMProfile *activeProfile = [self.profileStore activeProfile];

    for (FTMProfile *profile in self.profileStore.profiles) {
        NSMenuItem *profileItem = [[NSMenuItem alloc] initWithTitle:profile.name
                                                             action:@selector(selectProfileFromMenuItem:)
                                                      keyEquivalent:@""];
        profileItem.target = self;
        profileItem.representedObject = profile.profileID;
        if ([profile.profileID isEqualToString:activeProfile.profileID]) {
            profileItem.state = NSControlStateValueOn;
        }
        [profilesSubmenu addItem:profileItem];
    }

    if (profilesSubmenu.numberOfItems == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No Profiles" action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [profilesSubmenu addItem:empty];
    }

    NSMenuItem *profilesRoot = [[NSMenuItem alloc] initWithTitle:@"Default Profile (Unassigned Apps)"
                                                          action:nil
                                                   keyEquivalent:@""];
    profilesRoot.submenu = profilesSubmenu;
    return profilesRoot;
}

- (void)selectProfileFromMenuItem:(NSMenuItem *)menuItem {
    NSString *profileID = menuItem.representedObject;
    if (profileID.length == 0) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore setActiveProfileID:profileID error:&error]) {
        [self presentTransientError:error title:@"Profile Switch Failed"];
        return;
    }

    [self.soundResolver invalidateCache];
    [self setMenuItemsShowingRouteLine:NO];
    [self.preferencesWindowController reloadAllUI];
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    NSEventModifierFlags flags = [NSEvent modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
    [self setMenuItemsShowingRouteLine:FTMShouldShowRouteLineForModifierFlags(flags)];
}

- (void)menuDidClose:(NSMenu *)menu {
    (void)menu;
    [self setMenuItemsShowingRouteLine:NO];
}

#pragma mark - Menu Actions

- (void)toggleMute {
    self.isMuted = !self.isMuted;
    [[NSUserDefaults standardUserDefaults] setBool:self.isMuted forKey:FTMDefaultsKeyMuted];
    [self setMenuItemsShowingRouteLine:NO];
    [self.preferencesWindowController reloadAllUI];
}

- (void)toggleAssignedAppsOnlyMode {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL assignedAppsOnly = FTMReadAssignedAppsOnlyFromDefaults(defaults);
    FTMWriteAssignedAppsOnlyToDefaults(defaults, !assignedAppsOnly);
    [self.soundResolver invalidateCache];
    [self setMenuItemsShowingRouteLine:NO];
    [self.preferencesWindowController reloadAllUI];
}

- (void)ensurePreferencesWindowController {
    if (self.preferencesWindowController) {
        return;
    }

    self.preferencesWindowController = [[FTMPreferencesWindowController alloc] initWithProfileStore:self.profileStore
                                                                                             importer:self.soundPackImporter
                                                                                         soundResolver:self.soundResolver
                                                                                           soundPlayer:self.soundPlayer
                                                                                    permissionProvider:self];

    __weak typeof(self) weakSelf = self;
    self.preferencesWindowController.onProfilesChanged = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        [self.soundResolver invalidateCache];
        [self setMenuItemsShowingRouteLine:NO];
    };

    self.preferencesWindowController.onSettingsChanged = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        self.isMuted = [[NSUserDefaults standardUserDefaults] boolForKey:FTMDefaultsKeyMuted];
        [self refreshGlobalKeyMonitor];
        [self setMenuItemsShowingRouteLine:NO];
    };
}

- (void)showPreferencesWindow:(id)sender {
    (void)sender;
    [self ensurePreferencesWindowController];
    [self.preferencesWindowController presentWindow];
}

- (void)showPreferencesWindowSelectingSection:(NSString *)sectionIdentifier {
    [self ensurePreferencesWindowController];
    [self.preferencesWindowController presentWindowSelectingSection:sectionIdentifier];
}

- (void)openPermissionSetupFromMenu:(id)sender {
    (void)sender;
    [self showPreferencesWindowSelectingSection:FTMPreferencesSectionBehavior];
}

- (void)maybePresentFirstLaunchSetupPrompt {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL alreadyPrompted = [defaults boolForKey:FTMDefaultsKeyDidShowPermissionsSetupPrompt];
    BOOL accessibilityGranted = [self hasAccessibilityAccess];
    BOOL inputMonitoringGranted = [self hasInputMonitoringAccess];

    if (!FTMShouldPresentFirstLaunchSetupPrompt(alreadyPrompted, accessibilityGranted, inputMonitoringGranted)) {
        return;
    }

    [defaults setBool:YES forKey:FTMDefaultsKeyDidShowPermissionsSetupPrompt];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"Finish Setup for Global Typing Sounds";
    alert.informativeText = @"MacOSTypingSounds needs Accessibility and Input Monitoring permissions for global keyboard playback. Open App Behavior settings to complete setup.";
    [alert addButtonWithTitle:@"Open App Behavior"];
    [alert addButtonWithTitle:@"Later"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [self showPreferencesWindowSelectingSection:FTMPreferencesSectionBehavior];
    }
}

#pragma mark - App Launch/Quit Sounds

- (void)applicationLaunched:(NSNotification *)notification {
    if (self.isMuted) {
        return;
    }
    NSRunningApplication *runApp = notification.userInfo[@"NSWorkspaceApplicationKey"];
    FTMProfile *assignedProfile = [self.profileStore assignedProfileForBundleIdentifier:runApp.bundleIdentifier ?: @""];
    if (assignedProfile) {
        NSString *path = [self.soundResolver soundPathForEventSlotID:FTMSoundSlotLaunch profile:assignedProfile];
        [self.soundPlayer playSoundAtPath:path];
    }
}

- (void)applicationTerminated:(NSNotification *)notification {
    if (self.isMuted) {
        return;
    }
    NSRunningApplication *runApp = notification.userInfo[@"NSWorkspaceApplicationKey"];
    FTMProfile *assignedProfile = [self.profileStore assignedProfileForBundleIdentifier:runApp.bundleIdentifier ?: @""];
    if (assignedProfile) {
        NSString *path = [self.soundResolver soundPathForEventSlotID:FTMSoundSlotQuit profile:assignedProfile];
        [self.soundPlayer playSoundAtPath:path];
    }
}

- (void)applicationActivated:(NSNotification *)notification {
    (void)notification;
    [self refreshGlobalKeyMonitor];
    [self setMenuItemsShowingRouteLine:NO];
    [self.preferencesWindowController reloadAllUI];
}

#pragma mark - Error Presentation

- (void)presentStartupError:(NSError *)error {
    [self presentTransientError:error title:@"Startup Error"];
}

- (void)presentTransientError:(NSError *)error title:(NSString *)title {
    if (!error) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = title ?: @"Error";
        alert.informativeText = error.localizedDescription ?: @"Unknown error";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    });
}

#pragma mark - Permissions

- (BOOL)hasAccessibilityAccess {
    return AXIsProcessTrusted();
}

- (BOOL)hasInputMonitoringAccess {
    if (@available(macOS 10.15, *)) {
        return CGPreflightListenEventAccess();
    }
    return YES;
}

- (BOOL)hasKeyboardMonitoringAccess {
    return (self.missingKeyboardAccessComponents.count == 0);
}

- (BOOL)requestAccessibilityAccessPrompting:(BOOL)shouldPrompt {
    NSDictionary *options = shouldPrompt ? @{ (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES } : @{};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}

- (BOOL)requestInputMonitoringAccessPrompting:(BOOL)shouldPrompt {
    if (@available(macOS 10.15, *)) {
        if (shouldPrompt) {
            return CGRequestListenEventAccess();
        }
        return CGPreflightListenEventAccess();
    }
    return YES;
}

- (BOOL)isAccessibilityPermissionGranted {
    return [self hasAccessibilityAccess];
}

- (BOOL)isInputMonitoringPermissionGranted {
    return [self hasInputMonitoringAccess];
}

- (void)requestAccessibilityPermission {
    [self requestAccessibilityAccessPrompting:YES];
    [self refreshGlobalKeyMonitor];
    [self setMenuItemsShowingRouteLine:NO];
    [self.preferencesWindowController reloadAllUI];
}

- (void)requestInputMonitoringPermission {
    [self requestInputMonitoringAccessPrompting:YES];
    [self refreshGlobalKeyMonitor];
    [self setMenuItemsShowingRouteLine:NO];
    [self.preferencesWindowController reloadAllUI];
}

#pragma mark - Routing

- (FTMProfile *)effectiveTypingProfileForFrontmostApp {
    NSRunningApplication *frontmost = [[NSWorkspace sharedWorkspace] frontmostApplication];
    FTMProfile *assigned = [self.profileStore assignedProfileForBundleIdentifier:frontmost.bundleIdentifier ?: @""];
    if (assigned) {
        return assigned;
    }

    BOOL assignedAppsOnly = FTMReadAssignedAppsOnlyFromDefaults([NSUserDefaults standardUserDefaults]);
    if (assignedAppsOnly) {
        return nil;
    }

    return [self.profileStore activeProfile];
}

- (NSString *)currentRouteStatusTitle {
    NSRunningApplication *frontmost = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *appName = frontmost.localizedName.length
        ? frontmost.localizedName
        : (frontmost.bundleIdentifier.length ? frontmost.bundleIdentifier : @"(No Active App)");

    FTMProfile *assigned = [self.profileStore assignedProfileForBundleIdentifier:frontmost.bundleIdentifier ?: @""];
    if (assigned) {
        return [NSString stringWithFormat:@"Current App: %@ -> %@", appName, assigned.name ?: @"Profile"];
    }

    BOOL assignedAppsOnly = FTMReadAssignedAppsOnlyFromDefaults([NSUserDefaults standardUserDefaults]);
    if (assignedAppsOnly) {
        return [NSString stringWithFormat:@"Current App: %@ -> Silent (Unassigned App)", appName];
    }

    FTMProfile *fallback = [self.profileStore activeProfile];
    return [NSString stringWithFormat:@"Current App: %@ -> Default Profile (%@)", appName, fallback.name ?: @"Profile"];
}

enum {
    kVK_ANSI_L = 0x25,
    kVK_ANSI_K = 0x28,
};

@end
