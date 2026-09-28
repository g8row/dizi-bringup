# dizi (Redmi Pad Pro, SM7435 parrot) EvoX `bka` port: performance research

Scope: Evolution X Android 16 (`bka`), device tree forked from EvoX garnet, userdebug,
prebuilt GKI `5.10.246-android12-9` with stock Xiaomi modules, stock HyperOS OS3.0.303
vendor (A14, VNDK 32). Written 2026-09-26.

Facts checked locally in the tree and stock dump are marked **[local]**. Paths are
relative to `/build/alex/dizi`.

---

## 0. What this port does today (baseline facts)

| Area | Current state | Source |
|---|---|---|
| Power HAL | `android.hardware.power-service.lineage-libperfmgr` + `libqti-perfd-client` stub, `configs/power/powerhint.json` (byte-identical to EvoX garnet's) | [local] `evox/device/xiaomi/dizi/device.mk:269-298` |
| powerhint.json | 23 nodes (msm_performance min/max, kgsl, WALT sched_boost/migrate, core_ctl, bwmon, cpu_dma_latency); hints: INTERACTION, LAUNCH, CAMERA_*, SUSTAINED_PERFORMANCE. **No `AdpfConfig`, so ADPF hint sessions are reported as unsupported** | [local] |
| Kernel sched | `sched-walt.ko` loads from vendor_boot first stage; stock `init.kernel.post_boot-parrot.sh` sets the `walt` cpufreq governor, WALT up/down-migrate thresholds, core_ctl, `input_boost` (cpu0 1.8 GHz for 120 ms), bus_dcvs/bwmon | [local] `stock/unpacked/vendor_boot_b/ramdisk/lib/modules/`, `stock/dump/vendor/bin/init.kernel.post_boot-parrot.sh` |
| zram | Stock `init.kernel.post_boot.sh` creates a 4 GiB zram (50% of RAM, capped), `comp_algorithm` not set (kernel default `lzo-rle`), swappiness **180** (hardcoded for `dizi`/`ruan`), `compaction_proactiveness=0`, min_free_kbytes 11584 | [local] |
| zram.ko | Xiaomi build with "ExtM" writeback (`backing_dev`, `idle`, `writeback`); supports `lzo-rle` and `zstd` | [local] `strings zram.ko` |
| GKI config | `PSI=y`, `UCLAMP_TASK(_GROUP)=y`, `CGROUP_FREEZER=y`, `CRYPTO_LZ4=y`, `CRYPTO_ZSTD=y`, `DAMON_RECLAIM=y`, `IOSCHED_BFQ/KYBER/DEADLINE=y`, `F2FS_FS_COMPRESSION` (lz4/lz4hc/zstd), `EROFS_FS_ZIP=y`. **No `CONFIG_LRU_GEN` (no MGLRU)**. Full LTO + CFI, clang 12 | [local] ikconfig from `stock/unpacked/boot_b/kernel` |
| QTI perf HAL | Stock dump ships `vendor.qti.hardware.perf-hal-service`, `vendor/etc/perf/*` (perfboostsconfig with 79 configs, perfconfigstore, targetconfig), `powerhint.xml`, `libqti-perfd`-style libs. **The dizi port does not ship them.** efeisot_dizi does ship them; m0rf30/noble6 use xiaomi-libperfmgr | [local] `trees/ref/*/proprietary-files.txt` |
| SF props | Garnet-derived: `debug.sf.set_idle_timer_ms=1100`, `set_touch_timer_ms=200`, content detection on, durations app 13.67 ms / sf 12.33 ms (early=late), `game_default_frame_rate_override=120`, blur on | [local] `props/vendor.prop` |
| Dalvik heap | `tablet-10in-xhdpi-2048-dalvik-heap.mk` (growthlimit 192m, targetutil 0.75, maxfree 8m). That profile is meant for **2 GB** devices | [local] `device.mk:18` |
| ART | EvoX: `PRODUCT_USE_PROFILE_FOR_BOOT_IMAGE`, AOSP boot-image profile, `PRODUCT_DEXPREOPT_SPEED_APPS` (SystemUI, Launcher3QuickStep, Settings, ...), `dalvik.vm.systemuicompilerfilter=speed`, R8 for SystemUI/system_server | [local] `evox/vendor/lineage/config/{common,evolution}.mk` |
| Userdata | f2fs `fsync_mode=nobarrier` (same as stock), `atgc,gc_merge,age_extent_cache,compress_mode=user,compress_cache`, `inlinecrypt`, `checkpoint=fs` | [local] `rootdir/etc/fstab.qcom` |
| Read-only parts | erofs, AOSP default compressor `lz4hc,9` (no `BOARD_EROFS_*` overrides); super 9.1 GB | [local] `evox/build/make/core/Makefile:2149` |

---

## 1. Power / perf HAL on QTI

**Options**

1. **Stock QTI perf HAL** (`vendor.qti.hardware.perf@2.x` + `perfboostsconfig.xml`,
   `perfconfigstore.xml`, `targetconfig.xml`, `targetresourceconfigs.xml`) driven by
   the framework's `BoostFramework` (`QPerformance` in CAF frameworks/base). LineageOS
   frameworks do **not** carry BoostFramework/`libqti-perfd-client` hooks for launch or
   scroll boosts. So on EvoX the QTI HAL only gets requests from vendor clients (camera,
   display, thermal). It also pulls in IOP/prekill/`vendor.appcompact` features written
   for the QTI **lmkd** fork (`ro.lmk.enable_userspace_lmk`, `nstrat_*`), which AOSP
   lmkd does not read. Result: you carry a large blob stack for little gain. Useful as
   a *reference* for tuned opcodes and frequencies (the parrot launch boost, for example).
2. **Lineage/Pixel `power-libperfmgr`** (current choice). It is an AIDL Power HAL that
   receives framework `Boost`/`Mode` calls (INTERACTION, LAUNCH, DISPLAY_UPDATE_IMMINENT,
   SUSTAINED_PERFORMANCE, EXPENSIVE_RENDERING, GAME, ...) and writes sysfs nodes from
   `powerhint.json`. This is what all LineageOS QTI GKI devices do in 2024-2026.
   <https://github.com/LineageOS/android_hardware_lineage_interfaces/tree/lineage-23.0/power-libperfmgr>,
   <https://android.googlesource.com/platform/hardware/google/pixel/+/refs/heads/main/power-libperfmgr/>
3. **ADPF (hint sessions)**. The lineage-23 libperfmgr includes the Pixel ADPF stack
   (`PowerHintSession`, `UClampVoter`, `SessionChannel` [local]). It only activates if
   `powerhint.json` has an `AdpfConfig` (`AdpfConfigs` on newer versions) block. It sets
   per-thread `uclamp.min` for HWUI RenderThread/UI thread and game threads based on
   reported work durations. The GKI has `UCLAMP_TASK=y`, and `sched-walt.ko` references
   `uclamp_eff_value`/`uclamp_boosted` [local], so WALT does take uclamp into account
   when placing tasks. Docs: <https://developer.android.com/games/optimize/adpf>,
   Pixel libperfmgr ADPF implementation (`aidl/PowerHintSession.cpp` in the Pixel link above).

**Observations on the current powerhint.json**

- `INTERACTION` pins **all silver cores at max (1958400)**, gold min to 1497600, and sets
  `sched_boost=2` with busy hysteresis, for the duration the framework sends (touch and
  scroll). Stock WALT `input_boost` already raises cpu0 to 1.8 GHz for 120 ms per touch
  event, so the boost is applied twice. On a 12.1" tablet used for reading and video this
  can cost noticeable screen-on battery. It is a candidate for measured reduction, for
  example silver min ~1.4 GHz and no gold min.
- The json has no `DISPLAY_UPDATE_IMMINENT`, `EXPENSIVE_RENDERING` (GPU min freq), `GAME`
  or `AUDIO_*` actions. `EXPENSIVE_RENDERING` is cheap to add: the kgsl min_freq node
  already exists.
- `LAUNCH` (2 s): sched_boost=1, all cores min 1.5 GHz, gold max 2.4 GHz. This is reasonable.

**Verdict:** keep lineage-libperfmgr. Do **not** switch to the QTI perf HAL, because
nothing in EvoX's framework drives it. Stage B work: (a) re-tune INTERACTION against
the numbers in section 9, (b) add `EXPENSIVE_RENDERING`, (c) optionally add an
`AdpfConfig`. For (c), copy the structure from a lineage QTI GKI device and start with
conservative `UclampMin_High` (~400-512). Keep it only if `dumpsys gfxinfo` jank or
power improves; otherwise leave ADPF off.

---

## 2. Scheduler, uclamp, cpusets, task_profiles

- **WALT vs schedutil.** On parrot, WALT (`sched-walt.ko`) is loaded and owns core
  placement, core_ctl, input boost, RTG colocation and the `walt` governor. The GKI
  also has schedutil built in. Switching governors while WALT is loaded is untested by
  Qualcomm and loses core_ctl/input boost. **Keep WALT + walt governor** (the stock
  post_boot already does this). Pure EAS/schedutil is only realistic with a source
  kernel that drops WALT, and it is not worth doing on this SoC.
- **Knobs available with the prebuilt kernel** (userspace only, via init rc, post_boot
  or powerhint):
  `/proc/sys/walt/*` (up/down-migrate, sched_boost, input_boost, busy hysteresis,
  `sched_min_task_util_for_boost/colocation`), `/sys/devices/system/cpu/cpufreq/policy*/walt/*`
  (hispeed_freq/load, rate limits, `boost`, `rtg_boost_freq`), core_ctl, bus_dcvs/bwmon/L3,
  `/sys/kernel/msm_performance`, kgsl devfreq, cpusets, `cpu.uclamp.*` on cpuctl groups,
  per-task uclamp (through ADPF), vm sysctls, zram, block queue settings.
  Anything that needs new code (MGLRU, new governors, sched patches, zram recompression)
  needs a source kernel.
- **cpusets.** Stock post_boot sets background and system-background to 0-3 (silver).
  AOSP defaults: top-app 0-7, foreground 0-7 minus some. The EvoX init/vendor rc already
  creates `foreground/boost` and `camera-daemon`. Leave these alone.
- **task_profiles.json.** AOSP 16 system `task_profiles.json` plus an optional vendor
  override at `/vendor/etc/task_profiles.json` (the stock dump has none [local]).
  With WALT, `cpu.uclamp.latency_sensitive` and `uclamp.min` on the top-app group work
  as boosts. There is no need for a vendor override. Doc:
  <https://source.android.com/docs/core/perf/cgroups> (cgroup abstraction layer and task profiles), uclamp:
  <https://docs.kernel.org/scheduler/sched-util-clamp.html>.
- **sched boost at touch/launch.** This is already covered by WALT `input_boost` and
  libperfmgr INTERACTION/LAUNCH (section 1). Avoid layering a third mechanism (for
  example an init `property:` trigger that writes sched_boost).

**Verdict:** leave the scheduler at stock parrot values from post_boot. Tune only
through powerhint.json and measure.

---

## 3. Memory

- **lmkd.** AOSP lmkd in PSI mode (`ro.lmk.use_psi` defaults to true; no minfree levels).
  AOSP 16 defaults for a non-low-RAM device [local `system/memory/lmkd/lmkd.cpp`]:
  `psi_partial_stall_ms=70`, `psi_complete_stall_ms=700`, `thrashing_limit=100`,
  `thrashing_limit_decay=10`, `swap_free_low_percentage=10`. Pixel-style tuning for
  8 GB devices commonly sets `ro.lmk.swap_free_low_percentage=10`,
  `ro.lmk.thrashing_limit=30`-`100`, `ro.lmk.psi_partial_stall_ms=70`, and
  `ro.lmk.kill_heaviest_task=false`. The stock `perfconfigstore.xml` `ro.lmk.nstrat_*`
  and `enable_userspace_lmk` props are for the **QTI lmkd fork** and have no effect on
  AOSP lmkd, so do not copy them. Doc: <https://source.android.com/docs/core/perf/lmkd>,
  <https://android.googlesource.com/platform/system/memory/lmkd/+/refs/heads/main/README.md>.
  Verdict: start with AOSP defaults. Only if the device kills cached apps too eagerly
  (measure with `dumpsys activity lru`, `logcat -b events | grep lmk`), try
  `ro.lmk.thrashing_limit=50`/`ro.lmk.swap_util_max=90`.
- **zram.** Stock uses a 4 GiB zram at swappiness 180 with the default `lzo-rle`.
  - Algorithm: GKI has `CRYPTO_LZ4=y` and `CRYPTO_ZSTD=y`. **lz4** gives the lowest
    decompression latency (Pixel's default). **zstd** gives about 25-35% better ratio
    at 2-3x the CPU cost per fault. For an 8 GB tablet with 4x A78, lz4 is the latency
    choice and zstd the "more cached apps" choice. Recommendation: **lz4**, set before
    `disksize` (a vendor `init.dizi.rc` hook that runs before post_boot, or through
    fstab `zramsize=` + `swapon_all`). Verify: `cat /sys/block/zram0/comp_algorithm`.
    Check whether Xiaomi's zram.ko registers lz4 before relying on it: `strings` found
    only `lzo-rle`/`zstd` literals, but the algorithm list comes from the crypto API.
  - Size: 50% of RAM (4 GiB) is fine. Pixel uses 50-60%, some custom ROMs use 100%.
    More zram with MGLRU missing mostly adds kswapd CPU time. Keep 4 GiB.
  - Writeback: the Xiaomi "ExtM" zram.ko supports `backing_dev`/`writeback`. AOSP 16's
    **mmd** (memory management daemon) can manage zram writeback. Recompression needs
    kernel 6.2+ multi-comp, which 5.10 does not have. Writeback adds flash wear and
    latency. Verdict: **skip** on stock kernel. Doc: <https://source.android.com/docs/core/perf/mmd>,
    <https://docs.kernel.org/admin-guide/blockdev/zram.html>.
- **MGLRU:** `CONFIG_LRU_GEN` is absent in this 5.10 GKI [local]. It is on by default
  only in android14-5.15/6.1+. It cannot be added with a prebuilt kernel. A source
  kernel backport exists in some community 5.10 kernels but is invasive. Verdict:
  **skip** (or source-kernel stretch goal).
  <https://docs.kernel.org/admin-guide/mm/multigen_lru.html>
- **DAMON_RECLAIM** is built in (`CONFIG_DAMON_RECLAIM=y`) and off by default. It is
  generally untested with Android's memcg/lmkd. **Skip.**
- **Dalvik heap:** the current `tablet-10in-xhdpi-2048` profile is for 2 GB devices
  (growthlimit 192m, maxfree 8m means frequent GC for 2560x1600 bitmaps). The HyperOS
  stock product props are exactly `phone-xhdpi-6144-dalvik-heap.mk` (growthlimit 256m,
  heapsize 512m, targetutil 0.5, minfree 8m, maxfree 32m) [local]. **Switch to
  `phone-xhdpi-6144-dalvik-heap.mk`** (covers the 6/8 GB SKUs and also adds
  time-based GC trigger, USAP pool, and JIT sizes). Inherit it before anything else
  that sets `dalvik.vm.*` with `?=`, because the first `?=` wins.
- **ART GC:** stock sets `ro.dalvik.vm.enable_uffd_gc=true`. On A16, ART selects the CMC
  (userfaultfd) GC automatically on 5.10+. Verify with
  `logcat | grep -i 'CollectorTypeCMC\|userfaultfd'`. There is nothing to force.
- **Cached app freezer / app compaction:** these are framework features
  (`CachedAppOptimizer`), on by default in A16 and controlled through DeviceConfig
  (`activity_manager_native_boot`). `CGROUP_FREEZER=y` is in the GKI. Check
  `dumpsys activity settings | grep -i freez` and
  `adb shell cat /sys/fs/cgroup/uid_*/pid_*/cgroup.freeze`. The Xiaomi `millet_binder.ko`
  / `binder_prio.ko` modules are HyperOS's freezer assist and are unused by AOSP.
  <https://source.android.com/docs/core/perf/cached-apps-freezer>
- `ro.config.low_ram=false` is correct. Do not set `ro.config.per_app_memcg` unless
  lmkd needs it.

---

## 4. ART / dexpreopt

- Defaults (AOSP 16): apps use `speed-profile` when a profile exists, otherwise `verify`.
  The boot image uses a profile when `PRODUCT_USE_PROFILE_FOR_BOOT_IMAGE` is set (EvoX
  sets it with the AOSP generic `boot-image-profile.txt`). system_server jars are
  compiled `speed-profile` from framework profiles.
  <https://source.android.com/docs/core/runtime/configure>,
  <https://source.android.com/docs/core/runtime/configure/art-service>
- EvoX already compiles SystemUI, Launcher3QuickStep, Settings and a few others with
  `speed` (`PRODUCT_DEXPREOPT_SPEED_APPS`) and sets `dalvik.vm.systemuicompilerfilter=speed`.
  The cost is a few tens of MB on system/product. Super is 9.1 GB, so size is not a
  constraint.
- **Do not** set `PRODUCT_DEX_PREOPT_DEFAULT_COMPILER_FILTER=speed` globally. It inflates
  images and page-cache footprint, and cold-start gains over speed-profile are small or
  negative because of larger odex I/O.
- `DONT_DEXPREOPT_PREBUILTS := true` (Lineage) means GApps and prebuilt apps get compiled
  on device by ART Service (first boot or bg-dexopt). This is expected: first boot is
  slower and later boots are fine. Cloud profiles from Play apply automatically to
  store-installed apps when GMS is present. Nothing to configure.
- `WITH_DEXPREOPT_DEBUG_INFO := false` and `PRODUCT_MINIMIZE_JAVA_DEBUG_INFO` only apply
  to `user` builds in Lineage `common.mk`. On userdebug images are slightly bigger, which
  is fine.
- Boot image profile: a device-specific profile (collected with
  `pm dump-profiles --dump-classes-and-methods` / `art/tools/boot-image-profile`) gains
  at most a few percent. **Skip.**
- Verdict: **leave ART config as is.** Run `adb shell pm art dexopt-packages -r bg-dexopt`
  (or `cmd package bg-dexopt-job`) before benchmarking so the results are not skewed by
  apps still running in `verify`.

---

## 5. Graphics / UI (120 Hz, Adreno 710)

- **Refresh rate switching.** The panel supports multiple modes (check with
  `dumpsys display | grep -i 'supportedModes\|fps='`). Relevant props
  (<https://source.android.com/docs/core/graphics/multiple-refresh-rate>,
  <https://source.android.com/docs/core/graphics/surfaceflinger-props>):
  - `ro.surface_flinger.use_content_detection_for_refresh_rate=true`: keep.
  - `debug.sf.set_idle_timer_ms=1100` (port) vs `50000` (HyperOS, which relies on its own
    DFPS in displayfeature). With AOSP SF, 1100 ms is sensible: it drops to the minimum
    mode when idle. Keep it; consider 500-800 ms if idle power is high.
  - `ro.surface_flinger.set_touch_timer_ms=200`: keep.
  - Add `ro.surface_flinger.set_display_power_timer_ms=1000`, as Pixel does.
  - `config_defaultPeakRefreshRate=120`, `config_defaultRefreshRate=0`: fine. Keyguard
    max 60: fine.
  - `ro.surface_flinger.game_default_frame_rate_override=120` (port) vs 60 (stock).
    Games at 120 on a 10000 mAh tablet burn power and heat up. **Set 60** to match stock.
- **Phase offsets / durations.** `use_phase_offsets_as_durations=1` with app 13.67 ms +
  sf 12.33 ms = 26 ms, which is more than 3 vsyncs at 120 Hz (8.33 ms). That gives more
  buffering and more touch latency, but fewer missed frames. early/earlyGl = late
  duplicates remove the early-phase benefit. Garnet uses the same values. Treat changes
  as an experiment: measure `dumpsys SurfaceFlinger --latency` / perfetto
  FrameTimeline before changing (a common 120 Hz set is sf ~ 1 vsync + margin, app
  ~ 1.5-2 vsyncs). Do not blindly copy stock's `latch_unsignaled=1` or
  `disable_backpressure=1`, which are HyperOS-specific trade-offs.
- **RenderEngine / HWUI backend.** A16 AOSP defaults: HWUI `skiagl`, SF RenderEngine
  `skiaglthreaded` unless the device opts in to Vulkan (`ro.hwui.use_vulkan=true`,
  `debug.renderengine.backend=skiavkthreaded`, as Pixel does). On Adreno with an A14
  vendor Vulkan driver (VNDK 32), skiavk works on many SD7xx devices but has
  historically shown driver-specific glitches (blur, protected content, first-frame
  shader compile hitches). Verdict: **stay on skiagl for Stage A**. In Stage B, A/B test
  `debug.hwui.renderer=skiavk` (runtime prop, needs an app restart) with gfxinfo. Adopt
  it only if jank p90/p95 and power are no worse. Don't set it in the build before
  that. Check what is active: `dumpsys SurfaceFlinger | grep -i renderengine`,
  `dumpsys gfxinfo <pkg> | grep Pipeline`.
  Background: <https://source.android.com/docs/core/graphics/renderer> (HWUI),
  community SkiaVK notes <https://github.com/dyokism/SkiaVK>.
- **Blur.** `supports_background_blur=1` (EvoX default, `TARGET_ENABLE_BLUR`). Blur at
  2560x1600 costs extra GPU composition passes, which is noticeable on Adreno 710 in
  notification shade and recents. Keep it (EvoX UX expectation), but if shade jank
  appears, the fix is `TARGET_ENABLE_BLUR := false` or the
  `persist.sysui.disableBlur`/"Reduce transparency" toggle rather than SF hacks.
- `ro.hwui.*` cache size props present in stock (`texture_cache_size`, `layer_cache_size`,
  ...) are **dead since the Skia pipeline** (Android 9+). Do not carry them.
- `debug.sf.hw=0` / `debug.egl.hw` / `persist.sys.ui.hw`: placebo, remove if you add any.
- `vendor.display.enable_optimize_refresh=0` (from garnet): QTI display HAL knob. Leave it.

---

## 6. Storage / IO

- **userdata:** f2fs (stock also uses f2fs). The mount options are already the modern set
  (`atgc,gc_merge,age_extent_cache,compress_cache,inlinecrypt,checkpoint=fs`).
  `compress_mode=user` only compresses files that ART or apps explicitly request, which
  is harmless. **`fsync_mode=nobarrier` is Xiaomi's stock choice.** It improves fsync
  latency but risks data loss on sudden power loss. A tablet with a 10000 mAh battery
  rarely loses power abruptly, so matching stock is acceptable. Note it as a deliberate
  choice.
- **erofs for system:** already used. The AOSP default compressor is `lz4hc,9` with 4K
  pcluster. Options: `BOARD_EROFS_PCLUSTER_SIZE := 262144` (bigger pcluster gives a better
  ratio but more read amplification) or `BOARD_EROFS_COMPRESSOR := lz4hc,12`. Pixel uses
  `lz4hc` with default or 16K pcluster. Decompression is cheap with lz4 either way, and
  super has space. **Keep defaults.** Do not use `lzma`/`deflate` on system: they save
  space at a real CPU cost on page faults. <https://source.android.com/docs/core/architecture/android-kernel-file-system-support>
- **read-ahead:** stock init.qcom.rc sets dm-* read_ahead 2048 KB during boot and 512 KB
  after `sys.boot_completed`. post_boot sets 512 on dm/sd. The dizi `init.qcom.rc` keeps
  this [local]. Good, leave it.
- **I/O scheduler:** GKI has mq-deadline, kyber, bfq. For UFS the Android default is
  usually `none`/mq-deadline (check `cat /sys/block/sda/queue/scheduler`). BFQ helps
  interactive latency under heavy background writes but costs CPU. Leave the default,
  and change it only if perfetto shows block-layer stalls during installs/updates.
- **UFS:** clkgate disabled during boot and re-enabled after (stock) [local]. `discard`
  mount option plus `discard_max_bytes=128M` (stock). Keep.
- **fstrim / f2fs GC:** Android's `StorageManagerService` runs idle maintenance (fstrim
  and f2fs GC through vold, `IdleMaint`) daily when idle and charging. Leave it alone.
  `checkpoint_gc` for OTA is already in device.mk.

---

## 7. Build-level (toolchain)

- **ThinLTO:** on by default for all 64-bit device modules in AOSP 16 soong
  (`ltoDefault := true` unless `DISABLE_LTO`) [local `build/soong/cc/lto.go`]. Nothing to
  do.
- **AutoFDO/PGO:** AOSP ships sampled AFDO profiles in `toolchain/pgo-profiles/sampling`
  (ART, bionic, hwui, SF, ...). They apply automatically to modules with `afdo: true`.
  <https://source.android.com/docs/core/perf/autofdo>, <https://source.android.com/docs/core/perf/pgo>.
  Collecting dizi-specific ETM profiles is not feasible or worthwhile here.
  Kernel AutoFDO only exists for android15-6.6/android16-6.12
  (<https://android-developers.googleblog.com/2026/03/BoostingAndroid%20PerformanceIntroducingAutoFDO.html>),
  so it does not apply to 5.10.
- **-O3 / Polly / `-march` tweaks** (seen in some custom ROMs and kernels): no reproducible
  evidence of user-visible gains on Android userspace. They increase code size (I-cache
  pressure on the A55s) and often break ABI or determinism. Upstream AOSP already builds
  `-O2` + ThinLTO + AFDO for hot libraries. **Placebo at best; skip.** For a source
  kernel, the LineageOS kernel toolchain defaults (clang + ThinLTO) are fine. Kernel
  `-O3`/Polly patches are cosmetic.
- **ccache:** worth it for rebuild speed only (not runtime). Lineage `BoardConfigKernel.mk`
  honours `USE_CCACHE` with a system ccache. Use `export USE_CCACHE=1
  CCACHE_EXEC=/usr/bin/ccache`, `ccache -M 50G`. This speeds up iterations, not the device.

---

## 8. Placebo / harmful tweaks to avoid

| Tweak | Why not |
|---|---|
| `ro.hwui.*_cache_size`, `debug.sf.hw=1`, `persist.sys.ui.hw=1`, `debug.egl.hw=1`, `video.accelerate.hw` | Dead props (pre-Skia or pre-Android 5) |
| `windowsmgr.max_events_per_sec`, `ro.max.fling_velocity`, `touch.pressure.scale` | Removed long ago or placebo; touch latency is SF/kernel |
| `dalvik.vm.dex2oat-filter=speed` / `pm.dexopt.*=speed` globally | Larger odex, more I/O and RAM, longer installs |
| `ro.config.low_ram=true`, custom `ro.lmk.minfree_*` | Breaks the PSI lmkd model and hurts multitasking |
| `swappiness=100`/`vm.vfs_cache_pressure` edits from "RAM boosters" | Stock 180 is tuned for zram; untested changes cause more thrashing |
| Forcing `performance` governor, `sched_boost=1` permanently, disabling core_ctl | Thermal throttling kicks in sooner, sustained perf drops, battery collapses |
| Disabling `mi_thermald`/`thermal-engine-v2` or loading "nolimits" thermal conf | Skin temperature/safety risk; A78 boost drops later anyway |
| Disabling cached app freezer or app compaction | More background CPU, worse standby |
| Killing `logd`, lowering `persist.logd.size`, disabling `statsd`/`perfetto` | Negligible gain; loses diagnostics |
| `debug.sf.latch_unsignaled=1`, `disable_backpressure=1` copied from HyperOS | Tearing/glitches without Xiaomi's SF changes |
| `-O3`/Polly/`-march=armv8.2-a+...` global flags | Section 7 |
| `debug.hwui.renderer=skiavk` set blindly at build | Section 5; needs A/B |
| Aggressive `fstrim` cron or `f2fs gc_urgent` permanently on | Flash wear, idle power |

---

## 9. Measurement protocol (EvoX vs stock HyperOS baseline)

HyperOS OS3.0.303 is the baseline on the same unit (the stock backup exists in
`stock/backup`). Run each scenario on both ROMs.

**Preconditions (both ROMs):** same unit, battery 60-80%, 25 °C ambient, screen
brightness fixed (for example 200 nits: `settings put system screen_brightness_mode 0`
and a fixed value), Wi-Fi on and same AP, airplane otherwise, no SIM (dizi has none),
same app set installed (Chrome, YouTube, a heavy game such as Genshin or a Vulkan
benchmark, a large RecyclerView app), and apps fully dexopted
(`adb shell pm art dexopt-packages -r bg-dexopt`). Reboot, wait 5 min after
`sys.boot_completed`, and run each measurement 5x, reporting the median.

1. **Boot time.** `adb shell getprop ro.boottime.init` and the `boot_progress_*` events
   (`adb logcat -b events -d | grep boot_progress`), plus
   `adb shell cmd stats print-stats`/`dumpsys boot`. Record the time to
   `sys.boot_completed=1` (script: `adb reboot; adb wait-for-device; t0; until getprop
   sys.boot_completed = 1`). For detail, capture a perfetto boot trace
   (`persist.debug.perfetto.boottrace=1`,
   <https://perfetto.dev/docs/case-studies/android-boot-tracing>) or bootchart
   (`touch /data/bootchart/enabled`). <https://source.android.com/docs/core/perf/boot-times>
2. **App startup.** `am force-stop <pkg>; echo 3 > /proc/sys/vm/drop_caches` (root) for
   cold starts, then `am start -W -S -n <pkg>/<activity>` and read `TotalTime`. Use
   Settings, Chrome, Camera, and YouTube, cold and warm, 10 runs each.
   <https://developer.android.com/topic/performance/vitals/launch-time>
3. **UI jank.** `dumpsys gfxinfo <pkg> reset`, run a scripted fling
   (`input swipe 1280 1400 1280 300 150` x30 in Settings/Chrome, notification shade
   pull x20, recents x20), then `dumpsys gfxinfo <pkg>`: report janky frames %, p50/p90/p95/p99
   frame time, and "Missed Vsync"/"Slow UI thread". For system UI use `dumpsys gfxinfo
   com.android.systemui`. Also run the perfetto FrameTimeline track (see 6).
4. **Memory / multitasking.** Open 15 apps in sequence, then cycle back and count how
   many are still warm (`am start -W` shows `LaunchState: HOT/WARM/COLD`). Also record
   `dumpsys meminfo` summary, `cat /proc/pressure/memory`, `/sys/block/zram0/mm_stat`,
   and `logcat -b events | grep -c am_kill`.
5. **Battery / standby.** `dumpsys batterystats --reset`, then (a) 30 min local 1080p
   video loop at fixed brightness, (b) 30 min scripted web scroll, (c) 8 h overnight idle
   on Wi-Fi. Collect `dumpsys batterystats`, `/sys/power/suspend_stats` (success count,
   fail), `/sys/kernel/debug/wakeup_sources` or `dumpsys suspend_control_internal`,
   `cat /sys/class/power_supply/battery/{capacity,current_now}` sampled every 10 s.
   Record %/h and mA average. Upload `bugreport` to Battery Historian if needed.
6. **Scheduler / frequency.** Perfetto config with `linux.ftrace` (sched_switch,
   cpu_frequency, cpu_idle, sched_wakeup) + `android.surfaceflinger.frametimeline` +
   `linux.process_stats`, 10 s during fling and during app launch:
   `adb shell perfetto -o /data/misc/perfetto-traces/t.pftrace -t 10s sched freq idle
   am wm gfx view binder_driver hal dalvik power` and open it at <https://ui.perfetto.dev>.
   Use it to check whether INTERACTION or LAUNCH boosts actually fire (look for the
   `PowerHAL` atrace counters from libperfmgr) and whether RenderThread lands on gold cores.
7. **Thermals / sustained.** Run 3DMark Wild Life Extreme Stress Test or GFXBench Manhattan
   long-term (20 loops) and record the stability %. Also record
   `dumpsys thermalservice` and `cat /sys/class/thermal/thermal_zone*/temp`
   (cpu/skin/battery) every 10 s. Geekbench 6 single/multi as a sanity check (it should
   be about equal to stock because the kernel and firmware are the same).

Put the results in a table (stock / EvoX Stage A / EvoX Stage B), one change per build
when tuning. Accept a change only if it wins on its target metric without losing
more than 3% battery in scenarios 5a/5b.

---

## 10. Prioritized list

### Do now (Stage A/B, prebuilt kernel)

1. **Dalvik heap:** replace `tablet-10in-xhdpi-2048-dalvik-heap.mk` with
   `phone-xhdpi-6144-dalvik-heap.mk` (matches HyperOS values and adds USAP, time-based GC).
2. **Game frame rate override:** `ro.surface_flinger.game_default_frame_rate_override=60`
   (stock value), and add `ro.surface_flinger.set_display_power_timer_ms=1000`.
3. **Keep lineage-libperfmgr**, but measure the INTERACTION hint with the section 9
   protocol and likely soften it (silver min below max, drop gold min, keep sched_boost).
   Add an `EXPENSIVE_RENDERING` action (kgsl min_freq). Do **not** add the QTI perf HAL
   stack.
4. **zram:** switch to lz4 before the post_boot `disksize` write, if lz4 is available in
   `/sys/block/zram0/comp_algorithm`. Keep 4 GiB and swappiness 180.
5. **Keep stock post_boot WALT tuning, read-ahead, UFS clkgate and f2fs options.** Do not
   add sched/vm tweaks on top.
6. **Verify at runtime** (no build change): CMC GC active, freezer active,
   `comp_algorithm`, RenderEngine backend, supported display modes, and dexopt state
   before benchmarks.
7. **Benchmark protocol** (section 9) against HyperOS: boot, 4 app cold starts, gfxinfo
   fling, 30 min video/web drain, overnight idle, sustained GPU loop.
8. Stage B experiments, one per build, measured: `debug.hwui.renderer=skiavk` +
   `skiavkthreaded` RenderEngine; ADPF `AdpfConfig`; SF duration re-tune for 120 Hz;
   lmkd `thrashing_limit`.
9. ccache on the build host (`USE_CCACHE=1`) to speed up these iterations.

### Later (source kernel, LineageOS android_kernel_xiaomi_sm7435)

- Rebuild the same WALT configuration first (parity), then evaluate a MGLRU backport and
  zram multi-comp/recompression (enables mmd recompression) if the kernel base allows it.
- Tune from the kernel: WALT defaults, `input_boost` removal if the HAL covers touch,
  and uclamp-aware WALT patches from newer CLO releases.
- Kernel ThinLTO+CFI stays as it is in upstream defconfig. No `-O3`/Polly.
- Retune zram sizing after MGLRU.

### Skip

- QTI perf HAL / perfd / IOP / QTI-lmkd props (`ro.lmk.nstrat_*`, `vendor.appcompact.*`).
- Global `speed` dexpreopt, device-specific boot image profile.
- `-O3`, Polly, custom `-march`, "kernel AutoFDO" (not for 5.10).
- zram writeback / mmd on the stock kernel, DAMON_RECLAIM, MGLRU on prebuilt (impossible).
- Legacy build.prop "tweaks" (section 8), disabling thermal daemons, forcing governors.
- Changing erofs compressor or pcluster (defaults are fine) and changing the I/O scheduler
  without evidence.
- Porting HyperOS SF props (`latch_unsignaled`, `disable_backpressure`, idle timer 50000).

## 11. Measured on the device (b21, 2026-09-27)

QS pulldown (tools/ui-jank.sh QS_ONLY, landscape, 20 cycles), trace logs/build-21/trace/qs-b21.pftrace:

- Jank 5.97-6.13%, p99 38-42 ms. The "slow UI thread" frames are **not** CPU work in SystemUI:
  its main thread sleeps 3.4 s (runs 0.7 s) inside `draw-VRI[NotificationShade]`, waiting for its
  RenderThread. The RenderThread spends 3.7 s in `dequeueBuffer`/`waitForBufferRelease`; each
  frame renders in ~1 ms. **SystemUI is starved of buffers by SurfaceFlinger.**
- SurfaceFlinger: 785 of 822 frames are client-composited (shade blur over wallpaper/launcher).
  RenderEngine `drawLayers` averages 4.4 ms, GPU completion 5.3 ms, HWC `present` 7.2 ms
  (max 36 ms). finishFrame + present exceeds the 8.3 ms budget at 120 Hz.
- **Vulkan RenderEngine (`debug.renderengine.backend=skiavkthreaded`, the Pixel setting) is much
  worse on Adreno 710:** 31.8-35.8% jank, p50 32-34 ms (GL p50 9 ms). Rejected. Don't retry
  without a newer vendor Vulkan driver.
- ADPF won't help much here: the stall is buffer release, not CPU time in the app.
- Next: the stock libsdmcore hybrid (HWC present time), then the HWC present path itself
  (PerformHwCommit breakdown) and the SF buffer/latch settings.
- **Correction (warm runs):** the first QS run after `stop; start` is always worse (shader compilation):
  GL 8.6% cold vs 4.75% / 5.17% warm. Compare only warm runs.
- **Vulkan Graphite** (`debug.renderengine.backend` unset + `debug.renderengine.graphite=true`):
  11.9% cold, **4.90% / 5.34% warm, p50 9 ms: parity with GL**, before any priority fix. Ganesh-Vulkan
  (`skiavkthreaded`) stays bad (31.8% on its second run). Driver: VK_EXT_global_priority v2 without the query
  extension, so RE's queue is MEDIUM. Patch in evox/frameworks/native (VulkanInterface.cpp: try
  REALTIME -> HIGH -> MEDIUM); test Graphite + patch in b24 (research/vulkan-adreno710.md).

## 12. GPU vs display-engine composition (b24/b25, 2026-09-27)

- Stock HyperOS composes on the DPU (SDE pipes, `Device/Device`). Ours sent **every layer to the GPU
  in landscape** (`Device/Client` for all layers, SDM table shows only GPU_TARGET), even on the idle
  home screen, which has been true since at least b16.
- Cause: in landscape the wallpaper is a 2560x1600 buffer with ROT_90 plus a ~1.10x zoom crop.
  With `vendor.display.enable_rotator_ui=1` (set by init.qti.display_boot.sh, same as stock)
  the strategy tries the inline rotator, `ResourceImpl::DoPrepare: Resource reserving failed`, and
  the whole stack falls back to GPU. With `enable_rotator_ui=0` only the wallpaper goes to the GPU
  and the launcher, bars and decor go to SDE pipes. Portrait was already fine (Device/Device).
  Fixed in init.dizi.rc (b26).
- The QS pulldown stays ~5% either way: SF forces client composition for the layer that requests
  background blur and everything under it (Output.cpp `findLayerRequestingBackgroundComposition`),
  so the shade is GPU-composed by design. The frame timeline shows SF stuffing and SF GPU deadline
  misses, not app misses. GPU runs at ~875 of 940 MHz while doing it. The blur algorithm made no
  difference (kawase / kawase2 / kawase2_fix_aliasing all ~5%). Next: SF latch/backpressure props.
- **b26 result:** with enable_rotator_ui=0 the landscape home is fully Device/Device, wallpaper included.
  Settings fling 0.09-0.18% (p99 10 ms, was 0.71% / 22 ms), launcher 1.6-2.1% (was 4.3%),
  client-composited frames 97% -> 54% over the ui-jank run. The QS pulldown is unchanged (~5.6%, blur).
- **QS composition breakdown (b26):** with the shade open there are 7 layers (the 2 ScreenDecor corner
  overlays included), which overflows the DPU (3 real + 3 virtual pipes): all layers go to the GPU even
  with blur off. Decorations off + blur off: 0 client frames, 3.31% jank. Decorations off + blur on:
  5.3-5.7% (the blur forces client anyway). The composer has no DisplayDecoration (HW rounded corner)
  support, so SystemUI has to use the overlays. Stock HyperOS uses 20dp corners, probably via
  Xiaomi's RC path.
- Fabricated overlays can't carry dimens on this build (`cmd overlay fabricate` only accepts int
  types), so the blur radius needs a build: b27 sets max_shade_window_blur_radius 34dp -> 20dp.
- `debug.sf.enable_layer_caching=1` (SF planner): **worse**, 7.3-8.5%. Rejected.
- **b27 race:** the init.dizi.rc property overrides raced with CAF's init.qti.display_boot.sh; on b27 the
  composer started with enable_rotator_ui=1 (idle home all GPU, QS 44%). Fixed in 541c516 (b28): the parrot
  values are static build.prop entries, and the script and overrides are gone.
- **Blur radius 20dp vs 34dp** (composer fixed): 5.5% vs 5.6%. No effect; reverted.
- **EXPENSIVE_RENDERING GPU floor 940 MHz** (was 734): 4.70-5.09% (p90 17 ms) vs ~5.5% (p90 19 ms). Kept (b394fce, b29).
- Remaining QS floor ~4.7% = GPU composition of the full-screen layers under the blurred shade at
  2560x1600@120. Only faster GPU work (driver, blocked) or less of it (fewer/smaller layers under the
  shade) can move it.

## 13. Recents / overview (b29, 2026-09-28)

tools/recents-jank.sh: 5 apps in recents, then 10 x (APP_SWITCH, fling right/left, HOME), launcher gfxinfo.
- Landscape: **23.6-24.1% janky, p50 26 ms**, 964-989 slow-UI-thread frames, 71% GPU-composed.
- Trace (logs/build-29/trace/recents.pftrace): the overview animation runs frames inside a nested handler
  (x9.e, ~420 ms). Each frame draws the Taskbar and launcher windows, both blocked in dequeueBuffer.
  SF GPU completion averages 7.3 ms. Task-snapshot binder calls on LauncherBgIO take ~24 ms each (52 calls).
- Blur off: **2.99%, p50 11 ms**. Portrait (30dp depth blur): 7.31%.
- Cause: Pixel Launcher `dimen/max_depth_blur_radius_enhanced` is 30dp but **600dp in values-land**.
  LauncherOverlayDizi (96fda0a, b31) sets landscape to 30dp.

## 14. Intermittent 60 Hz panel on boot (b27, b31: "44 ms frames")

- Symptom on some boots: every animation runs at ~44 ms per frame (QS ~70%, recents ~55%) while
  CPU/GPU are at max clocks and SF reports the 120 Hz mode active. Props and the idle composition
  are identical to good boots. A composer restart or a mode change fixes it.
- Cause: HW vsync arrives every **~16.5 ms** (60 Hz), while SF schedules for 8.33 ms. The panel still
  runs the bootloader's timing. dmesg: bad boots have a **single** `dsi_display_set_mode` (120 Hz,
  same as the "current" mode, so the panel isn't reprogrammed). Good boots go 120 -> 30 -> 120 around
  8 s and 16.8 s, which programs it for real.
- Frequency: 4 of 8 boots in a reboot loop (tools/boot-health.sh, logs/build-31/boot-health-034422).
- Fix: XiaomiParts forces a 60 -> 120 Hz round trip at LOCKED_BOOT_COMPLETED (restoring the user's
  min/peak refresh settings), parts RefreshRateKick (b32). Manual test on a bad boot: QS 69.8% -> 5.2%.
- Proper fix later (kernel stage b, source display driver): force a full mode set on the first
  commit after the continuous-splash handoff.
- Note: the b27 blur-radius and b31 recents measurements ran on bad boots. Re-measure on good boots.
- Kernel side (MiCode vendor_opensource_display-drivers, dsi_display.c): during the continuous-splash
  handoff `is_skip_op_required()` skips the panel/host programming, so the panel keeps the
  bootloader's setup. The first 120 Hz `dsi_display_set_mode` matches `cur_mode`, so nothing forces
  a DFPS update. For stage (b) with a source msm_drm: after `dsi_display_cont_splash_config()`, mark
  the mode dirty (or force a DFPS/timing update on the first commit that leaves splash), then drop
  the XiaomiParts workaround.

## 15. zram lz4, ADPF, Dalvik profile (b34-b36, 2026-09-28)

tools/app-start.sh (cold: median of 3 after force-stop; return: after opening all 9 apps).
- **zram lz4 vs lzo-rle** (b35 vs b34): cold and hot times within noise (hot sum 1387 vs 1381 ms). Ratio 3.0:1
  vs 3.5:1. Kept lz4 (standard, faster decompression); no visible gain on this workload.
- **ADPF** (b36, 725a92f): sessions work under enforcing, RenderThread/UI uclamp.min up to 512 during flings,
  0 at idle, 0 denials. Jank within noise (the bottlenecks are GPU/SF). Kept for apps and games that use the
  performance hint API. SF hints (debug.sf.enable_adpf_cpu_hint) not enabled.
- **Dalvik phone-xhdpi-6144 vs tablet-2048** (live props + zygote restart, USAP pool on): cold starts
  equal or slightly worse (Settings 554 vs 540, Chrome 354 vs 328 ms), hot marginally better, jank equal.
  **Rejected**, keeping the tablet profile (the user's intuition was right).

## 16. Opening an app from Recents (release-1, b39, 2026-09-28)

`tools/recents-open-jank.sh` (user-build safe): from home, enter overview, tap the Settings or Chrome task
card (found by name in a UI dump), wait 2 s, go home. 10 cycles, warm second run.

| Run | launcher hwui janky | display timeline janky | SF missedFrames | clientComposition | sfLongGpu (of janky) |
|---|---|---|---|---|---|
| b39 userdebug, landscape | 8.15% | 14.8% | 638 / 3541 | 801 | 1027 / 1266 |
| release-1 user, landscape | 7.24% | 13.5% | 853 / 3383 | 1231 | 949 / 1108 |
| release-1, window blurs off | 6.90% | 13.0% | 849 / 3417 | 1253 | – |
| release-1, portrait | 6.71% | 13.1% | 873 / 3315 | 2491 | 930 / 1081 |

- **Findings:**
  - The release is not a regression; b39 is the same.
  - About 90% of the janky frames are SurfaceFlinger GPU composition running long (`sfLongGpuJankyFrames`).
    The rest are app deadline misses. `appBufferStuffing` (3-6k) is the backpressure that follows, not a cause.
- **What it is not:**
  - **Blur:** during the open animation the launcher layer carries `backgroundBlurRadius=60`, which forces it and
    the wallpaper to GPU composition. But `disable_window_blurs=1` changes nothing.
  - **Wallpaper rotation:** in landscape the wallpaper (2560x1600, ROT_90) is GPU-composed even at rest, because
    the inline rotator tops out at 1200 lines (`in_rot_maxheight`); see e91e6e2 for why `enable_rotator_ui=0`. But
    portrait, which needs no rotation, janks the same.
- **Composition during the animation:** mid-animation captures show the whole stack briefly CLIENT, plain app
  layers included. The HWC strategy drops to GPU, and then the GPU pass is slow.
- **Hypothesis (unverified):** the GPU clock is low when the transition starts. `LAUNCH` (sent by
  `startActivityFromRecents` and by going home, via `RootWindowContainer.startPowerModeLaunchIfNeeded`) boosts only
  the CPU. `INTERACTION` floors the GPU at 600 MHz and `EXPENSIVE_RENDERING` at 940 MHz.
  - Candidate fix: **build-42** (experiment/launch-gpu, `LAUNCH` → kgsl `min_freq` 734 MHz for 2 s).
  - Verify with `tools/recents-open-trace.sh` + `tools/perfetto/recents-open.sql` (jank per phase, GPU MHz per
    phase), and on userdebug by writing `min_freq` live.
