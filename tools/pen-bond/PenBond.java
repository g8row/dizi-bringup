// Bond a BLE device by address from adb (app_process as the shell user), for
// pens that advertise without the discoverable flag and so never show up in
// Settings. Needs `adb unroot`: the shell uid holds BLUETOOTH_CONNECT/PRIVILEGED.
// Usage: CLASSPATH=/data/local/tmp/penbond.dex app_process / PenBond <addr> [random|public] [unpair]
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.AttributionSource;
import android.os.Looper;
import android.os.Process;
import java.lang.reflect.Method;

public class PenBond {
    public static void main(String[] args) throws Exception {
        Looper.prepareMainLooper();
        // Sets up BluetoothServiceManager, as ActivityThread does for apps.
        Class.forName("android.app.ActivityThread").getMethod("initializeMainlineModules").invoke(null);
        AttributionSource src = new AttributionSource.Builder(Process.myUid())
                .setPackageName("com.android.shell").build();
        Method create = BluetoothAdapter.class.getMethod("createAdapter", android.content.Context.class);
        BluetoothAdapter adapter = (BluetoothAdapter) create.invoke(null, (Object) null);
        // Without a Context it attributes calls to (uid, null package); use the shell package.
        java.lang.reflect.Field f = BluetoothAdapter.class.getDeclaredField("mAttributionSource");
        f.setAccessible(true);
        f.set(adapter, src);

        String addr = args[0].toUpperCase();
        int type = args.length > 1 && args[1].equals("public")
                ? BluetoothDevice.ADDRESS_TYPE_PUBLIC : BluetoothDevice.ADDRESS_TYPE_RANDOM;
        BluetoothDevice dev = adapter.getRemoteLeDevice(addr, type);
        System.out.println("uid " + Process.myUid() + ", bond state before: " + dev.getBondState());
        if (args.length > 2 && args[2].equals("unpair")) {
            System.out.println("removeBond: " + dev.removeBond());
            return;
        }
        System.out.println("createBond: " + dev.createBond());
        for (int i = 0; i < 40 && dev.getBondState() != BluetoothDevice.BOND_BONDED; i++) {
            Thread.sleep(1000);
            System.out.println("bond state: " + dev.getBondState());
        }
    }
}
