#import <Cocoa/Cocoa.h>

#import "FTMProfileSystem.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const FTMPreferencesSectionProfiles;
FOUNDATION_EXPORT NSString * const FTMPreferencesSectionLibrary;
FOUNDATION_EXPORT NSString * const FTMPreferencesSectionRouting;
FOUNDATION_EXPORT NSString * const FTMPreferencesSectionBehavior;

@protocol FTMPreferencesPermissionProviding <NSObject>
- (BOOL)isAccessibilityPermissionGranted;
- (BOOL)isInputMonitoringPermissionGranted;
- (void)requestAccessibilityPermission;
- (void)requestInputMonitoringPermission;
@end

@interface FTMPreferencesWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@property (nonatomic, copy, nullable) void (^onProfilesChanged)(void);
@property (nonatomic, copy, nullable) void (^onSettingsChanged)(void);

- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore
                            importer:(FTMSoundPackImporter *)importer
                        soundResolver:(FTMSoundResolver *)soundResolver
                          soundPlayer:(FTMSoundPlayer *)soundPlayer;
- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore
                            importer:(FTMSoundPackImporter *)importer
                        soundResolver:(FTMSoundResolver *)soundResolver
                          soundPlayer:(FTMSoundPlayer *)soundPlayer
                   permissionProvider:(nullable id<FTMPreferencesPermissionProviding>)permissionProvider;

- (void)presentWindow;
- (void)presentWindowSelectingSection:(nullable NSString *)sectionIdentifier;
- (void)reloadAllUI;
@end

NS_ASSUME_NONNULL_END
