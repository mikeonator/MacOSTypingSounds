#import "FTMPreferencesWindowController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

NSString * const FTMPreferencesSectionProfiles = @"profiles";
NSString * const FTMPreferencesSectionLibrary = @"library";
NSString * const FTMPreferencesSectionRouting = @"routing";
NSString * const FTMPreferencesSectionBehavior = @"behavior";

static NSString *FTMWarningsAlertBody(NSArray<NSString *> *warnings) {
    if (warnings.count == 0) {
        return @"";
    }
    NSUInteger maxLines = MIN((NSUInteger)10, warnings.count);
    NSArray<NSString *> *snippet = [warnings subarrayWithRange:NSMakeRange(0, maxLines)];
    NSString *body = [snippet componentsJoinedByString:@"\n"];
    if (warnings.count > maxLines) {
        body = [body stringByAppendingFormat:@"\n… and %lu more", (unsigned long)(warnings.count - maxLines)];
    }
    return [body stringByAppendingFormat:@"\n\nTotal warnings: %lu", (unsigned long)warnings.count];
}

static void FTMPresentWarningsAlert(NSArray<NSString *> *warnings, NSString *title) {
    if (warnings.count == 0) {
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = title ?: @"Warnings";
    alert.informativeText = FTMWarningsAlertBody(warnings);
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

static BOOL FTMHasVisibleSettingsWindow(void) {
    for (NSWindow *window in [NSApp windows]) {
        if (!window.isVisible) {
            continue;
        }
        if ((window.styleMask & NSWindowStyleMaskTitled) == 0) {
            continue;
        }
        return YES;
    }
    return NO;
}

static void FTMUpdateActivationPolicyForSettingsWindows(void) {
    NSApplicationActivationPolicy targetPolicy = FTMHasVisibleSettingsWindow()
        ? NSApplicationActivationPolicyRegular
        : NSApplicationActivationPolicyAccessory;
    [NSApp setActivationPolicy:targetPolicy];
}

static void FTMPresentSettingsWindow(NSWindow *window) {
    if (!window) {
        return;
    }
    window.hidesOnDeactivate = NO;
    window.collectionBehavior |= NSWindowCollectionBehaviorMoveToActiveSpace;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [window makeKeyAndOrderFront:nil];
    [window orderFrontRegardless];
    [NSApp activateIgnoringOtherApps:YES];
}

@interface FTMPreferencesWindowController ()
@property (nonatomic, strong) FTMProfileStore *profileStore;
@property (nonatomic, strong) FTMSoundPackImporter *importer;
@property (nonatomic, strong) FTMSoundResolver *soundResolver;
@property (nonatomic, strong) FTMSoundPlayer *soundPlayer;
@property (nonatomic, weak, nullable) id<FTMPreferencesPermissionProviding> permissionProvider;

@property (nonatomic, strong) NSTableView *sectionsTableView;
@property (nonatomic, strong) NSTableView *profilesTableView;
@property (nonatomic, strong) NSTableView *librarySlotsTableView;
@property (nonatomic, strong) NSTableView *libraryAssignedTableView;
@property (nonatomic, strong) NSTableView *libraryAssetsTableView;
@property (nonatomic, strong) NSTableView *routingTableView;

@property (nonatomic, strong) NSButton *muteCheckbox;
@property (nonatomic, strong) NSButton *assignedAppsOnlyCheckbox;

@property (nonatomic, strong) NSTextField *editingProfileLabel;
@property (nonatomic, strong) NSTextField *activeProfileLabel;
@property (nonatomic, strong) NSTextField *helpTextLabel;
@property (nonatomic, strong) NSTextField *profilesSummaryLabel;
@property (nonatomic, strong) NSTextField *routingSummaryLabel;
@property (nonatomic, strong) NSTextField *behaviorSummaryLabel;
@property (nonatomic, strong) NSTextField *libraryWarningLabel;
@property (nonatomic, strong) NSTextField *accessibilityStatusLabel;
@property (nonatomic, strong) NSTextField *inputMonitoringStatusLabel;
@property (nonatomic, strong) NSTextField *versionFooterLabel;

@property (nonatomic, strong) NSButton *setActiveButton;
@property (nonatomic, strong) NSButton *duplicateButton;
@property (nonatomic, strong) NSButton *renameButton;
@property (nonatomic, strong) NSButton *deleteButton;

@property (nonatomic, strong) NSButton *importFolderButton;
@property (nonatomic, strong) NSButton *addFilesButton;
@property (nonatomic, strong) NSButton *assignButton;
@property (nonatomic, strong) NSButton *unassignButton;
@property (nonatomic, strong) NSButton *deleteAssetsButton;
@property (nonatomic, strong) NSButton *clearSlotButton;
@property (nonatomic, strong) NSButton *previewSlotButton;
@property (nonatomic, strong) NSButton *previewAssetButton;
@property (nonatomic, strong) NSSegmentedControl *libraryFilterControl;

@property (nonatomic, strong) NSButton *addRoutingFromRunningAppsButton;
@property (nonatomic, strong) NSButton *addRoutingByBundleIDButton;
@property (nonatomic, strong) NSButton *changeRoutingProfileButton;
@property (nonatomic, strong) NSButton *removeRoutingRuleButton;

@property (nonatomic, strong) NSButton *requestAccessibilityButton;
@property (nonatomic, strong) NSButton *requestInputMonitoringButton;

@property (nonatomic, strong) NSArray<FTMProfile *> *profilesSnapshot;
@property (nonatomic, strong) NSArray<NSString *> *slotIDs;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *slotCounts;
@property (nonatomic, strong) NSArray<FTMProfileAsset *> *mappingAssignedAssets;
@property (nonatomic, strong) NSArray<FTMProfileAsset *> *mappingAllAssets;
@property (nonatomic, strong) NSArray<FTMProfileAsset *> *mappingLibraryAssets;
@property (nonatomic, strong) NSSet<NSString *> *mappingUnassignedAssetIDs;
@property (nonatomic, strong) NSArray<FTMAppProfileRule *> *routingRulesSnapshot;
@property (nonatomic, strong) NSArray<NSDictionary<NSString *, NSString *> *> *settingsSections;

@property (nonatomic, strong) NSView *sectionsContainerView;
@property (nonatomic, strong) NSView *profilesSectionView;
@property (nonatomic, strong) NSView *librarySectionView;
@property (nonatomic, strong) NSView *routingSectionView;
@property (nonatomic, strong) NSView *behaviorSectionView;
@end

@implementation FTMPreferencesWindowController

#pragma mark - Lifecycle

- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore
                            importer:(FTMSoundPackImporter *)importer
                        soundResolver:(FTMSoundResolver *)soundResolver
                          soundPlayer:(FTMSoundPlayer *)soundPlayer {
    return [self initWithProfileStore:profileStore
                             importer:importer
                         soundResolver:soundResolver
                           soundPlayer:soundPlayer
                    permissionProvider:nil];
}

- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore
                            importer:(FTMSoundPackImporter *)importer
                        soundResolver:(FTMSoundResolver *)soundResolver
                          soundPlayer:(FTMSoundPlayer *)soundPlayer
                   permissionProvider:(id<FTMPreferencesPermissionProviding>)permissionProvider {
    NSRect frame = NSMakeRect(0, 0, 1320, 780);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Preferences";
    window.releasedWhenClosed = NO;
    window.delegate = self;

    self = [super initWithWindow:window];
    if (self) {
        _profileStore = profileStore;
        _importer = importer;
        _soundResolver = soundResolver;
        _soundPlayer = soundPlayer;
        _permissionProvider = permissionProvider;
        _profilesSnapshot = @[];
        _slotIDs = FTMAllSoundSlotIDs();
        _slotCounts = @{};
        _mappingAssignedAssets = @[];
        _mappingAllAssets = @[];
        _mappingLibraryAssets = @[];
        _mappingUnassignedAssetIDs = [NSSet set];
        _routingRulesSnapshot = @[];
        _settingsSections = @[
            @{@"identifier": FTMPreferencesSectionProfiles, @"title": @"Profiles", @"symbol": @"person.3.fill"},
            @{@"identifier": FTMPreferencesSectionLibrary, @"title": @"Sounds Library", @"symbol": @"music.note.list"},
            @{@"identifier": FTMPreferencesSectionRouting, @"title": @"App Routing", @"symbol": @"arrow.triangle.branch"},
            @{@"identifier": FTMPreferencesSectionBehavior, @"title": @"App Behavior", @"symbol": @"gearshape.2.fill"},
        ];
        [self buildUI];
        [self reloadAllUI];
    }
    return self;
}

- (void)presentWindow {
    [self presentWindowSelectingSection:nil];
}

- (void)presentWindowSelectingSection:(NSString *)sectionIdentifier {
    [self reloadAllUI];
    if (sectionIdentifier.length > 0) {
        [self selectSectionWithIdentifier:sectionIdentifier];
    }
    [self showWindow:nil];
    FTMPresentSettingsWindow(self.window);
}

- (void)reloadAllUI {
    NSString *selectedProfileID = [self selectedProfile].profileID;
    NSString *activeProfileID = self.profileStore.activeProfile.profileID;

    self.profilesSnapshot = self.profileStore.profiles;
    [self.profilesTableView reloadData];

    NSInteger rowToSelect = [self rowForProfileID:selectedProfileID];
    if (rowToSelect < 0) {
        rowToSelect = [self rowForProfileID:activeProfileID];
    }
    if (rowToSelect >= 0) {
        [self.profilesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)rowToSelect] byExtendingSelection:NO];
    } else {
        [self.profilesTableView deselectAll:nil];
    }

    [self refreshProfileDependentUI];
    [self refreshGlobalSettingsUI];
}

#pragma mark - UI Construction

- (void)buildUI {
    NSView *content = self.window.contentView;
    CGFloat sidebarWidth = 226.0;

    NSView *sidebar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, sidebarWidth, NSHeight(content.bounds))];
    sidebar.autoresizingMask = NSViewHeightSizable;
    [content addSubview:sidebar];

    self.sectionsContainerView = [[NSView alloc] initWithFrame:NSMakeRect(sidebarWidth, 0, NSWidth(content.bounds) - sidebarWidth, NSHeight(content.bounds))];
    self.sectionsContainerView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:self.sectionsContainerView];

    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(sidebarWidth - 1, 0, 1, NSHeight(content.bounds))];
    divider.boxType = NSBoxSeparator;
    divider.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
    [content addSubview:divider];

    NSTextField *sidebarTitle = [self label:@"Settings" frame:NSMakeRect(16, NSHeight(sidebar.bounds) - 34, sidebarWidth - 32, 20) bold:YES];
    sidebarTitle.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [sidebar addSubview:sidebarTitle];

    NSScrollView *sectionsScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 14, sidebarWidth - 20, NSHeight(sidebar.bounds) - 58)];
    sectionsScroll.borderType = NSNoBorder;
    sectionsScroll.hasVerticalScroller = YES;
    sectionsScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.sectionsTableView = [[NSTableView alloc] initWithFrame:sectionsScroll.bounds];
    self.sectionsTableView.identifier = @"settingsSectionsTable";
    NSTableColumn *sectionColumn = [[NSTableColumn alloc] initWithIdentifier:@"section"];
    sectionColumn.width = NSWidth(sectionsScroll.bounds);
    [self.sectionsTableView addTableColumn:sectionColumn];
    self.sectionsTableView.headerView = nil;
    self.sectionsTableView.delegate = self;
    self.sectionsTableView.dataSource = self;
    self.sectionsTableView.rowHeight = 34.0;
    if (@available(macOS 11.0, *)) {
        self.sectionsTableView.style = NSTableViewStyleSourceList;
    }
    self.sectionsTableView.allowsEmptySelection = NO;
    sectionsScroll.documentView = self.sectionsTableView;
    [sidebar addSubview:sectionsScroll];

    NSRect sectionBounds = self.sectionsContainerView.bounds;
    self.profilesSectionView = [[NSView alloc] initWithFrame:sectionBounds];
    self.librarySectionView = [[NSView alloc] initWithFrame:sectionBounds];
    self.routingSectionView = [[NSView alloc] initWithFrame:sectionBounds];
    self.behaviorSectionView = [[NSView alloc] initWithFrame:sectionBounds];

    for (NSView *section in @[self.profilesSectionView, self.librarySectionView, self.routingSectionView, self.behaviorSectionView]) {
        section.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.sectionsContainerView addSubview:section];
    }

    [self buildProfilesSectionUI];
    [self buildSoundsLibrarySectionUI];
    [self buildRoutingSectionUI];
    [self buildBehaviorSectionUI];

    [self.sectionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self showSelectedSection];
}

- (void)buildProfilesSectionUI {
    NSView *section = self.profilesSectionView;
    CGFloat width = NSWidth(section.bounds);
    CGFloat top = NSHeight(section.bounds) - 34;

    [section addSubview:[self label:@"Profiles" frame:NSMakeRect(24, top, 240, 24) bold:YES]];

    self.profilesSummaryLabel = [self label:@"Built-in packs are editable, and only missing defaults are seeded on startup." frame:NSMakeRect(24, top - 28, width - 48, 18) bold:NO];
    self.profilesSummaryLabel.textColor = [NSColor secondaryLabelColor];
    self.profilesSummaryLabel.autoresizingMask = NSViewWidthSizable;
    [section addSubview:self.profilesSummaryLabel];

    self.activeProfileLabel = [self label:@"Default profile for unassigned apps: (none)" frame:NSMakeRect(24, top - 54, width - 48, 20) bold:NO];
    self.activeProfileLabel.autoresizingMask = NSViewWidthSizable;
    self.activeProfileLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.activeProfileLabel.usesSingleLineMode = YES;
    [section addSubview:self.activeProfileLabel];

    CGFloat profilesTableBottom = 172.0;
    CGFloat profilesTableTopPadding = 106.0;
    CGFloat profilesTableHeight = NSHeight(section.bounds) - profilesTableBottom - profilesTableTopPadding;
    if (profilesTableHeight < 180.0) {
        profilesTableHeight = 180.0;
    }

    NSScrollView *profilesScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, profilesTableBottom, width - 48, profilesTableHeight)];
    profilesScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    profilesScroll.hasVerticalScroller = YES;
    profilesScroll.borderType = NSBezelBorder;
    self.profilesTableView = [[NSTableView alloc] initWithFrame:profilesScroll.bounds];
    self.profilesTableView.identifier = @"profilesTable";

    NSTableColumn *profileCol = [[NSTableColumn alloc] initWithIdentifier:@"profile"];
    profileCol.title = @"Profile";
    profileCol.width = NSWidth(profilesScroll.bounds) - 20;
    [self.profilesTableView addTableColumn:profileCol];

    self.profilesTableView.headerView = nil;
    self.profilesTableView.delegate = self;
    self.profilesTableView.dataSource = self;
    self.profilesTableView.target = self;
    self.profilesTableView.doubleAction = @selector(handleSetActiveProfile:);
    profilesScroll.documentView = self.profilesTableView;
    [section addSubview:profilesScroll];

    NSButton *newButton = [self button:@"New" action:@selector(handleNewProfile:) frame:NSMakeRect(24, 130, 110, 30)];
    [self applySymbolNamed:@"plus" toButton:newButton];
    [section addSubview:newButton];

    self.duplicateButton = [self button:@"Duplicate" action:@selector(handleDuplicateProfile:) frame:NSMakeRect(140, 130, 130, 30)];
    [self applySymbolNamed:@"plus.square.on.square" toButton:self.duplicateButton];
    [section addSubview:self.duplicateButton];

    self.renameButton = [self button:@"Rename" action:@selector(handleRenameProfile:) frame:NSMakeRect(276, 130, 110, 30)];
    [self applySymbolNamed:@"pencil" toButton:self.renameButton];
    [section addSubview:self.renameButton];

    self.deleteButton = [self button:@"Delete" action:@selector(handleDeleteProfile:) frame:NSMakeRect(392, 130, 110, 30)];
    [self applySymbolNamed:@"trash" toButton:self.deleteButton];
    [section addSubview:self.deleteButton];

    NSButton *importPackButton = [self button:@"Import Pack…" action:@selector(handleImportProfile:) frame:NSMakeRect(24, 88, 150, 30)];
    [self applySymbolNamed:@"square.and.arrow.down" toButton:importPackButton];
    [section addSubview:importPackButton];

    self.setActiveButton = [self button:@"Set Active Default" action:@selector(handleSetActiveProfile:) frame:NSMakeRect(180, 88, 170, 30)];
    [self applySymbolNamed:@"checkmark.circle" toButton:self.setActiveButton];
    [section addSubview:self.setActiveButton];
}

- (void)buildSoundsLibrarySectionUI {
    NSView *section = self.librarySectionView;
    CGFloat width = NSWidth(section.bounds);
    CGFloat top = NSHeight(section.bounds) - 34;

    [section addSubview:[self label:@"Sounds Library" frame:NSMakeRect(24, top, 240, 24) bold:YES]];

    self.editingProfileLabel = [self label:@"Editing profile: (none)" frame:NSMakeRect(24, top - 28, width - 48, 20) bold:NO];
    self.editingProfileLabel.autoresizingMask = NSViewWidthSizable;
    self.editingProfileLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.editingProfileLabel.usesSingleLineMode = YES;
    [section addSubview:self.editingProfileLabel];

    self.helpTextLabel = [self wrappingLabel:@"Supported import types: mp3, wav, m4a, aiff, ogg. OGG files are converted to WAV on import. Imported files are kept in the profile library, and you can map or unmap them from slots below." frame:NSMakeRect(24, top - 70, width - 48, 40)];
    self.helpTextLabel.textColor = [NSColor secondaryLabelColor];
    self.helpTextLabel.autoresizingMask = NSViewWidthSizable;
    [section addSubview:self.helpTextLabel];

    self.libraryWarningLabel = [self label:@"" frame:NSMakeRect(24, top - 94, width - 48, 18) bold:NO];
    self.libraryWarningLabel.textColor = [NSColor secondaryLabelColor];
    self.libraryWarningLabel.autoresizingMask = NSViewWidthSizable;
    [section addSubview:self.libraryWarningLabel];

    [section addSubview:[self label:@"Slots" frame:NSMakeRect(24, top - 124, 180, 18) bold:YES]];
    [section addSubview:[self label:@"Assigned Assets (Selected Slot)" frame:NSMakeRect(302, top - 124, 260, 18) bold:YES]];
    [section addSubview:[self label:@"Profile Library" frame:NSMakeRect(652, top - 124, 220, 18) bold:YES]];

    self.libraryFilterControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(width - 320, top - 130, 296, 24)];
    self.libraryFilterControl.autoresizingMask = NSViewMinXMargin;
    self.libraryFilterControl.segmentCount = 3;
    [self.libraryFilterControl setLabel:@"All" forSegment:0];
    [self.libraryFilterControl setLabel:@"Unassigned" forSegment:1];
    [self.libraryFilterControl setLabel:@"Assigned" forSegment:2];
    self.libraryFilterControl.selectedSegment = 0;
    self.libraryFilterControl.target = self;
    self.libraryFilterControl.action = @selector(handleLibraryFilterChanged:);
    [section addSubview:self.libraryFilterControl];

    CGFloat tablesTopMargin = 154;
    CGFloat tablesBottom = 222;
    CGFloat availableHeight = NSHeight(section.bounds) - tablesTopMargin - tablesBottom;
    if (availableHeight < 260) {
        availableHeight = 260;
    }

    NSScrollView *slotsScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, tablesBottom, 258, availableHeight)];
    slotsScroll.autoresizingMask = NSViewHeightSizable;
    slotsScroll.hasVerticalScroller = YES;
    slotsScroll.borderType = NSBezelBorder;
    self.librarySlotsTableView = [[NSTableView alloc] initWithFrame:slotsScroll.bounds];
    self.librarySlotsTableView.identifier = @"librarySlotsTable";
    NSTableColumn *slotNameCol = [[NSTableColumn alloc] initWithIdentifier:@"slotName"];
    slotNameCol.title = @"Slot";
    slotNameCol.width = 186;
    [self.librarySlotsTableView addTableColumn:slotNameCol];
    NSTableColumn *slotCountCol = [[NSTableColumn alloc] initWithIdentifier:@"slotCount"];
    slotCountCol.title = @"Count";
    slotCountCol.width = 60;
    [self.librarySlotsTableView addTableColumn:slotCountCol];
    self.librarySlotsTableView.delegate = self;
    self.librarySlotsTableView.dataSource = self;
    slotsScroll.documentView = self.librarySlotsTableView;
    [section addSubview:slotsScroll];

    NSScrollView *assignedScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(302, tablesBottom, 334, availableHeight)];
    assignedScroll.autoresizingMask = NSViewHeightSizable;
    assignedScroll.hasVerticalScroller = YES;
    assignedScroll.borderType = NSBezelBorder;
    self.libraryAssignedTableView = [[NSTableView alloc] initWithFrame:assignedScroll.bounds];
    self.libraryAssignedTableView.identifier = @"libraryAssignedTable";
    NSTableColumn *assignedCol = [[NSTableColumn alloc] initWithIdentifier:@"assignedName"];
    assignedCol.title = @"File";
    assignedCol.width = 316;
    [self.libraryAssignedTableView addTableColumn:assignedCol];
    self.libraryAssignedTableView.delegate = self;
    self.libraryAssignedTableView.dataSource = self;
    assignedScroll.documentView = self.libraryAssignedTableView;
    [section addSubview:assignedScroll];

    NSScrollView *libraryScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(652, tablesBottom, width - 676, availableHeight)];
    libraryScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    libraryScroll.hasVerticalScroller = YES;
    libraryScroll.borderType = NSBezelBorder;
    self.libraryAssetsTableView = [[NSTableView alloc] initWithFrame:libraryScroll.bounds];
    self.libraryAssetsTableView.identifier = @"libraryAssetsTable";
    NSTableColumn *libraryCol = [[NSTableColumn alloc] initWithIdentifier:@"libraryName"];
    libraryCol.title = @"File";
    libraryCol.width = NSWidth(libraryScroll.bounds) - 20;
    [self.libraryAssetsTableView addTableColumn:libraryCol];
    self.libraryAssetsTableView.delegate = self;
    self.libraryAssetsTableView.dataSource = self;
    libraryScroll.documentView = self.libraryAssetsTableView;
    [section addSubview:libraryScroll];

    self.importFolderButton = [self button:@"Import Folder…" action:@selector(handleImportFolderToLibrary:) frame:NSMakeRect(24, 176, 132, 30)];
    [self applySymbolNamed:@"square.and.arrow.down" toButton:self.importFolderButton];
    [section addSubview:self.importFolderButton];

    self.addFilesButton = [self button:@"Add Files…" action:@selector(handleAddFilesToLibrary:) frame:NSMakeRect(162, 176, 108, 30)];
    [self applySymbolNamed:@"plus" toButton:self.addFilesButton];
    [section addSubview:self.addFilesButton];

    self.unassignButton = [self button:@"<- Unassign" action:@selector(handleUnassignFromSlot:) frame:NSMakeRect(302, 176, 114, 30)];
    [self applySymbolNamed:@"arrow.uturn.backward" toButton:self.unassignButton];
    [section addSubview:self.unassignButton];

    self.clearSlotButton = [self button:@"Clear Slot" action:@selector(handleClearSlot:) frame:NSMakeRect(422, 176, 102, 30)];
    [self applySymbolNamed:@"xmark.circle" toButton:self.clearSlotButton];
    [section addSubview:self.clearSlotButton];

    self.previewSlotButton = [self button:@"Preview Slot" action:@selector(handlePreviewSlot:) frame:NSMakeRect(530, 176, 110, 30)];
    [self applySymbolNamed:@"play.circle" toButton:self.previewSlotButton];
    [section addSubview:self.previewSlotButton];

    self.assignButton = [self button:@"Assign -> Slot" action:@selector(handleAssignToSlot:) frame:NSMakeRect(652, 176, 122, 30)];
    [self applySymbolNamed:@"arrow.right.circle" toButton:self.assignButton];
    [section addSubview:self.assignButton];

    self.deleteAssetsButton = [self button:@"Delete From Profile…" action:@selector(handleDeleteAssets:) frame:NSMakeRect(780, 176, 156, 30)];
    [self applySymbolNamed:@"trash" toButton:self.deleteAssetsButton];
    [section addSubview:self.deleteAssetsButton];

    self.previewAssetButton = [self button:@"Preview Asset" action:@selector(handlePreviewAsset:) frame:NSMakeRect(942, 176, 118, 30)];
    self.previewAssetButton.autoresizingMask = NSViewMinXMargin;
    [self applySymbolNamed:@"play.circle.fill" toButton:self.previewAssetButton];
    [section addSubview:self.previewAssetButton];
}

- (void)buildRoutingSectionUI {
    NSView *section = self.routingSectionView;
    CGFloat width = NSWidth(section.bounds);
    CGFloat top = NSHeight(section.bounds) - 34;

    [section addSubview:[self label:@"App Routing" frame:NSMakeRect(24, top, 240, 24) bold:YES]];

    self.routingSummaryLabel = [self label:@"App routing assignments: 0" frame:NSMakeRect(24, top - 30, width - 48, 18) bold:NO];
    self.routingSummaryLabel.autoresizingMask = NSViewWidthSizable;
    [section addSubview:self.routingSummaryLabel];

    NSTextField *desc = [self wrappingLabel:@"Assign specific apps to profiles. Unassigned apps use the active default profile unless \"assigned apps only\" mode is enabled." frame:NSMakeRect(24, top - 88, width - 48, 48)];
    desc.textColor = [NSColor secondaryLabelColor];
    desc.autoresizingMask = NSViewWidthSizable;
    [section addSubview:desc];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, 172, width - 48, NSHeight(section.bounds) - 286)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    self.routingTableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    self.routingTableView.identifier = @"routingTable";

    NSTableColumn *appCol = [[NSTableColumn alloc] initWithIdentifier:@"app"];
    appCol.title = @"App";
    appCol.width = 260;
    [self.routingTableView addTableColumn:appCol];

    NSTableColumn *bundleCol = [[NSTableColumn alloc] initWithIdentifier:@"bundle"];
    bundleCol.title = @"Bundle Identifier";
    bundleCol.width = 430;
    [self.routingTableView addTableColumn:bundleCol];

    NSTableColumn *profileCol = [[NSTableColumn alloc] initWithIdentifier:@"profile"];
    profileCol.title = @"Profile";
    profileCol.width = 260;
    [self.routingTableView addTableColumn:profileCol];

    self.routingTableView.delegate = self;
    self.routingTableView.dataSource = self;
    scroll.documentView = self.routingTableView;
    [section addSubview:scroll];

    self.addRoutingFromRunningAppsButton = [self button:@"Add From Running Apps…" action:@selector(handleAddFromRunningApps:) frame:NSMakeRect(24, 130, 172, 30)];
    [self applySymbolNamed:@"plus.circle" toButton:self.addRoutingFromRunningAppsButton];
    [section addSubview:self.addRoutingFromRunningAppsButton];

    self.addRoutingByBundleIDButton = [self button:@"Add By Bundle ID…" action:@selector(handleAddByBundleID:) frame:NSMakeRect(202, 130, 142, 30)];
    [self applySymbolNamed:@"plus.square.dashed" toButton:self.addRoutingByBundleIDButton];
    [section addSubview:self.addRoutingByBundleIDButton];

    self.changeRoutingProfileButton = [self button:@"Change Profile…" action:@selector(handleChangeProfile:) frame:NSMakeRect(350, 130, 130, 30)];
    [self applySymbolNamed:@"arrow.triangle.2.circlepath" toButton:self.changeRoutingProfileButton];
    [section addSubview:self.changeRoutingProfileButton];

    self.removeRoutingRuleButton = [self button:@"Remove Assignment" action:@selector(handleRemoveRule:) frame:NSMakeRect(486, 130, 142, 30)];
    [self applySymbolNamed:@"minus.circle" toButton:self.removeRoutingRuleButton];
    [section addSubview:self.removeRoutingRuleButton];
}

- (void)buildBehaviorSectionUI {
    NSView *section = self.behaviorSectionView;
    CGFloat width = NSWidth(section.bounds);
    CGFloat top = NSHeight(section.bounds) - 34;

    [section addSubview:[self label:@"App Behavior" frame:NSMakeRect(24, top, 220, 24) bold:YES]];

    self.behaviorSummaryLabel = [self wrappingLabel:@"Global behavior controls update immediately and affect typing, launch, and quit playback." frame:NSMakeRect(24, top - 56, width - 48, 40)];
    self.behaviorSummaryLabel.autoresizingMask = NSViewWidthSizable;
    [section addSubview:self.behaviorSummaryLabel];

    self.muteCheckbox = [self checkbox:@"Mute all sound effects" action:@selector(handleMuteToggle:) frame:NSMakeRect(24, top - 96, 300, 22)];
    [section addSubview:self.muteCheckbox];

    self.assignedAppsOnlyCheckbox = [self checkbox:@"Play sounds in assigned apps only" action:@selector(handleAssignedAppsOnlyToggle:) frame:NSMakeRect(24, top - 126, 340, 22)];
    [section addSubview:self.assignedAppsOnlyCheckbox];

    NSTextField *tip = [self wrappingLabel:@"Tip: Global key playback requires Accessibility and Input Monitoring permissions in System Settings > Privacy & Security." frame:NSMakeRect(24, top - 186, width - 48, 54)];
    tip.textColor = [NSColor secondaryLabelColor];
    tip.autoresizingMask = NSViewWidthSizable;
    [section addSubview:tip];

    self.accessibilityStatusLabel = [self label:@"Accessibility: Required" frame:NSMakeRect(24, top - 228, 340, 20) bold:NO];
    [section addSubview:self.accessibilityStatusLabel];

    self.requestAccessibilityButton = [self button:@"Request Accessibility…" action:@selector(handleRequestAccessibilityPermission:) frame:NSMakeRect(370, top - 234, 188, 30)];
    [self applySymbolNamed:@"figure.wave.circle" toButton:self.requestAccessibilityButton];
    [section addSubview:self.requestAccessibilityButton];

    self.inputMonitoringStatusLabel = [self label:@"Input Monitoring: Required" frame:NSMakeRect(24, top - 266, 340, 20) bold:NO];
    [section addSubview:self.inputMonitoringStatusLabel];

    self.requestInputMonitoringButton = [self button:@"Request Input Monitoring…" action:@selector(handleRequestInputMonitoringPermission:) frame:NSMakeRect(370, top - 272, 210, 30)];
    [self applySymbolNamed:@"keyboard" toButton:self.requestInputMonitoringButton];
    [section addSubview:self.requestInputMonitoringButton];

    NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(24, 42, width - 48, 1)];
    line.boxType = NSBoxSeparator;
    line.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [section addSubview:line];

    self.versionFooterLabel = [self label:@"" frame:NSMakeRect(24, 16, width - 48, 20) bold:NO];
    self.versionFooterLabel.alignment = NSTextAlignmentRight;
    self.versionFooterLabel.textColor = [NSColor secondaryLabelColor];
    self.versionFooterLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [section addSubview:self.versionFooterLabel];
}

- (void)showSelectedSection {
    NSInteger row = self.sectionsTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.settingsSections.count) {
        row = 0;
    }
    NSString *identifier = self.settingsSections[(NSUInteger)row][@"identifier"];

    self.profilesSectionView.hidden = ![identifier isEqualToString:FTMPreferencesSectionProfiles];
    self.librarySectionView.hidden = ![identifier isEqualToString:FTMPreferencesSectionLibrary];
    self.routingSectionView.hidden = ![identifier isEqualToString:FTMPreferencesSectionRouting];
    self.behaviorSectionView.hidden = ![identifier isEqualToString:FTMPreferencesSectionBehavior];
}

- (BOOL)selectSectionWithIdentifier:(NSString *)identifier {
    NSInteger row = [self rowForSectionIdentifier:identifier];
    if (row < 0) {
        return NO;
    }
    [self.sectionsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self showSelectedSection];
    return YES;
}

- (NSInteger)rowForSectionIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return -1;
    }
    for (NSUInteger idx = 0; idx < self.settingsSections.count; idx++) {
        if ([self.settingsSections[idx][@"identifier"] isEqualToString:identifier]) {
            return (NSInteger)idx;
        }
    }
    return -1;
}

#pragma mark - Control Helpers

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame bold:(BOOL)bold {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.stringValue = text ?: @"";
    label.usesSingleLineMode = YES;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    if (bold) {
        label.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
    }
    return label;
}

- (NSTextField *)wrappingLabel:(NSString *)text frame:(NSRect)frame {
    NSTextField *label = [self label:text frame:frame bold:NO];
    label.usesSingleLineMode = NO;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.allowsEditingTextAttributes = NO;
    if ([label cell]) {
        [[label cell] setWraps:YES];
        [[label cell] setScrollable:NO];
    }
    return label;
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.bezelStyle = NSBezelStyleRounded;
    button.title = title;
    button.target = self;
    button.action = action;
    return button;
}

- (NSButton *)checkbox:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *checkbox = [[NSButton alloc] initWithFrame:frame];
    checkbox.buttonType = NSButtonTypeSwitch;
    checkbox.title = title;
    checkbox.target = self;
    checkbox.action = action;
    return checkbox;
}

- (void)applySymbolNamed:(NSString *)symbolName toButton:(NSButton *)button {
    if (!button || symbolName.length == 0) {
        return;
    }
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:button.title];
        if (image) {
            image.size = NSMakeSize(13, 13);
            button.image = image;
            button.imagePosition = NSImageLeading;
        }
    }
}

#pragma mark - Data Helpers

- (nullable FTMProfile *)selectedProfile {
    NSInteger row = self.profilesTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.profilesSnapshot.count) {
        return nil;
    }
    return self.profilesSnapshot[(NSUInteger)row];
}

- (NSString *)selectedSlotID {
    NSInteger row = self.librarySlotsTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.slotIDs.count) {
        return self.slotIDs.firstObject ?: FTMSoundSlotTyping;
    }
    return self.slotIDs[(NSUInteger)row];
}

- (NSArray<FTMProfileAsset *> *)selectedLibraryAssets {
    NSIndexSet *indexes = self.libraryAssetsTableView.selectedRowIndexes;
    NSMutableArray<FTMProfileAsset *> *assets = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        (void)stop;
        if (idx < self.mappingLibraryAssets.count) {
            [assets addObject:self.mappingLibraryAssets[idx]];
        }
    }];
    return [assets copy];
}

- (NSArray<FTMProfileAsset *> *)selectedAssignedAssets {
    NSIndexSet *indexes = self.libraryAssignedTableView.selectedRowIndexes;
    NSMutableArray<FTMProfileAsset *> *assets = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        (void)stop;
        if (idx < self.mappingAssignedAssets.count) {
            [assets addObject:self.mappingAssignedAssets[idx]];
        }
    }];
    return [assets copy];
}

- (nullable FTMAppProfileRule *)selectedRoutingRule {
    NSInteger row = self.routingTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.routingRulesSnapshot.count) {
        return nil;
    }
    return self.routingRulesSnapshot[(NSUInteger)row];
}

- (NSInteger)rowForProfileID:(NSString *)profileID {
    if (profileID.length == 0) {
        return -1;
    }
    for (NSUInteger idx = 0; idx < self.profilesSnapshot.count; idx++) {
        if ([self.profilesSnapshot[idx].profileID isEqualToString:profileID]) {
            return (NSInteger)idx;
        }
    }
    return -1;
}

- (NSURL *)urlForAsset:(FTMProfileAsset *)asset inProfile:(FTMProfile *)profile {
    if (!asset || !profile) {
        return nil;
    }
    NSURL *profileDir = [self.profileStore profileDirectoryURLForProfile:profile];
    NSURL *assetsDir = [profileDir URLByAppendingPathComponent:@"Assets" isDirectory:YES];
    return [assetsDir URLByAppendingPathComponent:asset.storedFileName ?: @""];
}

#pragma mark - UI Refresh

- (void)refreshGlobalSettingsUI {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL muted = [defaults boolForKey:FTMDefaultsKeyMuted];
    BOOL assignedOnly = FTMReadAssignedAppsOnlyFromDefaults(defaults);

    self.muteCheckbox.state = muted ? NSControlStateValueOn : NSControlStateValueOff;
    self.assignedAppsOnlyCheckbox.state = assignedOnly ? NSControlStateValueOn : NSControlStateValueOff;

    self.behaviorSummaryLabel.stringValue = muted
        ? @"Sound effects are currently muted."
        : (assignedOnly
           ? @"Playback is enabled in assigned apps only."
           : @"Playback is enabled in all apps using the default profile for unassigned apps.");

    [self refreshPermissionStatusUI];

    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"3.0.0";
    self.versionFooterLabel.stringValue = [NSString stringWithFormat:@"MacOSTypingSounds v%@", version];
}

- (void)refreshProfileDependentUI {
    FTMProfile *selectedProfile = [self selectedProfile];
    FTMProfile *activeProfile = self.profileStore.activeProfile;

    self.profilesSummaryLabel.stringValue = [NSString stringWithFormat:@"%lu profile(s) available. Built-in defaults seed only when missing.", (unsigned long)self.profilesSnapshot.count];
    self.editingProfileLabel.stringValue = [NSString stringWithFormat:@"Editing profile: %@", selectedProfile.name ?: @"(none)"];
    self.activeProfileLabel.stringValue = [NSString stringWithFormat:@"Default profile for unassigned apps: %@", activeProfile.name ?: @"(none)"];

    NSString *selectedSlotID = [self selectedSlotID];
    self.slotCounts = [self.profileStore slotFileCountsForProfile:selectedProfile];
    [self.librarySlotsTableView reloadData];

    NSUInteger slotIndex = [self.slotIDs indexOfObject:selectedSlotID];
    if (slotIndex == NSNotFound) {
        slotIndex = 0;
    }
    if (self.slotIDs.count > 0) {
        [self.librarySlotsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:slotIndex] byExtendingSelection:NO];
    } else {
        [self.librarySlotsTableView deselectAll:nil];
    }

    [self reloadMappingAssignedAssets];
    [self reloadMappingLibraryAssets];
    [self reloadRoutingSnapshot];

    NSUInteger typingCount = [self.profileStore assignedAssetsForSlotID:FTMSoundSlotTyping profile:selectedProfile].count;
    self.libraryWarningLabel.stringValue = (selectedProfile && typingCount == 0)
        ? @"Typing slot is empty. Playback falls back to bundled typing sounds."
        : @"";

    [self updateButtonStates];
}

- (void)reloadMappingAssignedAssets {
    FTMProfile *selectedProfile = [self selectedProfile];
    self.mappingAssignedAssets = [self.profileStore assignedAssetsForSlotID:[self selectedSlotID] profile:selectedProfile];
    [self.libraryAssignedTableView reloadData];
}

- (void)reloadMappingLibraryAssets {
    FTMProfile *selectedProfile = [self selectedProfile];
    NSArray<FTMProfileAsset *> *allAssets = [self.profileStore assetsForProfile:selectedProfile];
    NSArray<FTMProfileAsset *> *unassignedAssets = [self.profileStore unassignedAssetsForProfile:selectedProfile];
    NSSet<NSString *> *unassignedAssetIDs = [NSSet setWithArray:[unassignedAssets valueForKey:@"assetID"]];

    NSInteger filter = self.libraryFilterControl.selectedSegment;
    NSMutableArray<FTMProfileAsset *> *filteredAssets = [NSMutableArray array];
    for (FTMProfileAsset *asset in allAssets) {
        BOOL isUnassigned = [unassignedAssetIDs containsObject:asset.assetID];
        if (filter == 1 && !isUnassigned) {
            continue;
        }
        if (filter == 2 && isUnassigned) {
            continue;
        }
        [filteredAssets addObject:asset];
    }

    self.mappingAllAssets = allAssets;
    self.mappingUnassignedAssetIDs = unassignedAssetIDs;
    self.mappingLibraryAssets = [filteredAssets copy];
    [self.libraryAssetsTableView reloadData];
}

- (void)reloadRoutingSnapshot {
    self.routingRulesSnapshot = [[self.profileStore appRules] sortedArrayUsingComparator:^NSComparisonResult(FTMAppProfileRule *a, FTMAppProfileRule *b) {
        NSString *aName = a.appNameHint.length ? a.appNameHint : a.bundleIdentifier;
        NSString *bName = b.appNameHint.length ? b.appNameHint : b.bundleIdentifier;
        return [aName localizedCaseInsensitiveCompare:bName];
    }];
    self.routingSummaryLabel.stringValue = [NSString stringWithFormat:@"App routing assignments: %lu", (unsigned long)self.routingRulesSnapshot.count];
    [self.routingTableView reloadData];
    [self updateRoutingButtons];
}

- (void)refreshPermissionStatusUI {
    BOOL accessibilityGranted = [self isAccessibilityPermissionGranted];
    BOOL inputMonitoringGranted = [self isInputMonitoringPermissionGranted];

    self.accessibilityStatusLabel.stringValue = [NSString stringWithFormat:@"Accessibility: %@", accessibilityGranted ? @"Granted" : @"Required"];
    self.inputMonitoringStatusLabel.stringValue = [NSString stringWithFormat:@"Input Monitoring: %@", inputMonitoringGranted ? @"Granted" : @"Required"];

    if (@available(macOS 10.10, *)) {
        self.accessibilityStatusLabel.textColor = accessibilityGranted ? [NSColor systemGreenColor] : [NSColor systemRedColor];
        self.inputMonitoringStatusLabel.textColor = inputMonitoringGranted ? [NSColor systemGreenColor] : [NSColor systemRedColor];
    }

    self.requestAccessibilityButton.enabled = !accessibilityGranted;
    self.requestInputMonitoringButton.enabled = !inputMonitoringGranted;
}

- (void)updateButtonStates {
    FTMProfile *selectedProfile = [self selectedProfile];
    BOOL hasProfile = (selectedProfile != nil);
    BOOL selectedProfileIsActive = hasProfile && [selectedProfile.profileID isEqualToString:self.profileStore.activeProfile.profileID];

    self.duplicateButton.enabled = hasProfile;
    self.renameButton.enabled = hasProfile;
    self.deleteButton.enabled = hasProfile;
    self.setActiveButton.enabled = hasProfile && !selectedProfileIsActive;

    BOOL hasLibrarySelection = (self.libraryAssetsTableView.selectedRowIndexes.count > 0);
    BOOL hasAssignedSelection = (self.libraryAssignedTableView.selectedRowIndexes.count > 0);
    BOOL slotHasAssignments = (self.mappingAssignedAssets.count > 0);
    BOOL canPreviewSlot = hasProfile && ([self.soundResolver randomSoundPathForSlotID:[self selectedSlotID] profile:selectedProfile].length > 0);
    BOOL canPreviewAsset = hasProfile && ([self selectedLibraryAssets].count > 0);

    self.importFolderButton.enabled = hasProfile;
    self.addFilesButton.enabled = hasProfile;
    self.assignButton.enabled = hasProfile && hasLibrarySelection;
    self.unassignButton.enabled = hasProfile && hasAssignedSelection;
    self.deleteAssetsButton.enabled = hasProfile && hasLibrarySelection;
    self.clearSlotButton.enabled = hasProfile && slotHasAssignments;
    self.previewSlotButton.enabled = canPreviewSlot;
    self.previewAssetButton.enabled = canPreviewAsset;

    BOOL hasProfilesForRouting = (self.profilesSnapshot.count > 0);
    self.addRoutingFromRunningAppsButton.enabled = hasProfilesForRouting;
    self.addRoutingByBundleIDButton.enabled = hasProfilesForRouting;
    [self updateRoutingButtons];
}

- (void)updateRoutingButtons {
    BOOL hasSelection = (self.routingTableView.selectedRow >= 0 && self.routingTableView.selectedRow < (NSInteger)self.routingRulesSnapshot.count);
    self.changeRoutingProfileButton.enabled = hasSelection;
    self.removeRoutingRuleButton.enabled = hasSelection;
}

#pragma mark - Profile Actions

- (void)handleNewProfile:(id)sender {
    (void)sender;
    NSString *name = [self promptForTextWithTitle:@"New Profile"
                                          message:@"Enter a name for the new profile:"
                                     defaultValue:@"New Profile"];
    if (!name) {
        return;
    }

    NSError *error = nil;
    FTMProfile *profile = [self.profileStore createEmptyProfileNamed:name error:&error];
    if (!profile) {
        [self showErrorAlert:error title:@"Create Profile Failed"];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handleDuplicateProfile:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) {
        return;
    }

    NSError *error = nil;
    FTMProfile *copy = [self.profileStore duplicateProfile:profile error:&error];
    if (!copy) {
        [self showErrorAlert:error title:@"Duplicate Profile Failed"];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:copy.profileID invalidateResolver:YES];
}

- (void)handleRenameProfile:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) {
        return;
    }

    NSString *name = [self promptForTextWithTitle:@"Rename Profile"
                                          message:@"Enter a new name:"
                                     defaultValue:profile.name ?: @"Profile"];
    if (!name) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore renameProfile:profile toName:name error:&error]) {
        [self showErrorAlert:error title:@"Rename Profile Failed"];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:NO];
}

- (void)handleDeleteProfile:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Delete Profile?";
    alert.informativeText = [NSString stringWithFormat:@"Delete '%@' and all imported sounds in this profile?", profile.name ?: @"Profile"];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    NSError *error = nil;
    NSString *deletedID = profile.profileID;
    if (![self.profileStore deleteProfile:profile error:&error]) {
        [self showErrorAlert:error title:@"Delete Profile Failed"];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:deletedID invalidateResolver:YES];
}

- (void)handleImportProfile:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"Import";
    panel.message = @"Choose a soundpack folder. Audio files import recursively into a new profile library.";

    if ([panel runModal] != NSModalResponseOK) {
        return;
    }

    NSArray<NSString *> *warnings = nil;
    NSError *error = nil;
    FTMProfile *profile = [self.profileStore importProfileFromFolderURL:panel.URL importer:self.importer warnings:&warnings error:&error];
    if (!profile) {
        [self showErrorAlert:error title:@"Import Pack Failed"];
        return;
    }

    if (warnings.count) {
        NSString *title = [NSString stringWithFormat:@"Imported '%@' With Warnings", profile.name ?: @"Profile"];
        [self presentWarnings:warnings title:title];
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handleSetActiveProfile:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore setActiveProfileID:profile.profileID error:&error]) {
        [self showErrorAlert:error title:@"Set Active Profile Failed"];
        return;
    }

    if (self.onProfilesChanged) {
        self.onProfilesChanged();
    }
    [self reloadAllUI];
}

#pragma mark - Sounds Library Actions

- (void)handleLibraryFilterChanged:(id)sender {
    (void)sender;
    [self reloadMappingLibraryAssets];
    [self updateButtonStates];
}

- (void)handleImportFolderToLibrary:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) {
        return;
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Import a soundpack folder. Audio files are imported recursively as profile-library assets.";

    if ([panel runModal] != NSModalResponseOK) {
        return;
    }

    NSArray<NSString *> *warnings = nil;
    NSError *error = nil;
    if (![self.profileStore importAudioFolderFlat:panel.URL intoProfile:profile importer:self.importer warnings:&warnings error:&error]) {
        [self showErrorAlert:error title:@"Import Folder Failed"];
        return;
    }

    if (warnings.count) {
        NSString *title = [NSString stringWithFormat:@"Imported '%@' With Warnings", profile.name ?: @"Profile"];
        [self presentWarnings:warnings title:title];
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handleAddFilesToLibrary:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) {
        return;
    }

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;

    NSMutableArray<UTType *> *types = [NSMutableArray array];
    for (NSString *extension in FTMSupportedImportExtensions()) {
        UTType *type = [UTType typeWithFilenameExtension:extension];
        if (type) {
            [types addObject:type];
        }
    }
    panel.allowedContentTypes = types;
    panel.message = @"Add one or more audio files to the profile library.";

    if ([panel runModal] != NSModalResponseOK) {
        return;
    }

    NSArray<NSString *> *warnings = nil;
    NSError *error = nil;
    if (![self.profileStore addAudioFilesToProfileLibrary:panel.URLs profile:profile importer:self.importer warnings:&warnings error:&error]) {
        [self showErrorAlert:error title:@"Add Files Failed"];
        return;
    }

    if (warnings.count) {
        NSString *title = [NSString stringWithFormat:@"Added Files to '%@' With Warnings", profile.name ?: @"Profile"];
        [self presentWarnings:warnings title:title];
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handleAssignToSlot:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    NSArray<FTMProfileAsset *> *assets = [self selectedLibraryAssets];
    if (!profile || assets.count == 0) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore assignAssetIDs:[assets valueForKey:@"assetID"]
                                  toSlotID:[self selectedSlotID]
                                   profile:profile
                                     error:&error]) {
        [self showErrorAlert:error title:@"Assign Failed"];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handleUnassignFromSlot:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    NSArray<FTMProfileAsset *> *assets = [self selectedAssignedAssets];
    if (!profile || assets.count == 0) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore unassignAssetIDs:[assets valueForKey:@"assetID"]
                                  fromSlotID:[self selectedSlotID]
                                     profile:profile
                                       error:&error]) {
        [self showErrorAlert:error title:@"Unassign Failed"];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handleDeleteAssets:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    NSArray<FTMProfileAsset *> *assets = [self selectedLibraryAssets];
    if (!profile || assets.count == 0) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Delete Assets From Profile?";
    alert.informativeText = [NSString stringWithFormat:@"Delete %lu sound file(s) from '%@'? Any slot assignments using them will be removed.", (unsigned long)assets.count, profile.name ?: @"Profile"];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore deleteAssetIDsFromProfile:[assets valueForKey:@"assetID"] profile:profile error:&error]) {
        [self showErrorAlert:error title:@"Delete Assets Failed"];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handleClearSlot:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    NSString *slotID = [self selectedSlotID];
    if (!profile) {
        return;
    }

    if (self.mappingAssignedAssets.count > 1) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Clear Slot?";
        alert.informativeText = [NSString stringWithFormat:@"Remove %lu assignment(s) from %@? Files remain in the profile library.", (unsigned long)self.mappingAssignedAssets.count, FTMDisplayNameForSoundSlot(slotID)];
        [alert addButtonWithTitle:@"Clear"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return;
        }
    }

    NSError *error = nil;
    if (![self.profileStore clearSlotID:slotID profile:profile importer:self.importer error:&error]) {
        [self showErrorAlert:error title:@"Clear Slot Failed"];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handlePreviewSlot:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) {
        return;
    }
    NSString *path = [self.soundResolver randomSoundPathForSlotID:[self selectedSlotID] profile:profile];
    [self.soundPlayer playSoundAtPath:path];
}

- (void)handlePreviewAsset:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    FTMProfileAsset *asset = [self selectedLibraryAssets].firstObject;
    if (!profile || !asset) {
        return;
    }
    NSURL *assetURL = [self urlForAsset:asset inProfile:profile];
    [self.soundPlayer playSoundAtPath:assetURL.path];
}

#pragma mark - App Routing Actions

- (NSString *)promptForTextWithTitle:(NSString *)title message:(NSString *)message defaultValue:(NSString *)defaultValue {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"Input";
    alert.informativeText = message ?: @"";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 360, 24)];
    field.stringValue = defaultValue ?: @"";
    alert.accessoryView = field;

    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return nil;
    }

    NSString *trimmed = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length ? trimmed : nil;
}

- (nullable NSString *)chooseProfileIDWithTitle:(NSString *)title currentProfileID:(NSString *)currentProfileID {
    if (self.profileStore.profiles.count == 0) {
        return nil;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"Choose Profile";
    alert.informativeText = @"Select a profile for this app.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 320, 26) pullsDown:NO];
    for (FTMProfile *profile in self.profileStore.profiles) {
        [popup addItemWithTitle:profile.name ?: @"Profile"];
        popup.lastItem.representedObject = profile.profileID;
        if ([profile.profileID isEqualToString:currentProfileID]) {
            [popup selectItem:popup.lastItem];
        }
    }

    alert.accessoryView = popup;
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return nil;
    }

    return popup.selectedItem.representedObject;
}

- (void)showSimpleInfo:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"App Routing";
    alert.informativeText = message ?: @"";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)handleAddByBundleID:(id)sender {
    (void)sender;
    NSString *bundleID = [self promptForTextWithTitle:@"Add App Routing Rule"
                                              message:@"Enter the app bundle identifier (for example com.apple.Terminal):"
                                         defaultValue:@""];
    if (!bundleID) {
        return;
    }

    NSString *appName = [self promptForTextWithTitle:@"App Name (Optional)"
                                             message:@"Display name shown in the routing list:"
                                        defaultValue:@""];

    NSString *profileID = [self chooseProfileIDWithTitle:@"Assign Profile" currentProfileID:nil];
    if (!profileID) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore setAppRuleForBundleIdentifier:bundleID appNameHint:appName profileID:profileID error:&error]) {
        [self showErrorAlert:error title:@"Save Assignment Failed"];
        return;
    }

    [self.soundResolver invalidateCache];
    [self reloadRoutingSnapshot];
    if (self.onProfilesChanged) {
        self.onProfilesChanged();
    }
}

- (void)handleAddFromRunningApps:(id)sender {
    (void)sender;
    NSString *ownBundleID = [[[NSBundle mainBundle] bundleIdentifier] lowercaseString] ?: @"";

    NSArray<NSRunningApplication *> *running = [[[NSWorkspace sharedWorkspace] runningApplications] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSRunningApplication * _Nullable app, NSDictionary<NSString *,id> * _Nullable bindings) {
        (void)bindings;
        if (!app.bundleIdentifier.length) {
            return NO;
        }
        if ([[app.bundleIdentifier lowercaseString] isEqualToString:ownBundleID]) {
            return NO;
        }
        return YES;
    }]];

    if (running.count == 0) {
        [self showSimpleInfo:@"No running apps with bundle IDs were found."];
        return;
    }

    NSArray<NSRunningApplication *> *sorted = [running sortedArrayUsingComparator:^NSComparisonResult(NSRunningApplication *a, NSRunningApplication *b) {
        NSString *aName = a.localizedName ?: a.bundleIdentifier ?: @"";
        NSString *bName = b.localizedName ?: b.bundleIdentifier ?: @"";
        return [aName localizedCaseInsensitiveCompare:bName];
    }];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Add From Running Apps";
    alert.informativeText = @"Choose a running app to assign.";
    [alert addButtonWithTitle:@"Next"];
    [alert addButtonWithTitle:@"Cancel"];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 460, 26) pullsDown:NO];
    for (NSRunningApplication *app in sorted) {
        NSString *label = [NSString stringWithFormat:@"%@ (%@)", app.localizedName ?: @"App", app.bundleIdentifier ?: @""];
        [popup addItemWithTitle:label];
        popup.lastItem.representedObject = app;
    }
    alert.accessoryView = popup;

    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    NSRunningApplication *selectedApp = popup.selectedItem.representedObject;
    if (!selectedApp.bundleIdentifier.length) {
        return;
    }

    FTMAppProfileRule *existingRule = [self.profileStore appRuleForBundleIdentifier:selectedApp.bundleIdentifier];
    NSString *profileID = [self chooseProfileIDWithTitle:@"Assign Profile" currentProfileID:existingRule.profileID];
    if (!profileID) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore setAppRuleForBundleIdentifier:selectedApp.bundleIdentifier
                                               appNameHint:selectedApp.localizedName
                                                 profileID:profileID
                                                     error:&error]) {
        [self showErrorAlert:error title:@"Save Assignment Failed"];
        return;
    }

    [self.soundResolver invalidateCache];
    [self reloadRoutingSnapshot];
    if (self.onProfilesChanged) {
        self.onProfilesChanged();
    }
}

- (void)handleChangeProfile:(id)sender {
    (void)sender;
    FTMAppProfileRule *rule = [self selectedRoutingRule];
    if (!rule) {
        return;
    }

    NSString *profileID = [self chooseProfileIDWithTitle:@"Change Assigned Profile" currentProfileID:rule.profileID];
    if (!profileID) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore setAppRuleForBundleIdentifier:rule.bundleIdentifier
                                               appNameHint:rule.appNameHint
                                                 profileID:profileID
                                                     error:&error]) {
        [self showErrorAlert:error title:@"Change Assignment Failed"];
        return;
    }

    [self.soundResolver invalidateCache];
    [self reloadRoutingSnapshot];
    if (self.onProfilesChanged) {
        self.onProfilesChanged();
    }
}

- (void)handleRemoveRule:(id)sender {
    (void)sender;
    FTMAppProfileRule *rule = [self selectedRoutingRule];
    if (!rule) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Remove App Assignment?";
    alert.informativeText = [NSString stringWithFormat:@"Remove the profile assignment for %@?", rule.appNameHint.length ? rule.appNameHint : rule.bundleIdentifier];
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore removeAppRuleForBundleIdentifier:rule.bundleIdentifier error:&error]) {
        [self showErrorAlert:error title:@"Remove Assignment Failed"];
        return;
    }

    [self.soundResolver invalidateCache];
    [self reloadRoutingSnapshot];
    if (self.onProfilesChanged) {
        self.onProfilesChanged();
    }
}

#pragma mark - App Behavior Actions

- (void)handleMuteToggle:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:(self.muteCheckbox.state == NSControlStateValueOn)
                                            forKey:FTMDefaultsKeyMuted];
    [self refreshGlobalSettingsUI];
    if (self.onSettingsChanged) {
        self.onSettingsChanged();
    }
}

- (void)handleAssignedAppsOnlyToggle:(id)sender {
    (void)sender;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    FTMWriteAssignedAppsOnlyToDefaults(defaults, (self.assignedAppsOnlyCheckbox.state == NSControlStateValueOn));
    [self.soundResolver invalidateCache];
    [self refreshGlobalSettingsUI];
    if (self.onSettingsChanged) {
        self.onSettingsChanged();
    }
}

- (void)handleRequestAccessibilityPermission:(id)sender {
    (void)sender;
    if ([self.permissionProvider respondsToSelector:@selector(requestAccessibilityPermission)]) {
        [self.permissionProvider requestAccessibilityPermission];
    }
    [self refreshGlobalSettingsUI];
    if (self.onSettingsChanged) {
        self.onSettingsChanged();
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshGlobalSettingsUI];
        if (self.onSettingsChanged) {
            self.onSettingsChanged();
        }
    });
}

- (void)handleRequestInputMonitoringPermission:(id)sender {
    (void)sender;
    if ([self.permissionProvider respondsToSelector:@selector(requestInputMonitoringPermission)]) {
        [self.permissionProvider requestInputMonitoringPermission];
    }
    [self refreshGlobalSettingsUI];
    if (self.onSettingsChanged) {
        self.onSettingsChanged();
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshGlobalSettingsUI];
        if (self.onSettingsChanged) {
            self.onSettingsChanged();
        }
    });
}

- (BOOL)isAccessibilityPermissionGranted {
    if ([self.permissionProvider respondsToSelector:@selector(isAccessibilityPermissionGranted)]) {
        return [self.permissionProvider isAccessibilityPermissionGranted];
    }
    return NO;
}

- (BOOL)isInputMonitoringPermissionGranted {
    if ([self.permissionProvider respondsToSelector:@selector(isInputMonitoringPermissionGranted)]) {
        return [self.permissionProvider isInputMonitoringPermissionGranted];
    }
    return NO;
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.sectionsTableView) {
        return (NSInteger)self.settingsSections.count;
    }
    if (tableView == self.profilesTableView) {
        return (NSInteger)self.profilesSnapshot.count;
    }
    if (tableView == self.librarySlotsTableView) {
        return (NSInteger)self.slotIDs.count;
    }
    if (tableView == self.libraryAssignedTableView) {
        return (NSInteger)self.mappingAssignedAssets.count;
    }
    if (tableView == self.libraryAssetsTableView) {
        return (NSInteger)self.mappingLibraryAssets.count;
    }
    if (tableView == self.routingTableView) {
        return (NSInteger)self.routingRulesSnapshot.count;
    }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    return [self stringValueForTableView:tableView tableColumn:tableColumn row:row];
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row {
    if (!tableColumn) {
        return nil;
    }

    if (tableView == self.sectionsTableView) {
        if (row < 0 || row >= (NSInteger)self.settingsSections.count) {
            return nil;
        }

        static NSString * const sectionCellID = @"SettingsSectionCell";
        NSTableCellView *cell = [tableView makeViewWithIdentifier:sectionCellID owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableView.bounds.size.width, tableView.rowHeight)];
            cell.identifier = sectionCellID;

            NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(8, 8, 18, 18)];
            iconView.imageScaling = NSImageScaleProportionallyDown;
            iconView.autoresizingMask = NSViewMaxXMargin;
            cell.imageView = iconView;
            [cell addSubview:iconView];

            NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(32, 7, tableView.bounds.size.width - 42, 20)];
            textField.bezeled = NO;
            textField.drawsBackground = NO;
            textField.editable = NO;
            textField.selectable = NO;
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            textField.autoresizingMask = NSViewWidthSizable;
            cell.textField = textField;
            [cell addSubview:textField];
        }

        NSDictionary<NSString *, NSString *> *section = self.settingsSections[(NSUInteger)row];
        cell.textField.stringValue = section[@"title"] ?: @"";
        if (@available(macOS 11.0, *)) {
            NSString *symbolName = section[@"symbol"];
            cell.imageView.image = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:section[@"title"]];
        } else {
            cell.imageView.image = nil;
        }
        return cell;
    }

    NSString *identifier = [NSString stringWithFormat:@"%@.%@", tableView.identifier ?: @"table", tableColumn.identifier ?: @"col"];
    NSTableCellView *cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, tableColumn.width, tableView.rowHeight)];
        cell.identifier = identifier;

        NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(6, 1, tableColumn.width - 10, tableView.rowHeight - 2)];
        textField.bezeled = NO;
        textField.drawsBackground = NO;
        textField.editable = NO;
        textField.selectable = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        textField.usesSingleLineMode = YES;
        textField.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        cell.textField = textField;
        [cell addSubview:textField];
    }

    cell.textField.stringValue = [self stringValueForTableView:tableView tableColumn:tableColumn row:row] ?: @"";
    return cell;
}

- (NSString *)stringValueForTableView:(NSTableView *)tableView
                          tableColumn:(NSTableColumn *)tableColumn
                                  row:(NSInteger)row {
    if (tableView == self.sectionsTableView) {
        if (row < 0 || row >= (NSInteger)self.settingsSections.count) {
            return @"";
        }
        return self.settingsSections[(NSUInteger)row][@"title"] ?: @"";
    }

    if (tableView == self.profilesTableView) {
        if (row < 0 || row >= (NSInteger)self.profilesSnapshot.count) {
            return @"";
        }
        FTMProfile *profile = self.profilesSnapshot[(NSUInteger)row];
        BOOL isActive = [profile.profileID isEqualToString:self.profileStore.activeProfile.profileID];
        NSString *name = profile.name ?: @"Profile";
        return isActive ? [NSString stringWithFormat:@"%@ ✓", name] : name;
    }

    if (tableView == self.librarySlotsTableView) {
        if (row < 0 || row >= (NSInteger)self.slotIDs.count) {
            return @"";
        }
        NSString *slotID = self.slotIDs[(NSUInteger)row];
        if ([tableColumn.identifier isEqualToString:@"slotCount"]) {
            return [NSString stringWithFormat:@"%@", self.slotCounts[slotID] ?: @0];
        }
        return FTMDisplayNameForSoundSlot(slotID);
    }

    if (tableView == self.libraryAssignedTableView) {
        if (row < 0 || row >= (NSInteger)self.mappingAssignedAssets.count) {
            return @"";
        }
        FTMProfileAsset *asset = self.mappingAssignedAssets[(NSUInteger)row];
        return asset.displayName.length ? asset.displayName : (asset.storedFileName ?: @"");
    }

    if (tableView == self.libraryAssetsTableView) {
        if (row < 0 || row >= (NSInteger)self.mappingLibraryAssets.count) {
            return @"";
        }
        FTMProfileAsset *asset = self.mappingLibraryAssets[(NSUInteger)row];
        BOOL isUnassigned = [self.mappingUnassignedAssetIDs containsObject:asset.assetID];
        NSString *name = asset.displayName.length ? asset.displayName : (asset.storedFileName ?: @"");
        return isUnassigned ? [NSString stringWithFormat:@"%@ (Unassigned)", name] : name;
    }

    if (tableView == self.routingTableView) {
        if (row < 0 || row >= (NSInteger)self.routingRulesSnapshot.count) {
            return @"";
        }

        FTMAppProfileRule *rule = self.routingRulesSnapshot[(NSUInteger)row];
        if ([tableColumn.identifier isEqualToString:@"app"]) {
            return rule.appNameHint.length ? rule.appNameHint : @"(Unknown)";
        }
        if ([tableColumn.identifier isEqualToString:@"bundle"]) {
            return rule.bundleIdentifier ?: @"";
        }
        if ([tableColumn.identifier isEqualToString:@"profile"]) {
            FTMProfile *profile = [self.profileStore assignedProfileForBundleIdentifier:rule.bundleIdentifier];
            return profile.name.length ? profile.name : (rule.profileID ?: @"");
        }
    }

    return @"";
}

#pragma mark - Table View Delegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tableView = notification.object;
    if (tableView == self.sectionsTableView) {
        [self showSelectedSection];
        return;
    }

    if (tableView == self.profilesTableView) {
        [self refreshProfileDependentUI];
        return;
    }

    if (tableView == self.librarySlotsTableView) {
        [self reloadMappingAssignedAssets];
        [self updateButtonStates];
        return;
    }

    if (tableView == self.libraryAssignedTableView || tableView == self.libraryAssetsTableView) {
        [self updateButtonStates];
        return;
    }

    if (tableView == self.routingTableView) {
        [self updateRoutingButtons];
        return;
    }
}

#pragma mark - Utilities

- (void)notifyProfilesChangedAndReloadSelectingProfileID:(NSString *)profileID
                                        invalidateResolver:(BOOL)invalidateResolver {
    if (invalidateResolver) {
        [self.soundResolver invalidateCache];
    }
    if (self.onProfilesChanged) {
        self.onProfilesChanged();
    }

    [self reloadAllUI];

    NSInteger row = [self rowForProfileID:profileID];
    if (row >= 0) {
        [self.profilesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    }
}

- (void)showErrorAlert:(NSError *)error title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title ?: @"Action Failed";
    alert.informativeText = error.localizedDescription ?: @"Unknown error";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)presentWarnings:(NSArray<NSString *> *)warnings title:(NSString *)title {
    FTMPresentWarningsAlert(warnings, title);
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    dispatch_async(dispatch_get_main_queue(), ^{
        FTMUpdateActivationPolicyForSettingsWindows();
    });
}

@end
