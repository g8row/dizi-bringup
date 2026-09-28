# ADPF hint sessions on dizi (SM7435 parrot, GKI 5.10 + WALT, lineage-libperfmgr)

Written 2026-09-28. Scope: turn on Android Dynamic Performance Framework (ADPF) hint
sessions on the EvoX (A16, lineage-23.2) dizi port without regressing power or jank.
Facts checked in local sources are marked **[local]**. Paths are relative to
`/build/alex/dizi` unless absolute.

TL;DR

* Three things must all be in place. (1) An `AdpfConfig` array in `powerhint.json`.
  (2) SELinux for `sched_setattr` on other processes' threads. (3) The HWUI and SF
  client props, which both default to off. Our tree has none of the three today.
* In the QTI world, community trees with `AdpfConfig` on lineage-libperfmgr exist, but
  **no official LineageOS QTI tree has one** (19 trees checked at lineage-23.2, plus
  Pixel redbull/coral/sunfish/barbet in AOSP). This is still uncommon ground. Stock
  HyperOS does not use ADPF either: the stock QTI power HAL has no hint-session code [local].
* WALT handles uclamp: `uclamp.min` raises the frequency floor (`waltgov_get_util` ->
  `uclamp_rq_util_with`). It **also changes task placement**: any task with effective
  `uclamp.min > 0` and util > `sched_min_task_util_for_uclamp` (51) skips the A55
  cluster. So `UclampMin_Low` must be 0 on dizi, not Pixel's 2.
* Proposal: one `ADPF_DEFAULT` profile, Pixel-Tablet-style PID, `UclampMin_High` 512
  (about a 1.5 GHz floor on the A78s, equal to our INTERACTION floor),
  `ReportingRateLimitNs` 16.67 ms. Stage it: HWUI first, SurfaceFlinger second.

---

## 1. Real-world `AdpfConfig` blocks

### 1.1 How the search was done

I shallow-cloned about 470 device repos matching sm7435/garnet/sm7325/sm8250/sm8350/
sm8450/sm8550/nothing (GitHub repo search) and grepped every `powerhint*.json` for
`AdpfConfig`.

* **Official LineageOS lineage-23.2, no `AdpfConfig`:** xiaomi sm8150/sm8250/sm8350/
  sm8450/sm8550-common, xiaomi garnet (sm7435; the file is byte-identical to ours),
  oneplus sm8250/sm8350/sm8550/sm8650/sm8750-common, motorola sm7325/sm8250/sm8550-common,
  nothing spacewar/pong, sony sm8450/sm8550-common, samsung sm8250-common, xiaomi
  sm6250-common, google redbull/coral/sunfish/barbet/bonito. AOSP
  `device/google/{redbull,coral,sunfish,barbet}` (Qualcomm Pixels) have none either.
* **Hits (5):** listed below. All are community trees.

### 1.2 QTI example A: Nothing Phone (3a) "asteroids" (SM7635, lineage-libperfmgr, lineage-23.2)

Source: <https://github.com/hetnieuwebeginbv-glitch/android_device_nothing_asteroids/blob/lineage-23.2/configs/power/powerhint.json>
(commit 43fb29c). This is the closest match to our stack: lineage-libperfmgr,
`device/lineage/sepolicy/libperfmgr`, QTI GKI + WALT.

```json
"AdpfConfig": [{
  "Name": "ADPF_DEFAULT",
  "PID_On": true, "PID_Po": 3.0, "PID_Pu": 0.6, "PID_I": 0.0,
  "PID_I_Init": 200, "PID_I_High": 512, "PID_I_Low": -30, "PID_Do": 500.0, "PID_Du": 0.0,
  "UclampMin_On": true, "UclampMin_Init": 256, "UclampMin_LoadUp": 480,
  "UclampMin_LoadReset": 480, "UclampMin_High": 480, "UclampMin_Low": 2,
  "UclampMax_EfficientBase": 500, "UclampMax_EfficientOffset": 200,
  "SamplingWindow_P": 1, "SamplingWindow_I": 0, "SamplingWindow_D": 1,
  "ReportingRateLimitNs": 16666666, "TargetTimeFactor": 1.0, "StaleTimeFactor": 15.0,
  "GpuBoost": true, "GpuCapacityBoostMax": 45000,
  "HeuristicBoost_On": true, "HBoostModerateJankThreshold": 2, "HBoostOffMaxAvgDurRatio": 4.0,
  "HBoostSevereJankPidPu": 0.3, "HBoostSevereJankThreshold": 4,
  "HBoostUclampMinCeilingRange": [480, 722], "HBoostUclampMinFloorRange": [256, 410],
  "JankCheckTimeFactor": 1.0, "LowFrameRateThreshold": 25, "MaxRecordsNum": 30
}]
```

It also has an Event node mapping the SF tag to that profile:
`{"Name":"ADPF_HOOK","Paths":["<AdpfConfig>:SURFACEFLINGER"],"Values":["ADPF_DEFAULT"],"Type":"Event"}`.
Its sepolicy (`sepolicy/vendor/hal_power_default.te`) is:

```
allow hal_power_default self:capability sys_nice;
typeattribute hal_power_default mlstrustedsubject;
allow hal_power_default { appdomain system_server surfaceflinger }:process { getsched setsched };
allow hal_power_default { appdomain system_server surfaceflinger }:dir search;
allow hal_power_default { appdomain system_server surfaceflinger }:file { read open getattr };
```

Its props (`properties/vendor.prop`) are `debug.hwui.use_hint_manager=true` and
`debug.sf.enable_adpf_cpu_hint=true`.

Caveat: `GpuBoost` only works with the Pixel/Mali `GpuCapacityNode` sysfs, so on Adreno
it does nothing (see section 2.5).

### 1.3 QTI example B: OnePlus 11 sm8550-common (AlphaDroid 16.2, lineage-libperfmgr)

Source: <https://github.com/AlphaDroid-devices/device_oneplus_sm8550-common/blob/alpha-16.2/configs/powerhint.json>
(commit 1938b98). This is a minimal profile with only the mandatory fields.

```json
"AdpfConfig": [{
  "Name": "ADPF_DEFAULT",
  "PID_On": true, "PID_Po": 5.0, "PID_Pu": 3.0, "PID_I": 0.001,
  "PID_I_Init": 200, "PID_I_High": 512, "PID_I_Low": -120, "PID_Do": 500.0, "PID_Du": 0.0,
  "SamplingWindow_P": 1, "SamplingWindow_I": 0, "SamplingWindow_D": 1,
  "UclampMin_On": true, "UclampMin_Init": 100, "UclampMin_LoadUp": 200,
  "UclampMin_LoadReset": 300, "UclampMin_High": 384, "UclampMin_Low": 0,
  "ReportingRateLimitNs": 166666660, "TargetTimeFactor": 1.0, "StaleTimeFactor": 10.0
}]
```

It uses `UclampMin_Low: 0`. The same file also writes WALT
`/proc/sys/walt/sched_min_task_util_for_uclamp` and top-app `cpu.uclamp.*` nodes.

### 1.4 QTI example C: Xiaomi sm8350-common "venus" (AOSP-for-venus, pixel-libperfmgr)

Source: <https://github.com/AOSP-for-venus/platform_device_xiaomi_sm8350-common/blob/bak/configs/powerhint.json>
(commit 2a82589). This is the Pixel 8/9-style field set on a QTI SoC.

```json
{ "Name": "SYSTEM_UI_PROFILE",
  "PID_On": true, "PID_Po": 2.0, "PID_Pu": 0.5, "PID_I": 0.0, "PID_I_Init": 200,
  "PID_I_High": 512, "PID_I_Low": -30, "PID_Do": 500.0, "PID_Du": 0.0,
  "UclampMin_On": true, "UclampMin_Init": 231, "UclampMin_LoadUp": 730, "UclampMin_LoadReset": 730,
  "UclampMin_High": 480, "UclampMin_Low": 2,
  "UclampMax_EfficientBase": 500, "UclampMax_EfficientOffset": 200,
  "SamplingWindow_P": 1, "SamplingWindow_I": 0, "SamplingWindow_D": 1,
  "ReportingRateLimitNs": 166666660, "TargetTimeFactor": 1.0, "StaleTimeFactor": 15.0,
  "HeuristicBoost_On": true, "HBoostModerateJankThreshold": 2, "HBoostOffMaxAvgDurRatio": 4.0,
  "HBoostSevereJankPidPu": 0.3, "HBoostSevereJankThreshold": 8,
  "HBoostUclampMinCeilingRange": [480, 722], "HBoostUclampMinFloorRange": [230, 410],
  "JankCheckTimeFactor": 1.2, "LowFrameRateThreshold": 25, "MaxRecordsNum": 300,
  "GpuBoost": true, "GpuCapacityBoostMax": 25000 }
```

This tree has the tag node `<AdpfConfig>:SYSTEM_UI` and the full Pixel ADPF sepolicy
(`appdomain`, `platform_app`, `priv_app`, `untrusted_app`, `surfaceflinger`,
`hal_graphics_composer_default` and `system_server` `setsched`, plus
`self:capability sys_nice`). It sets `debug.sf.enable_adpf_cpu_hint=true` and
`debug.hwui.use_hint_manager=true` in `common.mk`.

### 1.5 Counter-example: Klozz / XPerience xiaomi sm8350-common

Sources: <https://github.com/Klozz/android_device_xiaomi_sm8350-common/blob/bka/power/powerhint.json>,
<https://github.com/TheXPerienceProject/android_device_xiaomi_sm8350-common/blob/xpe-20.2/power/powerhint.json>.

These define REFRESH_60/90/120FPS and GAME_MODE profiles with `UclampMin_High`
350/370/390/400. They also use made-up keys that current libperfmgr does not know:
`HBoostOnMissedCycles`, `HBoostUclampMin`, `HBoostPidPuFactor`, `PackageFilter`.

Unknown keys are ignored silently. But `HeuristicBoost_On: true` without the 9 required
`HBoost*` fields makes `ParseAdpfConfigs` clear the **whole list**. The result is "No
AdpfConfig", so ADPF is off. That tree actually ships `android.hardware.power-service-qti`,
so libperfmgr never reads the file. **Do not copy these.**

### 1.6 Pixel reference: Pixel Tablet "tangorpro" (AOSP main)

Source: <https://android.googlesource.com/device/google/tangorpro/+/383c2db8399c0364122e57b1944fbca11f67720a/powerhint.json>
(same content as the GrapheneOS mirror
<https://github.com/GrapheneOS/device_google_tangorpro/blob/14/powerhint.json>).

```json
{ "Name": "REFRESH_60FPS", "PID_On": true, "PID_Po": 2.0, "PID_Pu": 1.0, "PID_I": 0.0,
  "PID_I_Init": 200, "PID_I_High": 512, "PID_I_Low": -30, "PID_Do": 500.0, "PID_Du": 0.0,
  "UclampMin_On": true, "UclampMin_Init": 182, "UclampMin_LoadUp": 514, "UclampMin_LoadReset": 514,
  "UclampMin_High": 514, "UclampMin_Low": 2,
  "UclampMax_EfficientBase": 500, "UclampMax_EfficientOffset": 200,
  "SamplingWindow_P": 1, "SamplingWindow_I": 0, "SamplingWindow_D": 1,
  "ReportingRateLimitNs": 166666660, "TargetTimeFactor": 1.0, "StaleTimeFactor": 15.0,
  "HeuristicBoost_On": true, "HBoostModerateJankThreshold": 2, "HBoostOffMaxAvgDurRatio": 4.0,
  "HBoostSevereJankPidPu": 0.5, "HBoostSevereJankThreshold": 8,
  "HBoostUclampMinCeilingRange": [480, 722], "HBoostUclampMinFloorRange": [230, 410],
  "JankCheckTimeFactor": 1.2, "LowFrameRateThreshold": 25, "MaxRecordsNum": 300 },
{ "Name": "UiHighBoostWithoutPid", "PID_On": false, ..., "UclampMin_Init": 250,
  "UclampMin_High": 197, "UclampMin_Low": 197, "ReportingRateLimitNs": 1, "StaleTimeFactor": 5.0 },
{ "Name": "UiLowBoostWithoutPid", ... "UclampMin_High": 53, "UclampMin_Low": 53 ... },
{ "Name": "UiLowNoneBoost", ... "UclampMin_High": 0, "UclampMin_Low": 0 ... }
```

Pixel's values are tuned for Tensor capacities and Google's `vendor_sched`, not WALT.

### 1.7 Parser facts (our libperfmgr) [local]

From `evox/hardware/google/pixel/power-libperfmgr/libperfmgr/HintManager.cc:874-1058`:

* **Required** (if any is missing or has the wrong JSON type, *all* profiles are dropped):
  `Name` (unique), `PID_On`, `PID_Po`, `PID_Pu`, `PID_I`, `PID_I_Init`, `PID_I_High`,
  `PID_I_Low`, `PID_Do`, `PID_Du`, `UclampMin_On`, `UclampMin_Init`, `UclampMin_High`,
  `UclampMin_Low`, `SamplingWindow_P/I/D`, `StaleTimeFactor`, `ReportingRateLimitNs`,
  `TargetTimeFactor`.
  * Doubles must be JSON doubles: `2.0`, not `2`. jsoncpp's `isDouble()` accepts ints, so
    in practice ints work for doubles. `UInt`/`Int64` fields must be integers.
* **Optional:** `UclampMin_LoadUp` and `UclampMin_LoadReset` (both default to
  `UclampMin_High`), `UclampMax_EfficientBase/Offset`, `GpuBoost`, `GpuCapacityBoostMax`,
  `GpuCapacityLoadUpHeadroom`, `HeuristicRampup` + `DefaultRampupMult`/`HighRampupMult`.
  * `HeuristicBoost_On` requires all of these: `HBoostModerateJankThreshold`,
    `HBoostOffMaxAvgDurRatio`, `HBoostSevereJankPidPu`, `HBoostSevereJankThreshold`,
    `HBoostUclampMinCeilingRange`, `HBoostUclampMinFloorRange`, `JankCheckTimeFactor`,
    `LowFrameRateThreshold`, `MaxRecordsNum`.
* **Profile selection:**
  * The default is `AdpfConfig[0]`.
  * Per-SessionTag profiles come from Event nodes with path `<AdpfConfig>:<TAG>`, where
    TAG is `OTHER`, `SURFACEFLINGER`, `HWUI`, `GAME`, `APP` or `SYSUI`.
  * **Pitfall:** `Power::setMode(X, true)` calls `SetAdpfProfileFromDoHint(X)`
    (`PowerSessionManager.cpp:86-96`). A profile whose `Name` equals a Mode name (`GAME`,
    `LAUNCH`, `SUSTAINED_PERFORMANCE`, ...) becomes the global default when that mode turns
    on, and it is **not reverted** when the mode turns off. Use non-mode names such as
    `ADPF_DEFAULT`.
  * `applyUclampLocked` reads `UclampMin_On` from the default profile only.
* `getHintSessionPreferredRate` returns `ReportingRateLimitNs`. A value of 0 means
  "unsupported" (`Power.cpp:231`). system_server reads the rate **once at boot**
  (`HintManagerService.java:321`). `Hint Session Support` in `dumpsys performance_hint` is
  `rate != -1`.

---

## 2. What the power HAL needs besides the JSON

### 2.1 Kernel permission for uclamp

`set_uclamp()` (`evox/hardware/lineage/interfaces/power-libperfmgr/aidl/PowerSessionManager.cpp:64-80`)
calls `sched_setattr(tid, {SCHED_FLAG_KEEP_ALL|UTIL_CLAMP_MIN|UTIL_CLAMP_MAX}, 0)` on
threads of other processes (apps, SF, system_server).

In 5.10 `__sched_setscheduler()` (`kernel/lineage/kernel/sched/core.c:5510-5560`), when
the caller lacks `CAP_SYS_NICE`, **any** `SCHED_FLAG_UTIL_CLAMP` returns `-EPERM` ("Can't
change util-clamps"), and changing another user's task also returns `-EPERM`. So the HAL
needs `CAP_SYS_NICE`.

It runs as `user root` with no `capabilities` line
(`android.hardware.power-service.lineage-libperfmgr.rc`), so the kernel capability is
there. SELinux still has to allow it.

### 2.2 SELinux

* AOSP `system/sepolicy/private/hal_power.te` has only binder and `dalvik_dynamic_config_prop`.
  `vendor/hal_power_default.te` only declares the domain. `domain.te` grants `setsched`
  only on `self`. **So AOSP grants nothing for ADPF.** [local]
* `device/lineage/sepolicy/libperfmgr/vendor/hal_power_default.te` (which we include) has
  cgroup/cpu sysfs access, `vendor_power_prop`, IStats and thermal, but **no `setsched`
  or `sys_nice`** [local]. Our `sepolicy/vendor/hal_power_default.te` only adds
  `proc_walt` and `msm_perf`.
* Pixel puts these rules in `hardware/google/pixel-sepolicy/power-libperfmgr/hal_power_default.te`
  [local, also <https://android.googlesource.com/platform/hardware/google/pixel-sepolicy/+/refs/heads/main/power-libperfmgr/hal_power_default.te>].
  That directory is only pulled in by Pixel's `aidl/device.mk`, which we do not use:
  ```
  typeattribute hal_power_default mlstrustedsubject;
  allow hal_power_default appdomain:process { getsched setsched };
  allow hal_power_default self:capability sys_nice;
  allow hal_power_default surfaceflinger:process setsched;
  allow hal_power_default hal_graphics_composer_default:process setsched;
  allow hal_power_default system_server:process setsched;
  ```
* `mlstrustedsubject` is required. `private/mls` constrains `process setsched` to
  `l1 eq l2 or t1 == mlstrustedsubject`, and untrusted apps have per-app MLS categories.
  No neverallow blocks it for a vendor domain; Pixel and the Nothing tree both ship it.
* Without these rules sessions are still created, but you get
  `sched_setattr failed for thread N, err=13/1` in logcat and `avc: denied { setsched }` /
  `{ sys_nice }`. ADPF then does nothing.

**To add to `trees/staging/sepolicy/vendor/hal_power_default.te`:**

```
# ADPF: per-thread uclamp via sched_setattr
typeattribute hal_power_default mlstrustedsubject;
allow hal_power_default self:capability sys_nice;
allow hal_power_default { appdomain system_server surfaceflinger hal_graphics_composer_default }:process { getsched setsched };
# optional, only for the /data/vendor/etc debug config (userdebug)
userdebug_or_eng(`allow hal_power_default vendor_data_file:dir search; allow hal_power_default vendor_data_file:file r_file_perms;')
```

Check that the composer domain on dizi really is `hal_graphics_composer_default` (QTI
composer 3.x) with `ps -AZ | grep composer`. SF's ADPF session only lists SF threads, so
the composer rule is Pixel-only and optional.

### 2.3 WALT and uclamp on the 5.10 QTI kernel [local: `kernel/lineage/kernel/sched/walt/`]

* **Frequency.** `waltgov_get_util()` returns `uclamp_rq_util_with(rq, util, NULL)`
  (`cpufreq_walt.c:253-262`). So a runnable task's `uclamp.min` does raise that CPU's
  frequency floor. Enqueueing with a changed rq clamp triggers a `WALT_CPUFREQ_UCLAMP`
  governor callback (`walt.c:3974-3978`). WALT maps util to frequency as
  `freq = 1.25 * fmax * util / cap` (`walt_map_util_freq`).
* **Placement.** `walt_uclamp_boosted(p)` is `uclamp_eff_value(p, MIN) > 0 && task_util(p) > sched_min_task_util_for_uclamp`
  (default 51; `walt.h:528`, `sysctl.c:59`). A boosted task:
  * turns off energy evaluation and starts the CPU search at cluster 1 (`walt_cfs.c:186`);
  * counts as misfit on min-capacity CPUs (`task_fits_max`, `walt.h:758`).
  * **Effect:** any non-zero ADPF floor moves UI and RenderThread threads with util > 51
    onto the A78 cluster. For RT tasks (the SF main thread and RenderEngine are
    SCHED_FIFO), `walt_rt_task_fits_capacity()` requires `cpu_cap >= uclamp.min`
    (`walt_rt.c:110-120`). An SF floor above about 440 forces SF onto the big cores.
* **Cgroup clamp.** This kernel has the "fixed" semantics:
  `uclamp_tg_restrict()` = `clamp(task_req, tg_min, tg_max)` (`core.c:1103-1127`). Our
  top-app/foreground groups keep the default `cpu.uclamp.max` (max) and `min` 0, so ADPF
  values pass through. If anyone ever sets top-app `cpu.uclamp.max` below `UclampMin_High`,
  that cap wins.
* **RT default.** Stock `init.kernel.post_boot-parrot.sh:74` sets
  `sched_util_clamp_min_rt_default=0`. RT tasks therefore have no implicit 1024 boost, and
  an ADPF floor on SF threads is a real increase, not a decrease.
* **Colocation.** top-app has `cpu.uclamp.colocate 1` (`init.qti.kernel.rc:64`), so
  WALT's related-thread-group already aggregates top-app demand for frequency and
  upmigrate (group_upmigrate 100). ADPF adds a per-thread floor on top of that.
* **`sched_boost`.** Our LAUNCH/INTERACTION actions set `sched_boost`, and
  `sched_boost_no_override` is 1 for top-app/foreground. Full-throttle boost overrides
  placement anyway (`walt_cfs.c:175`).
* **Known caveats:**
  * uclamp is inherited on fork, because libperfmgr does not set `SCHED_FLAG_RESET_ON_FORK`.
    Threads spawned by a boosted RenderThread inherit its floor until the next vote update
    (discussion: <https://lkml.iu.edu/hypermail/linux/kernel/2304.2/04698.html>).
  * `err=3` (ESRCH) warnings for exited threads are normal; the HAL prunes them.
  * `CONFIG_UCLAMP_TASK(_GROUP)=y`, `UCLAMP_BUCKETS_COUNT=20`, `SCHED_DEBUG=y` [local
    `kernel/out-gki/.config`]. So `/proc/<pid>/task/<tid>/sched` shows `uclamp.min` and
    `effective uclamp.min` (`debug.c:1013-1016`), which is handy for verification.
* **What QTI does instead:** CLO's `vendor/qcom/opensource/power/PowerHintSession.cpp`
  [local] implements ADPF with perf-HAL opcodes. It uses `CPU_BOOST_HINT 0x104E` and WALT
  per-task load boost `SCHED_TASK_LOAD_BOOST 0x43C04000` (±80 %), not uclamp, and returns a
  preferred rate of 16.67 ms. It needs `libqti-perfd` and the vendor perf HAL, which we do
  not ship. So on our stack uclamp via libperfmgr is the only option.
  Qualcomm doc: <https://docs.qualcomm.com/bundle/publicresource/topics/80-PK177-134/google_adpf_and_qape.html>
  (JS-rendered, content not retrievable).

### 2.4 Properties

* **Power HAL side:** lineage-libperfmgr has no `vendor.powerhal.adpf.*` or
  `persist.vendor.powerhal.adpf*` switch. ADPF is on exactly when `AdpfConfig` parses [local].
  The only props the HAL reads are:
  * `vendor.powerhal.disp.idle_support/idle_wait`, `vendor.powerhal.interaction.min/max/offset`;
  * `vendor.powerhal.state/audio/rendering`;
  * `vendor.powerhal.config` (file name);
  * `vendor.powerhal.config.debug`: loads `/data/vendor/etc/<config>`, and the rc restarts
    the HAL on change when `ro.debuggable=1`;
  * `persist.vendor.powerhal.config.debug.usefallback`: without it, a bad debug JSON causes
    a `LOG(FATAL)` loop.
  * QTI's own HAL uses `vendor.debug.enable.adpf` for logging only; not relevant here.
* **Clients:** these are **not automatic**. Both default to false [local]:
  * HWUI: `debug.hwui.use_hint_manager` (`Properties.cpp:173`, default false). When true,
    `HintSessionWrapper` makes an `SessionTag::HWUI` session per window with the UI thread
    and RenderThread. Its target is `frame deadline * debug.hwui.target_cpu_time_percent`
    (default 70 %). It sends `CPU_LOAD_RESET` after idle, `CPU_LOAD_UP` for expensive
    frames, and `GPU_LOAD_UP`.
  * SurfaceFlinger: `debug.sf.enable_adpf_cpu_hint` (`FlagManager.cpp:256`). This is a
    legacy server flag: the sysprop override wins, otherwise it reads DeviceConfig
    `AdpfFeature__adpf_cpu_hint`, which is empty on our build, so false. It is read once at
    boot-finished (`SurfaceFlinger.cpp:848`). The session is SF main + RenderEngine threads,
    tag SURFACEFLINGER. SF also sends `CPU_LOAD_UP`/`CPU_LOAD_RESET` around display updates.
  * NDK/Java `PerformanceHint` users (games, Chrome, some launchers) create `APP`/`GAME`
    sessions once support is reported. No prop is involved; this cannot be switched off
    per client.

### 2.5 Pixel-only features to leave out

* `GpuBoost`/`GpuCapacity*`: `GpuCapacityNode` writes Mali `capacity_headroom` sysfs.
* `HeuristicRampup`: `/proc/vendor_sched/sched_qos/rampup_multiplier_set`.
* HeuristicBoost: this one does work generically, but it adds 9 knobs. Add it only if the
  plain PID proves too slow.
* `UclampMax_Efficient*`: only used when a client sets POWER_EFFICIENCY mode. It is
  harmless, but not needed for the first test.

---

## 3. Proposal for dizi

### 3.1 Capacity arithmetic (parrot)

* dts `capacity-dmips-mhz` is 1024 (A55) and 1945 (A78) (`kernel/lineage-devicetrees/qcom/parrot.dtsi`).
  With fmax 1.958 GHz and 2.4 GHz, the A55 capacity is 1024·1958.4 / (1945·2400) · 1024
  ≈ **440**, and the A78 is **1024**. Verify on device with
  `cat /sys/devices/system/cpu/cpu{0,4}/cpu_capacity`.
* WALT frequency floor from uclamp.min `u`, based on `1.25·fmax·u/cap`:

| u | A78 floor | A55 floor |
|---|---|---|
| 256 | 750 MHz | 1.42 GHz |
| 384 | 1.13 GHz | fmax |
| 480 | 1.41 GHz | fmax |
| 512 | 1.50 GHz | fmax |
| 614 | 1.80 GHz | fmax |
| ≥819 | 2.4 GHz (fmax) | fmax |

* A55 fmax is reached at u ≥ 352. In practice boosted tasks with util > 51 are placed on
  the A78s anyway (section 2.3), so the A78 column is the one that matters.
* Our INTERACTION action already sets a gold floor of 1.4976 GHz, and `input_boost` sets
  cpu0 to 1.8 GHz. A `UclampMin_High` of 512 matches the existing touch floor and does
  not exceed it. Values above ~600 would out-boost our own touch boost on every frame;
  the Pixel heuristic ceiling of 722 is about 2.1 GHz, which is too hot for a sustained UI.

### 3.2 Profile

```json
"AdpfConfig": [
  {
    "Name": "ADPF_DEFAULT",
    "PID_On": true,
    "PID_Po": 2.0,
    "PID_Pu": 1.0,
    "PID_I": 0.0,
    "PID_I_Init": 200,
    "PID_I_High": 512,
    "PID_I_Low": -30,
    "PID_Do": 500.0,
    "PID_Du": 0.0,
    "UclampMin_On": true,
    "UclampMin_Init": 256,
    "UclampMin_LoadUp": 512,
    "UclampMin_LoadReset": 512,
    "UclampMin_High": 512,
    "UclampMin_Low": 0,
    "SamplingWindow_P": 1,
    "SamplingWindow_I": 0,
    "SamplingWindow_D": 1,
    "ReportingRateLimitNs": 16666666,
    "TargetTimeFactor": 1.0,
    "StaleTimeFactor": 10.0
  }
]
```

No Event tag nodes are needed: every tag falls back to `AdpfConfig[0]`.

Reasoning:

* **PID** (units: error in 100 µs, output in uclamp points; `PowerHintSession.cpp:70-145`).
  These are the Pixel Tablet values, which are the most conservative in the set.
  * At 120 Hz the HWUI target is 8.33 ms × 0.7 = 5.8 ms (`dt` = 58).
  * A frame 2 ms late gives P = +40, and the D term on a jump from on-time to 2 ms late
    gives 500·20/58 ≈ +170. So one late frame lifts the floor by ~200, for example from
    256 to about 470.
  * Each frame 1 ms early lowers it by 10, so decay from 512 to 0 takes about 50 frames
    (~0.4 s at 120 Hz). That keeps boosts short-lived.
  * I stays off (`PID_I 0`), as on all the Pixels. `SamplingWindow_I` 0 is harmless.
  * AlphaDroid's Po 5 / Pu 3 reacts faster but oscillates more. Nothing's 3.0 / 0.6
    ramps up faster and decays slowly, which costs more power. Try those only if
    ui-jank shows the PID lagging.
* **`UclampMin_Low: 0`, not 2.** With WALT, any value > 0 counts as "uclamp boosted",
  which pins the thread to the A78s whenever util > 51 (section 2.3). With 0, the idle and
  light-frame state goes back to normal WALT energy-aware placement.
* **`UclampMin_Init: 256`.** First frames of a new session get a mild floor: A78 at
  750 MHz, just above the 691 MHz `scaling_min_freq`. It mostly acts as "place on big".
  Pixel uses 182; Nothing uses 256.
* **`UclampMin_High`, `LoadUp` and `LoadReset`: 512.** See 3.1. `CPU_LOAD_RESET` arrives
  when a window starts drawing after more than 100 ms idle, and `CPU_LOAD_UP` on expensive
  frames. The vote lasts `target·StaleTimeFactor/2` (≈29 ms for HWUI, ≈42 ms for SF) and
  `2·target` respectively. Fallback plan: if power suffers, try 384 (1.13 GHz).
* **`ReportingRateLimitNs: 16666666`.** This is the rate apps see
  (`getPreferredUpdateRateNanos`). It also sets the lifetime of the PID vote,
  `max(target·StaleTimeFactor, 2·ReportingRateLimitNs)` (`PowerHintSession.cpp:220-230`).
  With Pixel's 166.7 ms, every boost would linger **≥333 ms** after the last report. With
  16.7 ms the lifetime is set by StaleTimeFactor. The value matches QTI's own ADPF HAL
  (16666666) and the Nothing tree.
* **`StaleTimeFactor: 10`.** The vote expires 58 ms after the last HWUI report at
  120 Hz (83 ms for SF). That is shorter than Pixel's ×15 because the boost here also moves
  threads to the big cluster.
* **`TargetTimeFactor: 1.0`.** HWUI already takes 70 % of the deadline.

### 3.3 Enablement steps (staging tree)

1. Add the block above to `trees/staging/configs/power/powerhint.json`, keeping Nodes
   and Actions unchanged.
2. Add the SELinux rules from section 2.2 to `trees/staging/sepolicy/vendor/hal_power_default.te`.
3. **Phase A (HWUI only):** add `debug.hwui.use_hint_manager=true` to the vendor props
   (`props/vendor.prop`). Leave SF off (it is off by default).
4. **Phase B:** add `debug.sf.enable_adpf_cpu_hint=true`. SF threads are RT, and with
   High 512 > 440 an SF boost puts SF on the A78s. If Phase B shows no gain on the SF
   timestats "missed frames", keep it off. Alternatively, add an `ADPF_SF` profile with
   `UclampMin_High` 400 (A55 fmax without forcing the big cores) mapped via
   `{"Name":"ADPF_SF_TAG","Paths":["<AdpfConfig>:SURFACEFLINGER"],"Values":["ADPF_SF"],"Type":"Event"}`.
5. Iterate without a rebuild (userdebug):
   * `adb shell mkdir -p /data/vendor/etc`, then push the JSON to
     `/data/vendor/etc/powerhint.json`. Keep the label `vendor_data_file` (`restorecon`).
   * `setprop persist.vendor.powerhal.config.debug.usefallback true`, then
     `setprop vendor.powerhal.config.debug true`. The HAL restarts.
   * Then run `adb shell stop && adb shell start`. system_server and SF read "supported"
     and the rate only at boot, and HWUI reads its prop at process start.
   * This needs the `userdebug_or_eng` rule in 2.2, or temporary `setenforce 0`.

---

## 4. Test plan

### 4.1 Is it on?

* `adb logcat -b all -d | grep -E "AdpfConfigs parsed|No AdpfConfig|Failed to read AdpfConfig|Power hint is|sched_setattr failed|avc: denied.*(setsched|sys_nice)"`.
  Expect `1 AdpfConfigs parsed successfully` and SF `Power hint is supported` (Phase B).
  Expect **no** `sched_setattr failed ... err=1/13` and no avc lines.
* `adb shell dumpsys performance_hint`. Expect `HintSessionPreferredRate: 16666666`,
  `Hint Session Support: true`. While scrolling, expect active sessions per uid/pid
  (launcher, SystemUI, the foreground app; and SF, uid 1000, in Phase B).
* `adb shell dumpsys android.hardware.power.IPower/default`. Expect the
  `ADPF Tag Profile` / `Default non-tagged adpf profile` dump with our values, and per-session
  lines with `uclamp.min: N` (`PowerHintSession.cpp:733`).
* Confirm the kernel applied it during a fling: find the RenderThread tid (`ps -T -p <pid> | grep RenderThread`)
  and run `adb shell cat /proc/<pid>/task/<tid>/sched | grep uclamp`. Expect a non-zero
  `effective uclamp.min` during the fling and a return to 0 within about 60 ms of stopping.
* Perfetto: atrace categories `power gfx view sched freq`. The libperfmgr ATRACE counters
  are per session (`adpf.<id>-min`, `-target`, `-actl_last`, `pid.*`), shown next to
  RenderThread placement and CPU frequency.

### 4.2 What to measure

Run a baseline build (current) and the ADPF build on the same device, same orientation,
same battery or charging state, screen at 120 Hz. Use at least 3 runs per variant; report
the median and the spread.

| Test | Metric | Pass criterion |
|---|---|---|
| `QS_ONLY=1 tools/ui-jank.sh <id>` (fast A/B, repeat 3-5x) | hwui janky %, p90/p95/p99 frame time (SystemUI), SF timestats missed/janky frames | janky % and p95 not worse; ideally p99 down |
| `tools/ui-jank.sh <id>` full (app flings) | same, per app | no app regresses by more than noise; heavier apps improve |
| `tools/recents-jank.sh <id>` | launcher (quickstep) hwui janky %, p95; SF timestats | stays at or below the b34 level (~2.7 %) |
| Power / heat during the same loops | `policy{0,4}/stats/time_in_state` delta (A78 residency, time at >1.5 GHz), average `/sys/class/power_supply/battery/current_now` over a 5-min fling loop unplugged, `thermal_zone*` skin/CPU peak | A78 residency or average current up by no more than ~10 % unless jank improves clearly |
| Idle / video sanity | 5 min static home screen and 5 min video: `dumpsys performance_hint` sessions should go idle; current same as baseline | no residual floor (check `effective uclamp.min` = 0) |

Decision rules:

* If jank improves and power is flat, keep it and try Phase B.
* If jank is flat and power goes up, drop `UclampMin_High` to 384 and `LoadReset` to 384.
  If still no gain, disable ADPF (remove the `AdpfConfig`, or set `UclampMin_On:false`,
  which keeps sessions but does nothing) and keep the SELinux rules.
* If jank gets worse, look at the Perfetto trace. Likely causes: RenderThread moving to
  big cores and colliding with other big-core work, or inherited uclamp on forked threads.
  Check `sched_min_task_util_for_uclamp`, which could be raised via powerhint Nodes
  (the AlphaDroid tree does this).

---

## Sources

* Local: `evox/hardware/google/pixel/power-libperfmgr/libperfmgr/HintManager.cc`,
  `evox/hardware/lineage/interfaces/power-libperfmgr/aidl/{Power,PowerHintSession,PowerSessionManager}.cpp`,
  `evox/hardware/google/pixel-sepolicy/power-libperfmgr/hal_power_default.te`,
  `evox/device/lineage/sepolicy/libperfmgr/vendor/hal_power_default.te`,
  `evox/system/sepolicy/private/{hal_power.te,mls,domain.te}`,
  `evox/frameworks/base/libs/hwui/{Properties.cpp,renderthread/HintSessionWrapper.cpp}`,
  `evox/frameworks/native/services/surfaceflinger/{common/FlagManager.cpp,SurfaceFlinger.cpp,PowerAdvisor/PowerAdvisor.cpp}`,
  `evox/frameworks/base/services/core/java/com/android/server/power/hint/HintManagerService.java`,
  `evox/vendor/qcom/opensource/power/PowerHintSession.cpp`,
  `kernel/lineage/kernel/sched/{core.c,debug.c,walt/*}`, `kernel/lineage-devicetrees/qcom/parrot.dtsi`,
  `stock/dump/vendor/bin/init.kernel.post_boot-parrot.sh`, `stock/dump/vendor/etc/init/hw/init.qti.kernel.rc`.
* Nothing asteroids (SM7635): <https://github.com/hetnieuwebeginbv-glitch/android_device_nothing_asteroids/tree/lineage-23.2>
* AlphaDroid OnePlus sm8550-common: <https://github.com/AlphaDroid-devices/device_oneplus_sm8550-common/blob/alpha-16.2/configs/powerhint.json>
* AOSP-for-venus Xiaomi sm8350-common: <https://github.com/AOSP-for-venus/platform_device_xiaomi_sm8350-common/tree/bak>
* Klozz / XPerience sm8350-common (bad example): <https://github.com/Klozz/android_device_xiaomi_sm8350-common/blob/bka/power/powerhint.json>,
  <https://github.com/TheXPerienceProject/android_device_xiaomi_sm8350-common/blob/xpe-20.2/power/powerhint.json>
* Pixel Tablet: <https://android.googlesource.com/device/google/tangorpro/+/383c2db8399c0364122e57b1944fbca11f67720a/powerhint.json>,
  <https://github.com/GrapheneOS/device_google_tangorpro/blob/14/powerhint.json>
* Pixel ADPF sepolicy: <https://android.googlesource.com/platform/hardware/google/pixel-sepolicy/+/refs/heads/main/power-libperfmgr/hal_power_default.te>
* uclamp fork inheritance / ADPF discussion: <https://lkml.iu.edu/hypermail/linux/kernel/2304.2/04698.html>
* ADPF overview: <https://developer.android.com/games/optimize/adpf>
* Qualcomm "Google ADPF and QAPE": <https://docs.qualcomm.com/bundle/publicresource/topics/80-PK177-134/google_adpf_and_qape.html>
