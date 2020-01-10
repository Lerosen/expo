//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAsset.h>
#import <EXUpdates/EXUpdatesUtils.h>

@interface EXUpdatesAsset ()

@property (nonatomic, readwrite, strong) NSString * _Nullable filenameWithExtension;
@property (nonatomic, readwrite, strong) NSString * _Nullable contentHash;
@property (nonatomic, readwrite, strong) NSDictionary * _Nullable headers;

@end

@implementation EXUpdatesAsset

- (instancetype)initWithUrl:(NSURL * _Nonnull)url type:(NSString * _Nonnull)type
{
  if (self = [super init]) {
    _url = url;
    _type = type;
  }
  return self;
}

- (NSString *)filenameWithExtension
{
  if (!_filenameWithExtension) {
    if (_filename) {
      _filenameWithExtension = [NSString stringWithFormat:@"%@.%@", _filename, _type];
    }
  }
  return _filenameWithExtension;
}

- (NSString *)contentHash {
  if (!_contentHash) {
    if (_data) {
      _contentHash = [EXUpdatesUtils sha1WithData:_data];
    }
  }
  return _contentHash;
}

- (NSDictionary *)headers {
  if (!_headers) {
    if (_response && [_response isKindOfClass:[NSHTTPURLResponse class]]) {
      _headers = [(NSHTTPURLResponse *)_response allHeaderFields];
    }
  }
  return _headers;
}

@end
