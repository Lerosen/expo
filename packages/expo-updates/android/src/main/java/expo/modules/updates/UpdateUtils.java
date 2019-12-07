package expo.modules.updates;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.util.Log;

import java.security.MessageDigest;

public class UpdateUtils {

  private static String TAG = UpdateUtils.class.getSimpleName();

  public static String getBinaryVersion(Context context) {
    String versionName = null;
    try {
      PackageInfo pInfo = context.getPackageManager().getPackageInfo(context.getPackageName(), 0);
      versionName = pInfo.versionName;
    } catch (PackageManager.NameNotFoundException e) {
      Log.e(TAG, "Could not determine binary version", e);
    }
    return versionName;
  }

  public static String sha1(String string) {
    try {
      MessageDigest md = MessageDigest.getInstance("SHA-1");
      byte[] data = string.getBytes("UTF-8");
      md.update(data, 0, data.length);
      byte[] sha1hash = md.digest();
      return bytesToHex(sha1hash);
    } catch (Exception e) {
      Log.e(TAG, "Could not encode via SHA-1", e);
    }
    // fall back to returning a uri-encoded string if we can't do SHA-1 for some reason
    return Uri.encode(string);
  }

  // https://stackoverflow.com/questions/9655181/how-to-convert-a-byte-array-to-a-hex-string-in-java
  private static final char[] HEX_ARRAY = "0123456789ABCDEF".toCharArray();
  public static String bytesToHex(byte[] bytes) {
    char[] hexChars = new char[bytes.length * 2];
    for (int j = 0; j < bytes.length; j++) {
      int v = bytes[j] & 0xFF;
      hexChars[j * 2] = HEX_ARRAY[v >>> 4];
      hexChars[j * 2 + 1] = HEX_ARRAY[v & 0x0F];
    }
    return new String(hexChars);
  }
}
