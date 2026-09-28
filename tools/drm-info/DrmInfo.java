// Print Widevine properties (security level, system id, HDCP) from adb.
// Usage: CLASSPATH=/data/local/tmp/drminfo.dex app_process / DrmInfo
import android.media.MediaDrm;
import java.util.UUID;

public class DrmInfo {
    public static void main(String[] args) throws Exception {
        // MediaDrm needs a package name: borrow the system one (root only).
        android.os.Looper.prepareMainLooper();
        Class.forName("android.app.ActivityThread").getMethod("systemMain").invoke(null);
        UUID widevine = new UUID(0xEDEF8BA979D64ACEL, 0xA3C827DCD51D21EDL);
        System.out.println("widevine supported: " + MediaDrm.isCryptoSchemeSupported(widevine));
        MediaDrm drm = new MediaDrm(widevine);
        for (String p : new String[] {"vendor", "version", "securityLevel", "systemId",
                "hdcpLevel", "maxHdcpLevel", "oemCryptoApiVersion", "provisioningUniqueId"}) {
            try {
                String v = p.equals("provisioningUniqueId") ? "(bytes)" : drm.getPropertyString(p);
                System.out.println(p + ": " + v);
            } catch (Exception e) {
                System.out.println(p + ": <" + e.getClass().getSimpleName() + ">");
            }
        }
        System.out.println("maxSecurityLevel: " + MediaDrm.getMaxSecurityLevel());
        drm.close();
    }
}
