#import <Cocoa/Cocoa.h>

#import "FTMProfileSystem.h"

NS_ASSUME_NONNULL_BEGIN

@interface FTMPreferencesWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@property (nonatomic, copy, nullable) void (^onProfilesChanged)(void);
@property (nonatomic, copy, nullable) void (^onSettingsChanged)(void);

- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore
                            importer:(FTMSoundPackImporter *)importer
                        soundResolver:(FTMSoundResolver *)soundResolver
                          soundPlayer:(FTMSoundPlayer *)soundPlayer;

- (void)presentWindow;
- (void)showAppRoutingWindow;
- (void)reloadAllUI;
@end

NS_ASSUME_NONNULL_END
