#import "FTMPreferencesWindowController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@class FTMProfileMappingWindowController;
@class FTMAppRoutingWindowController;

@interface FTMProfileMappingWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, copy, nullable) void (^onProfileDataChanged)(NSString *profileID);
- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore
                            importer:(FTMSoundPackImporter *)importer
                        soundResolver:(FTMSoundResolver *)soundResolver
                          soundPlayer:(FTMSoundPlayer *)soundPlayer;
- (void)presentForProfile:(FTMProfile *)profile;
@end

@interface FTMAppRoutingWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, copy, nullable) void (^onRulesChanged)(void);
- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore;
- (void)presentWindow;
@end

#pragma mark - V2 Sound Mapping Window

@interface FTMProfileMappingWindowController ()
@property (nonatomic, strong) FTMProfileStore *profileStore;
@property (nonatomic, strong) FTMSoundPackImporter *importer;
@property (nonatomic, strong) FTMSoundResolver *soundResolver;
@property (nonatomic, strong) FTMSoundPlayer *soundPlayer;
@property (nonatomic, strong) FTMProfile *profile;
@property (nonatomic, strong) NSArray<NSString *> *slotIDs;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *slotCounts;
@property (nonatomic, strong) NSArray<FTMProfileAsset *> *assignedAssets;
@property (nonatomic, strong) NSArray<FTMProfileAsset *> *libraryAssets;
@property (nonatomic, strong) NSArray<FTMProfileAsset *> *allAssets;
@property (nonatomic, strong) NSTextField *profileLabel;
@property (nonatomic, strong) NSTextField *warningLabel;
@property (nonatomic, strong) NSTableView *slotsTableView;
@property (nonatomic, strong) NSTableView *assignedTableView;
@property (nonatomic, strong) NSTableView *libraryTableView;
@property (nonatomic, strong) NSSegmentedControl *libraryFilterControl;
@property (nonatomic, strong) NSButton *assignButton;
@property (nonatomic, strong) NSButton *unassignButton;
@property (nonatomic, strong) NSButton *deleteAssetsButton;
@property (nonatomic, strong) NSButton *previewSlotButton;
@property (nonatomic, strong) NSButton *previewAssetButton;
@property (nonatomic, strong) NSButton *clearSlotButton;
@end

@implementation FTMProfileMappingWindowController

- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore
                            importer:(FTMSoundPackImporter *)importer
                        soundResolver:(FTMSoundResolver *)soundResolver
                          soundPlayer:(FTMSoundPlayer *)soundPlayer {
    NSRect frame = NSMakeRect(0, 0, 1180, 640);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Sound Mapping";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _profileStore = profileStore;
        _importer = importer;
        _soundResolver = soundResolver;
        _soundPlayer = soundPlayer;
        _slotIDs = FTMAllSoundSlotIDs();
        _slotCounts = @{};
        _assignedAssets = @[];
        _libraryAssets = @[];
        _allAssets = @[];
        [self buildUI];
    }
    return self;
}

- (void)presentForProfile:(FTMProfile *)profile {
    self.profile = profile;
    [self reloadUI];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildUI {
    NSView *content = self.window.contentView;
    self.profileLabel = [self label:@"Profile: (none)" frame:NSMakeRect(16, 610, 520, 20) bold:YES];
    [content addSubview:self.profileLabel];
    self.warningLabel = [self label:@"" frame:NSMakeRect(16, 586, 840, 18) bold:NO];
    self.warningLabel.textColor = [NSColor secondaryLabelColor];
    [content addSubview:self.warningLabel];

    [content addSubview:[self label:@"Slots" frame:NSMakeRect(16, 560, 100, 18) bold:YES]];
    [content addSubview:[self label:@"Assigned Assets (Selected Slot)" frame:NSMakeRect(280, 560, 250, 18) bold:YES]];
    [content addSubview:[self label:@"Profile Library" frame:NSMakeRect(700, 560, 150, 18) bold:YES]];

    self.libraryFilterControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(860, 556, 300, 24)];
    self.libraryFilterControl.segmentCount = 3;
    [self.libraryFilterControl setLabel:@"All" forSegment:0];
    [self.libraryFilterControl setLabel:@"Unassigned" forSegment:1];
    [self.libraryFilterControl setLabel:@"Assigned" forSegment:2];
    self.libraryFilterControl.selectedSegment = 0;
    self.libraryFilterControl.target = self;
    self.libraryFilterControl.action = @selector(handleLibraryFilterChanged:);
    [content addSubview:self.libraryFilterControl];

    NSScrollView *slotsScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 160, 250, 390)];
    slotsScroll.borderType = NSBezelBorder;
    slotsScroll.hasVerticalScroller = YES;
    self.slotsTableView = [[NSTableView alloc] initWithFrame:slotsScroll.bounds];
    NSTableColumn *slotNameCol = [[NSTableColumn alloc] initWithIdentifier:@"slotName"];
    slotNameCol.width = 180;
    [self.slotsTableView addTableColumn:slotNameCol];
    NSTableColumn *slotCountCol = [[NSTableColumn alloc] initWithIdentifier:@"slotCount"];
    slotCountCol.width = 50;
    [self.slotsTableView addTableColumn:slotCountCol];
    self.slotsTableView.delegate = self;
    self.slotsTableView.dataSource = self;
    self.slotsTableView.headerView = nil;
    slotsScroll.documentView = self.slotsTableView;
    [content addSubview:slotsScroll];

    NSScrollView *assignedScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(280, 160, 400, 390)];
    assignedScroll.borderType = NSBezelBorder;
    assignedScroll.hasVerticalScroller = YES;
    self.assignedTableView = [[NSTableView alloc] initWithFrame:assignedScroll.bounds];
    NSTableColumn *assignedCol = [[NSTableColumn alloc] initWithIdentifier:@"assignedName"];
    assignedCol.width = 385;
    [self.assignedTableView addTableColumn:assignedCol];
    self.assignedTableView.delegate = self;
    self.assignedTableView.dataSource = self;
    self.assignedTableView.headerView = nil;
    assignedScroll.documentView = self.assignedTableView;
    [content addSubview:assignedScroll];

    NSScrollView *libraryScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(700, 160, 460, 390)];
    libraryScroll.borderType = NSBezelBorder;
    libraryScroll.hasVerticalScroller = YES;
    self.libraryTableView = [[NSTableView alloc] initWithFrame:libraryScroll.bounds];
    NSTableColumn *libraryCol = [[NSTableColumn alloc] initWithIdentifier:@"libraryName"];
    libraryCol.width = 440;
    [self.libraryTableView addTableColumn:libraryCol];
    self.libraryTableView.delegate = self;
    self.libraryTableView.dataSource = self;
    self.libraryTableView.headerView = nil;
    libraryScroll.documentView = self.libraryTableView;
    [content addSubview:libraryScroll];

    [content addSubview:[self button:@"Import Folder…" action:@selector(handleImportFolder:) frame:NSMakeRect(16, 116, 116, 28)]];
    [content addSubview:[self button:@"Add Files…" action:@selector(handleAddFiles:) frame:NSMakeRect(138, 116, 100, 28)]];

    self.assignButton = [self button:@"Assign -> Slot" action:@selector(handleAssignToSlot:) frame:NSMakeRect(700, 116, 104, 28)];
    [content addSubview:self.assignButton];
    self.unassignButton = [self button:@"<- Unassign" action:@selector(handleUnassignFromSlot:) frame:NSMakeRect(280, 116, 98, 28)];
    [content addSubview:self.unassignButton];
    self.deleteAssetsButton = [self button:@"Delete From Profile…" action:@selector(handleDeleteAssets:) frame:NSMakeRect(810, 116, 130, 28)];
    [content addSubview:self.deleteAssetsButton];
    self.clearSlotButton = [self button:@"Clear Slot" action:@selector(handleClearSlot:) frame:NSMakeRect(386, 116, 86, 28)];
    [content addSubview:self.clearSlotButton];
    self.previewSlotButton = [self button:@"Preview Slot" action:@selector(handlePreviewSlot:) frame:NSMakeRect(480, 116, 94, 28)];
    [content addSubview:self.previewSlotButton];
    self.previewAssetButton = [self button:@"Preview Asset" action:@selector(handlePreviewAsset:) frame:NSMakeRect(948, 116, 98, 28)];
    [content addSubview:self.previewAssetButton];
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame bold:(BOOL)bold {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.stringValue = text ?: @"";
    if (bold) {
        label.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
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

- (void)reloadUI {
    self.profileLabel.stringValue = [NSString stringWithFormat:@"Profile: %@", self.profile.name ?: @"(none)"];
    self.slotCounts = [self.profileStore slotFileCountsForProfile:self.profile];
    self.allAssets = [self.profileStore assetsForProfile:self.profile];
    if (self.slotsTableView.selectedRow < 0 && self.slotIDs.count > 0) {
        [self.slotsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
    [self reloadAssignedAssets];
    [self reloadLibraryAssets];
    [self updateWarningAndButtons];
    [self.slotsTableView reloadData];
    [self.assignedTableView reloadData];
    [self.libraryTableView reloadData];
}

- (void)reloadAssignedAssets {
    self.assignedAssets = [self.profileStore assignedAssetsForSlotID:[self selectedSlotID] profile:self.profile];
    [self.assignedTableView reloadData];
}

- (void)reloadLibraryAssets {
    NSArray<FTMProfileAsset *> *allAssets = [self.profileStore assetsForProfile:self.profile];
    NSArray<FTMProfileAsset *> *unassigned = [self.profileStore unassignedAssetsForProfile:self.profile];
    NSSet<NSString *> *unassignedIDs = [NSSet setWithArray:[unassigned valueForKey:@"assetID"]];
    NSInteger filter = self.libraryFilterControl.selectedSegment;
    NSMutableArray<FTMProfileAsset *> *filtered = [NSMutableArray array];
    for (FTMProfileAsset *asset in allAssets) {
        BOOL isUnassigned = [unassignedIDs containsObject:asset.assetID];
        if (filter == 1 && !isUnassigned) { continue; }
        if (filter == 2 && isUnassigned) { continue; }
        [filtered addObject:asset];
    }
    self.allAssets = allAssets;
    self.libraryAssets = [filtered copy];
    [self.libraryTableView reloadData];
}

- (void)updateWarningAndButtons {
    NSUInteger typingCount = [self.profileStore assignedAssetsForSlotID:FTMSoundSlotTyping profile:self.profile].count;
    self.warningLabel.stringValue = (typingCount == 0)
        ? @"Typing slot is empty. Playback will fall back to built-in typing sounds."
        : @"";
    BOOL hasProfile = (self.profile != nil);
    BOOL hasLibrarySelection = (self.libraryTableView.selectedRowIndexes.count > 0);
    BOOL hasAssignedSelection = (self.assignedTableView.selectedRowIndexes.count > 0);
    BOOL slotHasAssignments = (self.assignedAssets.count > 0);
    NSString *slotPath = hasProfile ? [self.soundResolver randomSoundPathForSlotID:[self selectedSlotID] profile:self.profile] : nil;
    self.assignButton.enabled = hasProfile && hasLibrarySelection;
    self.unassignButton.enabled = hasProfile && hasAssignedSelection;
    self.deleteAssetsButton.enabled = hasProfile && hasLibrarySelection;
    self.clearSlotButton.enabled = hasProfile && slotHasAssignments;
    self.previewSlotButton.enabled = hasProfile && slotPath.length > 0;
    self.previewAssetButton.enabled = hasProfile && hasLibrarySelection;
}

- (NSString *)selectedSlotID {
    NSInteger row = self.slotsTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.slotIDs.count) {
        return self.slotIDs.firstObject ?: FTMSoundSlotTyping;
    }
    return self.slotIDs[(NSUInteger)row];
}

- (NSArray<FTMProfileAsset *> *)selectedLibraryAssets {
    NSIndexSet *indexes = self.libraryTableView.selectedRowIndexes;
    NSMutableArray<FTMProfileAsset *> *assets = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        (void)stop;
        if (idx < self.libraryAssets.count) {
            [assets addObject:self.libraryAssets[idx]];
        }
    }];
    return [assets copy];
}

- (NSArray<FTMProfileAsset *> *)selectedAssignedAssets {
    NSIndexSet *indexes = self.assignedTableView.selectedRowIndexes;
    NSMutableArray<FTMProfileAsset *> *assets = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        (void)stop;
        if (idx < self.assignedAssets.count) {
            [assets addObject:self.assignedAssets[idx]];
        }
    }];
    return [assets copy];
}

- (NSURL *)urlForAsset:(FTMProfileAsset *)asset {
    if (!self.profile || !asset) { return nil; }
    NSURL *profileDir = [self.profileStore profileDirectoryURLForProfile:self.profile];
    return [[profileDir URLByAppendingPathComponent:@"Assets" isDirectory:YES] URLByAppendingPathComponent:asset.storedFileName ?: @""];
}

- (void)handleLibraryFilterChanged:(id)sender {
    (void)sender;
    [self reloadLibraryAssets];
    [self updateWarningAndButtons];
}

- (void)handleImportFolder:(id)sender {
    (void)sender;
    if (!self.profile) { return; }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.message = @"Import a soundpack folder. Audio files are imported recursively and start as Unassigned.";
    if ([panel runModal] != NSModalResponseOK) {
        return;
    }
    NSArray<NSString *> *warnings = nil;
    NSError *error = nil;
    if (![self.profileStore importAudioFolderFlat:panel.URL intoProfile:self.profile importer:self.importer warnings:&warnings error:&error]) {
        [self showError:error title:@"Import Failed"];
        return;
    }
    if (warnings.count) {
        [self showWarnings:warnings title:[NSString stringWithFormat:@"Imported '%@' With Warnings", self.profile.name ?: @"Profile"]];
    }
    [self notifyChanged];
}

- (void)handleAddFiles:(id)sender {
    (void)sender;
    if (!self.profile) { return; }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    NSMutableArray<UTType *> *types = [NSMutableArray array];
    for (NSString *ext in FTMSupportedImportExtensions()) {
        UTType *type = [UTType typeWithFilenameExtension:ext];
        if (type) { [types addObject:type]; }
    }
    panel.allowedContentTypes = types;
    if ([panel runModal] != NSModalResponseOK) { return; }
    NSArray<NSString *> *warnings = nil;
    NSError *error = nil;
    if (![self.profileStore addAudioFilesToProfileLibrary:panel.URLs profile:self.profile importer:self.importer warnings:&warnings error:&error]) {
        [self showError:error title:@"Add Files Failed"];
        return;
    }
    if (warnings.count) {
        [self showWarnings:warnings title:[NSString stringWithFormat:@"Added Files to '%@' With Warnings", self.profile.name ?: @"Profile"]];
    }
    [self notifyChanged];
}

- (void)handleAssignToSlot:(id)sender {
    (void)sender;
    if (!self.profile) { return; }
    NSArray<FTMProfileAsset *> *assets = [self selectedLibraryAssets];
    if (assets.count == 0) { return; }
    NSArray<NSString *> *assetIDs = [assets valueForKey:@"assetID"];
    NSError *error = nil;
    if (![self.profileStore assignAssetIDs:assetIDs toSlotID:[self selectedSlotID] profile:self.profile error:&error]) {
        [self showError:error title:@"Assign Failed"];
        return;
    }
    [self notifyChanged];
}

- (void)handleUnassignFromSlot:(id)sender {
    (void)sender;
    if (!self.profile) { return; }
    NSArray<FTMProfileAsset *> *assets = [self selectedAssignedAssets];
    if (assets.count == 0) { return; }
    NSArray<NSString *> *assetIDs = [assets valueForKey:@"assetID"];
    NSError *error = nil;
    if (![self.profileStore unassignAssetIDs:assetIDs fromSlotID:[self selectedSlotID] profile:self.profile error:&error]) {
        [self showError:error title:@"Unassign Failed"];
        return;
    }
    [self notifyChanged];
}

- (void)handleDeleteAssets:(id)sender {
    (void)sender;
    if (!self.profile) { return; }
    NSArray<FTMProfileAsset *> *assets = [self selectedLibraryAssets];
    if (assets.count == 0) { return; }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Delete Assets From Profile?";
    alert.informativeText = [NSString stringWithFormat:@"Delete %lu sound file(s) from '%@'? Any slot assignments using them will be removed.", (unsigned long)assets.count, self.profile.name ?: @"Profile"];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    NSError *error = nil;
    if (![self.profileStore deleteAssetIDsFromProfile:[assets valueForKey:@"assetID"] profile:self.profile error:&error]) {
        [self showError:error title:@"Delete Failed"];
        return;
    }
    [self notifyChanged];
}

- (void)handleClearSlot:(id)sender {
    (void)sender;
    if (!self.profile) { return; }
    if (self.assignedAssets.count > 1) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Clear Slot?";
        alert.informativeText = [NSString stringWithFormat:@"Remove %lu assignment(s) from %@? Files remain in the profile library.", (unsigned long)self.assignedAssets.count, FTMDisplayNameForSoundSlot([self selectedSlotID])];
        [alert addButtonWithTitle:@"Clear"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return;
        }
    }
    NSError *error = nil;
    if (![self.profileStore clearSlotID:[self selectedSlotID] profile:self.profile importer:self.importer error:&error]) {
        [self showError:error title:@"Clear Slot Failed"];
        return;
    }
    [self notifyChanged];
}

- (void)handlePreviewSlot:(id)sender {
    (void)sender;
    NSString *path = [self.soundResolver randomSoundPathForSlotID:[self selectedSlotID] profile:self.profile];
    [self.soundPlayer playSoundAtPath:path];
}

- (void)handlePreviewAsset:(id)sender {
    (void)sender;
    FTMProfileAsset *asset = [self selectedLibraryAssets].firstObject;
    [self.soundPlayer playSoundAtPath:[self urlForAsset:asset].path];
}

- (void)notifyChanged {
    [self reloadUI];
    if (self.onProfileDataChanged && self.profile.profileID.length > 0) {
        self.onProfileDataChanged(self.profile.profileID);
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.slotsTableView) { return (NSInteger)self.slotIDs.count; }
    if (tableView == self.assignedTableView) { return (NSInteger)self.assignedAssets.count; }
    if (tableView == self.libraryTableView) { return (NSInteger)self.libraryAssets.count; }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    if (tableView == self.slotsTableView) {
        if (row < 0 || row >= (NSInteger)self.slotIDs.count) { return @""; }
        NSString *slotID = self.slotIDs[(NSUInteger)row];
        return [NSString stringWithFormat:@"%@ (%@)", FTMDisplayNameForSoundSlot(slotID), self.slotCounts[slotID] ?: @0];
    }
    if (tableView == self.assignedTableView) {
        if (row < 0 || row >= (NSInteger)self.assignedAssets.count) { return @""; }
        FTMProfileAsset *asset = self.assignedAssets[(NSUInteger)row];
        return asset.displayName ?: asset.storedFileName ?: @"";
    }
    if (tableView == self.libraryTableView) {
        if (row < 0 || row >= (NSInteger)self.libraryAssets.count) { return @""; }
        FTMProfileAsset *asset = self.libraryAssets[(NSUInteger)row];
        BOOL isUnassigned = [[NSSet setWithArray:[[self.profileStore unassignedAssetsForProfile:self.profile] valueForKey:@"assetID"]] containsObject:asset.assetID];
        return isUnassigned ? [NSString stringWithFormat:@"%@ (Unassigned)", asset.displayName ?: asset.storedFileName ?: @""] : (asset.displayName ?: asset.storedFileName ?: @"");
    }
    return @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tableView = notification.object;
    if (tableView == self.slotsTableView) {
        [self reloadAssignedAssets];
        [self updateWarningAndButtons];
        return;
    }
    if (tableView == self.assignedTableView || tableView == self.libraryTableView) {
        [self updateWarningAndButtons];
    }
}

- (void)showError:(NSError *)error title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title ?: @"Error";
    alert.informativeText = error.localizedDescription ?: @"Unknown error";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)showWarnings:(NSArray<NSString *> *)warnings title:(NSString *)title {
    if (warnings.count == 0) { return; }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = title ?: @"Warnings";
    NSUInteger maxLines = MIN((NSUInteger)12, warnings.count);
    NSArray<NSString *> *snippet = [warnings subarrayWithRange:NSMakeRange(0, maxLines)];
    NSString *body = [snippet componentsJoinedByString:@"\n"];
    if (warnings.count > maxLines) {
        body = [body stringByAppendingFormat:@"\n… and %lu more", (unsigned long)(warnings.count - maxLines)];
    }
    alert.informativeText = body;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end

#pragma mark - V2 App Routing Window

@interface FTMAppRoutingWindowController ()
@property (nonatomic, strong) FTMProfileStore *profileStore;
@property (nonatomic, strong) NSArray<FTMAppProfileRule *> *rulesSnapshot;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSButton *changeProfileButton;
@property (nonatomic, strong) NSButton *removeButton;
@end

@implementation FTMAppRoutingWindowController

- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore {
    NSRect frame = NSMakeRect(0, 0, 860, 420);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"App Routing";
    window.releasedWhenClosed = NO;
    self = [super initWithWindow:window];
    if (self) {
        _profileStore = profileStore;
        _rulesSnapshot = @[];
        [self buildUI];
        [self reloadUI];
    }
    return self;
}

- (void)presentWindow {
    [self reloadUI];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildUI {
    NSView *content = self.window.contentView;
    NSTextField *header = [[NSTextField alloc] initWithFrame:NSMakeRect(16, 390, 830, 18)];
    header.bezeled = NO;
    header.drawsBackground = NO;
    header.editable = NO;
    header.selectable = NO;
    header.stringValue = @"Assigned apps use their profile for typing and launch/quit sounds.";
    [content addSubview:header];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 58, 828, 324)];
    scroll.borderType = NSBezelBorder;
    scroll.hasVerticalScroller = YES;
    self.tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    NSTableColumn *appCol = [[NSTableColumn alloc] initWithIdentifier:@"app"];
    appCol.title = @"App";
    appCol.width = 220;
    [self.tableView addTableColumn:appCol];
    NSTableColumn *bundleCol = [[NSTableColumn alloc] initWithIdentifier:@"bundle"];
    bundleCol.title = @"Bundle Identifier";
    bundleCol.width = 360;
    [self.tableView addTableColumn:bundleCol];
    NSTableColumn *profileCol = [[NSTableColumn alloc] initWithIdentifier:@"profile"];
    profileCol.title = @"Profile";
    profileCol.width = 220;
    [self.tableView addTableColumn:profileCol];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    scroll.documentView = self.tableView;
    [content addSubview:scroll];

    [content addSubview:[self button:@"Add From Running Apps…" action:@selector(handleAddFromRunningApps:) frame:NSMakeRect(16, 18, 160, 28)]];
    [content addSubview:[self button:@"Add By Bundle ID…" action:@selector(handleAddByBundleID:) frame:NSMakeRect(182, 18, 130, 28)]];
    self.changeProfileButton = [self button:@"Change Profile…" action:@selector(handleChangeProfile:) frame:NSMakeRect(318, 18, 120, 28)];
    [content addSubview:self.changeProfileButton];
    self.removeButton = [self button:@"Remove Assignment" action:@selector(handleRemoveRule:) frame:NSMakeRect(444, 18, 136, 28)];
    [content addSubview:self.removeButton];
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.bezelStyle = NSBezelStyleRounded;
    button.title = title;
    button.target = self;
    button.action = action;
    return button;
}

- (void)reloadUI {
    self.rulesSnapshot = [[self.profileStore appRules] sortedArrayUsingComparator:^NSComparisonResult(FTMAppProfileRule *a, FTMAppProfileRule *b) {
        NSString *aName = a.appNameHint.length ? a.appNameHint : a.bundleIdentifier;
        NSString *bName = b.appNameHint.length ? b.appNameHint : b.bundleIdentifier;
        return [aName localizedCaseInsensitiveCompare:bName];
    }];
    [self.tableView reloadData];
    [self updateButtons];
}

- (void)updateButtons {
    BOOL hasSelection = (self.tableView.selectedRow >= 0 && self.tableView.selectedRow < (NSInteger)self.rulesSnapshot.count);
    self.changeProfileButton.enabled = hasSelection;
    self.removeButton.enabled = hasSelection;
}

- (nullable FTMAppProfileRule *)selectedRule {
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.rulesSnapshot.count) {
        return nil;
    }
    return self.rulesSnapshot[(NSUInteger)row];
}

- (nullable NSString *)chooseProfileIDWithTitle:(NSString *)title currentProfileID:(NSString *)currentProfileID {
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

- (NSString *)promptForTextWithTitle:(NSString *)title message:(NSString *)message defaultValue:(NSString *)defaultValue {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"Input";
    alert.informativeText = message ?: @"";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 340, 24)];
    field.stringValue = defaultValue ?: @"";
    alert.accessoryView = field;
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return nil;
    }
    NSString *trimmed = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length ? trimmed : nil;
}

- (void)handleAddByBundleID:(id)sender {
    (void)sender;
    NSString *bundleID = [self promptForTextWithTitle:@"Add App Routing Rule"
                                             message:@"Enter the app bundle identifier (for example com.apple.Terminal):"
                                        defaultValue:@""];
    if (!bundleID) { return; }
    NSString *appName = [self promptForTextWithTitle:@"App Name (Optional)"
                                            message:@"Display name shown in the routing list:"
                                       defaultValue:@""];
    NSString *profileID = [self chooseProfileIDWithTitle:@"Assign Profile" currentProfileID:nil];
    if (!profileID) { return; }
    NSError *error = nil;
    if (![self.profileStore setAppRuleForBundleIdentifier:bundleID appNameHint:appName profileID:profileID error:&error]) {
        [self showError:error title:@"Save Assignment Failed"];
        return;
    }
    [self notifyRulesChanged];
}

- (void)handleAddFromRunningApps:(id)sender {
    (void)sender;
    NSArray<NSRunningApplication *> *running = [[[NSWorkspace sharedWorkspace] runningApplications] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSRunningApplication * _Nullable app, NSDictionary<NSString *,id> * _Nullable bindings) {
        (void)bindings;
        if (app == nil) { return NO; }
        NSString *bundleID = app.bundleIdentifier ?: @"";
        if (bundleID.length == 0) { return NO; }
        if ([[bundleID lowercaseString] isEqualToString:@"com.mikeonator.macostypingsounds"]) { return NO; }
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
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 420, 26) pullsDown:NO];
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
    if (!selectedApp.bundleIdentifier.length) { return; }
    FTMAppProfileRule *existingRule = [self.profileStore appRuleForBundleIdentifier:selectedApp.bundleIdentifier];
    NSString *profileID = [self chooseProfileIDWithTitle:@"Assign Profile" currentProfileID:existingRule.profileID];
    if (!profileID) { return; }
    NSError *error = nil;
    if (![self.profileStore setAppRuleForBundleIdentifier:selectedApp.bundleIdentifier
                                               appNameHint:selectedApp.localizedName
                                                 profileID:profileID
                                                     error:&error]) {
        [self showError:error title:@"Save Assignment Failed"];
        return;
    }
    [self notifyRulesChanged];
}

- (void)handleChangeProfile:(id)sender {
    (void)sender;
    FTMAppProfileRule *rule = [self selectedRule];
    if (!rule) { return; }
    NSString *profileID = [self chooseProfileIDWithTitle:@"Change Assigned Profile" currentProfileID:rule.profileID];
    if (!profileID) { return; }
    NSError *error = nil;
    if (![self.profileStore setAppRuleForBundleIdentifier:rule.bundleIdentifier
                                               appNameHint:rule.appNameHint
                                                 profileID:profileID
                                                     error:&error]) {
        [self showError:error title:@"Change Assignment Failed"];
        return;
    }
    [self notifyRulesChanged];
}

- (void)handleRemoveRule:(id)sender {
    (void)sender;
    FTMAppProfileRule *rule = [self selectedRule];
    if (!rule) { return; }
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
        [self showError:error title:@"Remove Assignment Failed"];
        return;
    }
    [self notifyRulesChanged];
}

- (void)notifyRulesChanged {
    [self reloadUI];
    if (self.onRulesChanged) {
        self.onRulesChanged();
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.tableView) {
        return (NSInteger)self.rulesSnapshot.count;
    }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView != self.tableView || row < 0 || row >= (NSInteger)self.rulesSnapshot.count) {
        return @"";
    }
    FTMAppProfileRule *rule = self.rulesSnapshot[(NSUInteger)row];
    if ([[tableColumn identifier] isEqualToString:@"app"]) {
        return rule.appNameHint.length ? rule.appNameHint : @"(Unknown)";
    }
    if ([[tableColumn identifier] isEqualToString:@"bundle"]) {
        return rule.bundleIdentifier ?: @"";
    }
    if ([[tableColumn identifier] isEqualToString:@"profile"]) {
        FTMProfile *profile = [self.profileStore assignedProfileForBundleIdentifier:rule.bundleIdentifier];
        return profile.name ?: rule.profileID ?: @"";
    }
    return @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateButtons];
}

- (void)showError:(NSError *)error title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title ?: @"Error";
    alert.informativeText = error.localizedDescription ?: @"Unknown error";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)showSimpleInfo:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"App Routing";
    alert.informativeText = message ?: @"";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end

@interface FTMPreferencesWindowController ()
@property (nonatomic, strong) FTMProfileStore *profileStore;
@property (nonatomic, strong) FTMSoundPackImporter *importer;
@property (nonatomic, strong) FTMSoundResolver *soundResolver;
@property (nonatomic, strong) FTMSoundPlayer *soundPlayer;

@property (nonatomic, strong) NSTableView *profilesTableView;
@property (nonatomic, strong) NSTableView *slotsTableView;
@property (nonatomic, strong) NSTableView *filesTableView;

@property (nonatomic, strong) NSButton *muteCheckbox;
@property (nonatomic, strong) NSButton *terminalOnlyCheckbox;
@property (nonatomic, strong) NSTextField *editingProfileLabel;
@property (nonatomic, strong) NSTextField *activeProfileLabel;
@property (nonatomic, strong) NSTextField *helpTextLabel;
@property (nonatomic, strong) NSTextField *routingSummaryLabel;

@property (nonatomic, strong) NSButton *setActiveButton;
@property (nonatomic, strong) NSButton *duplicateButton;
@property (nonatomic, strong) NSButton *renameButton;
@property (nonatomic, strong) NSButton *deleteButton;
@property (nonatomic, strong) NSButton *addFilesButton;
@property (nonatomic, strong) NSButton *removeFilesButton;
@property (nonatomic, strong) NSButton *clearSlotButton;
@property (nonatomic, strong) NSButton *previewSlotButton;
@property (nonatomic, strong) NSButton *editSoundMappingButton;
@property (nonatomic, strong) NSButton *manageAppRoutingButton;

@property (nonatomic, strong) NSArray<FTMProfile *> *profilesSnapshot;
@property (nonatomic, strong) NSArray<NSString *> *slotIDs;
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *slotCounts;
@property (nonatomic, strong) NSArray<NSURL *> *selectedSlotFiles;
@property (nonatomic, strong) FTMProfileMappingWindowController *profileMappingWindowController;
@property (nonatomic, strong) FTMAppRoutingWindowController *appRoutingWindowController;
@end

@implementation FTMPreferencesWindowController

- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore
                            importer:(FTMSoundPackImporter *)importer
                        soundResolver:(FTMSoundResolver *)soundResolver
                          soundPlayer:(FTMSoundPlayer *)soundPlayer {
    NSRect frame = NSMakeRect(0, 0, 1080, 700);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Preferences";
    window.releasedWhenClosed = NO;

    self = [super initWithWindow:window];
    if (self) {
        _profileStore = profileStore;
        _importer = importer;
        _soundResolver = soundResolver;
        _soundPlayer = soundPlayer;
        _profilesSnapshot = @[];
        _slotIDs = FTMAllSoundSlotIDs();
        _slotCounts = @{};
        _selectedSlotFiles = @[];
        [self buildUI];
        [self reloadAllUI];
    }
    return self;
}

- (void)presentWindow {
    [self reloadAllUI];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
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

    NSView *leftPane = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 290, NSHeight(content.bounds))];
    NSView *rightPane = [[NSView alloc] initWithFrame:NSMakeRect(290, 0, NSWidth(content.bounds) - 290, NSHeight(content.bounds))];
    [content addSubview:leftPane];
    [content addSubview:rightPane];

    NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(289, 0, 1, NSHeight(content.bounds))];
    divider.boxType = NSBoxSeparator;
    [content addSubview:divider];

    NSTextField *profilesTitle = [self label:@"Profiles" frame:NSMakeRect(16, 666, 200, 20) bold:YES];
    [leftPane addSubview:profilesTitle];

    NSScrollView *profilesScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 150, 258, 510)];
    profilesScroll.hasVerticalScroller = YES;
    profilesScroll.borderType = NSBezelBorder;
    self.profilesTableView = [[NSTableView alloc] initWithFrame:profilesScroll.bounds];
    NSTableColumn *profileCol = [[NSTableColumn alloc] initWithIdentifier:@"profile"];
    profileCol.title = @"Profile";
    profileCol.width = 250;
    [self.profilesTableView addTableColumn:profileCol];
    self.profilesTableView.headerView = nil;
    self.profilesTableView.delegate = self;
    self.profilesTableView.dataSource = self;
    self.profilesTableView.target = self;
    self.profilesTableView.doubleAction = @selector(handleSetActiveProfile:);
    profilesScroll.documentView = self.profilesTableView;
    [leftPane addSubview:profilesScroll];

    CGFloat y1 = 104;
    CGFloat y2 = 64;
    [leftPane addSubview:[self button:@"New" action:@selector(handleNewProfile:) frame:NSMakeRect(16, y1, 80, 28)]];
    self.duplicateButton = [self button:@"Duplicate" action:@selector(handleDuplicateProfile:) frame:NSMakeRect(102, y1, 86, 28)];
    [leftPane addSubview:self.duplicateButton];
    self.renameButton = [self button:@"Rename" action:@selector(handleRenameProfile:) frame:NSMakeRect(194, y1, 80, 28)];
    [leftPane addSubview:self.renameButton];

    self.deleteButton = [self button:@"Delete" action:@selector(handleDeleteProfile:) frame:NSMakeRect(16, y2, 80, 28)];
    [leftPane addSubview:self.deleteButton];
    [leftPane addSubview:[self button:@"Import Pack…" action:@selector(handleImportProfile:) frame:NSMakeRect(102, y2, 172, 28)]];

    self.setActiveButton = [self button:@"Set Active" action:@selector(handleSetActiveProfile:) frame:NSMakeRect(16, 24, 120, 28)];
    [leftPane addSubview:self.setActiveButton];

    [rightPane addSubview:[self label:@"Profile Editor" frame:NSMakeRect(16, 666, 200, 20) bold:YES]];
    self.editingProfileLabel = [self label:@"Editing: (none)" frame:NSMakeRect(16, 640, 420, 20) bold:NO];
    [rightPane addSubview:self.editingProfileLabel];
    self.activeProfileLabel = [self label:@"Default (Unassigned): (none)" frame:NSMakeRect(16, 616, 420, 20) bold:NO];
    [rightPane addSubview:self.activeProfileLabel];
    self.routingSummaryLabel = [self label:@"App Routing: 0 assignments" frame:NSMakeRect(16, 592, 420, 20) bold:NO];
    [rightPane addSubview:self.routingSummaryLabel];

    self.muteCheckbox = [self checkbox:@"Mute SFX" action:@selector(handleMuteToggle:) frame:NSMakeRect(470, 640, 180, 20)];
    [rightPane addSubview:self.muteCheckbox];
    self.terminalOnlyCheckbox = [self checkbox:@"Play SFX in assigned apps only" action:@selector(handleTerminalOnlyToggle:) frame:NSMakeRect(470, 616, 300, 20)];
    [rightPane addSubview:self.terminalOnlyCheckbox];
    self.editSoundMappingButton = [self button:@"Edit Sound Mapping…" action:@selector(handleEditSoundMapping:) frame:NSMakeRect(470, 584, 150, 28)];
    [rightPane addSubview:self.editSoundMappingButton];
    self.manageAppRoutingButton = [self button:@"Manage App Routing…" action:@selector(handleManageAppRouting:) frame:NSMakeRect(626, 584, 148, 28)];
    [rightPane addSubview:self.manageAppRoutingButton];

    self.helpTextLabel = [self wrappingLabel:@"Tip: Global key sounds require Keyboard access (System Settings > Privacy & Security > Accessibility and Input Monitoring). Assigned apps use their profile for typing and launch/quit sounds." frame:NSMakeRect(16, 540, 760, 42)];
    [rightPane addSubview:self.helpTextLabel];

    [rightPane addSubview:[self label:@"Sound Slots (Assigned Assets)" frame:NSMakeRect(16, 512, 240, 18) bold:YES]];
    [rightPane addSubview:[self label:@"Assigned Files In Selected Slot" frame:NSMakeRect(332, 512, 260, 18) bold:YES]];

    NSScrollView *slotsScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 206, 300, 300)];
    slotsScroll.hasVerticalScroller = YES;
    slotsScroll.borderType = NSBezelBorder;
    self.slotsTableView = [[NSTableView alloc] initWithFrame:slotsScroll.bounds];
    NSTableColumn *slotNameCol = [[NSTableColumn alloc] initWithIdentifier:@"slotName"];
    slotNameCol.title = @"Slot";
    slotNameCol.width = 220;
    [self.slotsTableView addTableColumn:slotNameCol];
    NSTableColumn *slotCountCol = [[NSTableColumn alloc] initWithIdentifier:@"slotCount"];
    slotCountCol.title = @"Count";
    slotCountCol.width = 70;
    [self.slotsTableView addTableColumn:slotCountCol];
    self.slotsTableView.delegate = self;
    self.slotsTableView.dataSource = self;
    slotsScroll.documentView = self.slotsTableView;
    [rightPane addSubview:slotsScroll];

    NSScrollView *filesScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(332, 206, 442, 300)];
    filesScroll.hasVerticalScroller = YES;
    filesScroll.borderType = NSBezelBorder;
    self.filesTableView = [[NSTableView alloc] initWithFrame:filesScroll.bounds];
    NSTableColumn *fileNameCol = [[NSTableColumn alloc] initWithIdentifier:@"fileName"];
    fileNameCol.title = @"File";
    fileNameCol.width = 430;
    [self.filesTableView addTableColumn:fileNameCol];
    self.filesTableView.delegate = self;
    self.filesTableView.dataSource = self;
    filesScroll.documentView = self.filesTableView;
    [rightPane addSubview:filesScroll];

    self.addFilesButton = [self button:@"Add Files…" action:@selector(handleAddFiles:) frame:NSMakeRect(332, 166, 100, 28)];
    [rightPane addSubview:self.addFilesButton];
    self.removeFilesButton = [self button:@"Remove Selected" action:@selector(handleRemoveSelectedFiles:) frame:NSMakeRect(438, 166, 128, 28)];
    [rightPane addSubview:self.removeFilesButton];
    self.clearSlotButton = [self button:@"Clear Slot" action:@selector(handleClearSlot:) frame:NSMakeRect(572, 166, 90, 28)];
    [rightPane addSubview:self.clearSlotButton];
    self.previewSlotButton = [self button:@"Preview Slot" action:@selector(handlePreviewSlot:) frame:NSMakeRect(668, 166, 106, 28)];
    [rightPane addSubview:self.previewSlotButton];

    [rightPane addSubview:[self wrappingLabel:@"Supported import types: mp3, wav, m4a, aiff, ogg (Ogg Vorbis imports convert to WAV).\nV2 imports packs as a flat library (folder names are ignored). Use Edit Sound Mapping to assign imported sounds to slots. Empty key slots fall back to typing; empty launch/quit uses bundled power sounds." frame:NSMakeRect(16, 118, 300, 78)]];
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame bold:(BOOL)bold {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.stringValue = text ?: @"";
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

#pragma mark - Data helpers

- (nullable FTMProfile *)selectedProfile {
    NSInteger row = self.profilesTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.profilesSnapshot.count) {
        return nil;
    }
    return self.profilesSnapshot[(NSUInteger)row];
}

- (NSString *)selectedSlotID {
    NSInteger row = self.slotsTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)self.slotIDs.count) {
        return self.slotIDs.firstObject ?: FTMSoundSlotTyping;
    }
    return self.slotIDs[(NSUInteger)row];
}

- (NSInteger)rowForProfileID:(NSString *)profileID {
    if (profileID.length == 0) {
        return -1;
    }
    for (NSUInteger i = 0; i < self.profilesSnapshot.count; i++) {
        if ([self.profilesSnapshot[i].profileID isEqualToString:profileID]) {
            return (NSInteger)i;
        }
    }
    return -1;
}

- (void)refreshGlobalSettingsUI {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.muteCheckbox.state = [defaults boolForKey:FTMDefaultsKeyMuted] ? NSControlStateValueOn : NSControlStateValueOff;
    self.terminalOnlyCheckbox.state = [defaults boolForKey:FTMDefaultsKeyAssignedAppsOnly] ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)refreshProfileDependentUI {
    FTMProfile *selected = [self selectedProfile];
    FTMProfile *active = self.profileStore.activeProfile;

    self.editingProfileLabel.stringValue = [NSString stringWithFormat:@"Editing: %@", selected.name ?: @"(none)"];
    self.activeProfileLabel.stringValue = [NSString stringWithFormat:@"Default (Unassigned Apps): %@", active.name ?: @"(none)"];
    self.routingSummaryLabel.stringValue = [NSString stringWithFormat:@"App Routing: %lu assignments", (unsigned long)self.profileStore.appRules.count];

    self.slotCounts = [self.profileStore slotFileCountsForProfile:selected];
    [self.slotsTableView reloadData];

    if (self.slotsTableView.selectedRow < 0 && self.slotIDs.count > 0) {
        [self.slotsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
    [self refreshSelectedSlotFiles];
    [self updateButtonStates];
}

- (void)refreshSelectedSlotFiles {
    FTMProfile *selectedProfile = [self selectedProfile];
    NSString *slotID = [self selectedSlotID];
    self.selectedSlotFiles = [self.profileStore fileURLsForSlotID:slotID profile:selectedProfile];
    [self.filesTableView reloadData];
    [self updateButtonStates];
}

- (void)updateButtonStates {
    BOOL hasProfile = ([self selectedProfile] != nil);
    BOOL hasSlot = (self.slotIDs.count > 0 && self.slotsTableView.selectedRow >= 0);
    BOOL hasSelectedFiles = (self.filesTableView.selectedRowIndexes.count > 0);
    BOOL slotHasFiles = (self.selectedSlotFiles.count > 0);
    BOOL canPreview = (hasProfile && hasSlot && [self previewPathForSelectedContext].length > 0);

    self.duplicateButton.enabled = hasProfile;
    self.renameButton.enabled = hasProfile;
    self.deleteButton.enabled = hasProfile;
    self.setActiveButton.enabled = hasProfile;
    self.editSoundMappingButton.enabled = hasProfile;
    self.manageAppRoutingButton.enabled = YES;

    self.addFilesButton.enabled = hasProfile && hasSlot;
    self.removeFilesButton.enabled = hasProfile && hasSlot && hasSelectedFiles;
    self.clearSlotButton.enabled = hasProfile && hasSlot && slotHasFiles;
    self.previewSlotButton.enabled = canPreview;
}

#pragma mark - Actions

- (void)handleNewProfile:(id)sender {
    (void)sender;
    NSString *name = [self promptForTextWithTitle:@"New Profile" message:@"Enter a name for the new profile:" defaultValue:@"New Profile"];
    if (!name) {
        return;
    }

    NSError *error = nil;
    FTMProfile *profile = [self.profileStore createEmptyProfileNamed:name error:&error];
    if (!profile) {
        [self showErrorAlert:error];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handleDuplicateProfile:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) { return; }

    NSError *error = nil;
    FTMProfile *copy = [self.profileStore duplicateProfile:profile error:&error];
    if (!copy) {
        [self showErrorAlert:error];
        return;
    }
    [self notifyProfilesChangedAndReloadSelectingProfileID:copy.profileID invalidateResolver:YES];
}

- (void)handleRenameProfile:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) { return; }

    NSString *name = [self promptForTextWithTitle:@"Rename Profile" message:@"Enter a new name:" defaultValue:profile.name ?: @"Profile"];
    if (!name) {
        return;
    }

    NSError *error = nil;
    if (![self.profileStore renameProfile:profile toName:name error:&error]) {
        [self showErrorAlert:error];
        return;
    }
    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:NO];
}

- (void)handleDeleteProfile:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) { return; }

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
        [self showErrorAlert:error];
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
    panel.message = @"Choose a soundpack folder. V2 imports audio files recursively and ignores folder names.";

    if ([panel runModal] != NSModalResponseOK) {
        return;
    }

    NSURL *folderURL = panel.URL;
    NSArray<NSString *> *warnings = nil;
    NSError *error = nil;
    FTMProfile *profile = [self.profileStore importProfileFromFolderURL:folderURL importer:self.importer warnings:&warnings error:&error];
    if (!profile) {
        [self showErrorAlert:error];
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
    if (!profile) { return; }

    NSError *error = nil;
    if (![self.profileStore setActiveProfileID:profile.profileID error:&error]) {
        [self showErrorAlert:error];
        return;
    }

    if (self.onProfilesChanged) {
        self.onProfilesChanged();
    }
    [self reloadAllUI];
}

- (void)handleAddFiles:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) { return; }
    NSString *slotID = [self selectedSlotID];

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
    panel.message = [NSString stringWithFormat:@"Add files to %@", FTMDisplayNameForSoundSlot(slotID)];

    if ([panel runModal] != NSModalResponseOK) {
        return;
    }

    NSArray<NSString *> *warnings = nil;
    NSError *error = nil;
    if (![self.profileStore addAudioFilesAtURLs:panel.URLs
                                       toSlotID:slotID
                                        profile:profile
                                       importer:self.importer
                                       warnings:&warnings
                                          error:&error]) {
        [self showErrorAlert:error];
        return;
    }

    if (warnings.count) {
        NSString *title = [NSString stringWithFormat:@"Added Files to '%@' With Warnings", profile.name ?: @"Profile"];
        [self presentWarnings:warnings title:title];
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handleRemoveSelectedFiles:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) { return; }
    NSString *slotID = [self selectedSlotID];
    NSIndexSet *rows = self.filesTableView.selectedRowIndexes;
    if (rows.count == 0) { return; }

    NSMutableArray<NSString *> *fileNames = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        (void)stop;
        if (idx < self.selectedSlotFiles.count) {
            [fileNames addObject:self.selectedSlotFiles[idx].lastPathComponent];
        }
    }];

    NSError *error = nil;
    if (![self.profileStore removeFilesNamed:fileNames fromSlotID:slotID profile:profile importer:self.importer error:&error]) {
        [self showErrorAlert:error];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handleClearSlot:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) { return; }
    NSString *slotID = [self selectedSlotID];
    if (self.selectedSlotFiles.count > 1) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Clear Slot?";
        alert.informativeText = [NSString stringWithFormat:@"Clear %lu files from %@?", (unsigned long)self.selectedSlotFiles.count, FTMDisplayNameForSoundSlot(slotID)];
        [alert addButtonWithTitle:@"Clear"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            return;
        }
    }

    NSError *error = nil;
    if (![self.profileStore clearSlotID:slotID profile:profile importer:self.importer error:&error]) {
        [self showErrorAlert:error];
        return;
    }

    [self notifyProfilesChangedAndReloadSelectingProfileID:profile.profileID invalidateResolver:YES];
}

- (void)handlePreviewSlot:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) { return; }
    NSString *path = [self previewPathForSelectedContext];
    [self.soundPlayer playSoundAtPath:path];
}

- (void)handleMuteToggle:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:(self.muteCheckbox.state == NSControlStateValueOn) forKey:FTMDefaultsKeyMuted];
    if (self.onSettingsChanged) {
        self.onSettingsChanged();
    }
    [self refreshGlobalSettingsUI];
}

- (void)handleTerminalOnlyToggle:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:(self.terminalOnlyCheckbox.state == NSControlStateValueOn) forKey:FTMDefaultsKeyAssignedAppsOnly];
    if (self.onSettingsChanged) {
        self.onSettingsChanged();
    }
    [self refreshGlobalSettingsUI];
}

- (void)handleEditSoundMapping:(id)sender {
    (void)sender;
    FTMProfile *profile = [self selectedProfile];
    if (!profile) { return; }
    [self showProfileMappingWindowForProfile:profile];
}

- (void)handleManageAppRouting:(id)sender {
    (void)sender;
    [self showAppRoutingWindow];
}

- (void)showProfileMappingWindowForProfile:(FTMProfile *)profile {
    if (!profile) { return; }
    if (!self.profileMappingWindowController) {
        self.profileMappingWindowController = [[FTMProfileMappingWindowController alloc] initWithProfileStore:self.profileStore
                                                                                                      importer:self.importer
                                                                                                  soundResolver:self.soundResolver
                                                                                                    soundPlayer:self.soundPlayer];
        __weak typeof(self) weakSelf = self;
        self.profileMappingWindowController.onProfileDataChanged = ^(NSString *profileID) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            [self notifyProfilesChangedAndReloadSelectingProfileID:profileID invalidateResolver:YES];
        };
    }
    [self.profileMappingWindowController presentForProfile:profile];
}

- (void)showAppRoutingWindow {
    if (!self.appRoutingWindowController) {
        self.appRoutingWindowController = [[FTMAppRoutingWindowController alloc] initWithProfileStore:self.profileStore];
        __weak typeof(self) weakSelf = self;
        self.appRoutingWindowController.onRulesChanged = ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { return; }
            if (self.onProfilesChanged) {
                self.onProfilesChanged();
            }
            [self reloadAllUI];
        };
    }
    [self.appRoutingWindowController presentWindow];
}

#pragma mark - Table Views

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.profilesTableView) {
        return (NSInteger)self.profilesSnapshot.count;
    }
    if (tableView == self.slotsTableView) {
        return (NSInteger)self.slotIDs.count;
    }
    if (tableView == self.filesTableView) {
        return (NSInteger)self.selectedSlotFiles.count;
    }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.profilesTableView) {
        if (row < 0 || row >= (NSInteger)self.profilesSnapshot.count) { return @""; }
        FTMProfile *profile = self.profilesSnapshot[(NSUInteger)row];
        BOOL isActive = [profile.profileID isEqualToString:self.profileStore.activeProfile.profileID];
        return isActive ? [NSString stringWithFormat:@"%@ ✓", profile.name] : profile.name;
    }

    if (tableView == self.slotsTableView) {
        if (row < 0 || row >= (NSInteger)self.slotIDs.count) { return @""; }
        NSString *slotID = self.slotIDs[(NSUInteger)row];
        if ([[tableColumn identifier] isEqualToString:@"slotCount"]) {
            return self.slotCounts[slotID] ?: @0;
        }
        return FTMDisplayNameForSoundSlot(slotID);
    }

    if (tableView == self.filesTableView) {
        if (row < 0 || row >= (NSInteger)self.selectedSlotFiles.count) { return @""; }
        return self.selectedSlotFiles[(NSUInteger)row].lastPathComponent;
    }

    return @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSTableView *tableView = notification.object;
    if (tableView == self.profilesTableView) {
        [self refreshProfileDependentUI];
        return;
    }
    if (tableView == self.slotsTableView) {
        [self refreshSelectedSlotFiles];
        return;
    }
    if (tableView == self.filesTableView) {
        [self updateButtonStates];
        return;
    }
}

#pragma mark - Utilities

- (void)notifyProfilesChangedAndReloadSelectingProfileID:(NSString *)profileID invalidateResolver:(BOOL)invalidateResolver {
    (void)invalidateResolver;
    if (self.onProfilesChanged) {
        self.onProfilesChanged();
    }
    [self reloadAllUI];
    NSInteger row = [self rowForProfileID:profileID];
    if (row >= 0) {
        [self.profilesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    }
}

- (void)showErrorAlert:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"Action Failed";
    alert.informativeText = error.localizedDescription ?: @"Unknown error";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (NSString *)previewPathForSelectedContext {
    FTMProfile *profile = [self selectedProfile];
    if (!profile) {
        return nil;
    }
    NSString *slotID = [self selectedSlotID];
    return [self.soundResolver randomSoundPathForSlotID:slotID profile:profile];
}

- (void)presentWarnings:(NSArray<NSString *> *)warnings title:(NSString *)title {
    if (warnings.count == 0) {
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = title ?: @"Warnings";
    NSUInteger maxLines = MIN((NSUInteger)10, warnings.count);
    NSArray<NSString *> *snippet = [warnings subarrayWithRange:NSMakeRange(0, maxLines)];
    NSString *body = [snippet componentsJoinedByString:@"\n"];
    if (warnings.count > maxLines) {
        body = [body stringByAppendingFormat:@"\n… and %lu more", (unsigned long)(warnings.count - maxLines)];
    }
    body = [body stringByAppendingFormat:@"\n\nTotal warnings: %lu", (unsigned long)warnings.count];
    alert.informativeText = body;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (NSString *)promptForTextWithTitle:(NSString *)title message:(NSString *)message defaultValue:(NSString *)defaultValue {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"Input";
    alert.informativeText = message ?: @"";
    [alert addButtonWithTitle:@"OK"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    input.stringValue = defaultValue ?: @"";
    alert.accessoryView = input;

    NSModalResponse response = [alert runModal];
    if (response != NSAlertFirstButtonReturn) {
        return nil;
    }

    NSString *trimmed = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length ? trimmed : nil;
}

@end
