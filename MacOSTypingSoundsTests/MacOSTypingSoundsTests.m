#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>

#import "FTMProfileSystem.h"

@interface MacOSTypingSoundsTests : XCTestCase
@property (nonatomic, strong) NSURL *tempBaseURL;
@property (nonatomic, strong) NSUserDefaults *testDefaults;
@property (nonatomic, copy) NSString *suiteName;
@end

@implementation MacOSTypingSoundsTests

- (void)setUp {
    [super setUp];

    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"MacOSTypingSoundsTests-%@", uuid]];
    self.tempBaseURL = [NSURL fileURLWithPath:tempPath isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.tempBaseURL withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *suiteName = [NSString stringWithFormat:@"MacOSTypingSoundsTests.%@", uuid];
    self.suiteName = suiteName;
    self.testDefaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
    [self.testDefaults removePersistentDomainForName:suiteName];
}

- (void)tearDown {
    if (self.testDefaults) {
        if (self.suiteName.length > 0) {
            [self.testDefaults removePersistentDomainForName:self.suiteName];
        }
    }
    [[NSFileManager defaultManager] removeItemAtURL:self.tempBaseURL error:nil];
    [super tearDown];
}

- (void)testProfileStoreCreatesDefaultProfileAndActiveProfile {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];

    NSError *error = nil;
    XCTAssertTrue([store loadOrInitialize:&error], @"loadOrInitialize failed: %@", error);
    XCTAssertNil(error);
    XCTAssertGreaterThan(store.profiles.count, 0);

    FTMProfile *active = [store activeProfile];
    XCTAssertNotNil(active);
    XCTAssertEqualObjects([self.testDefaults stringForKey:FTMDefaultsKeyActiveProfileID], active.profileID);

}

- (void)testSoundResolverMapsSpecialKeys {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([store loadOrInitialize:nil]);

    FTMSoundResolver *resolver = [[FTMSoundResolver alloc] initWithProfileStore:store bundle:[NSBundle mainBundle]];
    XCTAssertEqualObjects([resolver slotIDForKeyCode:36], FTMSoundSlotEnter);
    XCTAssertEqualObjects([resolver slotIDForKeyCode:76], FTMSoundSlotEnter);
    XCTAssertEqualObjects([resolver slotIDForKeyCode:51], FTMSoundSlotBackspace);
    XCTAssertEqualObjects([resolver slotIDForKeyCode:48], FTMSoundSlotTab);
    XCTAssertEqualObjects([resolver slotIDForKeyCode:49], FTMSoundSlotSpace);
    XCTAssertEqualObjects([resolver slotIDForKeyCode:53], FTMSoundSlotEscape);
    XCTAssertEqualObjects([resolver slotIDForKeyCode:12], FTMSoundSlotTyping);

}

- (void)testImporterRejectsMissingTypingFolder {
    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];
    NSURL *packURL = [self.tempBaseURL URLByAppendingPathComponent:@"BadPack" isDirectory:YES];
    NSURL *profileURL = [self.tempBaseURL URLByAppendingPathComponent:@"DestProfile" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:packURL withIntermediateDirectories:YES attributes:nil error:nil];

    NSError *error = nil;
    NSArray<NSString *> *warnings = nil;
    XCTAssertFalse([importer importSoundPackFolderURL:packURL intoProfileDirectory:profileURL warnings:&warnings error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, FTMProfileSystemErrorMissingTypingSounds);
}

- (void)testImporterImportsValidFolderConventionWithWavFile {
    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];
    NSURL *packURL = [self.tempBaseURL URLByAppendingPathComponent:@"GoodPack" isDirectory:YES];
    NSURL *typingURL = [packURL URLByAppendingPathComponent:@"typing" isDirectory:YES];
    NSURL *enterURL = [packURL URLByAppendingPathComponent:@"enter" isDirectory:YES];
    NSURL *profileURL = [self.tempBaseURL URLByAppendingPathComponent:@"ProfileDest" isDirectory:YES];

    [[NSFileManager defaultManager] createDirectoryAtURL:typingURL withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] createDirectoryAtURL:enterURL withIntermediateDirectories:YES attributes:nil error:nil];
    XCTAssertTrue([self writeTinyPCM16WavToURL:[typingURL URLByAppendingPathComponent:@"type.wav"]]);
    XCTAssertTrue([self writeTinyPCM16WavToURL:[enterURL URLByAppendingPathComponent:@"enter.wav"]]);

    NSError *error = nil;
    NSArray<NSString *> *warnings = nil;
    XCTAssertTrue([importer importSoundPackFolderURL:packURL intoProfileDirectory:profileURL warnings:&warnings error:&error], @"%@", error);
    XCTAssertNil(error);

    NSArray<NSURL *> *typingFiles = [importer fileURLsForSlotID:FTMSoundSlotTyping profileDirectory:profileURL];
    NSArray<NSURL *> *enterFiles = [importer fileURLsForSlotID:FTMSoundSlotEnter profileDirectory:profileURL];
    XCTAssertEqual(typingFiles.count, (NSUInteger)1);
    XCTAssertEqual(enterFiles.count, (NSUInteger)1);
}

- (void)testImporterConvertsOggVorbisToWav {
    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];
    NSURL *packURL = [self.tempBaseURL URLByAppendingPathComponent:@"OggPack" isDirectory:YES];
    NSURL *typingURL = [packURL URLByAppendingPathComponent:@"typing" isDirectory:YES];
    NSURL *profileURL = [self.tempBaseURL URLByAppendingPathComponent:@"OggProfileDest" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:typingURL withIntermediateDirectories:YES attributes:nil error:nil];

    NSURL *fixtureURL = [self oggFixtureURL];
    XCTAssertNotNil(fixtureURL);
    XCTAssertTrue([[NSFileManager defaultManager] copyItemAtURL:fixtureURL
                                                          toURL:[typingURL URLByAppendingPathComponent:@"typing_sample.ogg"]
                                                          error:nil]);

    NSError *error = nil;
    NSArray<NSString *> *warnings = nil;
    XCTAssertTrue([importer importSoundPackFolderURL:packURL intoProfileDirectory:profileURL warnings:&warnings error:&error], @"%@", error);
    XCTAssertNil(error);
    XCTAssertEqual(warnings.count, (NSUInteger)0);

    NSArray<NSURL *> *typingFiles = [importer fileURLsForSlotID:FTMSoundSlotTyping profileDirectory:profileURL];
    XCTAssertEqual(typingFiles.count, (NSUInteger)1);
    NSURL *convertedURL = typingFiles.firstObject;
    XCTAssertEqualObjects(convertedURL.pathExtension.lowercaseString, @"wav");

    NSNumber *sizeValue = nil;
    XCTAssertTrue([convertedURL getResourceValue:&sizeValue forKey:NSURLFileSizeKey error:nil]);
    XCTAssertGreaterThan(sizeValue.unsignedIntegerValue, (NSUInteger)0);
}

- (void)testProfileStoreAllowsClearingTypingSlotAndFallsBack {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([store loadOrInitialize:nil]);

    NSError *error = nil;
    FTMProfile *profile = [store createEmptyProfileNamed:@"Guardrail Clear" error:&error];
    XCTAssertNotNil(profile);
    XCTAssertNil(error);

    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];
    NSURL *sourceWavURL = [self.tempBaseURL URLByAppendingPathComponent:@"typing-single.wav"];
    XCTAssertTrue([self writeTinyPCM16WavToURL:sourceWavURL]);
    XCTAssertTrue([store addAudioFilesAtURLs:@[sourceWavURL]
                                    toSlotID:FTMSoundSlotTyping
                                     profile:profile
                                    importer:importer
                                    warnings:nil
                                       error:&error], @"%@", error);

    error = nil;
    XCTAssertTrue([store clearSlotID:FTMSoundSlotTyping profile:profile importer:importer error:&error]);
    XCTAssertNil(error);

    NSArray<NSURL *> *typingFiles = [store fileURLsForSlotID:FTMSoundSlotTyping profile:profile];
    XCTAssertEqual(typingFiles.count, (NSUInteger)0);

    FTMSoundResolver *resolver = [[FTMSoundResolver alloc] initWithProfileStore:store bundle:[NSBundle mainBundle]];
    NSString *path = [resolver randomSoundPathForSlotID:FTMSoundSlotTyping profile:profile];
    XCTAssertTrue(path == nil || path.length > 0);
}

- (void)testProfileStoreAllowsRemovingLastTypingSoundInV2 {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([store loadOrInitialize:nil]);

    NSError *error = nil;
    FTMProfile *profile = [store createEmptyProfileNamed:@"Guardrail Remove" error:&error];
    XCTAssertNotNil(profile);
    XCTAssertNil(error);

    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];
    NSURL *sourceWavURL = [self.tempBaseURL URLByAppendingPathComponent:@"typing-remove.wav"];
    XCTAssertTrue([self writeTinyPCM16WavToURL:sourceWavURL]);
    XCTAssertTrue([store addAudioFilesAtURLs:@[sourceWavURL]
                                    toSlotID:FTMSoundSlotTyping
                                     profile:profile
                                    importer:importer
                                    warnings:nil
                                       error:&error], @"%@", error);

    NSArray<NSURL *> *typingFiles = [store fileURLsForSlotID:FTMSoundSlotTyping profile:profile];
    XCTAssertEqual(typingFiles.count, (NSUInteger)1);

    error = nil;
    XCTAssertTrue([store removeFilesNamed:@[typingFiles.firstObject.lastPathComponent]
                                fromSlotID:FTMSoundSlotTyping
                                   profile:profile
                                  importer:importer
                                     error:&error]);
    XCTAssertNil(error);

    NSArray<NSURL *> *typingAfter = [store fileURLsForSlotID:FTMSoundSlotTyping profile:profile];
    XCTAssertEqual(typingAfter.count, (NSUInteger)0);
}

- (void)testFlatImportLeavesAssetsUnassigned {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([store loadOrInitialize:nil]);
    NSError *error = nil;
    FTMProfile *profile = [store createEmptyProfileNamed:@"Flat Import" error:&error];
    XCTAssertNotNil(profile);
    XCTAssertNil(error);

    NSURL *packURL = [self.tempBaseURL URLByAppendingPathComponent:@"FlatPack" isDirectory:YES];
    NSURL *nestedURL = [packURL URLByAppendingPathComponent:@"nested/sub" isDirectory:YES];
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:nestedURL withIntermediateDirectories:YES attributes:nil error:nil]);
    XCTAssertTrue([self writeTinyPCM16WavToURL:[packURL URLByAppendingPathComponent:@"one.wav"]]);
    XCTAssertTrue([self writeTinyPCM16WavToURL:[nestedURL URLByAppendingPathComponent:@"two.wav"]]);

    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];
    NSArray<NSString *> *warnings = nil;
    XCTAssertTrue([store importAudioFolderFlat:packURL intoProfile:profile importer:importer warnings:&warnings error:&error], @"%@", error);
    XCTAssertNil(error);
    XCTAssertNotNil(warnings);

    NSArray<FTMProfileAsset *> *assets = [store assetsForProfile:profile];
    NSArray<FTMProfileAsset *> *unassigned = [store unassignedAssetsForProfile:profile];
    XCTAssertEqual(assets.count, (NSUInteger)2);
    XCTAssertEqual(unassigned.count, (NSUInteger)2);
    XCTAssertEqual([store assignedAssetsForSlotID:FTMSoundSlotTyping profile:profile].count, (NSUInteger)0);
}

- (void)testAppRulePersistsAndResolvesAssignedProfile {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([store loadOrInitialize:nil]);
    FTMProfile *active = [store activeProfile];
    XCTAssertNotNil(active);

    NSError *error = nil;
    XCTAssertTrue([store setAppRuleForBundleIdentifier:@"com.example.TestApp"
                                            appNameHint:@"Test App"
                                              profileID:active.profileID
                                                  error:&error], @"%@", error);
    XCTAssertNil(error);

    FTMAppProfileRule *rule = [store appRuleForBundleIdentifier:@"com.example.TestApp"];
    XCTAssertNotNil(rule);
    XCTAssertEqualObjects(rule.appNameHint, @"Test App");
    FTMProfile *assigned = [store assignedProfileForBundleIdentifier:@"com.example.testapp"];
    XCTAssertEqualObjects(assigned.profileID, active.profileID);

    FTMProfileStore *reloaded = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([reloaded loadOrInitialize:&error], @"%@", error);
    XCTAssertNil(error);
    XCTAssertNotNil([reloaded appRuleForBundleIdentifier:@"com.example.testapp"]);
}

- (void)testAssignedAppsOnlyDefaultsReadPrecedence {
    XCTAssertFalse(FTMReadAssignedAppsOnlyFromDefaults(self.testDefaults));

    [self.testDefaults setBool:YES forKey:FTMDefaultsKeyTerminalsOnly];
    XCTAssertTrue(FTMReadAssignedAppsOnlyFromDefaults(self.testDefaults));

    [self.testDefaults setBool:NO forKey:FTMDefaultsKeyAssignedAppsOnly];
    XCTAssertFalse(FTMReadAssignedAppsOnlyFromDefaults(self.testDefaults));

    [self.testDefaults setBool:YES forKey:FTMDefaultsKeyRoutingAssignedAppsOnly];
    XCTAssertTrue(FTMReadAssignedAppsOnlyFromDefaults(self.testDefaults));
}

- (void)testAssignedAppsOnlyDefaultsWriteSyncsCanonicalAndLegacyV2Key {
    FTMWriteAssignedAppsOnlyToDefaults(self.testDefaults, YES);
    XCTAssertTrue([self.testDefaults boolForKey:FTMDefaultsKeyRoutingAssignedAppsOnly]);
    XCTAssertTrue([self.testDefaults boolForKey:FTMDefaultsKeyAssignedAppsOnly]);

    FTMWriteAssignedAppsOnlyToDefaults(self.testDefaults, NO);
    XCTAssertFalse([self.testDefaults boolForKey:FTMDefaultsKeyRoutingAssignedAppsOnly]);
    XCTAssertFalse([self.testDefaults boolForKey:FTMDefaultsKeyAssignedAppsOnly]);
}

- (void)testBackfillAssignedAppsOnlyDefaultsCopiesLegacyV2Key {
    [self.testDefaults setBool:YES forKey:FTMDefaultsKeyAssignedAppsOnly];
    XCTAssertNil([self.testDefaults objectForKey:FTMDefaultsKeyRoutingAssignedAppsOnly]);

    FTMBackfillAssignedAppsOnlyDefaultsIfNeeded(self.testDefaults);

    XCTAssertEqualObjects([self.testDefaults objectForKey:FTMDefaultsKeyRoutingAssignedAppsOnly], @YES);
    XCTAssertEqualObjects([self.testDefaults objectForKey:FTMDefaultsKeyAssignedAppsOnly], @YES);
}

- (void)testBackfillAssignedAppsOnlyDefaultsCopiesCanonicalForDowngrade {
    [self.testDefaults setBool:YES forKey:FTMDefaultsKeyRoutingAssignedAppsOnly];
    [self.testDefaults removeObjectForKey:FTMDefaultsKeyAssignedAppsOnly];
    XCTAssertNil([self.testDefaults objectForKey:FTMDefaultsKeyAssignedAppsOnly]);

    FTMBackfillAssignedAppsOnlyDefaultsIfNeeded(self.testDefaults);

    XCTAssertEqualObjects([self.testDefaults objectForKey:FTMDefaultsKeyAssignedAppsOnly], @YES);
}

- (void)testLoadOrInitializeBackfillsCanonicalAssignedAppsOnlyKey {
    [self.testDefaults setBool:YES forKey:FTMDefaultsKeyAssignedAppsOnly];
    XCTAssertNil([self.testDefaults objectForKey:FTMDefaultsKeyRoutingAssignedAppsOnly]);

    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    NSError *error = nil;
    XCTAssertTrue([store loadOrInitialize:&error], @"%@", error);
    XCTAssertNil(error);

    XCTAssertEqualObjects([self.testDefaults objectForKey:FTMDefaultsKeyRoutingAssignedAppsOnly], @YES);
    XCTAssertTrue(FTMReadAssignedAppsOnlyFromDefaults(self.testDefaults));
}

- (void)testLegacyTerminalOnlyMigrationSeedsRulesAndEnablesAssignedAppsOnly {
    [self.testDefaults setBool:YES forKey:FTMDefaultsKeyTerminalsOnly];
    [self.testDefaults removeObjectForKey:FTMDefaultsKeyDidMigrateV2Routing];
    [self.testDefaults removeObjectForKey:FTMDefaultsKeyAssignedAppsOnly];
    [self.testDefaults removeObjectForKey:FTMDefaultsKeyRoutingAssignedAppsOnly];

    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    NSError *error = nil;
    XCTAssertTrue([store loadOrInitialize:&error], @"%@", error);
    XCTAssertNil(error);

    XCTAssertTrue([self.testDefaults boolForKey:FTMDefaultsKeyDidMigrateV2Routing]);
    XCTAssertTrue([self.testDefaults boolForKey:FTMDefaultsKeyRoutingAssignedAppsOnly]);
    XCTAssertTrue([self.testDefaults boolForKey:FTMDefaultsKeyAssignedAppsOnly]);
    XCTAssertNotNil([store appRuleForBundleIdentifier:@"com.apple.terminal"]);
    XCTAssertNotNil([store appRuleForBundleIdentifier:@"com.googlecode.iterm2"]);
}

- (void)testAppRuleNormalizationDedupesCaseVariants {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([store loadOrInitialize:nil]);
    FTMProfile *active = [store activeProfile];
    XCTAssertNotNil(active);

    NSError *error = nil;
    XCTAssertTrue([store setAppRuleForBundleIdentifier:@"com.Example.MixedCase"
                                            appNameHint:@"Mixed A"
                                              profileID:active.profileID
                                                  error:&error], @"%@", error);
    XCTAssertNil(error);

    XCTAssertTrue([store setAppRuleForBundleIdentifier:@"COM.EXAMPLE.MIXEDCASE"
                                            appNameHint:@"Mixed B"
                                              profileID:active.profileID
                                                  error:&error], @"%@", error);
    XCTAssertNil(error);

    XCTAssertEqual(store.appRules.count, (NSUInteger)1);
    FTMAppProfileRule *rule = [store appRules].firstObject;
    XCTAssertEqualObjects(rule.bundleIdentifier, @"com.example.mixedcase");
    XCTAssertEqualObjects(rule.appNameHint, @"Mixed B");
}

- (void)testPruneInvalidAppRulesRemovesDuplicatesAndMissingProfiles {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    NSError *error = nil;
    XCTAssertTrue([store loadOrInitialize:&error], @"%@", error);
    XCTAssertNil(error);
    FTMProfile *active = [store activeProfile];
    XCTAssertNotNil(active);

    NSDictionary *metadata = @{
        @"schemaVersion": @3,
        @"profiles": @[[active dictionaryRepresentation]],
        @"appRules": @[
            @{
                @"bundleIdentifier": @"com.example.keep",
                @"profileID": active.profileID,
                @"appNameHint": @"Keep A",
            },
            @{
                @"bundleIdentifier": @"com.example.keep",
                @"profileID": active.profileID,
                @"appNameHint": @"Keep B",
            },
            @{
                @"bundleIdentifier": @"",
                @"profileID": active.profileID,
            },
            @{
                @"bundleIdentifier": @"com.example.missing",
                @"profileID": @"missing-profile-id",
            },
        ],
    };
    XCTAssertTrue([metadata writeToURL:store.metadataURL atomically:YES]);

    FTMProfileStore *reloaded = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([reloaded loadOrInitialize:&error], @"%@", error);
    XCTAssertNil(error);

    XCTAssertEqual(reloaded.appRules.count, (NSUInteger)1);
    FTMAppProfileRule *kept = [reloaded appRuleForBundleIdentifier:@"com.example.keep"];
    XCTAssertNotNil(kept);
    XCTAssertEqualObjects(kept.appNameHint, @"Keep B");
}

- (void)testDeleteAssetIDsRemovesAssignmentsAndFileURLs {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([store loadOrInitialize:nil]);

    NSError *error = nil;
    FTMProfile *profile = [store createEmptyProfileNamed:@"Delete Asset Cascade" error:&error];
    XCTAssertNotNil(profile);
    XCTAssertNil(error);

    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];
    NSURL *sourceWavURL = [self.tempBaseURL URLByAppendingPathComponent:@"delete-cascade.wav"];
    XCTAssertTrue([self writeTinyPCM16WavToURL:sourceWavURL]);
    XCTAssertTrue([store addAudioFilesAtURLs:@[sourceWavURL]
                                    toSlotID:FTMSoundSlotTyping
                                     profile:profile
                                    importer:importer
                                    warnings:nil
                                       error:&error], @"%@", error);
    XCTAssertNil(error);

    NSArray<FTMProfileAsset *> *assigned = [store assignedAssetsForSlotID:FTMSoundSlotTyping profile:profile];
    XCTAssertEqual(assigned.count, (NSUInteger)1);
    NSString *assetID = assigned.firstObject.assetID;
    NSString *pathBeforeDelete = [store fileURLsForSlotID:FTMSoundSlotTyping profile:profile].firstObject.path;
    XCTAssertNotNil(pathBeforeDelete);

    XCTAssertTrue([store deleteAssetIDsFromProfile:@[assetID] profile:profile error:&error], @"%@", error);
    XCTAssertNil(error);
    XCTAssertEqual([store assetsForProfile:profile].count, (NSUInteger)0);
    XCTAssertEqual([store assignedAssetsForSlotID:FTMSoundSlotTyping profile:profile].count, (NSUInteger)0);
    XCTAssertEqual([store fileURLsForSlotID:FTMSoundSlotTyping profile:profile].count, (NSUInteger)0);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:pathBeforeDelete]);
}

- (void)testAssignAssetIDsIsIdempotent {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([store loadOrInitialize:nil]);

    NSError *error = nil;
    FTMProfile *profile = [store createEmptyProfileNamed:@"Assign Idempotent" error:&error];
    XCTAssertNotNil(profile);
    XCTAssertNil(error);

    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];
    NSURL *sourceWavURL = [self.tempBaseURL URLByAppendingPathComponent:@"assign-idempotent.wav"];
    XCTAssertTrue([self writeTinyPCM16WavToURL:sourceWavURL]);
    XCTAssertTrue([store addAudioFilesToProfileLibrary:@[sourceWavURL]
                                               profile:profile
                                              importer:importer
                                              warnings:nil
                                                 error:&error], @"%@", error);
    XCTAssertNil(error);

    NSArray<FTMProfileAsset *> *assets = [store assetsForProfile:profile];
    XCTAssertEqual(assets.count, (NSUInteger)1);
    NSString *assetID = assets.firstObject.assetID;
    NSArray<NSString *> *duplicateIDs = @[assetID, assetID];

    XCTAssertTrue([store assignAssetIDs:duplicateIDs toSlotID:FTMSoundSlotTyping profile:profile error:&error], @"%@", error);
    XCTAssertTrue([store assignAssetIDs:@[assetID] toSlotID:FTMSoundSlotTyping profile:profile error:&error], @"%@", error);
    XCTAssertNil(error);

    XCTAssertEqual([store assignedAssetsForSlotID:FTMSoundSlotTyping profile:profile].count, (NSUInteger)1);
}

- (void)testSoundResolverReflectsUpdatedAssignmentsAfterInvalidateCache {
    FTMProfileStore *store = [[FTMProfileStore alloc] initWithBaseDirectoryURL:self.tempBaseURL defaults:self.testDefaults bundle:[NSBundle mainBundle]];
    XCTAssertTrue([store loadOrInitialize:nil]);

    NSError *error = nil;
    FTMProfile *profile = [store createEmptyProfileNamed:@"Resolver Cache" error:&error];
    XCTAssertNotNil(profile);
    XCTAssertNil(error);
    XCTAssertTrue([store setActiveProfileID:profile.profileID error:&error], @"%@", error);
    XCTAssertNil(error);

    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];
    NSURL *sourceWavURL = [self.tempBaseURL URLByAppendingPathComponent:@"resolver-cache.wav"];
    XCTAssertTrue([self writeTinyPCM16WavToURL:sourceWavURL]);
    XCTAssertTrue([store addAudioFilesAtURLs:@[sourceWavURL]
                                    toSlotID:FTMSoundSlotTyping
                                     profile:profile
                                    importer:importer
                                    warnings:nil
                                       error:&error], @"%@", error);
    XCTAssertNil(error);

    FTMSoundResolver *resolver = [[FTMSoundResolver alloc] initWithProfileStore:store bundle:[NSBundle mainBundle]];
    NSString *initialPath = [resolver randomSoundPathForSlotID:FTMSoundSlotTyping profile:nil];
    XCTAssertTrue(initialPath.length > 0);

    NSArray<FTMProfileAsset *> *assignedAssets = [store assignedAssetsForSlotID:FTMSoundSlotTyping profile:profile];
    XCTAssertEqual(assignedAssets.count, (NSUInteger)1);
    XCTAssertTrue([store deleteAssetIDsFromProfile:@[assignedAssets.firstObject.assetID] profile:profile error:&error], @"%@", error);
    XCTAssertNil(error);

    NSString *stalePath = [resolver randomSoundPathForSlotID:FTMSoundSlotTyping profile:nil];
    XCTAssertEqualObjects(stalePath, initialPath);

    [resolver invalidateCache];
    NSString *updatedPath = [resolver randomSoundPathForSlotID:FTMSoundSlotTyping profile:nil];
    XCTAssertNotEqualObjects(updatedPath, initialPath);
}

#pragma mark - Helpers

- (NSURL *)oggFixtureURL {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSURL *url = [bundle URLForResource:@"typing_sample" withExtension:@"ogg" subdirectory:@"Fixtures/Ogg"];
    if (!url) {
        url = [bundle URLForResource:@"typing_sample" withExtension:@"ogg"];
    }
    return url;
}

- (BOOL)writeTinyPCM16WavToURL:(NSURL *)url {
    int sampleRate = 22050;
    int channels = 1;
    int frameCount = 32;
    int bitsPerSample = 16;
    int bytesPerSample = bitsPerSample / 8;
    int dataSize = frameCount * channels * bytesPerSample;
    int riffChunkSize = 36 + dataSize;
    int byteRate = sampleRate * channels * bytesPerSample;
    short samples[32] = {0};

    NSMutableData *data = [NSMutableData data];
    [data appendBytes:"RIFF" length:4];
    [self appendLE32:(uint32_t)riffChunkSize toData:data];
    [data appendBytes:"WAVE" length:4];
    [data appendBytes:"fmt " length:4];
    [self appendLE32:16 toData:data];
    [self appendLE16:1 toData:data];
    [self appendLE16:(uint16_t)channels toData:data];
    [self appendLE32:(uint32_t)sampleRate toData:data];
    [self appendLE32:(uint32_t)byteRate toData:data];
    [self appendLE16:(uint16_t)(channels * bytesPerSample) toData:data];
    [self appendLE16:(uint16_t)bitsPerSample toData:data];
    [data appendBytes:"data" length:4];
    [self appendLE32:(uint32_t)dataSize toData:data];
    [data appendBytes:samples length:(NSUInteger)dataSize];

    return [data writeToURL:url atomically:YES];
}

- (void)appendLE16:(uint16_t)value toData:(NSMutableData *)data {
    uint8_t bytes[2];
    bytes[0] = (uint8_t)(value & 0xFF);
    bytes[1] = (uint8_t)((value >> 8) & 0xFF);
    [data appendBytes:bytes length:2];
}

- (void)appendLE32:(uint32_t)value toData:(NSMutableData *)data {
    uint8_t bytes[4];
    bytes[0] = (uint8_t)(value & 0xFF);
    bytes[1] = (uint8_t)((value >> 8) & 0xFF);
    bytes[2] = (uint8_t)((value >> 16) & 0xFF);
    bytes[3] = (uint8_t)((value >> 24) & 0xFF);
    [data appendBytes:bytes length:4];
}

@end
