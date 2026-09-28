# Source-built kernel for dizi: gap analysis and build plan (Phase 9 / Stage C)

Date: 2026-09-27. Scope: replace the stock prebuilt kernel in `evox/device/xiaomi/dizi-kernel`
(`KERNEL_PATH := $(DEVICE_PATH)-kernel`, `TARGET_FORCE_PREBUILT_KERNEL := true`) with one we build.
All checks were static (nothing flashed, no Android build touched). Scratch data and scripts are in
`/build/alex/dizi/kernel/scratch/`. MiCode side repos fetched for this are in `kernel/micode-extra/`
and the kernel toolchain is in `kernel/clang-r416183b/`.

## TL;DR

* **KMI is compatible.** The stock GKI Image is `5.10.246-android12-9` (KMI generation 9, ACK
  `android12-5.10-2025-12`). Both source trees are `android12-5.10` with `KMI_GENERATION=9`. The 377
  stock modules import 4163 distinct symbols. 1410 of those are exported by other stock modules and
  2753 by the kernel. **Every kernel symbol is in LineageOS's `android/abi_gki_aarch64.xml` with the
  same CRC** (0 mismatches, 0 missing). The stock modules are MODVERSIONS modules
  (vermagic `5.10.198-abOS3.0.303.0.WNSEUXM SMP preempt mod_unload modversions aarch64`), so only
  the CRCs and the vermagic tail after the version must match.
* **Use the LineageOS tree for the Image, not MiCode.** MiCode `ruan-u-oss` is 5.10.198. It is missing
  14 UFS vendor hooks (`android_vh_ufs_err_handler`, `..._err_check_ctrl`, `..._perf_huristic_ctrl`,
  and others) that the stock **`ufs_qcom.ko`** (first-stage boot storage) imports. A MiCode-built Image
  therefore cannot mount the stock rootfs. LineageOS (`SUBLEVEL = 269`, ACK
  `android12-5.10-2026-04-r1`) has all of them.
* **Toolchain:** the stock Image was built with `Android (7284624, based on r416183b) clang version
  12.0.5` / LLD 12.0.5, with full LTO, CFI (+shadow), SCS and TRIM_UNUSED_KSYMS. Both trees'
  `build.config.common` pin `clang-r416183b`. It is now cloned at `kernel/clang-r416183b`
  (from `LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b`).
* **Config:** a plain `gki_defconfig` from the lineage tree is within 9 meaningful lines of the stock
  Image's embedded ikconfig. The dizi vendor config is **not** in the MiCode drop:
  `build.config.msm.dizi` sets `MSM_ARCH=dizi`, but there is no `vendor/dizi_GKI.config`. However,
  `ruan_GKI.config` reproduces the stock dizi module set exactly.
* **Devicetree:** there is no dizi board DTS anywhere. The stock dtbo entry 0 (dizi, `board-id <0x2000b 0x01>`)
  decompiles and recompiles cleanly with dtc 1.7.2, so it can serve as "source". MiCode publishes the
  dizi display and camera overlays (`vendor_qcom_proprietary_{display,camera}-devicetree@ruan-u-oss`).
* **Recommended first step:** a standalone `make` of the lineage tree with **pure `gki_defconfig`**
  and clang-r416183b in `kernel/out-gki`. Check its `Module.symvers` against the stock module imports
  (`scratch/crc.py`, extended). Then `fastboot boot` a repacked boot.img (our Image + EvoX ramdisk),
  with stock vendor_boot, dtb, dtbo and modules left as they are. No Soong changes are needed until that boots.

## 1. Versions and KMI

| | Stock (OS3.0.303.0) | LineageOS `android_kernel_xiaomi_sm7435@lineage-23.2` | MiCode `ruan-u-oss` | EvoX `kernel/xiaomi/sm7435` (bka, headers source today) |
|---|---|---|---|---|
| Version | 5.10.246-android12-9-00012-g730d06ec05ff-ab15159037 | 5.10.269 | 5.10.198 | 5.10.257 |
| ACK base | common-android12-5.10-**2025-12** (from `UNUSED_KSYMS_WHITELIST` path) | android12-5.10-2026-04-r1 (`android/ACK_SHA`) + later stable | android12-5.10-2023-11_r2 | android12-5.10-2026-04-r1 |
| KMI gen | 9 | 9 | 9 | 9 |
| Compiler | clang 12.0.5 r416183b, LLD 12.0.5 | build.config: r416183b (Lineage's inline build uses `clang-stable` unless `TARGET_KERNEL_CLANG_VERSION` is set) | r416183b | same as Lineage |
| Vendor modules | built from Xiaomi's internal 5.10.198 tree (`scmversion g43bf340ad598`) | - | same base version as the modules, but see UFS hooks | - |

Symbol check (`scratch/crc.py`, parses `__versions` / `__ksymtab_strings` of every stock `.ko`):

* 377 unique modules (vendor_ramdisk 317, vendor_dlkm 283, 212 in both). No symbol is imported with two different CRCs.
* Kernel-exported imports: 2753 (the other 1410 all resolve to exports of stock modules). In lineage's ABI xml: 2753/2753, CRC mismatches 0.
  In MiCode's xml: 2739/2753. The 14 missing are the `ufs` vendor hooks, imported only by `ufs_qcom.ko`.
* Every import is also present as a symbol string in the stock Image, so the list is consistent.

Caveat: the xml CRCs describe Google's GKI build. A lineage build must be verified against the
**actual** `Module.symvers` it produces. That matters most for a "consolidated" config
(`gki_defconfig + vendor/parrot_GKI.config`, garnet style), which flips built-in options such as
`IOMMU_IO_PGTABLE_FAST=y`, `ARM64_AMU_EXTN=n`, `USB_DWC3_QCOM/OF_SIMPLE/HAPS=n`,
`QCOM_BALANCE_ANON_FILE_RECLAIM=y`, `VIRT_DRIVERS=y` and `WLAN_VENDOR_ATH=y`. **For stock modules,
build the Image from pure `gki_defconfig`.** That is Qualcomm's own "mixed build" model: GKI Image
from ACK plus vendor modules from msm-kernel.

### Dizi-specific modules and source availability

`scratch/modsrc.txt` maps each module to the Makefile that builds it.

| Class | Count | Notes |
|---|---|---|
| In lineage kernel tree (and MiCode) | 296 | in-tree QCOM/GKI vendor drivers |
| In lineage-modules only (techpack) | 51 | audio (machine, wcd937x/938x, lpass, wsa883x, swr), `msm_drm`, `camera`, `msm_video`, mmrm, IPA, rmnet. **Garnet-flavoured** |
| MiCode kernel only | 7 | `nt36532_spi`, `lct_tp`, `simtray`, `xlogchar`, `lc_auth_battery`, `cpumaxfreq`, `binder_prio` |
| lineage only | 1 | `mi_thermal_interface` |
| No source anywhere | 22 | see below (3 of them are qcacld/mmrm names generated by Kbuild, so 19 are really closed) |

Closed (no published source): `miev` (used by `xiaomi_touch`, `nt36532_spi`, `msm_drm`,
`qti_battery_charger_main`, `bt_fm_slim`, `leds-qpnp-flash-v2`), `xiaomi_hall`, the speaker amps
`sipa_dlkm`, `sipa_tuning_dlkm`, `fs1815_dlkm`, `lct_audio_info_dlkm` (pulled in by `machine_dlkm`
and `wcd937x_dlkm`), `millet_*` (6), `binder_gki`, `mi_memory`, `perf_helper`, `hardwareinfo`,
`bootinfo`, `swinfo`. MiCode has not published an audio-kernel `ruan` branch, so the dizi
`machine_dlkm` has no source either.

Touch and pen:
* `xiaomi_touch`: lineage has a rewritten 681-line driver with no pen mode. MiCode has a 465-line
  driver with `Touch_Pen_ENABLE = 20` and `update_pen_connect_strategy_value`, **but the stock `.ko`
  is newer**. It also exports `xiaomi_touch_mievent_report_{int,str}` and depends on `miev`, which the
  MiCode source lacks. The MiCode source is a fallback reference only.
* `nt36532_spi` and `lct_tp`: in MiCode only, with export sets identical to stock. `msm_drm` imports
  `set/get_lcd_reset_gpio_keep_high` from `nt36532_spi`.

Display: dizi's LCD bias `ocp2131`, backlight `sy7758` and `mi_disp` exist only in
`MiCode/vendor_opensource_display-drivers@ruan-u-oss`. lineage-modules' (garnet) `msm_drm` has none
of them. The dizi panels are `n83_35_02_0a` and `n83_42_02_0b` WQXGA C-PHY video.
Camera: `MiCode/vendor_qcom_opensource_camera-kernel@ruan-u-oss`.
Wi-Fi: `MiCode/vendor_qcom_opensource_wlan@ruan-u-oss` (qca6750). lineage-modules only has `.adrastea`.

## 2. Config

* Stock ikconfig was extracted from the Image to `scratch/stock-Image.config` (it has `IKCONFIG` embedded).
* Generated with clang-r416183b via `merge_config.sh` + `olddefconfig` into `scratch/cfg-*`:
  `lineage-gki`, `lineage-parrot`, `lineage-garnet`, `micode-gki`, `micode-parrot`, `micode-ruan`.
  The MiCode tree needs `CROSS_COMPILE=aarch64-linux-gnu-` in addition to `LLVM=1`. Without it, every
  `cc-option` check fails and CFI, LTO, SCS, BTI and MTE silently drop out.

Stock Image vs lineage `gki_defconfig` (`scratch/diff-stock-vs-lineage-gki.txt`). Apart from about 250
new `=n` symbols for QCOM options that GKI leaves unset, the differences are:
* `TRIM_UNUSED_KSYMS y -> n` and `UNUSED_KSYMS_WHITELIST` gone. These are set by the GKI build
  (`build.config.gki`), not by the defconfig. Untrimmed exports are a superset, which is harmless.
  Optionally set them with lineage's `android/abi_gki_aarch64*` lists for parity.
* `MEMFD_ASHMEM_SHIM=y` exists in stock (ACK 2025-12) but **not in the lineage tree at all**. It is a
  userspace-visible ashmem behaviour. Check `/dev/ashmem` users on bka after the first boot (expected
  to be low risk because the ashmem driver itself is still there).
* `SECURITY_SAFESETID n -> y` (lineage gki_defconfig change), `ARM64_ERRATUM_4118414` (new),
  `BUILD_ARM64_KERNEL_COMPRESSION_GZIP` (QCOM Kconfig default), plus a few QCOM timeout ints and
  `QCOM_SPEC_SYNC=m`. None of these touch the KMI.

MiCode `gki_defconfig` vs stock drops `CPU_MITIGATIONS`, `ARM64_ERRATUM_3194386`, `NET_SOCK_MSG`
and the `PROC_MEM_*` options, because the tree is older.

Vendor config (`scratch/modcfg.py`, which maps each stock `.ko` to its `obj-$(CONFIG_X)` and checks `=m`):
* MiCode `ruan_GKI.config`: all 301 in-tree stock modules resolve except `qcom_ipcc` (a Kconfig
  naming difference). Its 4 extra modules are `=y` in GKI anyway. **This is effectively the missing
  `dizi_GKI.config`.** Compared with MiCode `parrot_GKI.config` it adds `SIMTRAY_STATUS`,
  `TOUCHSCREEN_XIAOMI_TOUCHFEATURE`, `BATT_VERIFY`, MTD/MTD_OOPS, `BINDER_PRIO`,
  `QCOM_MINIDUMP_LAST_KMSG` and `AX88179`, drops `QCOM_MEM_OFFLINE`, and changes the watchdog
  bark/pet times (20000/15000).
* lineage `parrot_GKI.config`: 10 stock modules are missing (MTD set, `mi_thermal_interface`,
  `xiaomi_touch`, `qcom_ipcc`), and it adds focaltech, goodix, nt36xxx and mem_offline.
  lineage `parrot_GKI.config` and MiCode `parrot_GKI.config` differ only in the touch block: MiCode
  enables `TOUCHSCREEN_NT36xxx_HOSTDL_SPI` and `TOUCHSCREEN_COMMON` and disables FTS, Goodix and the
  trusted-touch options.
* MiCode `modules.list.msm.dizi` (the first-stage list) is the stock `vendor_ramdisk/modules.load`
  minus 4 closed modules (`bootinfo`, `miev`, `mi_memory`, `swinfo`) plus 6 debug modules. The
  vendor blocklist matches stock.
* M0Rf30's `dizi_GKI.config` is AI-written and wrong on basic points. Ignore it.

## 3. Devicetree

Stock images, split into `scratch/dt/`:
* `vendor_boot` dtb (`dizi-kernel/dtb/parrot.dtb`): 14 concatenated **pure QCOM SoC** base dtbs for
  Montague, Parrot, ParrotP, Parrot-SG and Ravelin variants, all with `board-id <0 0>` or `<0 0x600>`.
  The running tree matches the Parrot/ParrotP bases, which differ only in msm-id and model. Nothing
  here is Xiaomi-specific.
* `dtbo.img`: 39 entries (table ids all 0; the bootloader matches on the properties in each overlay).
  Entries 1-37 are QCOM reference boards (IDP/QRD/ATP/RUMI). The two Xiaomi entries are:
  * **entry 0, dizi:** `model "Qualcomm Technologies, Inc. Parrot QRD, DIZI based on SM7435P"`,
    `compatible "qcom,parrot-qrd", "qcom,parrot", "qcom,qrd"`,
    `qcom,msm-id <0x27a 0x277 0x247 0x219 0x265 0x279 0x27e> (each 0x10000)`,
    **`qcom,board-id <0x2000b 0x01>`**, `qcom,pmic-id-size 9`, `qcom,pmic-id <0 ... 0x2e>`.
    It contains 95 fragments: a fully merged overlay of board, audio, camera and display, with
    `__symbols__`, `__fixups__` and `__local_fixups__`.
  * entry 38, ruan: same, with `board-id <0x3000b 0x01>`.
  * Garnet, for comparison: `board-id <0x1000B 0>`, `xiaomi,miboard-id <0x11 0>`. There is no miboard-id on dizi.
* `dtc -I dtb -O dts` on entry 0 and back to dtb round-trips to an identical DTS (the blob grows by
  8 bytes of padding). The decompiled entry 0 can therefore be kept as the dizi board "source" and
  rebuilt with `mkdtboimg`.

Sources:
* lineage-devicetrees: the full QCOM parrot/ravelin/montague set (so the base dtbs can be rebuilt),
  plus garnet only (`garnet-sm7435*.dtsi`, `xiaomi-sm7435-common.dtsi`, garnet camera, audio and display).
  **No dizi or ruan files.**
* MiCode kernel: no dizi DTS. `MiCode/kernel_devicetree` only has `garnet-t-oss`.
* **MiCode `vendor_qcom_proprietary_display-devicetree@ruan-u-oss`** has
  `display/dizi-sde-display-qrd{.dtsi,-overlay.dts}` (default panel `dsi_n83_35_02_0a_wqxga_video_cphy`).
  **`vendor_qcom_proprietary_camera-devicetree@ruan-u-oss`** has `dizi-camera-sensor-qrd.dts{,i}` and `config/dizi.mk`.
* Not published: the dizi board overlay itself (touch SPI `touch@0` with `novatek,NVT-ts-spi` and
  `xiaomi-touch`, `xiaomi-hall`, the sia81xx/fs16xx amps, `lc,auth-battery`, `simtray`, charger,
  thermal and pinctrl) and the dizi audio overlay.

To build a matching dtbo from source, three pieces are missing: a `dizi-qrd-overlay.dts` (reconstruct
it from decompiled fragments 0-59 and 86-95, with labels restored from `__symbols__`/`__fixups__`), a
dizi audio overlay (the same approach), and a dtbo build wired the way garnet does it
(`BOARD_USES_QCOM_MERGE_DTBS_SCRIPT`, `TARGET_NEEDS_DTBOIMAGE`). The stock dtbo is not tied to the
kernel build, so it stays valid for stages (a) and (b) as long as the modules are the stock ones or
share their DT bindings.

## 4. Build approach

Options:
1. **Standalone make (recommended for stage a).** Build the lineage tree in `kernel/out-gki` with
   `make O=... ARCH=arm64 LLVM=1 LLVM_IAS=1 CROSS_COMPILE=aarch64-linux-gnu- gki_defconfig Image modules`
   (`PATH=kernel/clang-r416183b/bin:$PATH`, `HOSTCC=gcc` works). The result is `Image`,
   `vmlinux.symvers` and `Module.symvers`. Put the Image in the dizi-kernel repo on a branch, so the
   device tree stays unchanged (`TARGET_PREBUILT_KERNEL`). Cost is roughly 15-30 min on 48 cores; the
   full-LTO link is the single-threaded tail.
2. LineageOS inline build (the garnet approach: `TARGET_KERNEL_SOURCE`, `TARGET_KERNEL_CONFIG`,
   `TARGET_KERNEL_EXT_MODULE_ROOT/_EXT_MODULES`, `BOARD_USES_QCOM_MERGE_DTBS_SCRIPT`). Garnet builds
   everything from source with `clang-stable` (clang 19/20) and a consolidated config. For dizi this
   has two drawbacks. First, it changes `kernel/xiaomi/sm7435`, which also supplies the UAPI headers
   for the display and audio HALs (README gotcha 14). Second, mixing a clang-20 kernel with clang-12
   stock modules under CFI is untested. If we go inline later, set
   `TARGET_KERNEL_CLANG_VERSION := r416183b` (with the clang repo added to the manifest), use pure
   `gki_defconfig`, and keep the prebuilt `BOARD_VENDOR_*KERNEL_MODULES`.
3. Bazel/`build.sh` (MiCode `kernel_build@ruan-u-oss`, fetched) needs the full kernel-platform
   layout (`common` + `msm-kernel` + techpack), plus `dizi_GKI.config`, which does not exist. It is
   not worth the effort.

Staged plan:
* **(a) Source Image + stock modules + stock dtb/dtbo.** Take lineage `gki_defconfig` and clang-r416183b.
  1. Build. Diff `.config` against `scratch/stock-Image.config` (expected: the list in section 2).
  2. Run the CRC gate: every `__versions` entry of the 377 stock modules must match `Module.symvers`.
     Also compare the vermagic tail (`SMP preempt mod_unload modversions aarch64`).
  3. Repack: `unpack_bootimg --format=mkbootimg` on the EvoX `boot.img`, swap the kernel, and
     `fastboot boot` it. Ramdisk-only v4 plus the stock vendor_boot/dtbo stay flashed. This does not
     persist, and a reboot recovers.
  4. Validate with `tools/validate.sh` and the pen (mode 20), then commit the Image to `dizi-kernel`.
  Effort: about 1 day.
* **(b) Source modules, incrementally.** Base: the lineage kernel tree with `ruan_GKI.config` (as
  `vendor/dizi_GKI.config`), the MiCode `nt36532_spi`/`lct_tp`/`simtray`/`xlogchar`/`lc_auth_battery`
  /`binder_prio`/`cpumaxfreq` drivers, MiCode display-drivers, camera-kernel and wlan (ruan-u-oss),
  and lineage-modules for the rest of the techpack. **Keep prebuilt:** the 19 closed modules, the
  entire audio stack (`machine_dlkm` and the amps have no dizi source), and
  `xiaomi_touch` + `nt36532_spi` + `lct_tp` + `miev` for the pen.
  Swapping individual modules works only if module-to-module CRCs agree. To make that hold:
  synthesize a `Module.symvers` for the prebuilt exporters from their `__kcrctab` (e.g. `miev`'s
  `cdev_tevent_*`, `nt36532_spi`'s lcd-reset getters), and re-run the CRC gate for every stock module
  that remains (e.g. stock `nt36532_spi` against source `panel_event_notifier`).
  Effort: 1-3 weeks, mostly display and Wi-Fi bring-up.
* **(c) Source dtbo.** Start from decompiled dtbo entry 0 and split it into board, display, camera
  and audio parts. Replace display and camera with the MiCode sources and diff the merged result
  against stock. Keep the 14 QCOM base dtbs from lineage-devicetrees or from stock. Rebuild with
  `mkdtboimg` using the same board-id/msm-id. This is only needed once source modules need new
  bindings. Effort: 3-5 days.

## 5. Risks

* **Pen / touch (mode 20):** needs the **stock** `xiaomi_touch.ko` (the ioctl layout
  `{0, mode, value}`, mievent, and the pen connect strategy; see `recon/pen/FINDINGS.md`). With
  stage (a), all 7 touch-chain modules (`xiaomi_touch`, `nt36532_spi`, `lct_tp`, `miev`,
  `panel_event_notifier`, `msm_drm`, `qti_battery_charger_main`) stay stock and their kernel CRCs
  match, so the risk is low. In stage (b), never replace `xiaomi_touch` with lineage's, and keep
  `nt36532_spi`/`lct_tp`/`miev` together. A source `msm_drm` must export and import the same
  CRCs these modules use.
* CFI with a newer clang: avoided by using r416183b. Any other clang also needs CFI cross-DSO
  compatibility with the clang-12 modules, and that is not verified.
* Config that is consolidated rather than pure GKI: these options change built-in code and may break
  CRCs or behaviour. Use pure `gki_defconfig` for the Image.
* `MEMFD_ASHMEM_SHIM` is missing in lineage (section 2).
* Firmware and version coupling (README gotcha 8): the stock modules and firmware stay at
  OS3.0.303.0. A newer Image is fine under KMI stability, but never mix modules from different builds.
* Boot-failure debugging: ramoops at 0x80d00000 (`/sys/fs/pstore`) survives a warm reboot.
  `fastboot boot` avoids bricking the slot.
* `SECURITY_SAFESETID=y` and lineage's own `xiaomi_touch`/focaltech/goodix drivers (lineage only
  builds them with the parrot config) are irrelevant for pure `gki_defconfig`.

## Artifacts

* `kernel/scratch/stock-Image.config`: stock ikconfig.
* `kernel/scratch/cfg-*/.config`: generated configs. `diff-stock-vs-*.txt`: diffconfig output.
* `kernel/scratch/crc.py`: stock module `__versions` vs ABI xml (extend to read `Module.symvers` for the gate).
* `kernel/scratch/modsrc.py`, `modsrc.txt`: module to source Makefile map. `modcfg.py`: module to CONFIG `=m` check.
* `kernel/scratch/dt/`: split and decompiled stock base dtbs (`base.N.dts`) and dtbo entries
  (`dtbo.N.dts`); entry 0 is dizi.
* `kernel/clang-r416183b/`: the exact stock compiler.
* `kernel/micode-extra/`: MiCode `ruan-u-oss` display-devicetree, camera-devicetree, camera-kernel,
  display-drivers, wlan and kernel_build (all shallow clones).
