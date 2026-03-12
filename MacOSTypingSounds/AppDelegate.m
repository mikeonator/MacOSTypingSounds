//
//  AppDelegate.m
//  MacOSTypingSounds
//
//  Created by Hugo Gonzalez on 2/28/15.
//  Copyright (c) 2015 mdt. All rights reserved.
//

#import "AppDelegate.h"

#import <ApplicationServices/ApplicationServices.h>

#import "FTMPreferencesWindowController.h"
#import "FTMProfileSystem.h"

@interface AppDelegate ()
@property (strong, nonatomic) IBOutlet NSMenu *statusMenu;
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

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    (void)aNotification;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:@{
        FTMDefaultsKeyTerminalsOnly: @NO,
        FTMDefaultsKeyAssignedAppsOnly: @NO,
        FTMDefaultsKeyMuted: @NO,
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

    [self installGlobalKeyMonitor];
    [self installWorkspaceObservers];
    [self setupStatusItem];
    [self setMenuItems];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    (void)aNotification;
    if (self.globalKeyMonitor) {
        [NSEvent removeMonitor:self.globalKeyMonitor];
        self.globalKeyMonitor = nil;
    }
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
}

#pragma mark - Setup

- (void)installGlobalKeyMonitor {
    __weak typeof(self) weakSelf = self;
    self.globalKeyMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^(NSEvent *event) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }
        [self handleGlobalKeyDown:event];
    }];
}

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
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:28];
    if (self.statusItem.button) {
        self.statusItem.button.image = [NSImage imageNamed:@"pipboy_icon"];
    }
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
        [self togglePlayMode];
        return YES;
    }
    return NO;
}

#pragma mark - Status Menu

- (void)setMenuItems {
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenuItem *muteItem = [[NSMenuItem alloc] initWithTitle:(self.isMuted ? @"Unmute SFX" : @"Mute SFX")
                                                      action:@selector(toggleMute)
                                               keyEquivalent:@"k"];
    muteItem.target = self;
    [muteItem setKeyEquivalentModifierMask:(NSEventModifierFlagShift | NSEventModifierFlagCommand | NSEventModifierFlagControl)];
    [menu addItem:muteItem];

    BOOL assignedAppsOnly = [[NSUserDefaults standardUserDefaults] boolForKey:FTMDefaultsKeyAssignedAppsOnly];
    NSMenuItem *playModeItem = [[NSMenuItem alloc] initWithTitle:(assignedAppsOnly ? @"Play SFX always (use default for unassigned apps)" : @"Play SFX in assigned apps only")
                                                          action:@selector(togglePlayMode)
                                                   keyEquivalent:@"l"];
    playModeItem.target = self;
    [playModeItem setKeyEquivalentModifierMask:(NSEventModifierFlagShift | NSEventModifierFlagCommand | NSEventModifierFlagControl)];
    [menu addItem:playModeItem];

    [menu addItem:[NSMenuItem separatorItem]];
    NSString *routeTitle = [self currentRouteStatusTitle];
    if (routeTitle.length > 0) {
        NSMenuItem *routeItem = [[NSMenuItem alloc] initWithTitle:routeTitle action:nil keyEquivalent:@""];
        routeItem.enabled = NO;
        [menu addItem:routeItem];
    }
    [menu addItem:[self profilesMenuItem]];

    NSMenuItem *appRoutingItem = [[NSMenuItem alloc] initWithTitle:@"App Routing…"
                                                            action:@selector(showAppRoutingWindow:)
                                                     keyEquivalent:@""];
    appRoutingItem.target = self;
    [menu addItem:appRoutingItem];

    BOOL keyboardAccessGranted = [self hasKeyboardMonitoringAccess];
    NSMenuItem *accessibilityItem = [[NSMenuItem alloc] initWithTitle:(keyboardAccessGranted ? @"Keyboard Access Granted" : @"Request Keyboard Access…")
                                                              action:@selector(requestKeyboardAccess:)
                                                       keyEquivalent:@""];
    accessibilityItem.target = self;
    accessibilityItem.enabled = !keyboardAccessGranted;
    [menu addItem:accessibilityItem];

    NSMenuItem *preferencesItem = [[NSMenuItem alloc] initWithTitle:@"Preferences…"
                                                             action:@selector(showPreferencesWindow:)
                                                      keyEquivalent:@","];
    preferencesItem.target = self;
    [menu addItem:preferencesItem];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit MacOSTypingSounds" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
}

- (NSMenuItem *)profilesMenuItem {
    NSMenu *profilesSubmenu = [[NSMenu alloc] initWithTitle:@"Default Profile (Unassigned Apps)"];
    FTMProfile *activeProfile = [self.profileStore activeProfile];

    for (FTMProfile *profile in self.profileStore.profiles) {
        NSMenuItem *profileItem = [[NSMenuItem alloc] initWithTitle:profile.name action:@selector(selectProfileFromMenuItem:) keyEquivalent:@""];
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

    NSMenuItem *profilesRoot = [[NSMenuItem alloc] initWithTitle:@"Default Profile (Unassigned Apps)" action:nil keyEquivalent:@""];
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
    [self setMenuItems];
    [self.preferencesWindowController reloadAllUI];
}

#pragma mark - Menu Actions

- (void)toggleMute {
    self.isMuted = !self.isMuted;
    [[NSUserDefaults standardUserDefaults] setBool:self.isMuted forKey:FTMDefaultsKeyMuted];
    [self setMenuItems];
    [self.preferencesWindowController reloadAllUI];
}

- (void)togglePlayMode {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL assignedAppsOnly = [defaults boolForKey:FTMDefaultsKeyAssignedAppsOnly];
    // ON means "assigned apps only". Menu text toggles between the opposite labels.
    [defaults setBool:!assignedAppsOnly forKey:FTMDefaultsKeyAssignedAppsOnly];
    [self setMenuItems];
    [self.preferencesWindowController reloadAllUI];
}

- (void)showPreferencesWindow:(id)sender {
    (void)sender;
    if (!self.preferencesWindowController) {
        self.preferencesWindowController = [[FTMPreferencesWindowController alloc] initWithProfileStore:self.profileStore
                                                                                               importer:self.soundPackImporter
                                                                                           soundResolver:self.soundResolver
                                                                                             soundPlayer:self.soundPlayer];
        __weak typeof(self) weakSelf = self;
        self.preferencesWindowController.onProfilesChanged = ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            [self.soundResolver invalidateCache];
            [self setMenuItems];
        };
        self.preferencesWindowController.onSettingsChanged = ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            self.isMuted = [[NSUserDefaults standardUserDefaults] boolForKey:FTMDefaultsKeyMuted];
            [self setMenuItems];
        };
    }

    [self.preferencesWindowController presentWindow];
}

- (void)showAppRoutingWindow:(id)sender {
    (void)sender;
    [self showPreferencesWindow:nil];
    [self.preferencesWindowController showAppRoutingWindow];
}

- (void)requestAccessibilityAccess:(id)sender {
    (void)sender;
    [self requestKeyboardAccess:nil];
}

- (void)requestKeyboardAccess:(id)sender {
    (void)sender;
    [self requestInputMonitoringAccessPrompting:YES];
    [self requestAccessibilityAccessPrompting:YES];
    [self setMenuItems];
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
    [self setMenuItems];
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

#pragma mark - Accessibility

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
    return [self hasAccessibilityAccess] || [self hasInputMonitoringAccess];
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

#pragma mark - Routing

- (FTMProfile *)effectiveTypingProfileForFrontmostApp {
    NSRunningApplication *frontmost = [[NSWorkspace sharedWorkspace] frontmostApplication];
    FTMProfile *assigned = [self.profileStore assignedProfileForBundleIdentifier:frontmost.bundleIdentifier ?: @""];
    if (assigned) {
        return assigned;
    }
    BOOL assignedAppsOnly = [[NSUserDefaults standardUserDefaults] boolForKey:FTMDefaultsKeyAssignedAppsOnly];
    if (assignedAppsOnly) {
        return nil;
    }
    return [self.profileStore activeProfile];
}

- (NSString *)currentRouteStatusTitle {
    NSRunningApplication *frontmost = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *appName = frontmost.localizedName.length ? frontmost.localizedName : (frontmost.bundleIdentifier.length ? frontmost.bundleIdentifier : @"(No Active App)");
    FTMProfile *assigned = [self.profileStore assignedProfileForBundleIdentifier:frontmost.bundleIdentifier ?: @""];
    if (assigned) {
        return [NSString stringWithFormat:@"Current App: %@ -> %@", appName, assigned.name ?: @"Profile"];
    }
    BOOL assignedAppsOnly = [[NSUserDefaults standardUserDefaults] boolForKey:FTMDefaultsKeyAssignedAppsOnly];
    if (assignedAppsOnly) {
        return [NSString stringWithFormat:@"Current App: %@ -> Silent (Unassigned)", appName];
    }
    FTMProfile *fallback = [self.profileStore activeProfile];
    return [NSString stringWithFormat:@"Current App: %@ -> Default (%@)", appName, fallback.name ?: @"Profile"];
}

enum {
    kVK_ANSI_L = 0x25,
    kVK_ANSI_K = 0x28,
};

@end
