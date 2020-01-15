//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAppController.h>
#import <EXUpdates/EXUpdatesAppLoaderEmbedded.h>

NS_ASSUME_NONNULL_BEGIN

NSString * const kEXUpdatesEmbeddedManifestName = @"shell-app-manifest";
NSString * const kEXUpdatesEmbeddedManifestType = @"json";
NSString * const kEXUpdatesEmbeddedBundleFilename = @"shell-app";
NSString * const kEXUpdatesEmbeddedBundleFileType = @"bundle";

@implementation EXUpdatesAppLoaderEmbedded

+ (EXUpdatesUpdate * _Nullable)embeddedManifest
{
  static EXUpdatesUpdate *embeddedManifest;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    if (!embeddedManifest) {
      NSString *path = [[NSBundle mainBundle] pathForResource:kEXUpdatesEmbeddedManifestName ofType:kEXUpdatesEmbeddedManifestType];
      NSData *manifestData = [NSData dataWithContentsOfFile:path];

      NSError *err;
      id manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:kNilOptions error:&err];
      if (!manifest) {
        NSLog(@"Could not read embedded manifest: %@", [err localizedDescription]);
      } else {
        NSAssert([manifest isKindOfClass:[NSDictionary class]], @"embedded manifest should be a valid JSON file");
        embeddedManifest = [EXUpdatesUpdate updateWithManagedManifest:(NSDictionary *)manifest];
      }
    }
  });
  return embeddedManifest;
}

- (void)loadUpdateFromEmbeddedManifest
{
  [self startLoadingFromManifest:[[self class] embeddedManifest]];
}

- (void)downloadAsset:(EXUpdatesAsset *)asset
{
  NSURL *updatesDirectory = [EXUpdatesAppController sharedInstance].updatesDirectory;
  NSURL *destinationUrl = [updatesDirectory URLByAppendingPathComponent:asset.filename];
  if ([[NSFileManager defaultManager] fileExistsAtPath:[destinationUrl path]]) {
    [self handleAssetDownloadAlreadyExists:asset];
  } else {
    NSAssert(asset.nsBundleFilename, @"embedded asset nsBundleFilename must be nonnull");
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:asset.nsBundleFilename ofType:asset.type];
    NSAssert(bundlePath, @"NSBundle must contain the expected assets");

    NSError *err;
    if ([[NSFileManager defaultManager] copyItemAtPath:bundlePath toPath:[destinationUrl path] error:&err]) {
      [self handleAssetDownloadWithData:[NSData dataWithContentsOfFile:bundlePath] response:nil asset:asset];
    } else {
      [self handleAssetDownloadWithError:err asset:asset];
    }
  }
}

- (void)loadUpdateFromUrl:(NSURL *)url
{
  @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Should not call EXUpdatesAppLoaderEmbedded#loadUpdateFromUrl" userInfo:nil];
}

@end

NS_ASSUME_NONNULL_END
