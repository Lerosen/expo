//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesUpdate.h>

NS_ASSUME_NONNULL_BEGIN

@protocol EXUpdatesAppLauncher

@property (nonatomic, strong, readonly) EXUpdatesUpdate * _Nullable launchedUpdate;
@property (nonatomic, strong, readonly) NSURL * _Nullable launchAssetUrl;
@property (nonatomic, strong, readonly) NSDictionary * _Nullable assetFilesMap;

@end

NS_ASSUME_NONNULL_END
