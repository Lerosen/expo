//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAppController.h>
#import <EXUpdates/EXUpdatesDatabase.h>

#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

@interface EXUpdatesDatabase ()

@property (nonatomic, assign) sqlite3 *db;
@property (nonatomic, readwrite, strong) NSLock *lock;

@end

static NSString * const kEXUpdatesDatabaseErrorDomain = @"EXUpdatesDatabase";
static NSString * const kEXUpdatesDatabaseFilename = @"updates.db";

@implementation EXUpdatesDatabase

# pragma mark - lifecycle

- (instancetype)init
{
  if (self = [super init]) {
    _lock = [[NSLock alloc] init];
  }
  return self;
}

- (BOOL)openDatabaseWithError:(NSError ** _Nullable)error
{
  sqlite3 *db;
  NSURL *dbUrl = [[EXUpdatesAppController sharedInstance].updatesDirectory URLByAppendingPathComponent:kEXUpdatesDatabaseFilename];
  NSLog(@"%@", [dbUrl absoluteString]);
  BOOL shouldInitializeDatabase = ![[NSFileManager defaultManager] fileExistsAtPath:[dbUrl path]];
  int resultCode = sqlite3_open([[dbUrl absoluteString] UTF8String], &db);
  if (resultCode != SQLITE_OK) {
    NSLog(@"Error opening SQLite db: %@", [self _errorFromSqlite:_db].localizedDescription);
    sqlite3_close(db);

    if (resultCode == SQLITE_CORRUPT || resultCode == SQLITE_NOTADB) {
      NSString *archivedDbFilename = [NSString stringWithFormat:@"%f-%@", [[NSDate date] timeIntervalSince1970], kEXUpdatesDatabaseFilename];
      NSURL *destinationUrl = [[EXUpdatesAppController sharedInstance].updatesDirectory URLByAppendingPathComponent:archivedDbFilename];
      NSError *err;
      if ([[NSFileManager defaultManager] moveItemAtURL:dbUrl toURL:destinationUrl error:&err]) {
        NSLog(@"Moved corrupt SQLite db to %@", archivedDbFilename);
        if (sqlite3_open([[dbUrl absoluteString] UTF8String], &db) != SQLITE_OK) {
          if (error != nil) {
            *error = [self _errorFromSqlite:_db];
          }
          return NO;
        }
        shouldInitializeDatabase = YES;
      } else {
        NSString *description = [NSString stringWithFormat:@"Could not move existing corrupt database: %@", [err localizedDescription]];
        if (error != nil) {
          *error = [NSError errorWithDomain:kEXUpdatesDatabaseErrorDomain
                                       code:-1
                                   userInfo:@{ NSLocalizedDescriptionKey: description, NSUnderlyingErrorKey: err }];
        }
        return NO;
      }
    } else {
      if (error != nil) {
        *error = [self _errorFromSqlite:_db];
      }
      return NO;
    }
  }
  _db = db;

  if (shouldInitializeDatabase) {
    return [self _initializeDatabase:error];
  }
  return YES;
}

- (void)closeDatabase
{
  sqlite3_close(_db);
  _db = nil;
}

- (void)dealloc
{
  [self closeDatabase];
}

- (BOOL)_initializeDatabase:(NSError **)error
{
  NSAssert(_db, @"Missing database handle");

  NSString * const createTableStmts = @"\
   PRAGMA foreign_keys = ON;\
   CREATE TABLE \"updates\" (\
   \"id\"  BLOB UNIQUE,\
   \"commit_time\"  INTEGER NOT NULL UNIQUE,\
   \"binary_versions\"  TEXT NOT NULL,\
   \"launch_asset_id\" INTEGER,\
   \"metadata\"  TEXT,\
   \"status\"  INTEGER NOT NULL,\
   \"keep\"  INTEGER NOT NULL,\
   PRIMARY KEY(\"id\"),\
   FOREIGN KEY(\"launch_asset_id\") REFERENCES \"assets\"(\"id\") ON DELETE CASCADE\
   );\
   CREATE TABLE \"assets\" (\
   \"id\"  INTEGER PRIMARY KEY AUTOINCREMENT,\
   \"url\"  TEXT NOT NULL UNIQUE,\
   \"headers\"  TEXT,\
   \"type\"  TEXT NOT NULL,\
   \"metadata\"  TEXT,\
   \"download_time\"  INTEGER NOT NULL,\
   \"relative_path\"  TEXT NOT NULL,\
   \"hash\"  BLOB NOT NULL,\
   \"hash_type\"  INTEGER NOT NULL,\
   \"marked_for_deletion\"  INTEGER NOT NULL\
   );\
   CREATE TABLE \"updates_assets\" (\
   \"update_id\"  BLOB NOT NULL,\
   \"asset_id\" INTEGER NOT NULL,\
   FOREIGN KEY(\"update_id\") REFERENCES \"updates\"(\"id\") ON DELETE CASCADE,\
   FOREIGN KEY(\"asset_id\") REFERENCES \"assets\"(\"id\") ON DELETE CASCADE\
   );\
   CREATE INDEX \"index_updates_launch_asset_id\" ON \"updates\" (\"launch_asset_id\");\
   ";

  char *errMsg;
  if (sqlite3_exec(_db, [createTableStmts UTF8String], NULL, NULL, &errMsg) != SQLITE_OK) {
    if (error != nil) {
      *error = [self _errorFromSqlite:_db];
    }
    sqlite3_free(errMsg);
    return NO;
  };
  return YES;
}

# pragma mark - insert and update

- (void)addUpdate:(EXUpdatesUpdate *)update error:(NSError ** _Nullable)error
{
  NSString * const sql = @"INSERT INTO \"updates\" (\"id\", \"commit_time\", \"binary_versions\", \"metadata\", \"status\" , \"keep\")\
  VALUES (?1, ?2, ?3, ?4, ?5, 1);";

  [self _executeSql:sql
           withArgs:@[
                      update.updateId,
                      @([update.commitTime timeIntervalSince1970] * 1000),
                      update.binaryVersions,
                      update.metadata ?: [NSNull null],
                      @(EXUpdatesUpdateStatusPending)
                      ]
              error:error];
}

- (void)addNewAssets:(NSArray<EXUpdatesAsset *>*)assets toUpdateWithId:(NSUUID *)updateId error:(NSError ** _Nullable)error
{
  sqlite3_exec(_db, "BEGIN;", NULL, NULL, NULL);

  for (EXUpdatesAsset *asset in assets) {
    NSAssert(asset.downloadTime, @"asset downloadTime should be nonnull");
    NSAssert(asset.filename, @"asset filename should be nonnull");
    NSAssert(asset.contentHash, @"asset contentHash should be nonnull");

    NSString * const assetInsertSql = @"INSERT OR REPLACE INTO \"assets\" (\"url\", \"headers\", \"type\", \"metadata\", \"download_time\", \"relative_path\", \"hash\", \"hash_type\", \"marked_for_deletion\")\
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 0);";
    if ([self _executeSql:assetInsertSql
                 withArgs:@[
                          [asset.url absoluteString],
                          asset.headers ?: [NSNull null],
                          asset.type,
                          asset.metadata ?: [NSNull null],
                          [NSNumber numberWithDouble:[asset.downloadTime timeIntervalSince1970]],
                          asset.filename,
                          asset.contentHash,
                          @(EXUpdatesDatabaseHashTypeSha1)
                          ]
                    error:error] == nil) {
      sqlite3_exec(_db, "ROLLBACK;", NULL, NULL, NULL);
      return;
    }

    // statements must stay in precisely this order for last_insert_rowid() to work correctly
    if (asset.isLaunchAsset) {
      NSString * const updateSql = @"UPDATE updates SET launch_asset_id = last_insert_rowid() WHERE id = ?1;";
      if ([self _executeSql:updateSql withArgs:@[updateId] error:error] == nil) {
        sqlite3_exec(_db, "ROLLBACK;", NULL, NULL, NULL);
        return;
      }
    }

    NSString * const updateInsertSql = @"INSERT OR REPLACE INTO updates_assets (\"update_id\", \"asset_id\") VALUES (?1, last_insert_rowid());";
    if ([self _executeSql:updateInsertSql withArgs:@[updateId] error:error] == nil) {
      sqlite3_exec(_db, "ROLLBACK;", NULL, NULL, NULL);
      return;
    }
  }

  sqlite3_exec(_db, "COMMIT;", NULL, NULL, NULL);
}

- (BOOL)addExistingAsset:(EXUpdatesAsset *)asset toUpdateWithId:(NSUUID *)updateId error:(NSError ** _Nullable)error
{
  BOOL success;

  sqlite3_exec(_db, "BEGIN;", NULL, NULL, NULL);
  
  NSString * const assetSelectSql = @"SELECT id FROM assets WHERE url = ?1 LIMIT 1;";
  NSArray<NSDictionary *>* rows = [self _executeSql:assetSelectSql withArgs:@[asset.url] error:error];
  if (!rows || ![rows count]) {
    success = NO;
  } else {
    NSNumber *assetId = rows[0][@"id"];
    NSString * const insertSql = @"INSERT OR REPLACE INTO updates_assets (\"update_id\", \"asset_id\") VALUES (?1, ?2);";
    if ([self _executeSql:insertSql withArgs:@[updateId, assetId] error:error] == nil) {
      sqlite3_exec(_db, "ROLLBACK;", NULL, NULL, NULL);
      return NO;
    }
    if (asset.isLaunchAsset) {
      NSString * const updateSql = @"UPDATE updates SET launch_asset_id = ?1 WHERE id = ?2;";
      if ([self _executeSql:updateSql withArgs:@[assetId, updateId] error:error] == nil) {
        sqlite3_exec(_db, "ROLLBACK;", NULL, NULL, NULL);
        return NO;
      }
    }
    success = YES;
  }

  sqlite3_exec(_db, "COMMIT;", NULL, NULL, NULL);
  
  return success;
}

- (void)updateAsset:(EXUpdatesAsset *)asset error:(NSError ** _Nullable)error
{
  NSAssert(asset.downloadTime, @"asset downloadTime should be nonnull");
  NSAssert(asset.filename, @"asset filename should be nonnull");
  NSAssert(asset.contentHash, @"asset contentHash should be nonnull");

  NSString * const assetUpdateSql = @"UPDATE \"assets\" SET \"headers\" = ?2, \"type\" = ?3, \"metadata\" = ?4, \"download_time\" = ?5, \"relative_path\" = ?6, \"hash\" = ?7 WHERE \"url\" = ?1;";
  [self _executeSql:assetUpdateSql
           withArgs:@[
                      [asset.url absoluteString],
                      asset.headers ?: [NSNull null],
                      asset.type,
                      asset.metadata ?: [NSNull null],
                      [NSNumber numberWithDouble:[asset.downloadTime timeIntervalSince1970]],
                      asset.filename,
                      asset.contentHash
                      ]
              error:error];
}

- (void)markUpdateReadyWithId:(NSUUID *)updateId error:(NSError ** _Nullable)error
{
  NSString * const updateSql = @"UPDATE updates SET status = ?1, keep = 1 WHERE id = ?2;";
  [self _executeSql:updateSql
           withArgs:@[
                      @(EXUpdatesUpdateStatusReady),
                      updateId
                      ]
              error:error];
}

- (void)markUpdateForDeletionWithId:(NSUUID *)updateId error:(NSError ** _Nullable)error
{
  NSString *sql = [NSString stringWithFormat:@"UPDATE updates SET keep = 0, status = %li WHERE id = ?1;", (long)EXUpdatesUpdateStatusUnused];
  [self _executeSql:sql withArgs:@[updateId] error:error];
}

- (NSArray<NSDictionary *>* _Nullable)markUnusedAssetsForDeletionWithError:(NSError ** _Nullable)error
{
  // the simplest way to mark the assets we want to delete
  // is to mark all assets for deletion, then go back and unmark
  // those assets in updates we want to keep
  // this is safe as long as we have a lock and nothing else is happening
  // in the database during the execution of this method

  sqlite3_exec(_db, "BEGIN;", NULL, NULL, NULL);

  NSString * const update1Sql = @"UPDATE assets SET marked_for_deletion = 1;";
  if ([self _executeSql:update1Sql withArgs:nil error:error] == nil) {
    sqlite3_exec(_db, "ROLLBACK;", NULL, NULL, NULL);
    return nil;
  }

  NSString * const update2Sql = @"UPDATE assets SET marked_for_deletion = 0 WHERE id IN (\
  SELECT asset_id \
  FROM updates_assets \
  INNER JOIN updates ON updates_assets.update_id = updates.id\
  WHERE updates.keep = 1\
  );";
  if ([self _executeSql:update2Sql withArgs:nil error:error] == nil) {
    sqlite3_exec(_db, "ROLLBACK;", NULL, NULL, NULL);
    return nil;
  }

  sqlite3_exec(_db, "COMMIT;", NULL, NULL, NULL);

  NSString * const selectSql = @"SELECT * FROM assets WHERE marked_for_deletion = 1;";
  return [self _executeSql:selectSql withArgs:nil error:error];
}

- (void)deleteAssetsWithIds:(NSArray<NSNumber *>*)assetIds error:(NSError ** _Nullable)error
{
  NSMutableArray<NSString *>*assetIdStrings = [NSMutableArray new];
  for (NSNumber *assetId in assetIds) {
    [assetIdStrings addObject:[assetId stringValue]];
  }

  NSString *sql = [NSString stringWithFormat:@"DELETE FROM assets WHERE id IN (%@);",
                   [assetIdStrings componentsJoinedByString:@", "]];
  [self _executeSql:sql withArgs:nil error:error];
}

- (void)deleteUnusedUpdatesWithError:(NSError ** _Nullable)error
{
  NSString * const sql = @"DELETE FROM updates_assets WHERE update_id IN (SELECT id FROM updates WHERE keep = 0);\
  DELETE FROM updates WHERE keep = 0;";
  [self _executeSql:sql withArgs:nil error:error];
}

# pragma mark - select

- (NSArray<EXUpdatesUpdate *>* _Nullable)allUpdatesWithError:(NSError ** _Nullable)error
{
  NSString * const sql = @"SELECT * FROM updates;";
  NSArray<NSDictionary *>* rows = [self _executeSql:sql withArgs:nil error:error];
  if (!rows) {
    return nil;
  }

  NSMutableArray<EXUpdatesUpdate *>*launchableUpdates = [NSMutableArray new];
  for (NSDictionary *row in rows) {
    [launchableUpdates addObject:[self _updateWithRow:row]];
  }
  return launchableUpdates;
}

- (NSArray<EXUpdatesUpdate *>* _Nullable)launchableUpdatesWithError:(NSError ** _Nullable)error
{
  NSString *sql = [NSString stringWithFormat:@"SELECT *\
  FROM updates\
  WHERE status = %li;", (long)EXUpdatesUpdateStatusReady];

  NSArray<NSDictionary *>* rows = [self _executeSql:sql withArgs:nil error:error];
  if (!rows) {
    return nil;
  }
  
  NSMutableArray<EXUpdatesUpdate *>*launchableUpdates = [NSMutableArray new];
  for (NSDictionary *row in rows) {
    [launchableUpdates addObject:[self _updateWithRow:row]];
  }
  return launchableUpdates;
}

- (EXUpdatesUpdate * _Nullable)updateWithId:(NSUUID *)updateId error:(NSError ** _Nullable)error
{
  NSString * const sql = @"SELECT *\
  FROM updates\
  WHERE updates.id = ?1;";

  NSArray<NSDictionary *>* rows = [self _executeSql:sql withArgs:@[updateId] error:error];
  if (!rows || ![rows count]) {
    return nil;
  } else {
    return [self _updateWithRow:rows[0]];
  }
}

- (EXUpdatesAsset * _Nullable)launchAssetWithUpdateId:(NSUUID *)updateId error:(NSError ** _Nullable)error
{
  NSString * const sql = @"SELECT url, type, relative_path, metadata\
  FROM updates\
  INNER JOIN assets ON updates.launch_asset_id = assets.id\
  WHERE updates.id = ?1;";

  NSArray<NSDictionary *>*rows = [self _executeSql:sql withArgs:@[updateId] error:error];
  if (!rows || ![rows count]) {
    return nil;
  } else {
    if ([rows count] > 1) {
      NSLog(@"returned multiple updates with the same ID in launchAssetUrlWithUpdateId");
    }
    NSDictionary *row = rows[0];
    NSURL *url = [NSURL URLWithString:row[@"url"]];
    EXUpdatesAsset *asset = [[EXUpdatesAsset alloc] initWithUrl:url type:row[@"type"]];
    asset.filename = row[@"relative_path"];
    asset.metadata = row[@"metadata"];
    asset.isLaunchAsset = YES;
    return asset;
  }
}

- (NSArray<EXUpdatesAsset *>* _Nullable)assetsWithUpdateId:(NSUUID *)updateId error:(NSError ** _Nullable)error
{
  NSString * const sql = @"SELECT asset_id, url, type, relative_path, assets.metadata, launch_asset_id\
  FROM assets\
  INNER JOIN updates_assets ON updates_assets.asset_id = assets.id\
  INNER JOIN updates ON updates_assets.update_id = updates.id\
  WHERE updates.id = ?1;";

  NSArray<NSDictionary *>*rows = [self _executeSql:sql withArgs:@[updateId] error:error];
  if (!rows) {
    return nil;
  }

  NSMutableArray<EXUpdatesAsset *>*assets = [NSMutableArray arrayWithCapacity:rows.count];

  for (NSDictionary *row in rows) {
    NSURL *url = [NSURL URLWithString:row[@"url"]];
    EXUpdatesAsset *asset = [[EXUpdatesAsset alloc] initWithUrl:url type:row[@"type"]];
    asset.filename = row[@"relative_path"];
    asset.metadata = row[@"metadata"];
    asset.isLaunchAsset = [(NSNumber *)row[@"launch_asset_id"] isEqualToNumber:(NSNumber *)row[@"asset_id"]];
    [assets addObject:asset];
  }

  return assets;
}

# pragma mark - helper methods

- (NSArray<NSDictionary *>* _Nullable)_executeSql:(NSString *)sql withArgs:(NSArray * _Nullable)args error:(NSError ** _Nullable)error
{
  NSAssert(_db, @"Missing database handle");
  sqlite3_stmt *stmt;
  if (sqlite3_prepare_v2(_db, [sql UTF8String], -1, &stmt, NULL) != SQLITE_OK) {
    if (error != nil) {
      *error = [self _errorFromSqlite:_db];
    }
    return nil;
  }
  if (args) {
    if (![self _bindStatement:stmt withArgs:args]) {
      if (error != nil) {
        *error = [self _errorFromSqlite:_db];
      }
      return nil;
    }
  }

  NSMutableArray *rows = [NSMutableArray arrayWithCapacity:0];
  NSMutableArray *columnNames = [NSMutableArray arrayWithCapacity:0];

  int columnCount = 0;
  BOOL didFetchColumns = NO;
  int result;
  BOOL hasMore = YES;
  BOOL didError = NO;
  while (hasMore) {
    result = sqlite3_step(stmt);
    switch (result) {
      case SQLITE_ROW: {
        if (!didFetchColumns) {
          // get all column names once at the beginning
          columnCount = sqlite3_column_count(stmt);

          for (int i = 0; i < columnCount; i++) {
            [columnNames addObject:[NSString stringWithUTF8String:sqlite3_column_name(stmt, i)]];
          }
          didFetchColumns = YES;
        }
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        for (int i = 0; i < columnCount; i++) {
          id columnValue = [self _getValueWithStatement:stmt column:i];
          entry[columnNames[i]] = columnValue;
        }
        [rows addObject:entry];
        break;
      }
      case SQLITE_DONE:
        hasMore = NO;
        break;
      default:
        didError = YES;
        hasMore = NO;
        break;
    }
  }

  if (didError && error != nil) {
    *error = [self _errorFromSqlite:_db];
  }

  sqlite3_finalize(stmt);

  return didError ? nil : rows;
}

- (id)_getValueWithStatement:(sqlite3_stmt *)stmt column:(int)column
{
  int columnType = sqlite3_column_type(stmt, column);
  switch (columnType) {
    case SQLITE_INTEGER:
      return @(sqlite3_column_int64(stmt, column));
    case SQLITE_FLOAT:
      return @(sqlite3_column_double(stmt, column));
    case SQLITE_BLOB:
      NSAssert(sqlite3_column_bytes(stmt, column) == 16, @"SQLite BLOB value should be a valid UUID");
      return [[NSUUID alloc] initWithUUIDBytes:sqlite3_column_blob(stmt, column)];
    case SQLITE_TEXT:
      return [[NSString alloc] initWithBytes:(char *)sqlite3_column_text(stmt, column)
                                      length:sqlite3_column_bytes(stmt, column)
                                    encoding:NSUTF8StringEncoding];
  }
  return [NSNull null];
}

- (BOOL)_bindStatement:(sqlite3_stmt *)stmt withArgs:(NSArray *)args
{
  __block BOOL success = YES;
  [args enumerateObjectsUsingBlock:^(id _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    if ([obj isKindOfClass:[NSUUID class]]) {
      uuid_t bytes;
      [((NSUUID *)obj) getUUIDBytes:bytes];
      if (sqlite3_bind_blob(stmt, (int)idx + 1, bytes, 16, SQLITE_TRANSIENT) != SQLITE_OK) {
        success = NO;
        *stop = YES;
      }
    } else if ([obj isKindOfClass:[NSNumber class]]) {
      if (sqlite3_bind_int64(stmt, (int)idx + 1, [((NSNumber *)obj) longLongValue]) != SQLITE_OK) {
        success = NO;
        *stop = YES;
      }
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
      NSError *error;
      NSData *jsonData = [NSJSONSerialization dataWithJSONObject:(NSDictionary *)obj options:kNilOptions error:&error];
      if (!error && sqlite3_bind_text(stmt, (int)idx + 1, jsonData.bytes, (int)jsonData.length, SQLITE_TRANSIENT) != SQLITE_OK) {
        success = NO;
        *stop = YES;
      }
    } else if ([obj isKindOfClass:[NSNull class]]) {
      if (sqlite3_bind_null(stmt, (int)idx + 1) != SQLITE_OK) {
        success = NO;
        *stop = YES;
      }
    } else {
      // convert to string
      NSString *string = [obj isKindOfClass:[NSString class]] ? (NSString *)obj : [obj description];
      NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
      if (sqlite3_bind_text(stmt, (int)idx + 1, data.bytes, (int)data.length, SQLITE_TRANSIENT) != SQLITE_OK) {
        success = NO;
        *stop = YES;
      }
    }
  }];
  return success;
}

- (NSError *)_errorFromSqlite:(struct sqlite3 *)db
{
  int code = sqlite3_errcode(db);
  int extendedCode = sqlite3_extended_errcode(db);
  NSString *message = [NSString stringWithUTF8String:sqlite3_errmsg(db)];
  return [NSError errorWithDomain:kEXUpdatesDatabaseErrorDomain
                              code:extendedCode
                          userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error code %i: %@ (extended error code %i)", code, message, extendedCode]}];
}

- (EXUpdatesUpdate *)_updateWithRow:(NSDictionary *)row
{
  NSError *error;
  id metadata = [NSJSONSerialization JSONObjectWithData:[(NSString *)row[@"metadata"] dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
  NSAssert(!error && metadata && [metadata isKindOfClass:[NSDictionary class]], @"Update metadata should be a valid JSON object");
  EXUpdatesUpdate *update = [EXUpdatesUpdate updateWithId:row[@"id"]
                                               commitTime:[NSDate dateWithTimeIntervalSince1970:[(NSNumber *)row[@"commit_time"] doubleValue] / 1000]
                                           binaryVersions:row[@"binary_versions"]
                                                 metadata:metadata
                                                   status:(EXUpdatesUpdateStatus)[(NSNumber *)row[@"status"] integerValue]
                                                     keep:[(NSNumber *)row[@"keep"] boolValue]];
  return update;
}

@end

NS_ASSUME_NONNULL_END
