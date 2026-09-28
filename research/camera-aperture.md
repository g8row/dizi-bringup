# Aperture (CameraX) crash: `zoomRatioRange ... Framework throw an AssertionError`

Status: root cause found from the stock HyperOS dumpsys already captured on 2026-09-26. Fix is one prop. Researched 2026-09-27; nothing under evox/ was modified.

## TL;DR

- The stock camx HAL publishes **camera id 2** (a hidden back LOGICAL_MULTI_CAMERA) with
  `android.control.zoomRatioRange = [3.4028235e38 (FLT_MAX), 0.0]`, meaning min > max.
  Source: `/build/alex/dizi/recon/dumpsys/media.camera.txt` line 3189 (device 2 block starts at line 3141).
  Cameras 0, 1 and 3 report `[1.0 5.0]` (lines 90, 1652, 4656). The "[1.0 5.0] for them" reading covered only those cameras.
- When the framework reads this key it builds `new Range<Float>(FLT_MAX, 0.0)`. That constructor throws
  `IllegalArgumentException`, which `MarshalQueryableRange` wraps in an **AssertionError**. `getBase()` only catches
  `Exception`, so the Error goes up to CameraX. CameraX catches it and reports "Framework throw an AssertionError".
- Stock HyperOS never shows ids 2 and 3 to normal apps. Its framework caps the id list at 2 unless the caller is in
  `vendor.camera.aux.packagelist` or `vendor.camera.aux.packagelistext`. Stock `/system/build.prop` sets both lists
  (factory/test apps only).
- The LineageOS/EvoX framework reads the same prop, but **when the prop is unset every app gets all cameras**
  (`SystemProperties.get("vendor.camera.aux.packagelist", packageName)`, so the default is the caller's own package).
  The dizi tree does not set the prop, so Aperture/CameraX enumerates ids 2 and 3 and trips over camera 2.
- Fix: set `vendor.camera.aux.packagelist`, and **do not include `org.lineageos.aperture`** in it.

## 1. Framework path that throws the AssertionError

All paths below are under `/build/alex/dizi/evox/frameworks/base/core/java/android/`.

1. `hardware/camera2/CameraCharacteristics.java:305` calls `get()`, then `mProperties.get(key)`.
2. `hardware/camera2/impl/CameraMetadataNative.java:484` `get()`: there is no GetCommand override for `CONTROL_ZOOM_RATIO_RANGE`, so it calls `getBase()` (l.616-642).
3. `getBase()` calls `getMarshalerForKey()` (l.2525), which returns `MarshalQueryableRange` for `Range<Float>` with a float native type. It then calls `unmarshal`.
4. `hardware/camera2/marshal/impl/MarshalQueryableRange.java:82-96`: `mConstructor.newInstance(lower, upper)` fails with
   `InvocationTargetException` (cause: `IllegalArgumentException`), and the code rethrows that as `throw new AssertionError(e)`.
5. `util/Range.java:61`: `if (lower.compareTo(upper) > 0) throw new IllegalArgumentException("lower must be less than or equal to upper")`.
6. `getBase()` has only `catch (Exception e) { return null; }`. `AssertionError` is an `Error`, so it escapes.

This is not a vendor-tag or type mismatch. The tag is the standard `0x1002e`, type float[2], which is correct. The problem is the HAL's value. Other framework AssertionError sites (vendor-tag `MarshalQueryableEnum`, `getMaxRegions`, `logicalCam.physicalIds` UTF-8, and so on) don't apply to this key.

HAL detail for camera 2 (stock dump, lines 3141-4606):
- `availableCapabilities` includes `LOGICAL_MULTI_CAMERA`. `org.codeaurora.qcamera3.logicalCameraType = 7`. `lens.facing = BACK`. Resource cost 0.
- `logicalMultiCamera.physicalIds` byte[4] (dumpsys renders it as `[0 3]`). `availableMaxDigitalZoom = 5.0`, yet `zoomRatioRange = [FLT_MAX, 0]`.
  This looks like the CHI override's logical-camera caps builder (`ExtensionModule::FillLogicalCameraCaps` in
  `com.qti.chi.override.so`) leaving its min/max accumulators at their initial values.
- Camera 3 (FRONT, `logicalCameraType = 7`) has a valid range. It is just an aux duplicate.
- The service also reports "Number of normal (API1) camera devices: 2", mapping 0 to "0" and 1 to "1". The hardware has 2 real sensors (`persist.vendor.camera.mi.module.info = wide=aac_gc08a3_i;front=aac_ov08d10_i;`).

Chrome works because its camera2 enumeration tolerates failures on a single camera. CameraX `CameraRepository` initialisation instead fails as soon as one id throws.

## 2. How stock gates ids 2 and 3

- Stock `/build/alex/dizi/stock/dump/system/build.prop:177-205`:
  ```
  persist.vendor.camera.privapp.list=org.codeaurora.snapcam
  vendor.camera.aux.packagelist=com.xiaomi.runin,com.xiaomi.cameratest,com.xiaomi.factory.mmi,org.codeaurora.snapcam
  vendor.camera.aux.packagelistext=com.xiaomi.factory.CameraTestItem,com.firefightcam1,com.phonetest.hwttss
  ```
  These props don't show up in `recon/getprop.txt` because the capture could not read that context (it is listed in
  `stock/dump/system_ext/etc/selinux/system_ext_property_contexts:499-500`).
- Stock framework.jar (dexdump of `stock/dump/system/system/framework/framework.jar` classes2.dex):
  `CameraExtImplBase.isAuxCameraClient(pkg)` returns true only if pkg is in `vendor.camera.aux.packagelist` or
  `...packagelistext`. **An empty or unset list means false.** It is called from `Camera.getNumberOfCameras` (which returns 2 when false),
  `CameraManagerGlobal.extractCameraIdListLocked`, `onTorchStatusChangedLocked` and `setTorchMode`.
- EvoX framework: `frameworks/base/core/java/android/hardware/Camera.java:292-306` `shouldExposeAuxCamera()` reads the
  same props, but **the default is the caller's own package, so everyone gets aux cameras when the prop is unset**. It is used in
  `camera2/CameraManager.java:2503` (id list truncated to 2), `:2845` (`getCameraCharacteristics` throws "invalid cameraId" for id >= 2), `:3107` and `:3276`.
- SELinux: `device/lineage/sepolicy/common/private/property_contexts:6-7` labels the props `vendor_persist_camera_prop`.
  `appdomain.te` has `get_prop(appdomain, vendor_persist_camera_prop)`. `public/property.te` declares it `system_vendor_config_prop`, so vendor_init can set it and every app can read it.
- ArrayMap ordering: `DeviceCameraInfo.hashCode()` is `Objects.hash(id, deviceId)`, which increases for "0" through "3". The first 2 entries are therefore "0" and "1", which is correct.

## 3. Other trees

| Tree | What it does |
|---|---|
| `trees/ref/evox_garnet`, `lineage_garnet`, `lineage_pipa`, `noble6_*`, `m0rf30_dizi`, `ksn2_ruan` | Don't set any aux or privapp prop (only `ro.camera.enableCamera1MaxZsl=1`). garnet's own HAL presumably has no broken logical id. |
| `trees/ref/efeisot_dizi/system.prop:78,160-161` | Copies the stock lists (`persist.vendor.camera.privapp.list=org.codeaurora.snapcam`, `vendor.camera.aux.packagelist=org.codeaurora.snapcam,com.xiaomi.runin,...`, `...packagelistext=com.xiaomi.factory.CameraTestItem`). This is the same dizi HAL, so it hides ids 2 and 3 exactly as stock does. |
| LineageOS sm8550-common `vendor.prop` | `vendor.camera.aux.packagelist=com.android.camera,org.lineageos.aperture,org.lineageos.aperture.dev` |
| LineageOS sm8250-common `system.prop` | `vendor.camera.aux.packagelist=org.codeaurora.snapcam,com.android.camera,org.lineageos.aperture,org.lineageos.aperture.dev` |
| LineageOS sm8450-common / marble | No aux list. |

Those Lineage trees add Aperture because their aux ids are real lenses. **On dizi, adding Aperture would bring the crash back.** No reference tree uses an extract-files fixup on camx or chi for this. `ro.camerax.extensions.enabled` is unrelated. The Aperture overlay flags (`config_enableAuxCameras`, `config_ignoredAuxCameraIds`, `config_ignoreLogicalAuxCameras` in `packages/apps/Aperture/app/src/main/res/values/config.xml`) only take effect after CameraX has initialised, so they can't prevent this crash.

Links:
- https://github.com/LineageOS/android_device_xiaomi_sm8550-common/blob/lineage-22.2/vendor.prop
- https://github.com/LineageOS/android_device_xiaomi_sm8250-common/blob/lineage-22.2/system.prop
- https://github.com/LineageOS/android_device_xiaomi_msm8998-common/commit/1cf246f8b2852b0c6319a6ebb21c9e1937e06b80
- https://github.com/LineageOS/issues/issues/568 (aux exposure in Aperture)

## 4. Fixes (ranked)

1. **Prop (recommended; matches stock).** Add to `device/xiaomi/dizi/props/vendor.prop` under "# Camera":
   ```
   persist.vendor.camera.privapp.list=org.codeaurora.snapcam
   vendor.camera.aux.packagelist=com.xiaomi.runin,com.xiaomi.cameratest,com.xiaomi.factory.mmi,org.codeaurora.snapcam
   vendor.camera.aux.packagelistext=com.xiaomi.factory.CameraTestItem
   ```
   `packagelistext` is only read by the stock framework and does nothing on EvoX. The list must be non-empty and must exclude Aperture, Chrome and so on. Any apps not listed then see only ids 0 and 1. `props/system.prop` also works, as efeisot shows.
2. **Narrow alternative:** `vendor.camera.aux.packageexcludelist=org.lineageos.aperture` hides ids 2 and 3 from Aperture only. Every other CameraX app (Meet, WhatsApp, and others) would still crash, so option 1 is better.
3. **Framework hardening (ROM patch, not the device tree), defence in depth.** In `CameraMetadataNative.getBase()`, change
   `catch (Exception e)` to `catch (Exception | AssertionError e)`. Alternatively, in `MarshalQueryableRange.unmarshal` catch
   `InvocationTargetException` whose cause is `IllegalArgumentException` and return null. Camera 2 would then report a null zoomRatioRange instead of throwing. Aux apps could still misbehave on it, so this only complements fix 1.
4. **HAL patch (not recommended).** Hex-patching the logical-camera zoom range in `com.qti.chi.override.so` via an extract-files fixup would be fragile and hard to verify. There is no known camxoverridesettings knob for this.

## 5. Verification over adb

- Confirm the cause: `adb shell dumpsys media.camera | grep -A1 'zoomRatioRange (1002e)'`. The third entry (device 2) should read `[340282346638528859811704183484516925440.0 0.0]`.
- Test live before rebuilding (the prop is read on every call, so no reboot is needed):
  ```
  adb root
  adb shell setprop vendor.camera.aux.packagelist com.xiaomi.runin,com.xiaomi.cameratest,com.xiaomi.factory.mmi,org.codeaurora.snapcam
  adb shell am force-stop org.lineageos.aperture
  adb logcat -c; adb shell monkey -p org.lineageos.aperture 1
  adb logcat -d | grep -iE 'InitializationException|zoomRatioRange|AssertionError|CameraX'
  ```
  Expect no InitializationException, and the preview plus the front/back switch working. `adb shell setprop vendor.camera.aux.packagelist ''` does not restore the "expose all" behaviour, because an empty string is not the default; reboot to reset instead.
- After the build: `adb shell getprop vendor.camera.aux.packagelist` should return the list. Then re-check Aperture photo and video on both cameras, Chrome/WebRTC, and the QR scanner (Aperture's QrScannerActivity).
- Optional: after `adb shell pm grant org.lineageos.aperture android.permission.CAMERA`, `adb shell dumpsys media.camera` shows only ids 0 and 1 ever opened by Aperture.
