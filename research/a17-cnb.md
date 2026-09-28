# Moving to Evolution X on Android 17 (`cnb`)

State as of 2026-09-28.

## Upstream status

* **Evolution X `cnb`** (Android 17, `android-17.0.0_r1`, CP2A, Lineage `lineage-24.0` base). Work
  started on 2026-06-17. The manifest is still moving: its latest commit, "Initialize for Evolution X
  12.2+", is from 2026-09-28. A 2026-09-28 commit "Temporarily track lineage-23.2 branch for our
  repos" pins 34 Lineage repos back to 23.2 (Dialer, Messaging, bash, htop, the sm7250 HALs, ...).
  **Only 3 devices are official on cnb** (OTA `cnb`: marble, raphael, venus). bka has around 100.
* **LineageOS 24.0** is not released. There are branches, including `hardware/qcom-caf/common`,
  the `sm8450` HALs (`lineage-24.0-caf-sm8450`), `sepolicy_vndr` and `hardware_xiaomi`. **Lineage
  garnet / `kernel_xiaomi_sm7435` have no 24.0 branch** (latest is 23.2).
* **The EvoX garnet trees have `cnb` branches.** `device_xiaomi_garnet`, `vendor_xiaomi_garnet`,
  `kernel_xiaomi_garnet{,-modules}`, `hardware_xiaomi` (`cnb-no-dolby`), `hardware_dolby`
  (`cnb-aospa`) and `packages_apps_GameBar` all have one. Garnet is not in the cnb OTA yet.

## What garnet changed for cnb (bka...cnb, 8 commits)

| Commit | Change | Applies to dizi |
|---|---|---|
| 36c16fec | `configs/hidl/manifest.xml` target-level 6 → **7** (FCM 7) | yes (dizi is still 6) |
| a8c2501f | **64-bit only**: drop `TARGET_2ND_*`, `core_64_bit_only.mk`, remove 32-bit Adreno blobs, drop `run_64bit` audio flag | yes, see below |
| 40b41d75 | `hardware/google/pixel` is gone after CP2A: import only `pixel/pixelstats` + `pixel/power-libperfmgr` | yes (dizi `Android.bp:9`, `device.mk:300`) |
| 94d001a7 | legacy libion (`libion legacy_impl`, `device/lineage/sepolicy/libion`) | yes (same blobs) |
| 7b9b3505 | sepolicy: `esimswitcher_app` becomes coredomain | ruan only (eSIM) |
| ecaf84c3 | eSIM enable/disable toggle | ruan only |
| 13c69ca9 | kernel built with Clang r563880c (did not boot with the default) | no: dizi's kernel is built outside the tree |
| 76acebf3 | parts: DefaultDialerManager reference fix | check the dizi parts |

Kernel `cnb` is still 5.10 (now 5.10.269 LTS plus sm8450 lineage-20 merges), so nothing structural
changes. dizi builds its GKI and display driver outside the tree, so the only kernel input is uapi
headers. The modules repo only picked up small fixes (dsi clock unwind, camera memleaks, rmnet
MAPv5 names).

## dizi-specific work

* **64-bit only.** dizi's 32-bit vendor blobs: 55 `vendor/lib` entries. Of these, 33 are `rfsa`
  (Hexagon DSP code, which does not depend on the ARM ABI), 7 are egl, and the rest are the
  display/Adreno 32-bit variants that garnet also dropped. The stock 32-bit-only executables are
  `ssgqmigd` (we already ship `ssgqmigd64` as well), omx (already off), `dolbycodec2` (not
  shipped), `cas@1.2`, `vsimd`, `iperf` and factory tools. None of them look blocking.
* Rebase the 5 source patches in `device/xiaomi/dizi/patches`: releasetools target-files,
  init resource-cache, renderengine realtime Vulkan queue, vendor/lineage kernel out dir, gms
  uses-library.
* sepolicy, overlays, DiziPen/parts: expect new neverallows and framework resource renames. Redo the
  performance and jank work (SF/renderengine tuning, recents) on 17.
* `dizi-miuicamera` vendor (c0pt4n, gitlab `lineage-23.0`): whether it works on 17 is unknown.

## Cost

* A new platform means a clean build: a new `out/` of about 140 GB, and a full build rather than
  the 8-10 min incrementals.
* Use a second checkout (`evox-cnb`, `repo init -b cnb --reference` against the bka tree so the git
  objects are shared) and keep bka as the release line. That is about 250 GB of source (less with
  reference) plus about 140 GB of out. There is 1.9 TB free.
