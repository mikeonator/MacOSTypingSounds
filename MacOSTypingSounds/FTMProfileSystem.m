#import "FTMProfileSystem.h"

#include <stdlib.h>
#include <string.h>

#import "ThirdParty/stb_vorbis.c"

NSString * const FTMDefaultsKeyTerminalsOnly = @"terminalsOnly";
NSString * const FTMDefaultsKeyMuted = @"isMuted";
NSString * const FTMDefaultsKeyActiveProfileID = @"activeProfileID";
NSString * const FTMDefaultsKeyAssignedAppsOnly = @"assignedAppsOnly";
NSString * const FTMDefaultsKeyDidMigrateV2Routing = @"didMigrateV2Routing";

NSString * const FTMSoundSlotTyping = @"typing";
NSString * const FTMSoundSlotEnter = @"enter";
NSString * const FTMSoundSlotBackspace = @"backspace";
NSString * const FTMSoundSlotTab = @"tab";
NSString * const FTMSoundSlotSpace = @"space";
NSString * const FTMSoundSlotEscape = @"escape";
NSString * const FTMSoundSlotLaunch = @"launch";
NSString * const FTMSoundSlotQuit = @"quit";

NSString * const FTMProfileSystemErrorDomain = @"FTMProfileSystemErrorDomain";

static NSString * const FTMProfilesFileName = @"profiles.plist";
static NSString * const FTMProfilesDirectoryName = @"Profiles";
static NSString * const FTMProfileConfigFileName = @"profile-config.plist";
static NSString * const FTMProfileAssetsDirectoryName = @"Assets";
static NSInteger const FTMProfilesSchemaVersion = 3;
static NSInteger const FTMProfileConfigSchemaVersion = 1;

static NSString *FTMErrorDescription(NSString *description) {
    return description ?: @"Unknown error";
}

static NSError *FTMMakeError(FTMProfileSystemErrorCode code, NSString *description) {
    return [NSError errorWithDomain:FTMProfileSystemErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: FTMErrorDescription(description)}];
}

static NSArray<NSString *> *FTMSlotOrder(void) {
    static NSArray<NSString *> *slots;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        slots = @[
            FTMSoundSlotTyping,
            FTMSoundSlotEnter,
            FTMSoundSlotBackspace,
            FTMSoundSlotTab,
            FTMSoundSlotSpace,
            FTMSoundSlotEscape,
            FTMSoundSlotLaunch,
            FTMSoundSlotQuit,
        ];
    });
    return slots;
}

NSArray<NSString *> *FTMAllSoundSlotIDs(void) {
    return FTMSlotOrder();
}

NSString *FTMDisplayNameForSoundSlot(NSString *slotID) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        map = @{
            FTMSoundSlotTyping: @"Typing (Random Pool)",
            FTMSoundSlotEnter: @"Enter / Return",
            FTMSoundSlotBackspace: @"Backspace / Delete",
            FTMSoundSlotTab: @"Tab",
            FTMSoundSlotSpace: @"Space",
            FTMSoundSlotEscape: @"Escape",
            FTMSoundSlotLaunch: @"App Launch",
            FTMSoundSlotQuit: @"App Quit",
        };
    });
    return map[slotID] ?: slotID;
}

NSString *FTMFolderNameForSoundSlot(NSString *slotID) {
    return slotID ?: @"";
}

NSArray<NSString *> *FTMSupportedImportExtensions(void) {
    static NSArray<NSString *> *extensions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        extensions = @[@"mp3", @"wav", @"m4a", @"aiff", @"ogg"];
    });
    return extensions;
}

static NSSet<NSString *> *FTMSupportedImportExtensionSet(void) {
    static NSSet<NSString *> *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithArray:FTMSupportedImportExtensions()];
    });
    return set;
}

static NSURL *FTMSlotDirectoryURL(NSURL *profileDirectoryURL, NSString *slotID) {
    return [profileDirectoryURL URLByAppendingPathComponent:FTMFolderNameForSoundSlot(slotID) isDirectory:YES];
}

static NSURL *FTMProfileAssetsDirectoryURL(NSURL *profileDirectoryURL) {
    return [profileDirectoryURL URLByAppendingPathComponent:FTMProfileAssetsDirectoryName isDirectory:YES];
}

static NSURL *FTMProfileConfigURL(NSURL *profileDirectoryURL) {
    return [profileDirectoryURL URLByAppendingPathComponent:FTMProfileConfigFileName];
}

static BOOL FTMEnsureDirectoryExists(NSFileManager *fileManager, NSURL *directoryURL, NSError **error) {
    return [fileManager createDirectoryAtURL:directoryURL
                 withIntermediateDirectories:YES
                                  attributes:nil
                                       error:error];
}

static NSArray<NSURL *> *FTMDirectoryFilesSorted(NSFileManager *fileManager, NSURL *directoryURL) {
    NSArray<NSURL *> *urls = [fileManager contentsOfDirectoryAtURL:directoryURL
                                        includingPropertiesForKeys:nil
                                                           options:NSDirectoryEnumerationSkipsHiddenFiles
                                                             error:nil];
    if (!urls) {
        return @[];
    }

    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    for (NSURL *url in urls) {
        NSNumber *isDirectory = nil;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (![isDirectory boolValue]) {
            [files addObject:url];
        }
    }

    [files sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [[a lastPathComponent] localizedCaseInsensitiveCompare:[b lastPathComponent]];
    }];
    return files;
}

static NSArray<NSURL *> *FTMDirectoryFilesRecursiveSorted(NSFileManager *fileManager, NSURL *directoryURL) {
    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:directoryURL
                                                  includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                errorHandler:nil];
    if (!enumerator) {
        return @[];
    }

    NSMutableArray<NSURL *> *files = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        NSNumber *isDirectory = nil;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (![isDirectory boolValue]) {
            [files addObject:url];
        }
    }

    [files sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.path localizedCaseInsensitiveCompare:b.path];
    }];
    return files;
}

static NSString *FTMSanitizeBaseName(NSString *input) {
    if (input.length == 0) {
        return @"sound";
    }

    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<>\n\r\t"];
    NSArray<NSString *> *parts = [input componentsSeparatedByCharactersInSet:invalid];
    NSString *joined = [[parts componentsJoinedByString:@"_"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return joined.length > 0 ? joined : @"sound";
}

static NSURL *FTMUniqueDestinationURL(NSURL *directoryURL, NSString *baseName, NSString *extension, NSFileManager *fileManager) {
    NSString *safeBaseName = FTMSanitizeBaseName(baseName);
    NSString *safeExtension = extension.length ? [extension lowercaseString] : @"";
    NSUInteger counter = 0;

    while (YES) {
        NSString *candidateName;
        if (counter == 0) {
            candidateName = safeExtension.length ? [NSString stringWithFormat:@"%@.%@", safeBaseName, safeExtension] : safeBaseName;
        } else {
            candidateName = safeExtension.length ? [NSString stringWithFormat:@"%@-%lu.%@", safeBaseName, (unsigned long)counter, safeExtension] : [NSString stringWithFormat:@"%@-%lu", safeBaseName, (unsigned long)counter];
        }
        NSURL *candidateURL = [directoryURL URLByAppendingPathComponent:candidateName];
        if (![fileManager fileExistsAtPath:candidateURL.path]) {
            return candidateURL;
        }
        counter += 1;
    }
}

static BOOL FTMIsSupportedAudioExtension(NSString *extension) {
    NSSet<NSString *> *supported = FTMSupportedImportExtensionSet();
    NSString *safeExtension = extension ? extension : @"";
    return [supported containsObject:[safeExtension lowercaseString]];
}

static BOOL FTMValidateNativeAudioAtURL(NSURL *fileURL) {
    NSSound *sound = [[NSSound alloc] initWithContentsOfURL:fileURL byReference:YES];
    return sound != nil;
}

static NSString *FTMNormalizeBundleIdentifier(NSString *bundleIdentifier) {
    NSString *trimmed = [bundleIdentifier stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [[trimmed lowercaseString] copy];
}

static BOOL FTMIsLikelyBundleIdentifier(NSString *bundleIdentifier) {
    NSString *normalized = FTMNormalizeBundleIdentifier(bundleIdentifier);
    if (normalized.length == 0) {
        return NO;
    }
    return [normalized containsString:@"."];
}

static NSArray<NSString *> *FTMLegacyTerminalBundleIdentifiers(void) {
    static NSArray<NSString *> *bundles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bundles = @[
            @"com.googlecode.iterm2",
            @"com.apple.terminal",
            @"io.cool-retro-term",
            @"com.secretgeometry.cathode",
        ];
    });
    return bundles;
}

static void FTMAppendLE16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2];
    bytes[0] = (uint8_t)(value & 0xFF);
    bytes[1] = (uint8_t)((value >> 8) & 0xFF);
    [data appendBytes:bytes length:2];
}

static void FTMAppendLE32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4];
    bytes[0] = (uint8_t)(value & 0xFF);
    bytes[1] = (uint8_t)((value >> 8) & 0xFF);
    bytes[2] = (uint8_t)((value >> 16) & 0xFF);
    bytes[3] = (uint8_t)((value >> 24) & 0xFF);
    [data appendBytes:bytes length:4];
}

static BOOL FTMWritePCM16WAV(NSURL *destinationURL,
                             const short *interleavedPCM,
                             int samplesPerChannel,
                             int channels,
                             int sampleRate,
                             NSError **error) {
    if (!interleavedPCM || samplesPerChannel <= 0 || channels <= 0 || sampleRate <= 0) {
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorOggDecodeFailed, @"Decoded OGG audio was empty or invalid.");
        }
        return NO;
    }

    uint64_t totalSamples = (uint64_t)samplesPerChannel * (uint64_t)channels;
    uint64_t dataSize64 = totalSamples * sizeof(short);
    if (dataSize64 > UINT32_MAX) {
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorOggDecodeFailed, @"Decoded OGG audio is too large to write as WAV.");
        }
        return NO;
    }

    uint32_t dataSize = (uint32_t)dataSize64;
    uint32_t riffChunkSize = 36u + dataSize;
    uint16_t bitsPerSample = 16;
    uint16_t blockAlign = (uint16_t)(channels * (bitsPerSample / 8));
    uint32_t byteRate = (uint32_t)(sampleRate * blockAlign);

    NSMutableData *wavData = [NSMutableData dataWithCapacity:(NSUInteger)(44 + dataSize)];
    [wavData appendBytes:"RIFF" length:4];
    FTMAppendLE32(wavData, riffChunkSize);
    [wavData appendBytes:"WAVE" length:4];

    [wavData appendBytes:"fmt " length:4];
    FTMAppendLE32(wavData, 16);
    FTMAppendLE16(wavData, 1);
    FTMAppendLE16(wavData, (uint16_t)channels);
    FTMAppendLE32(wavData, (uint32_t)sampleRate);
    FTMAppendLE32(wavData, byteRate);
    FTMAppendLE16(wavData, blockAlign);
    FTMAppendLE16(wavData, bitsPerSample);

    [wavData appendBytes:"data" length:4];
    FTMAppendLE32(wavData, dataSize);
    [wavData appendBytes:interleavedPCM length:(NSUInteger)dataSize];

    return [wavData writeToURL:destinationURL options:NSDataWritingAtomic error:error];
}

static BOOL FTMConvertOggVorbisToWav(NSURL *oggURL, NSURL *wavURL, NSError **error) {
    int channels = 0;
    int sampleRate = 0;
    short *output = NULL;
    int samplesPerChannel = stb_vorbis_decode_filename([[oggURL path] fileSystemRepresentation], &channels, &sampleRate, &output);

    if (samplesPerChannel <= 0 || !output) {
        if (output) {
            free(output);
        }
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorOggDecodeFailed,
                                  [NSString stringWithFormat:@"Failed to decode OGG Vorbis file: %@", oggURL.lastPathComponent]);
        }
        return NO;
    }

    NSError *writeError = nil;
    BOOL ok = FTMWritePCM16WAV(wavURL, output, samplesPerChannel, channels, sampleRate, &writeError);
    free(output);
    if (!ok && error) {
        *error = writeError;
    }
    return ok;
}

static NSString *FTMSlotFallbackBundleResourceName(NSString *slotID) {
    if ([slotID isEqualToString:FTMSoundSlotEnter]) {
        return @"kenter";
    }
    if ([slotID isEqualToString:FTMSoundSlotLaunch]) {
        return @"poweron";
    }
    if ([slotID isEqualToString:FTMSoundSlotQuit]) {
        return @"poweroff";
    }
    return nil;
}

static NSArray<NSString *> *FTMBuiltinTypingResourceNames(void) {
    static NSArray<NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @[@"k2", @"k3", @"k4"];
    });
    return names;
}

static NSString *FTMUniqueProfileName(NSString *desiredName, NSArray<FTMProfile *> *existingProfiles, NSString *excludingProfileID) {
    NSString *base = desiredName.length ? [desiredName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"Profile";
    if (base.length == 0) {
        base = @"Profile";
    }

    NSMutableSet<NSString *> *taken = [NSMutableSet set];
    for (FTMProfile *profile in existingProfiles) {
        if (excludingProfileID && [profile.profileID isEqualToString:excludingProfileID]) {
            continue;
        }
        [taken addObject:[profile.name lowercaseString]];
    }

    if (![taken containsObject:[base lowercaseString]]) {
        return base;
    }

    NSUInteger idx = 2;
    while (YES) {
        NSString *candidate = [NSString stringWithFormat:@"%@ (%lu)", base, (unsigned long)idx];
        if (![taken containsObject:[candidate lowercaseString]]) {
            return candidate;
        }
        idx += 1;
    }
}

@interface FTMProfileStore ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) NSMutableArray<FTMProfile *> *mutableProfiles;
@property (nonatomic, strong) NSMutableArray<FTMAppProfileRule *> *mutableAppRules;
@end

@implementation FTMProfile

+ (instancetype)profileWithDictionary:(NSDictionary *)dictionary {
    FTMProfile *profile = [[FTMProfile alloc] init];
    profile.profileID = [dictionary[@"id"] isKindOfClass:[NSString class]] ? dictionary[@"id"] : [[NSUUID UUID] UUIDString];
    profile.name = [dictionary[@"name"] isKindOfClass:[NSString class]] ? dictionary[@"name"] : @"Profile";
    profile.relativePath = [dictionary[@"relativePath"] isKindOfClass:[NSString class]] ? dictionary[@"relativePath"] : profile.profileID;
    id created = dictionary[@"createdAt"];
    id updated = dictionary[@"updatedAt"];
    profile.createdAt = [created isKindOfClass:[NSDate class]] ? created : [NSDate date];
    profile.updatedAt = [updated isKindOfClass:[NSDate class]] ? updated : profile.createdAt;
    return profile;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"id": self.profileID ?: @"",
        @"name": self.name ?: @"Profile",
        @"relativePath": self.relativePath ?: self.profileID ?: @"",
        @"createdAt": self.createdAt ?: [NSDate date],
        @"updatedAt": self.updatedAt ?: [NSDate date],
    };
}

- (id)copyWithZone:(NSZone *)zone {
    FTMProfile *copy = [[[self class] allocWithZone:zone] init];
    copy.profileID = [self.profileID copy];
    copy.name = [self.name copy];
    copy.relativePath = [self.relativePath copy];
    copy.createdAt = self.createdAt;
    copy.updatedAt = self.updatedAt;
    return copy;
}

@end

@implementation FTMAppProfileRule

+ (instancetype)ruleWithDictionary:(NSDictionary *)dictionary {
    FTMAppProfileRule *rule = [[FTMAppProfileRule alloc] init];
    NSString *bundleIdentifier = [dictionary[@"bundleIdentifier"] isKindOfClass:[NSString class]] ? dictionary[@"bundleIdentifier"] : @"";
    rule.bundleIdentifier = FTMNormalizeBundleIdentifier(bundleIdentifier);
    rule.profileID = [dictionary[@"profileID"] isKindOfClass:[NSString class]] ? dictionary[@"profileID"] : @"";
    rule.appNameHint = [dictionary[@"appNameHint"] isKindOfClass:[NSString class]] ? dictionary[@"appNameHint"] : nil;
    id created = dictionary[@"createdAt"];
    id updated = dictionary[@"updatedAt"];
    rule.createdAt = [created isKindOfClass:[NSDate class]] ? created : [NSDate date];
    rule.updatedAt = [updated isKindOfClass:[NSDate class]] ? updated : rule.createdAt;
    return rule;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [@{
        @"bundleIdentifier": self.bundleIdentifier ?: @"",
        @"profileID": self.profileID ?: @"",
        @"createdAt": self.createdAt ?: [NSDate date],
        @"updatedAt": self.updatedAt ?: [NSDate date],
    } mutableCopy];
    if (self.appNameHint.length > 0) {
        dict[@"appNameHint"] = self.appNameHint;
    }
    return [dict copy];
}

- (id)copyWithZone:(NSZone *)zone {
    FTMAppProfileRule *copy = [[[self class] allocWithZone:zone] init];
    copy.bundleIdentifier = [self.bundleIdentifier copy];
    copy.profileID = [self.profileID copy];
    copy.appNameHint = [self.appNameHint copy];
    copy.createdAt = self.createdAt;
    copy.updatedAt = self.updatedAt;
    return copy;
}

@end

@implementation FTMProfileAsset

+ (instancetype)assetWithDictionary:(NSDictionary *)dictionary {
    FTMProfileAsset *asset = [[FTMProfileAsset alloc] init];
    asset.assetID = [dictionary[@"assetID"] isKindOfClass:[NSString class]] ? dictionary[@"assetID"] : [[NSUUID UUID] UUIDString];
    asset.displayName = [dictionary[@"displayName"] isKindOfClass:[NSString class]] ? dictionary[@"displayName"] : @"Sound";
    asset.storedFileName = [dictionary[@"storedFileName"] isKindOfClass:[NSString class]] ? dictionary[@"storedFileName"] : asset.displayName;
    id importedAt = dictionary[@"importedAt"];
    asset.importedAt = [importedAt isKindOfClass:[NSDate class]] ? importedAt : [NSDate date];
    asset.sourceExtension = [dictionary[@"sourceExtension"] isKindOfClass:[NSString class]] ? dictionary[@"sourceExtension"] : nil;
    return asset;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [@{
        @"assetID": self.assetID ?: @"",
        @"displayName": self.displayName ?: @"Sound",
        @"storedFileName": self.storedFileName ?: @"sound",
        @"importedAt": self.importedAt ?: [NSDate date],
    } mutableCopy];
    if (self.sourceExtension.length > 0) {
        dict[@"sourceExtension"] = self.sourceExtension;
    }
    return [dict copy];
}

- (id)copyWithZone:(NSZone *)zone {
    FTMProfileAsset *copy = [[[self class] allocWithZone:zone] init];
    copy.assetID = [self.assetID copy];
    copy.displayName = [self.displayName copy];
    copy.storedFileName = [self.storedFileName copy];
    copy.importedAt = self.importedAt;
    copy.sourceExtension = [self.sourceExtension copy];
    return copy;
}

@end

@interface FTMSoundPackImporter (FTMFlatImportInternal)
- (NSArray<NSURL *> *)ftm_recursiveSupportedAudioFilesUnderFolderURL:(NSURL *)folderURL
                                                            warnings:(NSArray<NSString *> * _Nullable __autoreleasing *)warnings;
- (nullable NSURL *)ftm_importAudioFileAtURL:(NSURL *)sourceURL
                               toDirectoryURL:(NSURL *)destinationDirectoryURL
                                preferredName:(NSString *)preferredName
                            sourceExtensionOut:(NSString * _Nullable * _Nullable)sourceExtensionOut
                                        error:(NSError * _Nullable * _Nullable)error;
@end

@implementation FTMSoundPackImporter {
    NSFileManager *_fileManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _fileManager = [NSFileManager defaultManager];
    }
    return self;
}

- (BOOL)importSoundPackFolderURL:(NSURL *)folderURL
            intoProfileDirectory:(NSURL *)profileDirectoryURL
                        warnings:(NSArray<NSString *> * _Nullable __autoreleasing *)warnings
                           error:(NSError * _Nullable __autoreleasing *)error {
    NSMutableArray<NSString *> *warningsList = [NSMutableArray array];
    NSError *dirError = nil;
    if (!FTMEnsureDirectoryExists(_fileManager, profileDirectoryURL, &dirError)) {
        if (error) { *error = dirError; }
        return NO;
    }

    NSMutableDictionary<NSString *, NSNumber *> *importedCounts = [NSMutableDictionary dictionary];

    for (NSString *slotID in FTMAllSoundSlotIDs()) {
        NSString *folderName = FTMFolderNameForSoundSlot(slotID);
        NSURL *sourceSlotURL = [folderURL URLByAppendingPathComponent:folderName isDirectory:YES];
        BOOL isDir = NO;
        if (![_fileManager fileExistsAtPath:sourceSlotURL.path isDirectory:&isDir] || !isDir) {
            importedCounts[slotID] = @0;
            continue;
        }

        NSArray<NSURL *> *sourceFiles = FTMDirectoryFilesSorted(_fileManager, sourceSlotURL);
        NSArray<NSString *> *slotWarnings = nil;
        NSUInteger before = [self fileURLsForSlotID:slotID profileDirectory:profileDirectoryURL].count;
        if (![self addAudioFilesAtURLs:sourceFiles toSlotID:slotID profileDirectory:profileDirectoryURL warnings:&slotWarnings error:error]) {
            return NO;
        }
        NSUInteger after = [self fileURLsForSlotID:slotID profileDirectory:profileDirectoryURL].count;
        importedCounts[slotID] = @(after > before ? (after - before) : 0);
        if (slotWarnings.count) {
            [warningsList addObjectsFromArray:slotWarnings];
        }
    }

    if ([importedCounts[FTMSoundSlotTyping] unsignedIntegerValue] == 0) {
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorMissingTypingSounds,
                                  @"Soundpack import failed: typing/ must contain at least one valid audio file.");
        }
        return NO;
    }

    if (warnings) {
        *warnings = [warningsList copy];
    }
    return YES;
}

- (BOOL)addAudioFilesAtURLs:(NSArray<NSURL *> *)audioURLs
                   toSlotID:(NSString *)slotID
           profileDirectory:(NSURL *)profileDirectoryURL
                   warnings:(NSArray<NSString *> * _Nullable __autoreleasing *)warnings
                      error:(NSError * _Nullable __autoreleasing *)error {
    if (![FTMAllSoundSlotIDs() containsObject:slotID]) {
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorInvalidSoundPack,
                                  [NSString stringWithFormat:@"Unknown sound slot: %@", slotID]);
        }
        return NO;
    }

    NSURL *slotDirectoryURL = FTMSlotDirectoryURL(profileDirectoryURL, slotID);
    NSError *dirError = nil;
    if (!FTMEnsureDirectoryExists(_fileManager, slotDirectoryURL, &dirError)) {
        if (error) { *error = dirError; }
        return NO;
    }

    NSMutableArray<NSString *> *warningList = [NSMutableArray array];
    for (NSURL *sourceURL in audioURLs) {
        NSNumber *isDirectory = nil;
        [sourceURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if ([isDirectory boolValue]) {
            [warningList addObject:[NSString stringWithFormat:@"Ignored folder in %@ slot: %@", slotID, sourceURL.lastPathComponent]];
            continue;
        }

        NSString *extension = [[sourceURL pathExtension] lowercaseString];
        if (!FTMIsSupportedAudioExtension(extension)) {
            [warningList addObject:[NSString stringWithFormat:@"Ignored unsupported file type: %@", sourceURL.lastPathComponent]];
            continue;
        }

        NSString *baseName = [[sourceURL lastPathComponent] stringByDeletingPathExtension];
        if ([extension isEqualToString:@"ogg"]) {
            NSURL *destURL = FTMUniqueDestinationURL(slotDirectoryURL, baseName, @"wav", _fileManager);
            NSError *oggError = nil;
            if (!FTMConvertOggVorbisToWav(sourceURL, destURL, &oggError)) {
                if (error) {
                    *error = oggError ?: FTMMakeError(FTMProfileSystemErrorOggDecodeFailed,
                                                     [NSString stringWithFormat:@"Failed to import OGG file %@", sourceURL.lastPathComponent]);
                }
                return NO;
            }
            continue;
        }

        if (!FTMValidateNativeAudioAtURL(sourceURL)) {
            [warningList addObject:[NSString stringWithFormat:@"Ignored unreadable audio file: %@", sourceURL.lastPathComponent]];
            continue;
        }

        NSURL *destURL = FTMUniqueDestinationURL(slotDirectoryURL, baseName, extension, _fileManager);
        NSError *copyError = nil;
        if (![_fileManager copyItemAtURL:sourceURL toURL:destURL error:&copyError]) {
            if (error) {
                *error = copyError ?: FTMMakeError(FTMProfileSystemErrorFileOperationFailed,
                                                   [NSString stringWithFormat:@"Failed copying %@", sourceURL.lastPathComponent]);
            }
            return NO;
        }
    }

    if (warnings) {
        *warnings = [warningList copy];
    }
    return YES;
}

- (BOOL)removeFilesNamed:(NSArray<NSString *> *)fileNames
              fromSlotID:(NSString *)slotID
        profileDirectory:(NSURL *)profileDirectoryURL
                   error:(NSError * _Nullable __autoreleasing *)error {
    NSURL *slotDirectoryURL = FTMSlotDirectoryURL(profileDirectoryURL, slotID);
    for (NSString *fileName in fileNames) {
        NSURL *fileURL = [slotDirectoryURL URLByAppendingPathComponent:fileName];
        if (![_fileManager fileExistsAtPath:fileURL.path]) {
            continue;
        }
        NSError *removeError = nil;
        if (![_fileManager removeItemAtURL:fileURL error:&removeError]) {
            if (error) { *error = removeError; }
            return NO;
        }
    }
    return YES;
}

- (BOOL)clearSlotID:(NSString *)slotID
   profileDirectory:(NSURL *)profileDirectoryURL
              error:(NSError * _Nullable __autoreleasing *)error {
    NSArray<NSURL *> *files = [self fileURLsForSlotID:slotID profileDirectory:profileDirectoryURL];
    NSArray<NSString *> *names = [files valueForKey:@"lastPathComponent"];
    return [self removeFilesNamed:names fromSlotID:slotID profileDirectory:profileDirectoryURL error:error];
}

- (NSArray<NSURL *> *)fileURLsForSlotID:(NSString *)slotID
                       profileDirectory:(NSURL *)profileDirectoryURL {
    NSURL *slotDirectoryURL = FTMSlotDirectoryURL(profileDirectoryURL, slotID);
    return FTMDirectoryFilesSorted(_fileManager, slotDirectoryURL);
}

- (NSArray<NSURL *> *)ftm_recursiveSupportedAudioFilesUnderFolderURL:(NSURL *)folderURL
                                                            warnings:(NSArray<NSString *> * _Nullable __autoreleasing *)warnings {
    NSMutableArray<NSString *> *warningList = [NSMutableArray array];
    NSMutableArray<NSURL *> *results = [NSMutableArray array];
    for (NSURL *url in FTMDirectoryFilesRecursiveSorted(_fileManager, folderURL)) {
        NSString *extension = [[url pathExtension] lowercaseString];
        if (!FTMIsSupportedAudioExtension(extension)) {
            [warningList addObject:[NSString stringWithFormat:@"Ignored unsupported file type: %@", url.lastPathComponent]];
            continue;
        }
        [results addObject:url];
    }
    if (warnings) {
        *warnings = [warningList copy];
    }
    return [results copy];
}

- (NSURL *)ftm_importAudioFileAtURL:(NSURL *)sourceURL
                      toDirectoryURL:(NSURL *)destinationDirectoryURL
                       preferredName:(NSString *)preferredName
                   sourceExtensionOut:(NSString * _Nullable __autoreleasing *)sourceExtensionOut
                               error:(NSError * _Nullable __autoreleasing *)error {
    NSError *dirError = nil;
    if (!FTMEnsureDirectoryExists(_fileManager, destinationDirectoryURL, &dirError)) {
        if (error) { *error = dirError; }
        return nil;
    }

    NSString *sourceExt = [[sourceURL pathExtension] lowercaseString];
    if (!FTMIsSupportedAudioExtension(sourceExt)) {
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorInvalidSoundPack,
                                  [NSString stringWithFormat:@"Unsupported audio type: %@", sourceURL.lastPathComponent]);
        }
        return nil;
    }

    NSString *baseName = preferredName.length ? preferredName : [[sourceURL lastPathComponent] stringByDeletingPathExtension];
    if ([sourceExt isEqualToString:@"ogg"]) {
        NSURL *destURL = FTMUniqueDestinationURL(destinationDirectoryURL, baseName, @"wav", _fileManager);
        NSError *oggError = nil;
        if (!FTMConvertOggVorbisToWav(sourceURL, destURL, &oggError)) {
            if (error) { *error = oggError; }
            return nil;
        }
        if (sourceExtensionOut) { *sourceExtensionOut = sourceExt; }
        return destURL;
    }

    if (!FTMValidateNativeAudioAtURL(sourceURL)) {
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorInvalidSoundPack,
                                  [NSString stringWithFormat:@"Unreadable audio file: %@", sourceURL.lastPathComponent]);
        }
        return nil;
    }

    NSURL *destURL = FTMUniqueDestinationURL(destinationDirectoryURL, baseName, sourceExt, _fileManager);
    NSError *copyError = nil;
    if (![_fileManager copyItemAtURL:sourceURL toURL:destURL error:&copyError]) {
        if (error) { *error = copyError; }
        return nil;
    }
    if (sourceExtensionOut) { *sourceExtensionOut = sourceExt; }
    return destURL;
}

@end

@implementation FTMProfileStore

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults bundle:(NSBundle *)bundle {
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
    NSURL *appSupport = urls.firstObject ?: [NSURL fileURLWithPath:[@"~/Library/Application Support" stringByExpandingTildeInPath] isDirectory:YES];
    NSURL *baseURL = [appSupport URLByAppendingPathComponent:@"MacOSTypingSounds" isDirectory:YES];
    return [self initWithBaseDirectoryURL:baseURL defaults:defaults bundle:bundle];
}

- (instancetype)initWithBaseDirectoryURL:(NSURL *)baseDirectoryURL
                                defaults:(NSUserDefaults *)defaults
                                  bundle:(NSBundle *)bundle {
    self = [super init];
    if (self) {
        _defaults = defaults ?: [NSUserDefaults standardUserDefaults];
        _bundle = bundle ?: [NSBundle mainBundle];
        _fileManager = [NSFileManager defaultManager];
        _mutableProfiles = [NSMutableArray array];
        _mutableAppRules = [NSMutableArray array];
        _profilesRootURL = [baseDirectoryURL URLByAppendingPathComponent:FTMProfilesDirectoryName isDirectory:YES];
        _metadataURL = [baseDirectoryURL URLByAppendingPathComponent:FTMProfilesFileName];
    }
    return self;
}

- (NSArray<FTMProfile *> *)profiles {
    return [self.mutableProfiles copy];
}

- (NSArray<FTMAppProfileRule *> *)appRules {
    return [self.mutableAppRules copy];
}

- (BOOL)loadOrInitialize:(NSError * _Nullable __autoreleasing *)error {
    NSURL *baseDirectoryURL = [self.metadataURL URLByDeletingLastPathComponent];
    NSError *dirError = nil;
    if (!FTMEnsureDirectoryExists(self.fileManager, baseDirectoryURL, &dirError) ||
        !FTMEnsureDirectoryExists(self.fileManager, self.profilesRootURL, &dirError)) {
        if (error) { *error = dirError; }
        return NO;
    }

    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfURL:self.metadataURL];
    [self.mutableProfiles removeAllObjects];
    [self.mutableAppRules removeAllObjects];

    if ([metadata isKindOfClass:[NSDictionary class]]) {
        NSArray *profileDicts = [metadata[@"profiles"] isKindOfClass:[NSArray class]] ? metadata[@"profiles"] : @[];
        for (id entry in profileDicts) {
            if ([entry isKindOfClass:[NSDictionary class]]) {
                [self.mutableProfiles addObject:[FTMProfile profileWithDictionary:entry]];
            }
        }
        NSArray *ruleDicts = [metadata[@"appRules"] isKindOfClass:[NSArray class]] ? metadata[@"appRules"] : @[];
        for (id entry in ruleDicts) {
            if (![entry isKindOfClass:[NSDictionary class]]) { continue; }
            FTMAppProfileRule *rule = [FTMAppProfileRule ruleWithDictionary:entry];
            if (rule.bundleIdentifier.length == 0 || rule.profileID.length == 0) { continue; }
            [self.mutableAppRules addObject:rule];
        }
    }

    if (self.mutableProfiles.count == 0) {
        if (![self createBuiltInDefaultProfile:error]) {
            return NO;
        }
    }

    NSString *activeProfileID = [self.defaults stringForKey:FTMDefaultsKeyActiveProfileID];
    if (![self profileWithID:activeProfileID]) {
        [self.defaults setObject:self.mutableProfiles.firstObject.profileID forKey:FTMDefaultsKeyActiveProfileID];
    }

    for (FTMProfile *profile in self.mutableProfiles) {
        if (![self ensureProfileStorageAndConfigForProfile:profile error:error]) {
            return NO;
        }
    }

    [self pruneInvalidAppRules];
    [self migrateLegacyTerminalOnlyToAssignedAppsOnlyIfNeeded];
    return [self saveMetadata:error];
}

- (nullable FTMProfile *)activeProfile {
    NSString *profileID = [self.defaults stringForKey:FTMDefaultsKeyActiveProfileID];
    FTMProfile *profile = [self profileWithID:profileID];
    return profile ?: self.mutableProfiles.firstObject;
}

- (BOOL)setActiveProfileID:(NSString *)profileID error:(NSError * _Nullable __autoreleasing *)error {
    if (![self profileWithID:profileID]) {
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Selected profile no longer exists.");
        }
        return NO;
    }
    [self.defaults setObject:profileID forKey:FTMDefaultsKeyActiveProfileID];
    return YES;
}

- (nullable FTMAppProfileRule *)appRuleForBundleIdentifier:(NSString *)bundleIdentifier {
    NSString *normalized = FTMNormalizeBundleIdentifier(bundleIdentifier);
    if (normalized.length == 0) {
        return nil;
    }
    for (FTMAppProfileRule *rule in self.mutableAppRules) {
        if ([rule.bundleIdentifier isEqualToString:normalized]) {
            return rule;
        }
    }
    return nil;
}

- (nullable FTMProfile *)assignedProfileForBundleIdentifier:(NSString *)bundleIdentifier {
    FTMAppProfileRule *rule = [self appRuleForBundleIdentifier:bundleIdentifier];
    if (!rule) {
        return nil;
    }
    return [self profileWithID:rule.profileID];
}

- (BOOL)setAppRuleForBundleIdentifier:(NSString *)bundleIdentifier
                           appNameHint:(NSString *)appNameHint
                             profileID:(NSString *)profileID
                                 error:(NSError * _Nullable __autoreleasing *)error {
    NSString *normalized = FTMNormalizeBundleIdentifier(bundleIdentifier);
    if (normalized.length == 0 || !FTMIsLikelyBundleIdentifier(normalized)) {
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorInvalidSoundPack, @"Enter a valid app bundle identifier (for example com.apple.Terminal).");
        }
        return NO;
    }
    FTMProfile *profile = [self profileWithID:profileID];
    if (!profile) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile not found for app assignment."); }
        return NO;
    }

    FTMAppProfileRule *rule = [self appRuleForBundleIdentifier:normalized];
    if (!rule) {
        rule = [[FTMAppProfileRule alloc] init];
        rule.bundleIdentifier = normalized;
        rule.createdAt = [NSDate date];
        [self.mutableAppRules addObject:rule];
    }
    rule.profileID = profileID;
    rule.appNameHint = appNameHint.length ? appNameHint : nil;
    rule.updatedAt = [NSDate date];
    if (!rule.createdAt) {
        rule.createdAt = rule.updatedAt;
    }
    return [self saveMetadata:error];
}

- (BOOL)removeAppRuleForBundleIdentifier:(NSString *)bundleIdentifier error:(NSError * _Nullable __autoreleasing *)error {
    FTMAppProfileRule *rule = [self appRuleForBundleIdentifier:bundleIdentifier];
    if (!rule) {
        return YES;
    }
    [self.mutableAppRules removeObject:rule];
    return [self saveMetadata:error];
}

- (FTMProfile *)createEmptyProfileNamed:(NSString *)name error:(NSError * _Nullable __autoreleasing *)error {
    NSString *resolvedName = FTMUniqueProfileName(name, self.mutableProfiles, nil);
    FTMProfile *profile = [[FTMProfile alloc] init];
    profile.profileID = [[NSUUID UUID] UUIDString];
    profile.name = resolvedName;
    profile.relativePath = profile.profileID;
    profile.createdAt = [NSDate date];
    profile.updatedAt = profile.createdAt;

    NSURL *dirURL = [self profileDirectoryURLForProfile:profile];
    NSError *dirError = nil;
    if (!FTMEnsureDirectoryExists(self.fileManager, dirURL, &dirError)) {
        if (error) { *error = dirError; }
        return nil;
    }
    if (![self ensureProfileStorageAndConfigForProfile:profile error:error]) {
        [self.fileManager removeItemAtURL:dirURL error:nil];
        return nil;
    }

    [self.mutableProfiles addObject:profile];
    if (![self saveMetadata:error]) {
        [self.mutableProfiles removeObject:profile];
        [self.fileManager removeItemAtURL:dirURL error:nil];
        return nil;
    }

    if (self.mutableProfiles.count == 1) {
        [self.defaults setObject:profile.profileID forKey:FTMDefaultsKeyActiveProfileID];
    }
    return profile;
}

- (nullable FTMProfile *)duplicateProfile:(FTMProfile *)profile error:(NSError * _Nullable __autoreleasing *)error {
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile to duplicate was not found."); }
        return nil;
    }

    NSString *copyName = FTMUniqueProfileName([NSString stringWithFormat:@"%@ Copy", existing.name], self.mutableProfiles, nil);
    FTMProfile *copy = [[FTMProfile alloc] init];
    copy.profileID = [[NSUUID UUID] UUIDString];
    copy.name = copyName;
    copy.relativePath = copy.profileID;
    copy.createdAt = [NSDate date];
    copy.updatedAt = copy.createdAt;

    NSURL *sourceURL = [self profileDirectoryURLForProfile:existing];
    NSURL *destURL = [self profileDirectoryURLForProfile:copy];
    NSError *copyError = nil;
    if (![self.fileManager copyItemAtURL:sourceURL toURL:destURL error:&copyError]) {
        if (error) { *error = copyError; }
        return nil;
    }
    if (![self ensureProfileStorageAndConfigForProfile:copy error:error]) {
        [self.fileManager removeItemAtURL:destURL error:nil];
        return nil;
    }

    [self.mutableProfiles addObject:copy];
    if (![self saveMetadata:error]) {
        [self.mutableProfiles removeObject:copy];
        [self.fileManager removeItemAtURL:destURL error:nil];
        return nil;
    }
    return copy;
}

- (BOOL)renameProfile:(FTMProfile *)profile toName:(NSString *)name error:(NSError * _Nullable __autoreleasing *)error {
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile to rename was not found."); }
        return NO;
    }
    existing.name = FTMUniqueProfileName(name, self.mutableProfiles, existing.profileID);
    existing.updatedAt = [NSDate date];
    return [self saveMetadata:error];
}

- (BOOL)deleteProfile:(FTMProfile *)profile error:(NSError * _Nullable __autoreleasing *)error {
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile to delete was not found."); }
        return NO;
    }

    NSURL *dirURL = [self profileDirectoryURLForProfile:existing];
    NSError *removeError = nil;
    if ([self.fileManager fileExistsAtPath:dirURL.path] && ![self.fileManager removeItemAtURL:dirURL error:&removeError]) {
        if (error) { *error = removeError; }
        return NO;
    }

    [self.mutableProfiles removeObject:existing];
    NSIndexSet *rulesToRemove = [self.mutableAppRules indexesOfObjectsPassingTest:^BOOL(FTMAppProfileRule * _Nonnull rule, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)idx; (void)stop;
        return [rule.profileID isEqualToString:existing.profileID];
    }];
    if (rulesToRemove.count > 0) {
        [self.mutableAppRules removeObjectsAtIndexes:rulesToRemove];
    }

    if (self.mutableProfiles.count == 0) {
        if (![self createBuiltInDefaultProfile:error]) {
            return NO;
        }
    }

    NSString *activeID = [self.defaults stringForKey:FTMDefaultsKeyActiveProfileID];
    if (![self profileWithID:activeID]) {
        [self.defaults setObject:self.mutableProfiles.firstObject.profileID forKey:FTMDefaultsKeyActiveProfileID];
    }

    return [self saveMetadata:error];
}

- (nullable FTMProfile *)importProfileFromFolderURL:(NSURL *)folderURL
                                            importer:(FTMSoundPackImporter *)importer
                                            warnings:(NSArray<NSString *> * _Nullable __autoreleasing *)warnings
                                               error:(NSError * _Nullable __autoreleasing *)error {
    NSString *folderName = folderURL.lastPathComponent.length ? folderURL.lastPathComponent : @"Imported Profile";
    FTMProfile *profile = [self createEmptyProfileNamed:folderName error:error];
    if (!profile) {
        return nil;
    }

    NSArray<NSString *> *importWarnings = nil;
    if (![self importAudioFolderFlat:folderURL intoProfile:profile importer:importer warnings:&importWarnings error:error]) {
        [self.mutableProfiles removeObject:profile];
        [self.fileManager removeItemAtURL:[self profileDirectoryURLForProfile:profile] error:nil];
        [self saveMetadata:nil];
        return nil;
    }

    if (warnings) {
        *warnings = importWarnings;
    }
    return profile;
}

- (BOOL)importAudioFolderFlat:(NSURL *)folderURL
                    intoProfile:(FTMProfile *)profile
                       importer:(FTMSoundPackImporter *)importer
                       warnings:(NSArray<NSString *> * _Nullable __autoreleasing *)warnings
                          error:(NSError * _Nullable __autoreleasing *)error {
    NSArray<NSString *> *scanWarnings = nil;
    NSArray<NSURL *> *audioURLs = [importer ftm_recursiveSupportedAudioFilesUnderFolderURL:folderURL warnings:&scanWarnings];
    if (audioURLs.count == 0) {
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorInvalidSoundPack, @"Import failed: no supported audio files were found in the selected folder.");
        }
        if (warnings) { *warnings = scanWarnings ?: @[]; }
        return NO;
    }

    NSArray<NSString *> *importWarnings = nil;
    if (![self addAudioFilesToProfileLibrary:audioURLs profile:profile importer:importer warnings:&importWarnings error:error]) {
        if (warnings) {
            NSMutableArray *merged = [NSMutableArray arrayWithArray:scanWarnings ?: @[]];
            [merged addObjectsFromArray:importWarnings ?: @[]];
            *warnings = [merged copy];
        }
        return NO;
    }

    if (warnings) {
        NSMutableArray *merged = [NSMutableArray arrayWithArray:scanWarnings ?: @[]];
        [merged addObjectsFromArray:importWarnings ?: @[]];
        *warnings = [merged copy];
    }
    return YES;
}

- (BOOL)addAudioFilesToProfileLibrary:(NSArray<NSURL *> *)audioURLs
                              profile:(FTMProfile *)profile
                             importer:(FTMSoundPackImporter *)importer
                             warnings:(NSArray<NSString *> * _Nullable __autoreleasing *)warnings
                                error:(NSError * _Nullable __autoreleasing *)error {
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile not found."); }
        return NO;
    }
    if (![self ensureProfileStorageAndConfigForProfile:existing error:error]) {
        return NO;
    }

    NSMutableDictionary *config = [self mutableProfileConfigForProfile:existing createIfMissing:YES error:error];
    if (!config) {
        return NO;
    }
    NSMutableArray *assets = [config[@"assets"] mutableCopy] ?: [NSMutableArray array];
    NSURL *assetsDir = [self assetsDirectoryURLForProfile:existing];
    NSMutableArray<NSString *> *warningList = [NSMutableArray array];
    NSUInteger importedCount = 0;

    for (NSURL *sourceURL in audioURLs) {
        NSNumber *isDir = nil;
        [sourceURL getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
        if ([isDir boolValue]) {
            [warningList addObject:[NSString stringWithFormat:@"Ignored folder: %@", sourceURL.lastPathComponent]];
            continue;
        }
        NSString *sourceExt = nil;
        NSError *importError = nil;
        NSString *preferredName = [[NSUUID UUID] UUIDString];
        NSURL *destURL = [importer ftm_importAudioFileAtURL:sourceURL
                                             toDirectoryURL:assetsDir
                                              preferredName:preferredName
                                          sourceExtensionOut:&sourceExt
                                                      error:&importError];
        if (!destURL) {
            NSString *message = importError.localizedDescription ?: [NSString stringWithFormat:@"Failed importing %@", sourceURL.lastPathComponent];
            [warningList addObject:message];
            continue;
        }
        FTMProfileAsset *asset = [[FTMProfileAsset alloc] init];
        asset.assetID = [[NSUUID UUID] UUIDString];
        asset.displayName = sourceURL.lastPathComponent ?: destURL.lastPathComponent ?: @"Sound";
        asset.storedFileName = destURL.lastPathComponent ?: @"sound";
        asset.importedAt = [NSDate date];
        asset.sourceExtension = sourceExt;
        [assets addObject:[asset dictionaryRepresentation]];
        importedCount += 1;
    }

    if (importedCount == 0) {
        if (warnings) { *warnings = [warningList copy]; }
        if (error) {
            *error = FTMMakeError(FTMProfileSystemErrorInvalidSoundPack, @"No valid audio files could be imported.");
        }
        return NO;
    }

    config[@"assets"] = assets;
    if (![self saveProfileConfig:config forProfile:existing error:error]) {
        return NO;
    }
    if (![self touchProfile:existing error:error]) {
        return NO;
    }

    if (warnings) { *warnings = [warningList copy]; }
    return YES;
}

- (BOOL)addAudioFilesAtURLs:(NSArray<NSURL *> *)audioURLs
                   toSlotID:(NSString *)slotID
                    profile:(FTMProfile *)profile
                   importer:(FTMSoundPackImporter *)importer
                   warnings:(NSArray<NSString *> * _Nullable __autoreleasing *)warnings
                      error:(NSError * _Nullable __autoreleasing *)error {
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile not found."); }
        return NO;
    }
    NSArray<FTMProfileAsset *> *beforeAssets = [self assetsForProfile:existing];
    NSMutableSet<NSString *> *beforeIDs = [NSMutableSet set];
    for (FTMProfileAsset *asset in beforeAssets) {
        [beforeIDs addObject:asset.assetID];
    }
    if (![self addAudioFilesToProfileLibrary:audioURLs profile:existing importer:importer warnings:warnings error:error]) {
        return NO;
    }
    NSArray<FTMProfileAsset *> *afterAssets = [self assetsForProfile:existing];
    NSMutableArray<NSString *> *newIDs = [NSMutableArray array];
    for (FTMProfileAsset *asset in afterAssets) {
        if (![beforeIDs containsObject:asset.assetID]) {
            [newIDs addObject:asset.assetID];
        }
    }
    if (newIDs.count == 0) {
        return YES;
    }
    return [self assignAssetIDs:newIDs toSlotID:slotID profile:existing error:error];
}

- (BOOL)removeFilesNamed:(NSArray<NSString *> *)fileNames
              fromSlotID:(NSString *)slotID
                 profile:(FTMProfile *)profile
                importer:(FTMSoundPackImporter *)importer
                   error:(NSError * _Nullable __autoreleasing *)error {
    (void)importer;
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile not found."); }
        return NO;
    }
    NSArray<FTMProfileAsset *> *slotAssets = [self assignedAssetsForSlotID:slotID profile:existing];
    NSMutableSet<NSString *> *fileNameSet = [NSMutableSet setWithArray:fileNames ?: @[]];
    NSMutableArray<NSString *> *assetIDs = [NSMutableArray array];
    for (FTMProfileAsset *asset in slotAssets) {
        if ([fileNameSet containsObject:asset.storedFileName] || [fileNameSet containsObject:asset.displayName]) {
            [assetIDs addObject:asset.assetID];
        }
    }
    if (assetIDs.count == 0) {
        return YES;
    }
    return [self unassignAssetIDs:assetIDs fromSlotID:slotID profile:existing error:error];
}

- (BOOL)clearSlotID:(NSString *)slotID
            profile:(FTMProfile *)profile
           importer:(FTMSoundPackImporter *)importer
              error:(NSError * _Nullable __autoreleasing *)error {
    (void)importer;
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile not found."); }
        return NO;
    }
    NSArray<FTMProfileAsset *> *slotAssets = [self assignedAssetsForSlotID:slotID profile:existing];
    NSMutableArray<NSString *> *assetIDs = [NSMutableArray arrayWithCapacity:slotAssets.count];
    for (FTMProfileAsset *asset in slotAssets) {
        [assetIDs addObject:asset.assetID];
    }
    return [self unassignAssetIDs:assetIDs fromSlotID:slotID profile:existing error:error];
}

- (NSArray<FTMProfileAsset *> *)assetsForProfile:(FTMProfile *)profile {
    if (!profile) {
        return @[];
    }
    NSError *error = nil;
    if (![self ensureProfileStorageAndConfigForProfile:profile error:&error]) {
        (void)error;
        return @[];
    }
    NSDictionary *config = [self profileConfigForProfile:profile error:nil];
    NSArray *assetDicts = [config[@"assets"] isKindOfClass:[NSArray class]] ? config[@"assets"] : @[];
    NSMutableArray<FTMProfileAsset *> *assets = [NSMutableArray arrayWithCapacity:assetDicts.count];
    for (id item in assetDicts) {
        if (![item isKindOfClass:[NSDictionary class]]) { continue; }
        FTMProfileAsset *asset = [FTMProfileAsset assetWithDictionary:item];
        if (asset.assetID.length == 0 || asset.storedFileName.length == 0) { continue; }
        [assets addObject:asset];
    }
    return [assets copy];
}

- (NSArray<FTMProfileAsset *> *)assignedAssetsForSlotID:(NSString *)slotID profile:(FTMProfile *)profile {
    if (!profile || ![FTMAllSoundSlotIDs() containsObject:slotID]) {
        return @[];
    }
    NSDictionary *config = [self profileConfigForProfile:profile error:nil];
    if (![config isKindOfClass:[NSDictionary class]]) {
        return @[];
    }
    NSArray<FTMProfileAsset *> *assets = [self assetsForProfile:profile];
    NSMutableDictionary<NSString *, FTMProfileAsset *> *assetsByID = [NSMutableDictionary dictionaryWithCapacity:assets.count];
    for (FTMProfileAsset *asset in assets) {
        assetsByID[asset.assetID] = asset;
    }
    NSDictionary *slotAssignments = [config[@"slotAssignments"] isKindOfClass:[NSDictionary class]] ? config[@"slotAssignments"] : @{};
    NSArray *slotAssetIDs = [slotAssignments[slotID] isKindOfClass:[NSArray class]] ? slotAssignments[slotID] : @[];
    NSMutableArray<FTMProfileAsset *> *resolved = [NSMutableArray array];
    for (id assetID in slotAssetIDs) {
        if (![assetID isKindOfClass:[NSString class]]) { continue; }
        FTMProfileAsset *asset = assetsByID[assetID];
        if (asset) {
            [resolved addObject:asset];
        }
    }
    return [resolved copy];
}

- (NSArray<FTMProfileAsset *> *)unassignedAssetsForProfile:(FTMProfile *)profile {
    if (!profile) {
        return @[];
    }
    NSArray<FTMProfileAsset *> *assets = [self assetsForProfile:profile];
    NSDictionary *config = [self profileConfigForProfile:profile error:nil];
    NSDictionary *slotAssignments = [config[@"slotAssignments"] isKindOfClass:[NSDictionary class]] ? config[@"slotAssignments"] : @{};
    NSMutableSet<NSString *> *assignedIDs = [NSMutableSet set];
    for (NSString *slotID in FTMAllSoundSlotIDs()) {
        NSArray *slotIDs = [slotAssignments[slotID] isKindOfClass:[NSArray class]] ? slotAssignments[slotID] : @[];
        for (id assetID in slotIDs) {
            if ([assetID isKindOfClass:[NSString class]]) {
                [assignedIDs addObject:assetID];
            }
        }
    }
    NSMutableArray<FTMProfileAsset *> *unassigned = [NSMutableArray array];
    for (FTMProfileAsset *asset in assets) {
        if (![assignedIDs containsObject:asset.assetID]) {
            [unassigned addObject:asset];
        }
    }
    return [unassigned copy];
}

- (BOOL)assignAssetIDs:(NSArray<NSString *> *)assetIDs
               toSlotID:(NSString *)slotID
                profile:(FTMProfile *)profile
                  error:(NSError * _Nullable __autoreleasing *)error {
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile not found."); }
        return NO;
    }
    if (![FTMAllSoundSlotIDs() containsObject:slotID]) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorInvalidSoundPack, @"Unknown sound slot."); }
        return NO;
    }
    NSMutableDictionary *config = [self mutableProfileConfigForProfile:existing createIfMissing:YES error:error];
    if (!config) { return NO; }
    NSArray<FTMProfileAsset *> *assets = [self assetsForProfile:existing];
    NSMutableSet<NSString *> *validIDs = [NSMutableSet set];
    for (FTMProfileAsset *asset in assets) {
        [validIDs addObject:asset.assetID];
    }
    NSMutableDictionary *slotAssignments = [config[@"slotAssignments"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *slotArray = [[slotAssignments[slotID] isKindOfClass:[NSArray class]] ? slotAssignments[slotID] : @[] mutableCopy];
    NSMutableSet<NSString *> *existingIDs = [NSMutableSet set];
    for (id item in slotArray) {
        if ([item isKindOfClass:[NSString class]]) {
            [existingIDs addObject:item];
        }
    }
    for (NSString *assetID in assetIDs ?: @[]) {
        if (![assetID isKindOfClass:[NSString class]]) { continue; }
        if (![validIDs containsObject:assetID]) { continue; }
        if ([existingIDs containsObject:assetID]) { continue; }
        [slotArray addObject:assetID];
        [existingIDs addObject:assetID];
    }
    slotAssignments[slotID] = slotArray;
    [self normalizeSlotAssignmentsDictionary:slotAssignments];
    config[@"slotAssignments"] = slotAssignments;
    if (![self saveProfileConfig:config forProfile:existing error:error]) {
        return NO;
    }
    return [self touchProfile:existing error:error];
}

- (BOOL)unassignAssetIDs:(NSArray<NSString *> *)assetIDs
               fromSlotID:(NSString *)slotID
                  profile:(FTMProfile *)profile
                    error:(NSError * _Nullable __autoreleasing *)error {
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile not found."); }
        return NO;
    }
    if (![FTMAllSoundSlotIDs() containsObject:slotID]) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorInvalidSoundPack, @"Unknown sound slot."); }
        return NO;
    }
    NSMutableDictionary *config = [self mutableProfileConfigForProfile:existing createIfMissing:YES error:error];
    if (!config) { return NO; }
    NSMutableDictionary *slotAssignments = [config[@"slotAssignments"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray *slotArray = [[slotAssignments[slotID] isKindOfClass:[NSArray class]] ? slotAssignments[slotID] : @[] mutableCopy];
    if (slotArray.count == 0) {
        return YES;
    }
    NSSet<NSString *> *removeIDs = [NSSet setWithArray:assetIDs ?: @[]];
    NSIndexSet *indexes = [slotArray indexesOfObjectsPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        (void)idx; (void)stop;
        return [obj isKindOfClass:[NSString class]] && [removeIDs containsObject:obj];
    }];
    if (indexes.count == 0) {
        return YES;
    }
    [slotArray removeObjectsAtIndexes:indexes];
    slotAssignments[slotID] = slotArray;
    [self normalizeSlotAssignmentsDictionary:slotAssignments];
    config[@"slotAssignments"] = slotAssignments;
    if (![self saveProfileConfig:config forProfile:existing error:error]) {
        return NO;
    }
    return [self touchProfile:existing error:error];
}

- (BOOL)deleteAssetIDsFromProfile:(NSArray<NSString *> *)assetIDs
                           profile:(FTMProfile *)profile
                             error:(NSError * _Nullable __autoreleasing *)error {
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile not found."); }
        return NO;
    }
    NSSet<NSString *> *deleteIDs = [NSSet setWithArray:assetIDs ?: @[]];
    if (deleteIDs.count == 0) {
        return YES;
    }
    NSMutableDictionary *config = [self mutableProfileConfigForProfile:existing createIfMissing:YES error:error];
    if (!config) { return NO; }

    NSArray<FTMProfileAsset *> *assets = [self assetsForProfile:existing];
    NSMutableArray<NSDictionary *> *keptAssetDicts = [NSMutableArray array];
    NSURL *assetsDir = [self assetsDirectoryURLForProfile:existing];
    for (FTMProfileAsset *asset in assets) {
        if ([deleteIDs containsObject:asset.assetID]) {
            NSURL *fileURL = [assetsDir URLByAppendingPathComponent:asset.storedFileName];
            [self.fileManager removeItemAtURL:fileURL error:nil];
            continue;
        }
        [keptAssetDicts addObject:[asset dictionaryRepresentation]];
    }

    NSMutableDictionary *slotAssignments = [config[@"slotAssignments"] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSString *slotID in FTMAllSoundSlotIDs()) {
        NSMutableArray *slotArray = [[slotAssignments[slotID] isKindOfClass:[NSArray class]] ? slotAssignments[slotID] : @[] mutableCopy];
        NSIndexSet *indexes = [slotArray indexesOfObjectsPassingTest:^BOOL(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            (void)idx; (void)stop;
            return [obj isKindOfClass:[NSString class]] && [deleteIDs containsObject:obj];
        }];
        if (indexes.count > 0) {
            [slotArray removeObjectsAtIndexes:indexes];
        }
        slotAssignments[slotID] = slotArray;
    }
    [self normalizeSlotAssignmentsDictionary:slotAssignments];

    config[@"assets"] = keptAssetDicts;
    config[@"slotAssignments"] = slotAssignments;
    if (![self saveProfileConfig:config forProfile:existing error:error]) {
        return NO;
    }
    return [self touchProfile:existing error:error];
}

- (NSDictionary<NSString *,NSNumber *> *)slotFileCountsForProfile:(FTMProfile *)profile {
    NSMutableDictionary<NSString *, NSNumber *> *counts = [NSMutableDictionary dictionary];
    for (NSString *slotID in FTMAllSoundSlotIDs()) {
        counts[slotID] = @([self assignedAssetsForSlotID:slotID profile:profile].count);
    }
    return counts;
}

- (NSArray<NSURL *> *)fileURLsForSlotID:(NSString *)slotID profile:(FTMProfile *)profile {
    if (!profile) {
        return @[];
    }
    NSURL *assetsDir = [self assetsDirectoryURLForProfile:profile];
    NSMutableArray<NSURL *> *urls = [NSMutableArray array];
    for (FTMProfileAsset *asset in [self assignedAssetsForSlotID:slotID profile:profile]) {
        NSURL *url = [assetsDir URLByAppendingPathComponent:asset.storedFileName];
        if ([self.fileManager fileExistsAtPath:url.path]) {
            [urls addObject:url];
        }
    }
    return [urls copy];
}

- (NSURL *)profileDirectoryURLForProfile:(FTMProfile *)profile {
    return [self.profilesRootURL URLByAppendingPathComponent:profile.relativePath isDirectory:YES];
}

- (BOOL)touchProfile:(FTMProfile *)profile error:(NSError * _Nullable __autoreleasing *)error {
    FTMProfile *existing = [self profileWithID:profile.profileID];
    if (!existing) {
        if (error) { *error = FTMMakeError(FTMProfileSystemErrorProfileNotFound, @"Profile not found."); }
        return NO;
    }
    existing.updatedAt = [NSDate date];
    return [self saveMetadata:error];
}

#pragma mark - Private

- (FTMProfile *)profileWithID:(NSString *)profileID {
    if (profileID.length == 0) {
        return nil;
    }
    for (FTMProfile *profile in self.mutableProfiles) {
        if ([profile.profileID isEqualToString:profileID]) {
            return profile;
        }
    }
    return nil;
}

- (NSURL *)assetsDirectoryURLForProfile:(FTMProfile *)profile {
    return FTMProfileAssetsDirectoryURL([self profileDirectoryURLForProfile:profile]);
}

- (NSURL *)profileConfigURLForProfile:(FTMProfile *)profile {
    return FTMProfileConfigURL([self profileDirectoryURLForProfile:profile]);
}

- (NSMutableDictionary *)emptyProfileConfigDictionary {
    NSMutableDictionary *slotAssignments = [NSMutableDictionary dictionary];
    for (NSString *slotID in FTMAllSoundSlotIDs()) {
        slotAssignments[slotID] = [NSMutableArray array];
    }
    return [@{
        @"schemaVersion": @(FTMProfileConfigSchemaVersion),
        @"assets": [NSMutableArray array],
        @"slotAssignments": slotAssignments,
    } mutableCopy];
}

- (void)normalizeSlotAssignmentsDictionary:(NSMutableDictionary *)slotAssignments {
    for (NSString *slotID in FTMAllSoundSlotIDs()) {
        NSArray *existing = [slotAssignments[slotID] isKindOfClass:[NSArray class]] ? slotAssignments[slotID] : @[];
        NSMutableArray *normalized = [NSMutableArray array];
        for (id item in existing) {
            if ([item isKindOfClass:[NSString class]] && [((NSString *)item) length] > 0) {
                [normalized addObject:item];
            }
        }
        slotAssignments[slotID] = normalized;
    }
}

- (NSDictionary *)profileConfigForProfile:(FTMProfile *)profile error:(NSError * _Nullable __autoreleasing *)error {
    if (![self ensureProfileStorageAndConfigForProfile:profile error:error]) {
        return nil;
    }
    NSDictionary *raw = [NSDictionary dictionaryWithContentsOfURL:[self profileConfigURLForProfile:profile]];
    if (![raw isKindOfClass:[NSDictionary class]]) {
        return [self emptyProfileConfigDictionary];
    }
    NSMutableDictionary *config = [raw mutableCopy];
    if (![config[@"assets"] isKindOfClass:[NSArray class]]) {
        config[@"assets"] = @[];
    }
    NSMutableDictionary *slotAssignments = [config[@"slotAssignments"] isKindOfClass:[NSDictionary class]] ? [config[@"slotAssignments"] mutableCopy] : [NSMutableDictionary dictionary];
    [self normalizeSlotAssignmentsDictionary:slotAssignments];
    config[@"slotAssignments"] = slotAssignments;
    config[@"schemaVersion"] = @(FTMProfileConfigSchemaVersion);
    return [config copy];
}

- (NSMutableDictionary *)mutableProfileConfigForProfile:(FTMProfile *)profile
                                        createIfMissing:(BOOL)createIfMissing
                                                  error:(NSError * _Nullable __autoreleasing *)error {
    NSURL *configURL = [self profileConfigURLForProfile:profile];
    NSDictionary *raw = [NSDictionary dictionaryWithContentsOfURL:configURL];
    if (![raw isKindOfClass:[NSDictionary class]]) {
        if (!createIfMissing) {
            return nil;
        }
        NSMutableDictionary *fresh = [self emptyProfileConfigDictionary];
        if (![self saveProfileConfig:fresh forProfile:profile error:error]) {
            return nil;
        }
        return fresh;
    }
    NSMutableDictionary *config = [raw mutableCopy];
    if (![config[@"assets"] isKindOfClass:[NSArray class]]) {
        config[@"assets"] = [NSMutableArray array];
    } else {
        config[@"assets"] = [config[@"assets"] mutableCopy];
    }
    NSMutableDictionary *slotAssignments = [config[@"slotAssignments"] isKindOfClass:[NSDictionary class]] ? [config[@"slotAssignments"] mutableCopy] : [NSMutableDictionary dictionary];
    [self normalizeSlotAssignmentsDictionary:slotAssignments];
    config[@"slotAssignments"] = slotAssignments;
    config[@"schemaVersion"] = @(FTMProfileConfigSchemaVersion);
    return config;
}

- (BOOL)saveProfileConfig:(NSDictionary *)config forProfile:(FTMProfile *)profile error:(NSError * _Nullable __autoreleasing *)error {
    NSURL *dirURL = [self profileDirectoryURLForProfile:profile];
    NSURL *assetsURL = [self assetsDirectoryURLForProfile:profile];
    NSError *dirError = nil;
    if (!FTMEnsureDirectoryExists(self.fileManager, dirURL, &dirError) || !FTMEnsureDirectoryExists(self.fileManager, assetsURL, &dirError)) {
        if (error) { *error = dirError; }
        return NO;
    }
    NSMutableDictionary *mutable = [config mutableCopy] ?: [self emptyProfileConfigDictionary];
    mutable[@"schemaVersion"] = @(FTMProfileConfigSchemaVersion);
    if (![mutable[@"assets"] isKindOfClass:[NSArray class]]) {
        mutable[@"assets"] = @[];
    }
    NSMutableDictionary *slotAssignments = [mutable[@"slotAssignments"] isKindOfClass:[NSDictionary class]] ? [mutable[@"slotAssignments"] mutableCopy] : [NSMutableDictionary dictionary];
    [self normalizeSlotAssignmentsDictionary:slotAssignments];
    mutable[@"slotAssignments"] = slotAssignments;
    BOOL ok = [mutable writeToURL:[self profileConfigURLForProfile:profile] atomically:YES];
    if (!ok && error) {
        *error = FTMMakeError(FTMProfileSystemErrorFileOperationFailed, @"Failed to save profile configuration.");
    }
    return ok;
}

- (BOOL)ensureProfileStorageAndConfigForProfile:(FTMProfile *)profile error:(NSError * _Nullable __autoreleasing *)error {
    NSURL *profileDir = [self profileDirectoryURLForProfile:profile];
    NSURL *assetsDir = [self assetsDirectoryURLForProfile:profile];
    NSError *dirError = nil;
    if (!FTMEnsureDirectoryExists(self.fileManager, profileDir, &dirError) ||
        !FTMEnsureDirectoryExists(self.fileManager, assetsDir, &dirError)) {
        if (error) { *error = dirError; }
        return NO;
    }
    NSURL *configURL = [self profileConfigURLForProfile:profile];
    if ([self.fileManager fileExistsAtPath:configURL.path]) {
        return YES;
    }
    return [self migrateLegacySlotFoldersIntoProfileConfigForProfile:profile error:error];
}

- (BOOL)migrateLegacySlotFoldersIntoProfileConfigForProfile:(FTMProfile *)profile error:(NSError * _Nullable __autoreleasing *)error {
    NSMutableDictionary *config = [self emptyProfileConfigDictionary];
    NSMutableArray *assets = [NSMutableArray array];
    NSMutableDictionary *slotAssignments = [config[@"slotAssignments"] mutableCopy];
    NSURL *profileDir = [self profileDirectoryURLForProfile:profile];
    NSURL *assetsDir = [self assetsDirectoryURLForProfile:profile];
    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];

    for (NSString *slotID in FTMAllSoundSlotIDs()) {
        NSArray<NSURL *> *legacyFiles = FTMDirectoryFilesSorted(self.fileManager, FTMSlotDirectoryURL(profileDir, slotID));
        NSMutableArray *slotAssetIDs = [NSMutableArray array];
        for (NSURL *legacyURL in legacyFiles) {
            NSString *sourceExt = nil;
            NSError *importErr = nil;
            NSString *preferred = [[NSUUID UUID] UUIDString];
            NSURL *destURL = [importer ftm_importAudioFileAtURL:legacyURL
                                                 toDirectoryURL:assetsDir
                                                  preferredName:preferred
                                              sourceExtensionOut:&sourceExt
                                                          error:&importErr];
            if (!destURL) {
                continue;
            }
            FTMProfileAsset *asset = [[FTMProfileAsset alloc] init];
            asset.assetID = [[NSUUID UUID] UUIDString];
            asset.displayName = legacyURL.lastPathComponent ?: destURL.lastPathComponent ?: @"Sound";
            asset.storedFileName = destURL.lastPathComponent ?: @"sound";
            asset.importedAt = [NSDate date];
            asset.sourceExtension = sourceExt;
            [assets addObject:[asset dictionaryRepresentation]];
            [slotAssetIDs addObject:asset.assetID];
        }
        slotAssignments[slotID] = slotAssetIDs;
    }

    config[@"assets"] = assets;
    config[@"slotAssignments"] = slotAssignments;
    return [self saveProfileConfig:config forProfile:profile error:error];
}

- (void)pruneInvalidAppRules {
    if (self.mutableAppRules.count == 0) {
        return;
    }
    NSMutableDictionary<NSString *, FTMAppProfileRule *> *unique = [NSMutableDictionary dictionary];
    for (FTMAppProfileRule *rule in self.mutableAppRules) {
        if (rule.bundleIdentifier.length == 0 || rule.profileID.length == 0) { continue; }
        if (![self profileWithID:rule.profileID]) { continue; }
        unique[rule.bundleIdentifier] = rule;
    }
    NSArray<NSString *> *sortedKeys = [[unique allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [self.mutableAppRules removeAllObjects];
    for (NSString *key in sortedKeys) {
        [self.mutableAppRules addObject:unique[key]];
    }
}

- (void)migrateLegacyTerminalOnlyToAssignedAppsOnlyIfNeeded {
    if ([self.defaults boolForKey:FTMDefaultsKeyDidMigrateV2Routing]) {
        return;
    }
    BOOL legacyTerminalsOnly = [self.defaults boolForKey:FTMDefaultsKeyTerminalsOnly];
    if (!legacyTerminalsOnly) {
        [self.defaults setBool:YES forKey:FTMDefaultsKeyDidMigrateV2Routing];
        return;
    }
    if (self.mutableAppRules.count > 0) {
        [self.defaults setBool:YES forKey:FTMDefaultsKeyDidMigrateV2Routing];
        return;
    }
    FTMProfile *fallback = [self activeProfile];
    if (!fallback) {
        [self.defaults setBool:YES forKey:FTMDefaultsKeyDidMigrateV2Routing];
        return;
    }
    NSDate *now = [NSDate date];
    for (NSString *bundleID in FTMLegacyTerminalBundleIdentifiers()) {
        FTMAppProfileRule *rule = [[FTMAppProfileRule alloc] init];
        rule.bundleIdentifier = bundleID;
        rule.profileID = fallback.profileID;
        rule.appNameHint = nil;
        rule.createdAt = now;
        rule.updatedAt = now;
        [self.mutableAppRules addObject:rule];
    }
    [self.defaults setBool:YES forKey:FTMDefaultsKeyAssignedAppsOnly];
    [self.defaults setBool:YES forKey:FTMDefaultsKeyDidMigrateV2Routing];
}

- (BOOL)saveMetadata:(NSError * _Nullable __autoreleasing *)error {
    NSMutableArray<NSDictionary *> *profilesArray = [NSMutableArray arrayWithCapacity:self.mutableProfiles.count];
    for (FTMProfile *profile in self.mutableProfiles) {
        [profilesArray addObject:[profile dictionaryRepresentation]];
    }
    NSMutableArray<NSDictionary *> *rulesArray = [NSMutableArray arrayWithCapacity:self.mutableAppRules.count];
    for (FTMAppProfileRule *rule in self.mutableAppRules) {
        [rulesArray addObject:[rule dictionaryRepresentation]];
    }
    NSDictionary *metadata = @{
        @"schemaVersion": @(FTMProfilesSchemaVersion),
        @"profiles": profilesArray,
        @"appRules": rulesArray,
    };
    BOOL ok = [metadata writeToURL:self.metadataURL atomically:YES];
    if (!ok && error) {
        *error = FTMMakeError(FTMProfileSystemErrorFileOperationFailed, @"Failed to save profile metadata.");
    }
    return ok;
}

- (BOOL)createBuiltInDefaultProfile:(NSError * _Nullable __autoreleasing *)error {
    FTMProfile *profile = [self createEmptyProfileNamed:@"Fallout Classic" error:error];
    if (!profile) {
        return NO;
    }

    NSMutableArray<NSURL *> *typingURLs = [NSMutableArray array];
    for (NSString *resourceName in FTMBuiltinTypingResourceNames()) {
        NSURL *url = [self.bundle URLForResource:resourceName withExtension:@"mp3"];
        if (url) { [typingURLs addObject:url]; }
    }

    FTMSoundPackImporter *importer = [[FTMSoundPackImporter alloc] init];
    NSArray<NSString *> *warnings = nil;
    if (typingURLs.count > 0) {
        if (![self addAudioFilesAtURLs:typingURLs
                              toSlotID:FTMSoundSlotTyping
                               profile:profile
                              importer:importer
                              warnings:&warnings
                                 error:error]) {
            return NO;
        }
    }

    NSArray<NSDictionary *> *singletons = @[
        @{@"slot": FTMSoundSlotEnter, @"name": @"kenter", @"ext": @"mp3"},
        @{@"slot": FTMSoundSlotLaunch, @"name": @"poweron", @"ext": @"mp3"},
        @{@"slot": FTMSoundSlotQuit, @"name": @"poweroff", @"ext": @"mp3"},
    ];
    for (NSDictionary *entry in singletons) {
        NSURL *url = [self.bundle URLForResource:entry[@"name"] withExtension:entry[@"ext"]];
        if (url) {
            [self addAudioFilesAtURLs:@[url]
                             toSlotID:entry[@"slot"]
                              profile:profile
                             importer:importer
                             warnings:nil
                                error:nil];
        }
    }

    profile.updatedAt = [NSDate date];
    [self.defaults setObject:profile.profileID forKey:FTMDefaultsKeyActiveProfileID];
    return YES;
}

@end

@interface FTMSoundResolver ()
@property (nonatomic, strong) FTMProfileStore *profileStore;
@property (nonatomic, strong) NSBundle *bundle;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<NSString *, NSArray<NSString *> *> *> *cachedSlotsByProfileID;
@end

@implementation FTMSoundResolver

- (instancetype)initWithProfileStore:(FTMProfileStore *)profileStore bundle:(NSBundle *)bundle {
    self = [super init];
    if (self) {
        _profileStore = profileStore;
        _bundle = bundle ?: [NSBundle mainBundle];
        _cachedSlotsByProfileID = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)invalidateCache {
    [self.cachedSlotsByProfileID removeAllObjects];
}

- (NSString *)slotIDForKeyCode:(unsigned short)keyCode {
    switch (keyCode) {
        case 36: // Return
        case 76: // Keypad Enter
            return FTMSoundSlotEnter;
        case 51: // Delete/Backspace
            return FTMSoundSlotBackspace;
        case 48: // Tab
            return FTMSoundSlotTab;
        case 49: // Space
            return FTMSoundSlotSpace;
        case 53: // Escape
            return FTMSoundSlotEscape;
        default:
            return FTMSoundSlotTyping;
    }
}

- (NSString *)soundPathForKeyCode:(unsigned short)keyCode {
    return [self soundPathForKeyCode:keyCode profile:nil];
}

- (NSString *)soundPathForKeyCode:(unsigned short)keyCode profile:(FTMProfile *)profile {
    return [self randomSoundPathForSlotID:[self slotIDForKeyCode:keyCode] profile:profile];
}

- (NSString *)soundPathForEventSlotID:(NSString *)slotID {
    return [self soundPathForEventSlotID:slotID profile:nil];
}

- (NSString *)soundPathForEventSlotID:(NSString *)slotID profile:(FTMProfile *)profile {
    return [self randomSoundPathForSlotID:slotID profile:profile];
}

- (NSString *)randomSoundPathForSlotID:(NSString *)slotID profile:(FTMProfile *)profile {
    if (!slotID.length) {
        return nil;
    }

    NSArray<NSString *> *paths = [self soundPathsForSlotID:slotID profile:profile];
    if (paths.count == 0 && ![slotID isEqualToString:FTMSoundSlotLaunch] && ![slotID isEqualToString:FTMSoundSlotQuit]) {
        paths = [self soundPathsForSlotID:FTMSoundSlotTyping profile:profile];
    }

    if (paths.count > 0) {
        uint32_t idx = arc4random_uniform((uint32_t)paths.count);
        return paths[idx];
    }

    NSString *fallbackSpecific = FTMSlotFallbackBundleResourceName(slotID);
    if (fallbackSpecific) {
        return [self.bundle pathForResource:fallbackSpecific ofType:@"mp3"];
    }

    NSArray<NSString *> *builtins = FTMBuiltinTypingResourceNames();
    if (builtins.count > 0) {
        uint32_t idx = arc4random_uniform((uint32_t)builtins.count);
        return [self.bundle pathForResource:builtins[idx] ofType:@"mp3"];
    }

    return nil;
}

- (NSArray<NSString *> *)soundPathsForSlotID:(NSString *)slotID profile:(FTMProfile *)profile {
    if (profile) {
        NSArray<NSURL *> *urls = [self.profileStore fileURLsForSlotID:slotID profile:profile];
        NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:urls.count];
        for (NSURL *url in urls) {
            [paths addObject:url.path];
        }
        return paths;
    }

    FTMProfile *active = [self.profileStore activeProfile];
    if (!active) {
        return @[];
    }
    NSDictionary<NSString *, NSArray<NSString *> *> *cache = self.cachedSlotsByProfileID[active.profileID];
    if (!cache) {
        cache = [self buildCacheForProfile:active];
        if (cache) {
            self.cachedSlotsByProfileID[active.profileID] = cache;
        }
    }
    return cache[slotID] ?: @[];
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)buildCacheForProfile:(FTMProfile *)profile {
    NSMutableDictionary<NSString *, NSArray<NSString *> *> *cache = [NSMutableDictionary dictionary];
    for (NSString *slotID in FTMAllSoundSlotIDs()) {
        NSArray<NSURL *> *urls = [self.profileStore fileURLsForSlotID:slotID profile:profile];
        NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:urls.count];
        for (NSURL *url in urls) {
            [paths addObject:url.path];
        }
        cache[slotID] = [paths copy];
    }
    return [cache copy];
}

@end

@implementation FTMSoundPlayer {
    NSMutableArray<NSSound *> *_liveSounds;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _liveSounds = [NSMutableArray array];
    }
    return self;
}

- (void)playSoundAtPath:(NSString *)path {
    if (path.length == 0) {
        return;
    }

    NSSound *sound = [[NSSound alloc] initWithContentsOfFile:path byReference:YES];
    if (!sound) {
        return;
    }
    sound.delegate = self;
    [_liveSounds addObject:sound];
    if (![sound play]) {
        [_liveSounds removeObject:sound];
    }
}

- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)finishedPlaying {
    (void)finishedPlaying;
    [_liveSounds removeObject:sound];
}

@end
