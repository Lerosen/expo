//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesConfig.h>
#import <EXUpdates/EXUpdatesAppController.h>
#import <EXUpdates/EXUpdatesAppLauncher.h>
#import <EXUpdates/EXUpdatesAppLauncherEmergency.h>
#import <EXUpdates/EXUpdatesAppLauncherWithDatabase.h>
#import <EXUpdates/EXUpdatesAppLoaderEmbedded.h>
#import <EXUpdates/EXUpdatesAppLoaderRemote.h>
#import <EXUpdates/EXUpdatesReaper.h>
#import <EXUpdates/EXUpdatesSelectionPolicyNewest.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <arpa/inet.h>

NS_ASSUME_NONNULL_BEGIN

static NSString * const kEXUpdatesEventName = @"Expo.nativeUpdatesEvent";
static NSString * const kEXUpdatesUpdateAvailableEventName = @"updateAvailable";
static NSString * const kEXUpdatesNoUpdateAvailableEventName = @"noUpdateAvailable";
static NSString * const kEXUpdatesErrorEventName = @"error";
static NSString * const kEXUpdatesAppControllerErrorDomain = @"EXUpdatesAppController";

@interface EXUpdatesAppController ()

@property (nonatomic, readwrite, strong) id<EXUpdatesAppLauncher> launcher;
@property (nonatomic, readwrite, strong) EXUpdatesDatabase *database;
@property (nonatomic, readwrite, strong) id<EXUpdatesSelectionPolicy> selectionPolicy;
@property (nonatomic, readwrite, strong) EXUpdatesAppLoaderEmbedded *embeddedAppLoader;
@property (nonatomic, readwrite, strong) EXUpdatesAppLoaderRemote *remoteAppLoader;

@property (nonatomic, readwrite, strong) NSURL *updatesDirectory;
@property (nonatomic, readwrite, assign) BOOL isEnabled;

@property (nonatomic, strong) id<EXUpdatesAppLauncher> candidateLauncher;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL isReadyToLaunch;
@property (nonatomic, assign) BOOL isTimerFinished;
@property (nonatomic, assign) BOOL hasLaunched;

@property (nonatomic, assign) BOOL isEmergencyLaunch;

@end

@implementation EXUpdatesAppController

+ (instancetype)sharedInstance
{
  static EXUpdatesAppController *theController;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    if (!theController) {
      theController = [[EXUpdatesAppController alloc] init];
    }
  });
  return theController;
}

- (instancetype)init
{
  if (self = [super init]) {
    _database = [[EXUpdatesDatabase alloc] init];
    _selectionPolicy = [[EXUpdatesSelectionPolicyNewest alloc] init];
    _isEnabled = NO;
    _isReadyToLaunch = NO;
    _isTimerFinished = NO;
    _hasLaunched = NO;
  }
  return self;
}

- (void)start
{
  _isEnabled = YES;
  NSError *fsError = [self _initializeUpdatesDirectory];
  if (fsError) {
    [self _emergencyLaunchWithError:fsError];
    return;
  }

  NSError *dbError;
  if (![_database openDatabaseWithError:&dbError]) {
    [self _emergencyLaunchWithError:dbError];
    return;
  }

  NSNumber *launchWaitMs = [EXUpdatesConfig sharedInstance].launchWaitMs;
  if ([launchWaitMs isEqualToNumber:@(0)]) {
    _isTimerFinished = YES;
  } else {
    NSDate *fireDate = [NSDate dateWithTimeIntervalSinceNow:[launchWaitMs doubleValue] / 1000];
    _timer = [[NSTimer alloc] initWithFireDate:fireDate interval:0 target:self selector:@selector(_timerDidFire) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSDefaultRunLoopMode];
  }

  [self _maybeLoadEmbeddedUpdate];

  EXUpdatesAppLauncherWithDatabase *launcher = [[EXUpdatesAppLauncherWithDatabase alloc] init];
  _launcher = launcher;
  [launcher launchUpdateWithSelectionPolicy:_selectionPolicy completion:^(BOOL success) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (success) {
        self->_isReadyToLaunch = YES;
        [self _maybeFinish];

        if (!self->_remoteAppLoader && [[self class] _shouldCheckForUpdate]) {
          self->_remoteAppLoader = [[EXUpdatesAppLoaderRemote alloc] init];
          self->_remoteAppLoader.delegate = self;
          [self->_remoteAppLoader loadUpdateFromUrl:[EXUpdatesConfig sharedInstance].remoteUrl];
        } else {
          [self _runReaperInBackground];
        }
      } else {
        [self _emergencyLaunchWithError:[NSError errorWithDomain:kEXUpdatesAppControllerErrorDomain
                                                            code:-1
                                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to find or load launch asset"}]];
      }
    });
  }];
}

- (void)startAndShowLaunchScreen:(UIWindow *)window
{
  UIViewController *rootViewController = [UIViewController new];
  NSArray *views;
  @try {
    NSString *launchScreen = (NSString *)[[NSBundle mainBundle] objectForInfoDictionaryKey:@"UILaunchStoryboardName"] ?: @"LaunchScreen";
    views = [[NSBundle mainBundle] loadNibNamed:launchScreen owner:self options:nil];
  } @catch (NSException *_) {
    NSLog(@"LaunchScreen.xib is missing. Unexpected loading behavior may occur.");
  }
  if (views) {
    rootViewController.view = views.firstObject;
    rootViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  } else {
    UIView *view = [UIView new];
    view.backgroundColor = [UIColor whiteColor];;
    rootViewController.view = view;
  }
  window.rootViewController = rootViewController;
  [window makeKeyAndVisible];

  [self start];
}

- (BOOL)requestRelaunch
{
  if (_bridge) {
    [_database.lock lock];
    EXUpdatesAppLauncherWithDatabase *launcher = [[EXUpdatesAppLauncherWithDatabase alloc] init];
    _candidateLauncher = launcher;
    [launcher launchUpdateWithSelectionPolicy:self->_selectionPolicy completion:^(BOOL success) {
      if (success) {
        dispatch_async(dispatch_get_main_queue(), ^{
          self->_launcher = self->_candidateLauncher;
          [self->_database.lock unlock];
          [self->_bridge reload];
          [self _runReaperInBackground];
        });
      }
    }];
    return true;
  } else {
    NSLog(@"EXUpdatesAppController: Failed to reload because bridge was nil. Did you set the bridge property on the controller singleton?");
    return false;
  }
}

- (EXUpdatesUpdate * _Nullable)launchedUpdate
{
  return _launcher.launchedUpdate ?: nil;
}

- (NSURL * _Nullable)launchAssetUrl
{
  return _launcher.launchAssetUrl ?: nil;
}

- (NSDictionary * _Nullable)assetFilesMap
{
  return _launcher.assetFilesMap ?: nil;
}

# pragma mark - internal

- (void)_maybeFinish
{
  NSAssert([NSThread isMainThread], @"EXUpdatesAppController:_maybeFinish should only be called on the main thread");
  if (!_isTimerFinished || !_isReadyToLaunch) {
    // too early, bail out
    return;
  }
  if (_hasLaunched) {
    // we've already fired once, don't do it again
    return;
  }

  // TODO: remove this assertion and replace it with
  // [self _emergencyLaunchWithError:];
  NSAssert(self.launchAssetUrl != nil, @"_maybeFinish should only be called when we have a valid launchAssetUrl");

  _hasLaunched = YES;
  if (self->_delegate) {
    [self->_delegate appController:self didStartWithSuccess:YES];
  }
}

- (void)_timerDidFire
{
  NSAssert([NSThread isMainThread], @"EXUpdatesAppController: timer should only run on mainRunLoop");
  _isTimerFinished = YES;
  [self _maybeFinish];
}

- (NSError * _Nullable)_initializeUpdatesDirectory
{
  NSAssert(!_updatesDirectory, @"EXUpdatesAppController:_initializeUpdatesDirectory should only be called once per instance");

  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSURL *applicationDocumentsDirectory = [[fileManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
  NSURL *updatesDirectory = [applicationDocumentsDirectory URLByAppendingPathComponent:@".expo-internal"];
  NSString *updatesDirectoryPath = [updatesDirectory path];

  BOOL isDir;
  BOOL exists = [fileManager fileExistsAtPath:updatesDirectoryPath isDirectory:&isDir];
  if (!exists || !isDir) {
    if (exists && !isDir) {
      NSError *err;
      BOOL wasRemoved = [fileManager removeItemAtPath:updatesDirectoryPath error:&err];
      if (!wasRemoved) {
        return err;
      }
    }
    NSError *err;
    BOOL wasCreated = [fileManager createDirectoryAtPath:updatesDirectoryPath withIntermediateDirectories:YES attributes:nil error:&err];
    if (!wasCreated) {
      return err;
    }
  }

  _updatesDirectory = updatesDirectory;
  return nil;
}

- (void)_maybeLoadEmbeddedUpdate
{
  if ([_selectionPolicy shouldLoadNewUpdate:[EXUpdatesAppLoaderEmbedded embeddedManifest]
                         withLaunchedUpdate:[EXUpdatesAppLauncherWithDatabase launchableUpdateWithSelectionPolicy:_selectionPolicy]]) {
    _embeddedAppLoader = [[EXUpdatesAppLoaderEmbedded alloc] init];
    [_embeddedAppLoader loadUpdateFromEmbeddedManifest];
  }
}

- (void)_sendEventToBridgeWithType:(NSString *)eventType body:(NSDictionary *)body
{
  if (_bridge) {
    NSMutableDictionary *mutableBody = [body mutableCopy];
    mutableBody[@"type"] = eventType;
    [_bridge enqueueJSCall:@"RCTDeviceEventEmitter.emit" args:@[kEXUpdatesEventName, mutableBody]];
  } else {
    NSLog(@"EXUpdatesAppController: Could not emit %@ event. Did you set the bridge property on the controller singleton?", eventType);
  }
}

- (void)_runReaperInBackground
{
  if (_launcher.launchedUpdate) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
      [EXUpdatesReaper reapUnusedUpdatesWithSelectionPolicy:self->_selectionPolicy
                                             launchedUpdate:self->_launcher.launchedUpdate];
    });
  }
}

- (void)_emergencyLaunchWithError:(NSError *)error
{
  if (_timer) {
    [_timer invalidate];
  }

  _isEmergencyLaunch = YES;
  _hasLaunched = YES;

  EXUpdatesAppLauncherEmergency *launcher = [[EXUpdatesAppLauncherEmergency alloc] init];
  _launcher = launcher;
  [launcher launchUpdateWithFatalError:error];

  if (self->_delegate) {
    [self->_delegate appController:self didStartWithSuccess:self.launchAssetUrl != nil];
  }
}

+ (BOOL)_shouldCheckForUpdate
{
  EXUpdatesConfig *config = [EXUpdatesConfig sharedInstance];
  switch (config.checkOnLaunch) {
    case EXUpdatesCheckAutomaticallyConfigNever:
      return NO;
    case EXUpdatesCheckAutomaticallyConfigWifiOnly: {
      struct sockaddr_in zeroAddress;
      bzero(&zeroAddress, sizeof(zeroAddress));
      zeroAddress.sin_len = sizeof(zeroAddress);
      zeroAddress.sin_family = AF_INET;

      SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *) &zeroAddress);
      SCNetworkReachabilityFlags flags;
      SCNetworkReachabilityGetFlags(reachability, &flags);

      return (flags & kSCNetworkReachabilityFlagsIsWWAN) == 0;
    }
    case EXUpdatesCheckAutomaticallyConfigAlways:
    default:
      return YES;
  }
}

# pragma mark - EXUpdatesAppLoaderDelegate

- (BOOL)appLoader:(EXUpdatesAppLoader *)appLoader shouldStartLoadingUpdate:(EXUpdatesUpdate *)update
{
  BOOL shouldStartLoadingUpdate = [_selectionPolicy shouldLoadNewUpdate:update withLaunchedUpdate:_launcher.launchedUpdate];
  NSLog(@"manifest downloaded, shouldStartLoadingUpdate is %@", shouldStartLoadingUpdate ? @"YES" : @"NO");
  return shouldStartLoadingUpdate;
}

- (void)appLoader:(EXUpdatesAppLoader *)appLoader didFinishLoadingUpdate:(EXUpdatesUpdate * _Nullable)update
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_timer) {
      [self->_timer invalidate];
    }
    self->_isTimerFinished = YES;

    if (update) {
      if (!self->_hasLaunched) {
        EXUpdatesAppLauncherWithDatabase *launcher = [[EXUpdatesAppLauncherWithDatabase alloc] init];
        self->_candidateLauncher = launcher;
        [launcher launchUpdateWithSelectionPolicy:self->_selectionPolicy completion:^(BOOL success) {
          if (success) {
            dispatch_async(dispatch_get_main_queue(), ^{
              if (!self->_hasLaunched) {
                self->_launcher = self->_candidateLauncher;
                [self _maybeFinish];
              }
              [self _runReaperInBackground];
            });
          }
        }];
      } else {
        [self _sendEventToBridgeWithType:kEXUpdatesUpdateAvailableEventName
                                    body:@{@"manifest": update.rawManifest}];
        [self _runReaperInBackground];
      }
    } else {
      NSLog(@"No update available");
      // there's no update, so signal we're ready to launch
      [self _maybeFinish];
      [self _runReaperInBackground];
    }
  });
}

- (void)appLoader:(EXUpdatesAppLoader *)appLoader didFailWithError:(NSError *)error
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_timer) {
      [self->_timer invalidate];
    }
    self->_isTimerFinished = YES;
    NSLog(@"update failed to load: %@", error.localizedDescription);
    [self _maybeFinish];
    [self _sendEventToBridgeWithType:kEXUpdatesErrorEventName body:@{@"message": error.localizedDescription}];
  });
}

@end

NS_ASSUME_NONNULL_END
