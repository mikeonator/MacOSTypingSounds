#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const FTMDefaultsKeyTerminalsOnly;
FOUNDATION_EXPORT NSString * const FTMDefaultsKeyMuted;
FOUNDATION_EXPORT NSString * const FTMDefaultsKeyActiveProfileID;
FOUNDATION_EXPORT NSString * const FTMDefaultsKeyAssignedAppsOnly;
FOUNDATION_EXPORT NSString * const FTMDefaultsKeyDidMigrateV2Routing;

FOUNDATION_EXPORT NSString * const FTMSoundSlotTyping;
FOUNDATION_EXPORT NSString * const FTMSoundSlotEnter;
FOUNDATION_EXPORT NSString * const FTMSoundSlotBackspace;
FOUNDATION_EXPORT NSString * const FTMSoundSlotTab;
FOUNDATION_EXPORT NSString * const FTMSoundSlotSpace;
FOUNDATION_EXPORT NSString * const FTMSoundSlotEscape;
FOUNDATION_EXPORT NSString * const FTMSoundSlotLaunch;
FOUNDATION_EXPORT NSString * const FTMSoundSlotQuit;

FOUNDATION_EXPORT NSString * const FTMProfileSystemErrorDomain;

typedef NS_ENUM(NSInteger, FTMProfileSystemErrorCode) {
    FTMProfileSystemErrorUnknown = 1,
    FTMProfileSystemErrorInvalidSoundPack = 2,
    FTMProfileSystemErrorMissingTypingSounds = 3,
    FTMProfileSystemErrorOggDecodeFailed = 4,
    FTMProfileSystemErrorProfileNotFound = 5,
    FTMProfileSystemErrorFileOperationFailed = 6,
};

FOUNDATION_EXPORT NSArray<NSString *> *FTMAllSoundSlotIDs(void);
FOUNDATION_EXPORT NSString *FTMDisplayNameForSoundSlot(NSString *slotID);
FOUNDATION_EXPORT NSString *FTMFolderNameForSoundSlot(NSString *slotID);
FOUNDATION_EXPORT NSArray<NSString *> *FTMSupportedImportExtensions(void);

@interface FTMProfile : NSObject <NSCopying>
@property (nonatomic, copy) NSString *profileID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *relativePath;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *updatedAt;

+ (instancetype)profileWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface FTMAppProfileRule : NSObject <NSCopying>
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *profileID;
@property (nonatomic, copy, nullable) NSString *appNameHint;
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *updatedAt;

+ (instancetype)ruleWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface FTMProfileAsset : NSObject <NSCopying>
@property (nonatomic, copy) NSString *assetID;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, copy) NSString *storedFileName;
@property (nonatomic, strong) NSDate *importedAt;
@property (nonatomic, copy, nullable) NSString *sourceExtension;

+ (instancetype)assetWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface FTMSoundPackImporter : NSObject
- (BOOL)importSoundPackFolderURL:(NSURL *)folderURL
            intoProfileDirectory:(NSURL *)profileDirectoryURL
                        warnings:(NSArray<NSString *> * _Nullable * _Nullable)warnings
                           error:(NSError * _Nullable * _Nullable)error;

- (BOOL)addAudioFilesAtURLs:(NSArray<NSURL *> *)audioURLs
                   toSlotID:(NSString *)slotID
           profileDirectory:(NSURL *)profileDirectoryURL
                   warnings:(NSArray<NSString *> * _Nullable * _Nullable)warnings
                      error:(NSError * _Nullable * _Nullable)error;

- (BOOL)removeFilesNamed:(NSArray<NSString *> *)fileNames
              fromSlotID:(NSString *)slotID
        profileDirectory:(NSURL *)profileDirectoryURL
                   error:(NSError * _Nullable * _Nullable)error;

- (BOOL)clearSlotID:(NSString *)slotID
   profileDirectory:(NSURL *)profileDirectoryURL
              error:(NSError * _Nullable * _Nullable)error;

- (NSArray<NSURL *> *)fileURLsForSlotID:(NSString *)slotID
                       profileDirectory:(NSURL *)profileDirectoryURL;
@end

@interface FTMProfileStore : NSObject
@property (nonatomic, strong, readonly) NSArray<FTMProfile *> *profiles;
@property (nonatomic, strong, readonly) NSArray<FTMAppProfileRule *> *appRules;
@property (nonatomic, strong, readonly) NSURL *profilesRootURL;
@property (nonatomic, strong, readonly) NSURL *metadataURL;

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults bundle:(NSBundle *)bundle;
- (instancetype)initWithBaseDirectoryURL:(NSURL *)baseDirectoryURL
                                defaults:(NSUserDefaults *)defaults
                                  bundle:(NSBundle *)bundle NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)loadOrInitialize:(NSError * _Nullable * _Nullable)error;
- (nullable FTMProfile *)activeProfile;
- (BOOL)setActiveProfileID:(NSString *)profileID error:(NSError * _Nullable * _Nullable)error;
 - (nullable FTMAppProfileRule *)appRuleForBundleIdentifier:(NSString *)bundleIdentifier;
 - (nullable FTMProfile *)assignedProfileForBundleIdentifier:(NSString *)bundleIdentifier;
 - (BOOL)setAppRuleForBundleIdentifier:(NSString *)bundleIdentifier
                            appNameHint:(nullable NSString *)appNameHint
                              profileID:(NSString *)profileID
                                  error:(NSError * _Nullable * _Nullable)error;
 - (BOOL)removeAppRuleForBundleIdentifier:(NSString *)bundleIdentifier error:(NSError * _Nullable * _Nullable)error;

- (FTMProfile *)createEmptyProfileNamed:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (nullable FTMProfile *)duplicateProfile:(FTMProfile *)profile error:(NSError * _Nullable * _Nullable)error;
- (BOOL)renameProfile:(FTMProfile *)profile toName:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (BOOL)deleteProfile:(FTMProfile *)profile error:(NSError * _Nullable * _Nullable)error;

- (nullable FTMProfile *)importProfileFromFolderURL:(NSURL *)folderURL
                                            importer:(FTMSoundPackImporter *)importer
                                            warnings:(NSArray<NSString *> * _Nullable * _Nullable)warnings
                                               error:(NSError * _Nullable * _Nullable)error;

- (BOOL)addAudioFilesAtURLs:(NSArray<NSURL *> *)audioURLs
                   toSlotID:(NSString *)slotID
                    profile:(FTMProfile *)profile
                   importer:(FTMSoundPackImporter *)importer
                   warnings:(NSArray<NSString *> * _Nullable * _Nullable)warnings
                      error:(NSError * _Nullable * _Nullable)error;

- (BOOL)removeFilesNamed:(NSArray<NSString *> *)fileNames
              fromSlotID:(NSString *)slotID
                 profile:(FTMProfile *)profile
                importer:(FTMSoundPackImporter *)importer
                   error:(NSError * _Nullable * _Nullable)error;

- (BOOL)clearSlotID:(NSString *)slotID
            profile:(FTMProfile *)profile
           importer:(FTMSoundPackImporter *)importer
              error:(NSError * _Nullable * _Nullable)error;

 - (BOOL)importAudioFolderFlat:(NSURL *)folderURL
                    intoProfile:(FTMProfile *)profile
                       importer:(FTMSoundPackImporter *)importer
                       warnings:(NSArray<NSString *> * _Nullable * _Nullable)warnings
                          error:(NSError * _Nullable * _Nullable)error;
 - (BOOL)addAudioFilesToProfileLibrary:(NSArray<NSURL *> *)audioURLs
                               profile:(FTMProfile *)profile
                              importer:(FTMSoundPackImporter *)importer
                              warnings:(NSArray<NSString *> * _Nullable * _Nullable)warnings
                                 error:(NSError * _Nullable * _Nullable)error;
 - (NSArray<FTMProfileAsset *> *)assetsForProfile:(nullable FTMProfile *)profile;
 - (NSArray<FTMProfileAsset *> *)assignedAssetsForSlotID:(NSString *)slotID profile:(nullable FTMProfile *)profile;
 - (NSArray<FTMProfileAsset *> *)unassignedAssetsForProfile:(nullable FTMProfile *)profile;
 - (BOOL)assignAssetIDs:(NSArray<NSString *> *)assetIDs
               toSlotID:(NSString *)slotID
                profile:(FTMProfile *)profile
                  error:(NSError * _Nullable * _Nullable)error;
 - (BOOL)unassignAssetIDs:(NSArray<NSString *> *)assetIDs
               fromSlotID:(NSString *)slotID
                  profile:(FTMProfile *)profile
                    error:(NSError * _Nullable * _Nullable)error;
 - (BOOL)deleteAssetIDsFromProfile:(NSArray<NSString *> *)assetIDs
                           profile:(FTMProfile *)profile
                             error:(NSError * _Nullable * _Nullable)error;

- (NSDictionary<NSString *, NSNumber *> *)slotFileCountsForProfile:(nullable FTMProfile *)profile;
- (NSArray<NSURL *> *)fileURLsForSlotID:(NSString *)slotID profile:(nullable FTMProfile *)profile;
- (NSURL *)profileDirectoryURLForProfile:(FTMProfile *)profile;
- (BOOL)touchProfile:(FTMProfile *)profile error:(NSError * _Nullable * _Nullable)error;
@end

@interface FTMSoundResolver : NSObject
- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore bundle:(NSBundle *)bundle;
- (NSString *)slotIDForKeyCode:(unsigned short)keyCode;
- (nullable NSString *)soundPathForKeyCode:(unsigned short)keyCode;
- (nullable NSString *)soundPathForKeyCode:(unsigned short)keyCode profile:(nullable FTMProfile *)profile;
- (nullable NSString *)soundPathForEventSlotID:(NSString *)slotID;
- (nullable NSString *)soundPathForEventSlotID:(NSString *)slotID profile:(nullable FTMProfile *)profile;
- (nullable NSString *)randomSoundPathForSlotID:(NSString *)slotID profile:(nullable FTMProfile *)profile;
- (void)invalidateCache;
@end

@interface FTMSoundPlayer : NSObject <NSSoundDelegate>
- (void)playSoundAtPath:(nullable NSString *)path;
@end

NS_ASSUME_NONNULL_END
