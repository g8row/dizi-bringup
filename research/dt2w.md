# Double-tap-to-wake (DT2W) on dizi: research

Status: offline research, 2026-09-28. I had no tablet, so nothing here was tested on hardware.
Tags: **[verified-bin]** = checked against the stock `.ko`/`.so` we ship, **[verified-log]** = seen in a
captured stock dmesg/dumpsys, **[source]** = MiCode source only (the stock module matches it closely,
see 2.0), **[unverified]** = inference, needs checking on the device.

## TL;DR

* Finger DT2W is enabled **only** by writing the input event `EV_SYN / SYN_CONFIG / value 5`
  (`WAKEUP_ON`) to the touchscreen's evdev node (`NVTCapacitiveTouchScreen`, event6 on stock and on
  build-13). Value `4` (`WAKEUP_OFF`) disables it. HyperOS does exactly this at boot [verified-log].
* **Neither of the other two routes works with the stock modules:**
  * `/proc/tp_gesture` is not created (`LCT_TP_GESTURE_EN 0`).
  * xiaomi-touch mode 14 (`Touch_Doubletap_Mode`) is stored but nothing acts on it.
  * The garnet `power-mode.cpp` and the `gesture_double_tap_*` sysfs nodes that garnet used do not
    exist on dizi either.
* The driver reports `KEY_WAKEUP` (143) on `NVTCapacitiveTouchScreen`. `Generic.kl` maps it to
  `KEYCODE_WAKEUP`, which `PhoneWindowManager` already treats as a wake key. No keylayout work is needed.
* Recommended implementation:
  1. A power HAL mode extension (`libperfmgr-ext-dizi`) that writes the SYN_CONFIG event on
     `Mode::DOUBLE_TAP_TO_WAKE`.
  2. Set `config_supportDoubleTapWake=true`.
  3. Two `input_device` sepolicy allow rules.
  4. Optionally, a small frameworks/base patch that ignores `KEYCODE_WAKEUP` while the hall cover is
     closed.
* The power cost is real: with gesture mode on, the display driver **keeps the panel rails and bias
  on** during screen-off (`[TP gesture], lcd_reset_keep_high` in the stock log), and the touch IC keeps
  scanning. This has to be measured against our ~6 mA idle. There is also a source-level
  regulator-refcount leak (4.2) that can keep the panel rails on after DT2W is turned off again.

---

## 1. How stock HyperOS does it

### 1.1 Evidence that stock uses the SYN_CONFIG input-event route

* Stock boot dmesg, `/build/alex/dizi/recon/dmesg-boot.txt:8683-8686` [verified-log]. About 17 s into
  boot, while system_server is starting, something writes the event and the driver switches gesture
  mode on:
  ```
  [17.252553] [NVT-ts] nvt_gesture_switch 182: Enter. type = 0, code = 1, value = 5
  [17.252565] [NVT-ts] set_lcd_reset_gpio_keep_high 4362: gesture_pen and gesture_mode All True
  [17.252568] [NVT-ts] lct_nvt_tp_gesture_callback 4392: enable gesture mode
  ```
  `type 0 / code 1` is `EV_SYN / SYN_CONFIG`, and `value 5` is `WAKEUP_ON`.
* Stock `dumpsys input`, `/build/alex/dizi/recon/dumpsys/input.txt:14` [verified-log]:
  * `InputCommonConfig ... mTouchWakeupMode: 5`. This is MIUI's native input config, and the value
    matches `WAKEUP_ON`.
  * Line 110-111: `TouchWakeUpFeatureManager HasDoubleTapWakeUpSupport = false`. My reading is that
    HyperOS's alternative route (touchfeature mode 14) is reported as unsupported on this device, so it
    falls back to the input-event route [unverified interpretation].
* The code doing the write is MIUI's `libmiinputflinger`
  (`/build/alex/dizi/stock/dump/system_ext/lib64/libmiinputflinger.so`). Its strings include
  `&touchWakeUpMode`, `    mTouchWakeupMode: %d`, `MiInputManager::setInputConfig`, `power/wakeup`
  and `Failed to set power/wakeup node at %s` [verified-bin, strings only]. I did not disassemble the
  exact write, so the mechanism is inferred from the matching value and timing.
* On screen-off, the stock suspend path takes the gesture branch (`recon/dmesg-boot.txt:10726-10742`,
  10774) [verified-log]:
  ```
  [96.285533] nvt_ts_suspend 4206: Gesture pen on, Disable pen shorthand gesture, Disable pen gesture
  [96.309672] nvt_ts_suspend 4213: Enabled touch wakeup gesture
  [96.450275] dsi_panel_post_unprepare: [TP gesture], lcd_reset_keep_high      <- panel power stays on
  ```

### 1.2 The stock touchfeature HAL is only an ioctl pass-through

* `/build/alex/dizi/stock/dump/vendor/etc/init/vendor.xiaomi.hw.touchfeature@1.0-service.rc` does the
  following:
  * chowns `/dev/xiaomi-touch` and `/dev/mipp_pen0`;
  * starts `touchfeature-hal-1-0` as user `system`.
* `vendor/lib64/hw/vendor.xiaomi.hw.touchfeature@1.0-impl.so` exports only `setModeValue`,
  `getModeValue`, `setModeLongValue`, `modeReset` and similar, and uses `ioctl` on
  `/dev/xiaomi-touch`. It has no gesture or DT2W logic [verified-bin, strings].
* The stock vendor has no `/proc/tp_gesture` handling and no settings key or init trigger for DT2W
  (grep over `stock/dump/vendor` and `odm`). The setting lives in the MIUI framework and native
  inputflinger, which we don't ship.

## 2. Kernel interface available with our (stock) modules

### 2.0 Source vs binary

* Stock modules: `/build/alex/dizi/evox/device/xiaomi/dizi-kernel/modules/{vendor_dlkm,vendor_ramdisk}/`
  * `nt36532_spi.ko` md5 f345398f…
  * `lct_tp.ko` md5 fca8770a…
  * `xiaomi_touch.ko` md5 3cdf4e9e…
  * `msm_drm.ko` md5 745a6fbd…, identical to `stock/dump/vendor_dlkm/lib/modules/msm_drm.ko`.
* Source: `/build/alex/dizi/kernel/micode-ruan/drivers/input/touchscreen/{nt36532_spi,lct_tp,xiaomi}/`.
* The binary matches this source closely:
  * The log line numbers in the stock module (`nvt_gesture_switch 182`) equal the source line numbers.
  * Other line numbers are only about 20 lines off.
  * All gesture strings and symbols are present.
  * The stock `xiaomi_touch.ko` has extra `xiaomi_touch_mievent_*` exports that are not in this
    source, but the ioctl layout is the same.

### 2.1 Enable path: `nvt_gesture_switch` (the only working one)

* `nt36xxx.c:180-193` [source], confirmed by disassembly [verified-bin]:
  * The stock `nvt_gesture_switch` at `.text+0x4fc` checks `w1==0`, `w2==1`, then `w3==5` (enable) or
    `w3==4` (disable).
  * It is installed as `ts->input_dev->event = nvt_gesture_switch` (`nt36xxx.c:3558`).
  * `WAKEUP_OFF 0x04` and `WAKEUP_ON 0x05` are defined in `lct_tp/lct_tp_gesture.h:4-5`.
* Kernel delivery: `evdev_write` → `input_inject_event` → `SYN_CONFIG` is `INPUT_PASS_TO_ALL`, so
  `dev->event()` is called. It runs under `dev->event_lock` (a spinlock). The callback only sets flags
  and calls printk, so that is fine.
* Userspace write: one `struct input_event {timeval; u16 type=0 (EV_SYN); u16 code=1 (SYN_CONFIG);
  s32 value=5|4}` (24 bytes on arm64) to `/dev/input/eventN`, where `EVIOCGNAME ==
  "NVTCapacitiveTouchScreen"`.
  * The node is event6 in both `recon/input-devices.txt` and
    `logs/build-13/boot-2/input-devices.txt`.
  * Don't hard-code it; look it up by name.
* Quick manual test as root: `sendevent /dev/input/event6 0 1 5`.
* `lct_nvt_tp_gesture_callback(flag)` (`nt36xxx.c:4372-4389`) [source]:
  * **If the touch is awake**, it sets `ts->is_gesture_mode = flag` and calls
    `set_lcd_reset_gpio_keep_high(flag)`.
  * **If the touch is suspended** (`!bTouchIsAwake`), it only sets `ts->delay_gesture = true` and
    throws `flag` away. On resume, `nt36xxx.c:4311-4315` runs
    `lct_nvt_tp_gesture_callback(!ts->is_gesture_mode)`, which **toggles** the state instead of
    applying the requested value.
  * Result: a write made while the screen is off can leave the wrong state, for example two writes
    while off still produce one toggle.
  * **Rule for userspace: only write while the screen is on, and re-assert the desired value after
    each wake.**

### 2.2 Routes that don't work with the stock modules

* **`/proc/tp_gesture`: not present.**
  * `lct_tp/lct_tp_common.h:38` sets `LCT_TP_GESTURE_EN 0`, so `lct_tp_create_procfs()` never calls
    `init_lct_tp_gesture()` (`lct_tp_common.c:101-109`).
  * The NVT `lct_tp_nvt_mifunc` has no `tp_gesture_cb` (`nt36xxx.c:3203-3221`).
  * Stock `lct_tp.ko` has the `init_lct_tp_work/selftest/grip_area Succeeded!` strings but **no**
    `init_lct_tp_gesture Succeeded!` [verified-bin].
  * Even if it existed, it is created 0444.
* **xiaomi-touch mode 14 `Touch_Doubletap_Mode` (`xiaomi/xiaomi_touch.h:58`): a no-op.**
  * `nvt_set_cur_value()` (`nt36xxx.c:2814-3044`) has no case for 14. It falls through to `default:`
    and only the stored value changes.
  * Stock disassembly of `nvt_set_cur_value` (`.text+0x6444`) compares with 0x1e, 0x18 (24), 0x1d
    (29), 0x14 (20), 0x16 (22) and a ≤8 switch. **No 0xe** [verified-bin].
  * So garnet's `power/power-mode.cpp` (trees/staging git `f904545`, ioctl `{0,14,1}`) would do
    nothing here. It also used a 3-int buffer, but the driver copies 256 ints
    (`recon/pen/FINDINGS.md`).
* **Mode 24 `Touch_Pen_Shorthand`: affects only the pen.** It sets `gesture_pen |= 0x02`
  (`nt36xxx.c:2840-2842`, via `nvt_set_gesture_mode`, 2719-2734). That makes suspend take the gesture
  branch, but a finger double-click is only reported when `is_gesture_mode` is set
  (`nt36xxx.c:1457-1464`). Mode 24 enables the "pen one click" fake pen tap (1514-1547), not DT2W.
* **The `gesture_double_tap_enabled/_state` and `gesture_single_tap_enabled` sysfs nodes** (used by
  the Lineage xiaomi multihal double-tap sensor) are not in the stock `xiaomi_touch.ko`. It only has
  `touch_dev/palm_sensor` and `pen_connect_strategy` [verified-bin strings;
  `recon/touch-sysfs.txt`].
  * The chown lines in `trees/staging/rootdir/etc/init.target.rc:117-125` are dead garnet leftovers.
  * The sensor route (`config_dozeDoubleTapSensorType`) is not possible.

### 2.3 What happens on suspend with gesture mode on

`nvt_ts_suspend`, `nt36xxx.c:4148-4252` [source; the stock log in 1.1 matches]:
1. The IRQ stays enabled and the SPI GENI master is **not** `pm_runtime_put`
   (`if (!is_gesture_mode && !gesture_pen)` guard, 4160-4169).
2. The driver writes `0x7B, gesture_pen&0x02`. This turns pen reporting off in the IC unless pen
   shorthand is on.
3. It writes host command `0x13` ("wakeup gesture mode") instead of `0x11` (deep sleep).
4. It calls `enable_irq_wake(ts->client->irq)`.
   * There is **no matching `disable_irq_wake`** anywhere. Stock has only one `irq_set_irq_wake`
     call [verified-bin], so the wake depth grows on every gesture suspend.
   * This is harmless in practice, because with gesture off the IC is in deep sleep and the IRQ is
     disabled.
5. `device_init_wakeup(dev,1)` at probe (3642-3644).
6. On a gesture IRQ while asleep:
   * `pm_wakeup_event(dev, 5000)` (1927-1931) holds a 5 s wakeup source.
   * The IRQ thread waits for the bus resume (`NVT_PM_WAIT_BUS_RESUME_COMPLETE`, 1934-1942,
     `nvt_ts_pm_suspend/resume` 4581-4599).
   * `nvt_ts_wakeup_gesture_report()` sends `KEY_WAKEUP` down+up on `NVTCapacitiveTouchScreen`
     (1428-1512).
7. At system suspend, the GENI SPI driver force-suspends the still-active master if its queue is idle
   (`micode-ruan/drivers/spi/spi-msm-geni.c:2610-2636`, "Force suspend"). The runtime-active SPI
   should therefore not block deep sleep [source; confirm with `suspend_stats`].
8. Display side: `set_lcd_reset_gpio_keep_high(true)` makes `dsi_panel_power_off()` return early, so
   **the panel regulators, OCP2131 bias, reset and enable GPIOs all stay on** while the screen is off
   (`micode-extra/vendor_opensource_display-drivers/msm/dsi/dsi_panel.c:448-499`; stock log
   `[TP gesture], lcd_reset_keep_high`). NT36532 is a TDDI touch/display driver IC, so it needs the
   panel rails to keep scanning [unverified: that it is TDDI, inferred from this coupling].

### 2.4 The event that reaches Android

* The input device `NVTCapacitiveTouchScreen` (phys `input/ts`) has key bitmap `KEY=400 0 0 8000 0 0`,
  which is BTN_TOUCH(330) + **KEY_WAKEUP(143)** (`recon/input-devices.txt`). Stock EventHub classes it
  as `KEYBOARD | TOUCH | TOUCH_MT` (`recon/dumpsys/input.txt:224-226`).
* The keylayout is `Generic.kl` (`recon/dumpsys/input.txt:233`), which has `key 143 WAKEUP`
  (`evox/frameworks/base/data/keyboards/Generic.kl:165`).
* No `.kl` or `.idc` is needed.
* `PhoneWindowManager` wakes the device (`evox/frameworks/base/.../policy/PhoneWindowManager.java`):
  * line 5598-5613: the `KEYCODE_WAKEUP` case sets `isWakeKey`, unless Lineage double-tap-to-doze is
    on;
  * line 5790-5793: it then calls `wakeUpFromWakeKey(event, withProximityCheck=true)`.
  * `config_proximityCheckOnWake` defaults to false (`lineage-sdk/.../values/config.xml:10`).
* EvoX's InputReader logs `Disabling NVTCapacitiveTouchScreen ... viewport is not active` on
  screen-off (`logs/build-38/exercise-074604/logcat.txt:3821`). That comes from
  `TouchInputMapper.cpp:902` and disables only the touch mapper, not the device or its
  KeyboardInputMapper. So KEY_WAKEUP should still be delivered [source; test it].
* The pen device `NVTCapacitivePen` also declares `KEY_POWER` (`nt36xxx.c:3609-3611`), but the driver
  never reports it (the pen gesture reports a fake pen tap instead).

## 3. Recommended implementation for our tree

### 3.1 Ranked options

1. **(Recommended) Power HAL mode extension.**
   * AOSP `PowerManagerService` already turns `Settings.Secure.DOUBLE_TAP_TO_WAKE` into
     `setMode(Mode::DOUBLE_TAP_TO_WAKE, on)`:
     * `PowerManagerService.java:1746-1753` when the setting changes;
     * `:1386` sets false at boot.
     * Both happen only if `config_supportDoubleTapWake` is true.
   * Our power HAL, `android.hardware.power-service.lineage-libperfmgr`, runs as root/group system
     (`hardware/lineage/interfaces/power-libperfmgr/aidl/*.rc`). It calls
     `setDeviceSpecificMode()`/`isDeviceSpecificModeSupported()` from a static lib chosen with soong
     config `power_libperfmgr.mode_extension_lib` (`hardware/lineage/interfaces/power-libperfmgr/Android.bp:49-52`;
     the stub is `aidl/PowerModeExtension.cpp`).
   * This is the standard Lineage pattern, and garnet used it too (`f904545`, via the older
     `TARGET_POWERHAL_MODE_EXT`).
   * No new service and no new settings UI: AOSP Settings shows "Tap to wake" (`tap_to_wake`,
     `packages/apps/Settings/.../display/TapToWakePreferenceController.java`) when the config is true.
2. **Property-driven helper, like `xiaomi-pen`.**
   * DiziParts (or a SystemUI tile) observes the setting and sets `vendor.touch.dt2w`. An init
     `on property:` trigger runs a small vendor binary that writes the event (same pattern as
     `trees/staging/rootdir/etc/init.dizi.rc:61-68` and `pen/xiaomi-pen.cpp`).
   * It works without touching the power HAL, but duplicates what PMS already does and needs more
     plumbing. Use it only if the power HAL route is blocked.
3. **Kernel-side** (rebuild `nt36532_spi` with mode-14 support or `LCT_TP_GESTURE_EN 1`): **not
   allowed**, because we must keep the stock touch modules for the pen.
4. **Not possible:** xiaomi-touch mode 14 (no-op), `/proc/tp_gesture` (absent), and the Lineage
   double-tap sensor (no sysfs nodes). See 2.2.

### 3.2 File-by-file plan (option 1)

1. **`trees/staging/power/power-mode.cpp`** (new). Note that it must use the **pixel** namespace from
   `PowerModeExtension.cpp`, not garnet's old `aidl::android::hardware::power::impl`.
   ```cpp
   #include <aidl/android/hardware/power/BnPower.h>
   #include <android-base/logging.h>
   #include <android-base/unique_fd.h>
   #include <dirent.h>
   #include <fcntl.h>
   #include <linux/input.h>
   #include <cstring>
   #include <memory>
   #include <string>

   namespace aidl::google::hardware::power::impl::pixel {
   using ::aidl::android::hardware::power::Mode;
   namespace {
   constexpr char kTouchName[] = "NVTCapacitiveTouchScreen";
   constexpr int kWakeupOff = 0x04;  // lct_tp_gesture.h WAKEUP_OFF
   constexpr int kWakeupOn = 0x05;   // lct_tp_gesture.h WAKEUP_ON

   android::base::unique_fd openTouch() {
       std::unique_ptr<DIR, decltype(&closedir)> dir(opendir("/dev/input"), closedir);
       if (!dir) return {};
       while (dirent* de = readdir(dir.get())) {
           if (strncmp(de->d_name, "event", 5)) continue;
           android::base::unique_fd fd(
                   open((std::string("/dev/input/") + de->d_name).c_str(), O_RDWR | O_CLOEXEC));
           char name[64] = {};
           if (fd >= 0 && ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) > 0 &&
               !strcmp(name, kTouchName))
               return fd;
       }
       return {};
   }

   bool setTouchGesture(bool on) {
       auto fd = openTouch();
       if (fd < 0) { PLOG(ERROR) << "dt2w: no " << kTouchName; return false; }
       input_event ev{};
       ev.type = EV_SYN; ev.code = SYN_CONFIG; ev.value = on ? kWakeupOn : kWakeupOff;
       if (write(fd, &ev, sizeof(ev)) != sizeof(ev)) { PLOG(ERROR) << "dt2w write"; return false; }
       LOG(INFO) << "dt2w " << (on ? "on" : "off");
       return true;
   }
   }  // namespace

   bool isDeviceSpecificModeSupported(Mode type, bool* _aidl_return) {
       if (type != Mode::DOUBLE_TAP_TO_WAKE) return false;
       *_aidl_return = true;
       return true;
   }

   bool setDeviceSpecificMode(Mode type, bool enabled) {
       if (type != Mode::DOUBLE_TAP_TO_WAKE) return false;   // leave INTERACTIVE etc. to libperfmgr
       setTouchGesture(enabled);
       return true;
   }
   }  // namespace aidl::google::hardware::power::impl::pixel
   ```
   * Optional hardening against the toggle-on-resume bug in 2.1:
     * Remember the last requested value.
     * On `Mode::INTERACTIVE` true, start a detached thread that sleeps about 1.5 s and re-writes the
       value, but only if still interactive.
     * Return `false` for INTERACTIVE, so libperfmgr still handles its hint.
     * PMS normally changes DT2W only while the screen is on (the user is in Settings), so this is
       only needed for `settings put` from adb or restore while the screen is off.
2. **`trees/staging/Android.bp`** (or `power/Android.bp`; it is in the device soong namespace):
   ```
   cc_library_static {
       name: "libperfmgr-ext-dizi",
       defaults: ["android.hardware.power-ndk_shared"],
       vendor: true,
       srcs: ["power/power-mode.cpp"],
       shared_libs: ["libbase"],
   }
   ```
3. **`trees/staging/device.mk`**, next to the Power block (line 271):
   `$(call soong_config_set,power_libperfmgr,mode_extension_lib,//$(LOCAL_PATH):libperfmgr-ext-dizi)`.
   The fully-qualified `//device/xiaomi/dizi:` form is needed because the power HAL namespace doesn't
   import ours. This follows the usual Lineage convention; confirm it with a build.
4. **`trees/staging/overlay/FrameworkOverlayDizi/res/values/config.xml`**: add
   `<bool name="config_supportDoubleTapWake">true</bool>`. It is currently absent, so it defaults to
   false (`frameworks/base/core/res/res/values/config.xml:4326`).
5. **`trees/staging/overlay/SettingsProviderOverlayDizi/res/values/defaults.xml`**: AOSP defaults
   `def_double_tap_to_wake` to **true** (`SettingsProvider/res/values/defaults.xml:188`, applied in the
   v120 upgrade step, `SettingsProvider.java:4524-4533`). HyperOS also ships it on
   (`mTouchWakeupMode: 5`). Until the drain is measured, I suggest
   `<bool name="def_double_tap_to_wake">false</bool>`, then revisit. This only affects fresh data.
6. **`trees/staging/sepolicy/vendor/hal_power_default.te`**: add
   ```
   allow hal_power_default input_device:dir r_dir_perms;
   allow hal_power_default input_device:chr_file rw_file_perms;
   ```
   * `/dev/input/*` is root:input 0660 and the HAL runs as root, so DAC is fine.
   * I found no neverallow for vendor domains; `hal_fingerprint.te:3-4` in our tree already has the
     same rules for another HAL.
   * `sepolicy/vendor/hal_power.te` (touchfeature_device) is a garnet mode-14 leftover. It is harmless,
     and can be dropped once nothing else needs it.
7. **Cleanup (optional):** remove the dead `gesture_*_tap_*` chown/chmod lines in
   `rootdir/etc/init.target.rc:117-125`.
8. **Hall cover (recommended, separate change): `patches/frameworks/base/000N-...patch`.**
   * In `PhoneWindowManager` `case KEYCODE_WAKEUP`, set `isWakeKey = false` when
     `mDefaultDisplayPolicy.getLidState() == LID_CLOSED && getLidBehavior() == LID_BEHAVIOR_SLEEP`.
   * This mirrors `shouldEnableWakeGestureLp()` at `PhoneWindowManager.java:3708-3713`, which already
     does the same for sensor wake gestures.
   * Our overlay sets `config_lidControlsSleep=true` (`FrameworkOverlayDizi/.../config.xml:25`), so
     `LID_BEHAVIOR` defaults to SLEEP (`DatabaseHelper.java:2458-2469`).
   * A HAL-side approach (turn gesture mode off when the cover closes) can't cover the common case,
     "screen already off, then cover closed": the driver ignores changes while suspended (2.1). So the
     wake has to be filtered in the framework. The IC still takes the IRQ and the SoC still wakes
     briefly, but the screen stays off.

Everything else already exists: the `KEY_WAKEUP` keylayout, `PhoneWindowManager` wake handling, and
the Settings toggle.

## 4. Risks

### 4.1 Deep sleep drain (main risk) [unverified magnitude]

* When DT2W is on and the screen is off:
  * the panel VDD/VDDIO regulators, the OCP2131 ±bias and the reset/enable GPIOs stay on
    (`dsi_panel.c:448-499`; stock log `lcd_reset_keep_high`);
  * the NT36532 stays in gesture-scan mode instead of deep sleep (`0x13` instead of `0x11`).
* I have no number. It could plausibly be a few mA at the battery, which is significant against the
  ~6 mA idle (PLAN.md:91). **Measure it.**
* Each gesture or noise IRQ also holds a 5 s wakeup source (`pm_wakeup_event(...,5000)`), so noisy
  firmware in gesture mode could keep the SoC out of suspend for long periods.

### 4.2 Regulator refcount leak in the display driver [source; verify]

* `dsi_panel_power_off()` returns before `dsi_pwr_enable_regulator(false)` while keep_high is set,
  but `dsi_panel_power_on()` still calls `dsi_pwr_enable_regulator(true)` on every wake.
  `regs->refcount++` is at `msm/dsi/dsi_pwr.c:381-388`.
* So after N screen-off/on cycles with DT2W on, the refcount is N+1. When DT2W is later turned off,
  power_off only decrements once, so **the panel rails would stay on in suspend until reboot**.
* Stock has the same behaviour, since we ship the same `msm_drm.ko`.
* Check it in `/sys/kernel/debug/regulator/regulator_summary` (see the test plan). If it's real,
  document it: "toggle DT2W off → reboot to get the full idle back". It can't be fixed without
  rebuilding `msm_drm.ko`, which we could do, since display is already source-buildable
  (`kernel/out-display`).

### 4.3 False wakes in a bag or case

* All firmware gestures map to `KEY_WAKEUP`, not just double-click (`gesture_key_array`,
  `nt36xxx.c:128-144`). Only double-click checks `is_gesture_mode`, and the letters/slides are reported
  unconditionally when the firmware sends them. Whether the dizi firmware enables letter/slide
  gestures in `0x13` mode is unknown [unverified].
* Hall cover: the framework does not filter `KEYCODE_WAKEUP` while the lid is closed (only sensor wake
  gestures, `PhoneWindowManager.java:3708`). Without the patch in 3.2 step 8, taps through a closed
  cover wake the screen, and it then stays on until the screen timeout.
* Stock HyperOS behaviour with the cover closed is unknown [unverified].
* The tablet has no proximity sensor that I know of, so the Lineage proximity-check-on-wake doesn't
  help.

### 4.4 Pen and palm interaction [source]

* The pen protocol (mode 20 via `xiaomi-pen`) doesn't touch `is_gesture_mode`.
* In a gesture suspend, the driver sends `0x7B 0` (pen off; stock log "Disable pen gesture"). The pen
  can't wake the tablet, and it adds no cost.
* On resume, `update_pen_status(true)` re-sends the pen state (`nt36xxx.c:4321`).
* Don't set mode 24 (pen shorthand). It turns on the fake pen-tap report and a second keep-high
  condition.
* Palm events (`nvt_check_palm`, 1850-1871) are dropped before the gesture parse, with no interaction.
* Note that nothing in the driver distinguishes pen from finger for double-click. The IC firmware
  decides.

### 4.5 Other issues

* The toggle-on-resume bug (2.1) can invert the state if something writes while the screen is off.
* The event node number can change, so look it up by name.
* If the power HAL restarts, the driver keeps its state; PMS does not resend.

## 5. Test plan (when the tablet is back)

1. **Before any code, as root on the current build:**
   * `getevent -pl` to find the node, then `sendevent /dev/input/eventN 0 1 5`.
   * `dmesg | grep -E "nvt_gesture_switch|enable gesture mode"` should show the lines from 1.1.
   * Press power off, then double-tap.
     * Expected: `getevent -lt` (run in another shell before screen-off) shows `KEY_WAKEUP` down/up.
     * Expected: dmesg shows `Gesture : Double Click.`, and the screen wakes.
   * Check `dmesg | grep "TP gesture"`, which should show `lcd_reset_keep_high`.
   * Then `sendevent ... 0 1 4`, screen off, and check that `Enabled touch wakeup gesture` is absent
     and `enter sleep mode` is present.
2. **Power** (unplugged; use `tools/suspend-watch.sh` and the method in `research/performance.md`
   §365). Take three 20-30 min runs each of:
   * (a) DT2W off after a fresh boot;
   * (b) DT2W on;
   * (c) DT2W on for several screen cycles, then off, without a reboot.

   For each run, record:
   * mA,
   * `/sys/power/suspend_stats`,
   * `/sys/kernel/debug/wakeup_sources` (look at spi0.0 / nvt),
   * `/sys/kernel/wakeup_reasons/last_resume_reason`,
   * `/proc/interrupts` (NVT IRQ count),
   * `/sys/kernel/debug/regulator/regulator_summary` (panel vregs; in (c), check for the refcount
     leak from 4.2).
3. **Implementation:** after flashing the power-ext build:
   * Toggle Settings > Display > Tap to wake. Check logcat `powerhal-libperfmgr`, `dt2w on/off`, the
     dmesg lines, and no avc denials.
   * Reboot with it on, and check that it is still active (PMS sets false then true at boot).
   * Run `settings put secure double_tap_to_wake 1` while the screen is off, then wake. Confirm the
     state is right (the toggle-bug case). If it's wrong, add the INTERACTIVE re-assert.
4. **Pen:** with the pen paired and DT2W on:
   * after a screen-off/on cycle, check that pen hover and draw work (`tools/pen-test`);
   * check that pen taps don't wake the screen;
   * check dmesg `Disable pen gesture`.
5. **Hall:**
   * Close the cover with the screen on: it goes to sleep, and double-taps on the cover do not wake it
     (with the patch).
   * Screen off first, then close the cover: same result.
   * Open the cover: it wakes (`LID_BEHAVIOR`). Double-tap still works afterwards.
6. **False-wake soak:** leave it in a bag or case overnight with DT2W on. Check the batterystats
   screen-on count and wake reasons (`dumpsys power` `WAKE_REASON_WAKE_KEY` / "android.policy:KEY").

## Verified on release-1 (2026-09-28, Magisk root)

- `sendevent /dev/input/event6 0 1 5` with the screen on logs `nvt_gesture_switch ... value = 5`,
  `gesture_pen and gesture_mode All True` and `enable gesture mode`.
- At screen off: `nvt_ts_suspend: Enabled touch wakeup gesture`, then `[TP gesture], lcd_reset_keep_high`.
  A double tap logs `Gesture : Double Click.` and the tablet wakes. The user confirmed it.
- **The mode survives suspend/resume:** later suspends log `Enabled touch wakeup gesture` again, and a second
  double tap woke the tablet with nothing re-sent. The HAL therefore writes only on the setting change, and never
  while the panel is off (the driver would defer the write and toggle on the next resume).
- **Implemented in 83fa9e8:** `power/power-mode.cpp` (`libperfmgr-ext-dizi`, `Mode::DOUBLE_TAP_TO_WAKE`),
  `config_supportDoubleTapWake`, `def_double_tap_to_wake=false`, and hal_power_default access to input_device.
- **Open:** standby drain with DT2W on (and on-then-off), and taps through a closed cover (a PhoneWindowManager lid
  check).
