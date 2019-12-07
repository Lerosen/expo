package expo.modules.updates.db;

import android.content.Context;
import android.util.Log;

import expo.modules.updates.db.dao.AssetDao;
import expo.modules.updates.db.dao.UpdateDao;
import expo.modules.updates.db.entity.AssetEntity;
import expo.modules.updates.db.entity.UpdateAssetEntity;
import expo.modules.updates.db.entity.UpdateEntity;

import androidx.annotation.NonNull;
import androidx.room.Database;
import androidx.room.Room;
import androidx.room.RoomDatabase;
import androidx.room.TypeConverters;
import androidx.sqlite.db.SupportSQLiteDatabase;

@Database(entities = {UpdateEntity.class, UpdateAssetEntity.class, AssetEntity.class}, version = 1)
@TypeConverters({Converters.class})
public abstract class UpdatesDatabase extends RoomDatabase {

  private static UpdatesDatabase sInstance;

  private static final String DB_NAME = "updates.db";
  private static final String TAG = UpdatesDatabase.class.getSimpleName();

  public abstract UpdateDao updateDao();
  public abstract AssetDao assetDao();

  public static synchronized UpdatesDatabase getInstance(Context context) {
    if (sInstance == null) {
      sInstance = Room.databaseBuilder(context, UpdatesDatabase.class, DB_NAME)
              .fallbackToDestructiveMigration()
              .allowMainThreadQueries() // TODO: decide if this is necessary
              .addCallback(new RoomDatabase.Callback() {
                @Override
                public void onCreate(@NonNull SupportSQLiteDatabase db) {
                  super.onCreate(db);
                  Log.i(TAG, db.getPath());
                }
              })
              .build();
    }
    return sInstance;
  }
}
