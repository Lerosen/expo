//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAppController.h>
#import <EXUpdates/EXUpdatesAppLauncher.h>
#import <EXUpdates/EXUpdatesAppLoaderEmbedded.h>
#import <EXUpdates/EXUpdatesDatabase.h>
#import <EXUpdates/EXUpdatesFileDownloader.h>

NS_ASSUME_NONNULL_BEGIN

@interface EXUpdatesAppLauncher ()

@property (nonatomic, strong, readwrite) EXUpdatesUpdate * _Nullable launchedUpdate;
@property (nonatomic, strong, readwrite) NSURL * _Nullable launchAssetUrl;
@property (nonatomic, strong, readwrite) NSMutableDictionary * _Nullable assetFilesMap;

@property (nonatomic, strong) EXUpdatesFileDownloader *downloader;

@property (nonatomic, strong) NSLock *lock;
@property (nonatomic, assign) int assetsToDownload;
@property (nonatomic, assign) int assetsToDownloadFinished;

@end

static NSString * const kEXUpdatesAppLauncherErrorDomain = @"AppLauncher";

@implementation EXUpdatesAppLauncher

- (instancetype)init
{
  if (self = [super init]) {
    _lock = [NSLock new];
    _assetsToDownload = 0;
    _assetsToDownloadFinished = 0;
  }
  return self;
}

- (EXUpdatesUpdate * _Nullable)launchableUpdateWithSelectionPolicy:(id<EXUpdatesSelectionPolicy>)selectionPolicy
{
  EXUpdatesDatabase *database = [EXUpdatesAppController sharedInstance].database;
  NSArray<EXUpdatesUpdate *>* launchableUpdates = [database launchableUpdates];
  return [selectionPolicy launchableUpdateWithUpdates:launchableUpdates];
}

- (void)launchUpdateWithSelectionPolicy:(id<EXUpdatesSelectionPolicy>)selectionPolicy
{
  if (!_launchedUpdate) {
    _launchedUpdate = [self launchableUpdateWithSelectionPolicy:selectionPolicy];
  }
  
  _assetFilesMap = [NSMutableDictionary new];
  NSURL *updatesDirectory = [EXUpdatesAppController sharedInstance].updatesDirectory;

  [_lock lock];
  if (_launchedUpdate) {
    for (EXUpdatesAsset *asset in _launchedUpdate.assets) {
      if ([self ensureAssetExists:asset]) {
        NSURL *assetLocalUrl = [updatesDirectory URLByAppendingPathComponent:asset.filename];
        if (asset.isLaunchAsset) {
          _launchAssetUrl = assetLocalUrl;
        } else {
          [_assetFilesMap setObject:[assetLocalUrl absoluteString] forKey:[asset.url absoluteString]];
        }
      }
    }
  }

  if (_assetsToDownload == 0 && _delegate) {
    [_delegate appLauncher:self didFinishWithSuccess:YES];
  }
  [_lock unlock];
}

- (BOOL)ensureAssetExists:(EXUpdatesAsset *)asset
{
  NSURL *assetLocalUrl = [[EXUpdatesAppController sharedInstance].updatesDirectory URLByAppendingPathComponent:asset.filename];
  BOOL assetFileExists = [[NSFileManager defaultManager] fileExistsAtPath:[assetLocalUrl path]];
  if (!assetFileExists) {
    // something has gone wrong, we're missing the asset
    // first check to see if a copy is embedded in the binary
    EXUpdatesUpdate *embeddedManifest = [EXUpdatesAppController sharedInstance].embeddedAppLoader.embeddedManifest;
    if (embeddedManifest) {
      EXUpdatesAsset *matchingAsset;
      for (EXUpdatesAsset *embeddedAsset in embeddedManifest.assets) {
        if ([[embeddedAsset.url absoluteString] isEqualToString:[asset.url absoluteString]]) {
          matchingAsset = embeddedAsset;
          break;
        }
      }

      if (matchingAsset && matchingAsset.nsBundleFilename) {
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:matchingAsset.nsBundleFilename ofType:matchingAsset.type];
        NSError *error;
        if ([[NSFileManager defaultManager] copyItemAtPath:bundlePath toPath:[assetLocalUrl path] error:&error]) {
          assetFileExists = YES;
        } else {
          NSLog(@"Error copying asset: %@", error.localizedDescription);
        }
      }
    }
  }

  if (!assetFileExists) {
    // we couldn't copy the file from the embedded assets
    // so we need to attempt to download it
    _assetsToDownload++;
    [self.downloader downloadFileFromURL:asset.url toPath:[assetLocalUrl path] successBlock:^(NSData * _Nonnull data, NSURLResponse * _Nonnull response) {
      asset.data = data;
      asset.response = response;
      asset.downloadTime = [NSDate date];
      [self _assetDownloadDidFinish:asset withLocalUrl:assetLocalUrl];
    } errorBlock:^(NSError * _Nonnull error, NSURLResponse * _Nonnull response) {
      [self _assetDownloadDidError:error];
    }];
  }

  return assetFileExists;
}

- (EXUpdatesFileDownloader *)downloader
{
  if (!_downloader) {
    _downloader = [[EXUpdatesFileDownloader alloc] init];
  }
  return _downloader;
}

- (void)_assetDownloadDidFinish:(EXUpdatesAsset *)asset withLocalUrl:(NSURL *)localUrl
{
  [_lock lock];
  _assetsToDownloadFinished++;
  [[EXUpdatesAppController sharedInstance].database updateAsset:asset];
  if (asset.isLaunchAsset) {
    _launchAssetUrl = localUrl;
  } else {
    [_assetFilesMap setObject:[localUrl absoluteString] forKey:[asset.url absoluteString]];
  }

  if (_assetsToDownloadFinished == _assetsToDownload && _delegate) {
    [_delegate appLauncher:self didFinishWithSuccess:_launchAssetUrl != nil];
  }
  [_lock unlock];
}

- (void)_assetDownloadDidError:(NSError *)error
{
  [_lock lock];
  _assetsToDownloadFinished++;
  if (_assetsToDownloadFinished == _assetsToDownload && _delegate) {
    [_delegate appLauncher:self didFinishWithSuccess:_launchAssetUrl != nil];
  }
  [_lock unlock];
}

@end

NS_ASSUME_NONNULL_END
