# Plain LineageOS 23.2 on dizi (lineage-2, 2026-09-28)

A test of the dizi device tree on stock LineageOS 23.2 (same Android 16 QPR base as EvoX bka), mainly to
compare Trebuchet (Launcher3 Quickstep built from source) with the Pixel Launcher prebuilt.

## Tree and build

- Source: `/build/alex/dizi/lineage`, repo `lineage-23.2` with `--reference` to evox.
  - hardware/xiaomi, hardware/dolby, GameBar and the kernel headers are pinned to the evox commits
    (`.repo/local_manifests/dizi.xml`).
  - device/xiaomi/{dizi,dizi-kernel}, vendor/xiaomi/dizi and vendor/dizi-bench are `cp -a` copies.
    The device tree is on branch lineage-23.2.
- Build reuse:
  - `out-dizi` is a `cp -a` of evox's.
  - `tools/match-mtimes.py evox lineage` gives blob-identical files evox's mtimes: it matched 1.64M files,
    and 2.8k differ (frameworks/base 1250, Settings 310, lineage-sdk 192, recovery 176, ...).
  - The first build ran 83k ninja actions in 71 min; the second (after a sepolicy fix) ran 15k in 19 min.
- Device tree changes:
  - `sepolicy/private/compat/202404/202404.ignore.cil` for devicesettings_app and settingslib_prop.
    Lineage's system/sepolicy runs the treble compat tests, which EvoX's fork doesn't.
- Platform patches:
  - build/make, frameworks/native and vendor/lineage apply as-is.
  - system/core isn't needed: Lineage has no is_upgrade resource-cache wipe.
- `TREE=lineage tools/build.sh <id> bacon superimage`; `TREE=lineage tools/deploy.sh <id> --wipe`.
  The build is test-keys, so moving from the EvoX release needs a wipe.

## Boot

- Booted first time (43 s to boot_completed), SELinux enforcing.
- USB adb came up without a replug.
- The user confirmed that camera, audio, screen and the launcher work.
- Tombstones:
  - hardware/dolby `dolbycodec2` (Codec2 `default2`) crashes in `BnHwComponentStore::_hidl_listComponents`
    (null RefBase).
  - mediaserver then aborted once: `Codec2 service "default2" does not have IConfigurable`.
  - EvoX ships the same services (same out/ contents), so this is likely shared. The note in a17-cnb.md
    saying dolbycodec2 isn't shipped is stale.
- AVC denials: about 15 triples, mostly system_app -> HAL binder calls and adbroot; nothing blocking.

## Jank (landscape, warm runs, same scripts as EvoX)

`tools/apps.sh` now resolves the launcher, browser, clock and gallery apps, so the scripts run on both ROMs.

| Test | EvoX (research/performance.md) | Lineage (Trebuchet, Jelly) |
|---|---|---|
| Settings fling | 0.09-0.18% | **0.05%**, p99 7 ms |
| Browser fling | Chrome (layer timeline) | Jelly 0.00%, p99 7 ms |
| Launcher home fling | 1.6-2.1% | **6.10%**, p90 18 / p99 44 ms, 88 slow issue draw |
| QS pulldown | ~4.7-5.6% | **4.00%**, p99 32 ms |
| Recents (enter, fling cards, home) | 2.99% (after the landscape blur fix; 24% before) | 4.02%, p50 11 ms |
| Recents -> app, launcher hwui | 6.7-9.2% | 8.79% (7.04% in a 20-cycle run) |
| Recents -> app, display timeline | 13.0-14.8% | **20.7%** (17.7% in a 20-cycle run) |

- Trebuchet is AOT-compiled (`speed`, prebuilt dexpreopt), so JIT on the first boot is not a factor.
- LauncherOverlayDizi targets com.google.android.apps.nexuslauncher, so it doesn't apply here. Launcher3 has no
  600dp landscape blur (max_depth_blur_radius_enhanced is 30dp in values/ only), so nothing is lost.
- In recents-open, an unnamed layer (`none`, probably the transition leash or the blur/dim surface) is 33-48% janky.
  The Jelly layer is janky 53% of its 122 frames while it opens.
- Logs: logs/lineage-2/ (logs-235016, ui-jank-*, recents-*).

## Next

- Perfetto traces of the home-page fling and of Recents -> app on Trebuchet: find what "slow issue draw commands"
  and the `none` layer are. Launcher3 is source here, so fixes can go in directly.
