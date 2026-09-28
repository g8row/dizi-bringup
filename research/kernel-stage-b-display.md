# Kernel stage (b): source-built msm_drm.ko (display) for dizi

Date: 2026-09-28. Static work only: no device access, nothing under `evox/` was touched.
Everything lives in `/build/alex/dizi/kernel/out-display/` and `/build/alex/dizi/kernel/patches/`.

## TL;DR

* **It builds.** `msm_drm.ko` from MiCode `vendor_opensource_display-drivers@ruan-u-oss` (33bdb80)
  builds as an external module against the lineage GKI tree with clang r416183b, full LTO and CFI.
  There are 0 compiler warnings and 0 modpost warnings. The only source change is one include path.
* **CRCs match.** No stock module imports anything from `msm_drm`, including the touch and pen chain
  (`nt36532_spi`, `xiaomi_touch`, `lct_tp`, `miev`, `panel_event_notifier`). A swap therefore
  cannot break another module's symbol resolution. On top of that:
  * **Exports:** all 51 symbols that our build exports have the **same CRC as stock**.
  * **Imports:** all 823 imports have the same CRC as the stock `msm_drm.ko`'s imports (0 mismatches).
    Every import resolves against `out-gki/Module.symvers` (the Image we boot) plus a `Module.symvers`
    synthesized from the stock dependency modules.
* **It is not feature-identical to stock.** The stock `.ko` was built from a *newer* internal Xiaomi
  tree than the one MiCode published. Missing in source (section 4):
  * the `miev` (MIUI telemetry) hooks;
  * the Xiaomi hardware-monitor/`hwconf` framework (9 exports that nothing imports);
  * the display/fps/HBM counters;
  * an extended register-read ESD check (`0x0a/0x90/0x91/0x92/0xAB`) with an ESD delay timer.

  All **791 DT property strings are identical**, so the source driver parses the stock dtbo the same way.
* **The splash-timing fix is prepared, not applied:** `patches/0002-...splash.patch` (it touches SDE
  INTF and DSI; dsi_display.c alone is not enough, see section 5). A second module was built with it.

## 1. Stock msm_drm.ko

`evox/device/xiaomi/dizi-kernel/modules/{vendor_ramdisk,vendor_dlkm}/msm_drm.ko`: the two copies are
byte-identical, 5 850 576 bytes, stripped, not signed (no module signature appended).

* vermagic `5.10.198 SMP preempt mod_unload modversions aarch64`, scmversion `gfb7d22e036e6`, softdep `pre: msm-mmrm`.
* depends: `miev, smem, msm_dma_iommu_mapping, qcom_iommu_util, nt36532_spi, pm8941-pwrkey, qcom_rpmh,
  msm-mmrm, spmi-pmic-arb, pinctrl-msm, panel_event_notifier, hdcp, fsa4480-i2c, msm_ext_display,
  qcom_ipc_logging, altmode-glink, dwc3-msm, gh_msgq, gh_irq_lend, gh_rm_drv, gh_mem_notifier, qcom-scm`.
* Symbols imported from other stock modules include:
  * `miev`: `cdev_tevent_{alloc,add_int,add_str,write,destroy}`
  * `nt36532_spi`: `get_lcd_reset_gpio_keep_high`
  * `panel_event_notifier`: `panel_event_notification_trigger`
  * `msm_ext_display`: `msm_ext_disp_{register,deregister}_intf`
  * `hdcp`: 14 `hdcp1_*`/`hdcp2_*`
  * `msm-mmrm`: `mmrm_client_{register,deregister,set_value}`
* 839 imports and 60 exports in total (`out-display/analysis/stock-{imports,exports}.txt`).
* **Reverse dependencies: none.** `tools/modsyms.py users` scanned all 377 stock modules and none
  imports any of the 60 exports. The tool was cross-checked on `nt36532_spi`, where it correctly
  reports `msm_drm` as the importer. So there is **no CRC constraint from the touch/pen chain on msm_drm**.
  The chain meets msm_drm only in one direction: msm_drm imports from it
  (`nt36532_spi`: `get_lcd_reset_gpio_keep_high`; `panel_event_notifier`: `panel_event_notification_trigger`).
  Those CRCs come from the stock exporters and match (section 3).

## 2. Build configuration

* Display config is `config/gki_parrotdisp.conf` + `gki_parrotdispconf.h`, selected in `msm/Kbuild`
  by `CONFIG_ARCH_PARROT=y`. It enables:
  * `DRM_MSM` with SDE, DSI and DSI_PARSER;
  * `SDE_WB`, `SDE_RSC`, `SDE_VM`, `DP` + `DP_MST`;
  * `MDSS_PLL`, `MSM_MMRM`, `HDCP_QSEECOM`, `MSM_EXT_DISPLAY`;
  * `REGISTER_LOGGING` and `SDE_EVTLOG_DEBUG`.

  `mi_disp/*` (including `mi_bias_ocp2131` and `mi_backlight_sy7758`) is built unconditionally. There
  are no `CONFIG_MI_DISP*` switches in this tree, and `DISPLAY_FACTORY_BUILD` is off. The stock
  rotator exports (`sde_rotator_inline_*`) and functions are reproduced as well.
* The kernel side needs the *vendor* config, not pure gki_defconfig. Otherwise every
  `IS_ENABLED(CONFIG_QCOM_FSA4480_I2C/MSM_EXT_DISPLAY/HDCP_QSEECOM/GH_*/ARCH_PARROT...)` compiles out,
  and the stock dependency list would not be reproduced. `out-display/kobj` is therefore the lineage
  tree with `gki_defconfig` + MiCode `vendor/ruan_GKI.config` (the de-facto dizi config), `olddefconfig`
  and `modules_prepare`, with **`out-gki/Module.symvers` copied in**. Imported kernel CRCs therefore
  come from the Image we actually boot. This is Qualcomm's mixed-build model: GKI Image plus vendor
  modules built against the vendor config.
* The dependency modules' CRCs come from `deps/stock-deps.symvers` (287 exports). It is synthesized by
  `tools/modsyms.py symvers` from the `__crc_*` absolute symbols (the `__kcrctab` relocation targets)
  of the 22 stock dependency `.ko`s. Nothing had to be built from source for this.
* Command (`out-display/build.sh <srcdir>`):
  `make -C lineage O=out-display/kobj ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- M=<src>
  KERNEL_SRC=lineage DISPLAY_ROOT=<src> MODNAME=msm_drm BOARD_PLATFORM=parrot CONFIG_DRM_MSM=m
  KCFLAGS=-I micode-ruan/drivers/input/touchscreen KBUILD_EXTRA_SYMBOLS=deps/stock-deps.symvers modules`.
  `KERNEL_SRC` is needed for `drivers/clk/qcom` headers (`clk-regmap.h`).
* Source build fix (patch 0001): `msm/dsi/dsi_panel.h` includes
  `../../../../../../kernel_platform/msm-kernel/drivers/input/touchscreen/nt36532_spi/dsi_touch_gesture.h`.
  The patch replaces it with `nt36532_spi/dsi_touch_gesture.h`, resolved through the -I path. The
  header comes from micode-ruan and only declares `set/get_lcd_reset_gpio_keep_high`.
* The resulting vermagic is `5.10.269-gki-gec878c86253a SMP preempt mod_unload modversions aarch64`.
  Because of MODVERSIONS, only the part after the version string is compared, and it matches stock.
  depends = the stock list minus `miev`.

## 3. Comparison with stock (baseline build, `out/msm_drm.ko`)

| | stock | source build |
|---|---|---|
| file (debug-stripped) | 5 850 576 | 6 141 760 |
| .text | 1 698 808 | 1 806 104 (+6%; different kernel/headers, same LTO/CFI) |
| .rodata / .data / .bss | 506 064 / 44 272 / 136 633 | 500 440 / 44 008 / 136 161 |
| exports | 60 | 51: all 51 have an identical CRC; the 9 missing are the hw_monitor/hwconf API |
| imports (`__versions`) | 839 | 823: all common ones have an identical CRC (0 mismatches) |
| imports only in stock | | `cdev_tevent_*` (miev) ×5; `raw_notifier_*` ×3, `simple_attr_*` ×4, `hrtimer_init/start_range_ns`, `ktime_get_with_offset`, `generic_file_llseek` (hw_monitor, ESD timer) |
| functions (t/T, LTO suffixes normalized) | 4056 | 4059: 61 only in stock, 64 only in ours (all 64 are LTO `.NNNN` clones of static helpers) |
| DT property strings (`qcom,`/`mi,`) | 791 | 791, identical |

Functions only in stock that are real features, not inlining noise:
* **mievent:** `mi_disp_mievent_{int,str,recovery}` and `get_mievent_*`. These are MIUI telemetry;
  "panel Underrun", "panel WP Read Failed" and similar strings are reported to `miev`.
* **Hardware monitor / hwconf:**
  * `{add,register,unregister,update}_hw_{component,monitor}_info`, `hw_monitor_notifier_*`
  * `hwconf_*`, `hw_item_*`, `hw_{info,mon}_{show,store}`
  * `disp_count_*` and `mi_dsi_panel_{active,backlight,fps,HBM,state}_count`, `mi_sde_encoder_calc_fps`

  These are sysfs statistics and nothing imports them.
* **ESD extension:** `mi_read_esd_lcd_code` (reads panel registers 0x0a/0x90/0x91/0x92/0xAB),
  `mi_sde_esd_delay_timer_init`, `mi_esd_thread_hrtimer_func` and `esd_timer_work_handler` ("esd in delay").
  Our build keeps QCOM's `reg_read` ESD, which the DT configures as `0x0a == 0x9c`, plus Xiaomi's
  `mi_esd_err_irq_handle` on `mi,esd-err-irq-gpio{,-second}`.
* Panel cell-id / white-point register reading (`[I]cell_id = %s`, `zgq add dsi_panel_parse_wp_reg_read_config`),
  a `disp_fod` kthread and some debug prints.
* Minor QCOM-side differences (cwb count check, vbif client error path, DP vreg deinit) show that the
  stock QCOM base is slightly newer as well.
* The `sde_encoder_get_clones`, `dp_*` and `sde_rotator_validate_item` entries exist in the source.
  They are only inlined differently.

Assessment: for EvoX the missing pieces are telemetry and statistics. The one behavioural difference
is the extra ESD register check and delay timer. Panel init sequences, DSI timings, dfps list,
pen-rate commands (`DSI_CMD_SET_DISP_PEN_*HZ`), ocp2131 bias and sy7758 backlight are all present.
They are parsed from the same DT properties.

## 4. Remaining blocks and risks before trying it on the device

1. **Runtime is untested.** The ABI (CRC) gate passes, but the source is older than stock. Check on
   the device: panel on, brightness (sy7758), dfps switching, pen (mode 20) scan-rate commands, ESD
   recovery (`echo 1 > /sys/kernel/debug/.../esd_trigger`), DP alt-mode, doze/AOD and HBM.
2. Userspace that depends on the missing sysfs nodes (hw_monitor/`disp_count`) or on mievent is
   MIUI-only. EvoX display HAL / XiaomiParts should not need them; grep the EvoX tree before
   testing.
3. `msm_drm.ko` sits in **both** vendor_ramdisk (first stage) and vendor_dlkm. Replace both, or
   test with a repacked vendor_boot only. `fastboot boot` does not cover vendor_boot, so testing
   needs a flash to the inactive slot or an A/B-safe repack.
4. The stock `miev` still loads, but msm_drm no longer depends on it. That is harmless, because
   other modules (`xiaomi_touch`, `nt36532_spi`, ...) keep pulling it in.
5. The rest of stage (b) still applies: other source modules must re-run the CRC gate against the
   stock modules that remain.

## 5. Cont-splash 60 Hz fix (performance.md s14), prepared, not applied

Root cause, refined from the source:
* The dizi panel DT (`dtbo.0`, n83_35_02_0a/n83_42_02_0b) has a **single 60 Hz timing**
  (vfp 2784), with `dfps_immediate_porch_mode_vfp` and the list `120 90 60 50 48 30`. The kernel
  expands the list into modes and marks the **first (120 Hz)** as preferred. The bootloader lights
  the panel with the 60 Hz base timing.
* The first commit after splash is a full enable, because `sde_crtc/connector_duplicate_state` drop
  the splash state. At that point `dsi_display_validate_mode_change()` returns early because
  `panel->cur_mode` is still NULL, so no DFPS/VRR flag is set. `dsi_display_enable()` then skips all
  host programming (`is_skip_op_required()`), and `sde_encoder_phys_vid_setup_timing_engine()` skips
  INTF programming and the INTF flush (`phys_enc->cont_splash_enabled`).
* Result: the kernel believes 120 Hz while the INTF and DSI host keep the bootloader's 60 Hz timing.
  The next genuine refresh change (the "good boot" 120 -> 30 -> 120, or XiaomiParts' RefreshRateKick)
  is a VRR switch, which programs both the INTF and the DSI host.
* Refresh in video mode is generated by the **SDE INTF timing generator**, so a DSI-only fix in
  dsi_display.c would desynchronise the INTF and DSI. Marking the mode dirty does not work either: it
  would force a full, non-seamless modeset (panel off/on), or the `VRR` flag would make
  `dsi_bridge_pre_enable` skip the splash cleanup.

Patch `0002` (SDE + DSI, about 150 lines):
* `sde_hw_intf`: a new `get_vtotal` op that reads back `INTF_VSYNC_PERIOD_F0 / (INTF_HSYNC_CTL >> 16)`.
* `sde_encoder_phys_vid_setup_timing_engine()`: during splash, compare the hardware vtotal with the
  mode's vtotal. If they differ, program the timing generator and let `phys_vid_enable()` set the INTF
  flush bit (`phys_enc->splash_timing_update`). If they are equal, behaviour is unchanged.
* `dsi_display.c`: a new `dsi_display_splash_timing_fixup()`, called in the splash branch of
  `dsi_display_enable()` after `dsi_display_config_ctrl_for_cont_splash()`, while the splash clocks
  are still on. It runs only for video mode with immediate-VFP DFPS. It reads `DSI_VIDEO_MODE_TOTAL`,
  and if that differs from `cur_mode` it calls `dsi_ctrl_async_timing_update()`, which turns on the
  timing double buffer, and sets `display->splash_timing_db_pending`.
* `dsi_drm.c` `dsi_conn_prepare_commit()`: if the flag is pending, release the timing DB
  (`dsi_ctrl_timing_db_update(false)`, the same step a DFPS switch performs) before the kickoff that
  flushes the INTF. It then sends the Xiaomi pen-rate command set for the new refresh rate
  (`mi_dsi_panel_match_fps_pen_setting()`).

Built as `out/msm_drm-splashfix.ko`. Its exports and imports (CRCs) are identical to the baseline
build. Expected dmesg on a bad boot: `intf 1: splash vtotal <60Hz> != mode vtotal <120Hz> (120 Hz),
reprogramming timing` and `[msm-dsi-info]: [...] splash vtotal ... updating host timing`.
Test plan: loop reboots with `tools/boot-health.sh`, disable XiaomiParts RefreshRateKick, and check
the HW vsync period (~8.3 ms) on every boot. Risk: the INTF flush during handoff. QCOM skips it
because the bootloader pipeline is single-buffered. The fix flushes only when the timings actually
differ, which is exactly the VRR programming sequence, just done during the handoff frame.
If a boot glitches, drop the pen-rate hunk first, then fall back to XiaomiParts.

## Files

* `kernel/out-display/build.sh`: build script (`./build.sh src` or `./build.sh src-fix`).
* `kernel/out-display/kobj/`: lineage objdir with gki+ruan vendor config, modules_prepare, and out-gki Module.symvers.
* `kernel/out-display/deps/stock-deps.symvers` (+ `list`): synthesized CRCs of the 22 stock dependency modules.
* `kernel/out-display/tools/modsyms.py`: `exports | imports | symvers | users` for `.ko` files.
* `kernel/out-display/src/`: git, branch `master` = pristine MiCode 33bdb80 + patch 0001 (baseline build tree).
* `kernel/out-display/src-fix/`: git worktree, branch `splash-fix` = master + patch 0002.
* `kernel/out-display/out/msm_drm.ko` (sha256 `b4fcf368...`) and `out/msm_drm-splashfix.ko`
  (sha256 `0bf3db92...`): both debug-stripped. Unstripped copies are in `src*/msm/msm_drm.ko`.
* `kernel/out-display/analysis/`: stock/src exports, imports, funcs, strings, DT props, and diffs.
* `kernel/patches/0001-disp-msm-dsi-include-nt36532-dsi_touch_gesture.h-via-include-path.patch`
* `kernel/patches/0002-disp-msm-program-handoff-timing-when-it-differs-from-splash.patch`
