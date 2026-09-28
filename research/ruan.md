# ruan (Redmi Pad Pro 5G / POCO Pad 5G) vs dizi: stock ROM comparison

Compared ruan Global `OS3.0.303.0.WFSMIXM` (fastboot tgz from `bigota.d.miui.com`, md5
`56a6035d5b9f37d790dc88f4270f1786`) with the dizi EEA `OS3.0.303.0.WNSEUXM` dump. Same build
number. Work files are in `stock/ruan/` (`cmp/` holds the unpacked boot images, split dtbs, merged
trees and file lists).

## Kernel and modules: shared

* `boot.img` kernel: **byte-identical**.
* vendor_boot ramdisk: the same 311 modules, with **identical `.text`**. Only the vermagic
  (`-abOS3.0.303.0.WNSEUXM` vs `-WFSMIXM`) and scmversion strings differ. `modules.load{,.recovery}`
  differ only in where `miev.ko` sits. `modules.blocklist` is identical.
* vendor_dlkm: the same 271 modules, with identical `.text`.
* The source-built GKI Image and modules therefore apply to ruan unchanged.

## Device tree

* Base dtbs (vendor_boot, 14 SoC dtbs): identical apart from phandle numbering.
* dtbo: both ROMs carry a dizi entry (0, `board-id <0x2000b 0x01>`) and a ruan entry (38,
  `<0x3000b 0x01>`). **Each ROM only fully populates its own board.** The ruan entry in the dizi ROM
  has no camera nodes (cam-sensor0/1, eeprom0/1, actuator0, flash, cam-res-mgr). The dizi entry in
  the ruan ROM, merged onto ParrotP, is identical to the dizi ROM's once phandles are ignored. **The
  ruan ROM's `dtbo.img` is correct for both boards.**
* Real ruan vs dizi board differences (both merged from the ruan ROM):
  * `mpss_region@8bc00000`: 0x2c00000 (44 MiB) on dizi vs 0xe600000 (230 MiB) on ruan (modem).
  * `qcom,rmtfs_sharedmem`: 0x280000 vs 0x800000.
  * dizi keeps backlight/reset properties on the unused QCOM reference panel
    `mdss_dsi_vtdr6130_fhd_plus_cmd`. The real panels (n83 35/42) are the same.
  * Nothing else differs: touch, pen, hall, audio amps, cameras, charger and simtray are all the same.

## vendor / odm

vendor has 3814 files in common. 193 of them differ, but 152 of those have identical code
(build-id or rodata noise only). ruan adds 189 files; dizi has 8 that ruan lacks.

* **ruan-only (the whole delta is modem and GNSS):** qcrilNrd and the qcril* libraries plus
  `qcril_database` (21 files), IMS (`imsdaemon`, `ims_rtp_daemon`, radio.ims-V12), qtiradio and
  qtiradioconfig, data iwlan and dataconnection-saidl, `qms`, `qmipriod`, `ATFWD-daemon`,
  `embmsslServer`, `ccid_daemon_nr` (SIM card reader), secure_element@1.x. There is also a
  **full GNSS stack** (`android.hardware.gnss-aidl-service-qti`, `loc_launcher`, `slim_daemon`,
  vendor.qti.gnss, izat/gps/sap/apdr.conf, `garden_app`), plus the telephony
  cdma/gsm/ims permission xmls and `thermal-phone.conf`. **dizi has no GPS; ruan does.**
* dizi-only: `init.mi.serial.sh`, `thermal-demo.conf`, and 6 `qc_Global_1.x.xml`.
* Real config differences: the audio calibration `parrot_qrd/QRD_acdb_cal.acdb` and `.qwsp`
  differ (1.62 MB vs 1.53 MB), so ruan needs its own. The following also differ:
  * `sar_config.xml` (`is_wifi_only` false, plus cellular keys)
  * `android.hardware.location.gps.xml` (adds the gps feature)
  * the thermal confs (encrypted)
  * `battery_info.xml` (whitespace only)
  * the `qc*.xml` sets
* Firmware (`a710_zap`, `CAMERA_ICP`, `evass`, `vpu20`): about 100 bytes differ per `.mdt`,
  probably per-product signing. Each device must keep its own.
* init rc files: none differ. The dizi rc files already carry the `hwname=ruan` branches.
* odm: ruan SKUs are `n83u{cn,cnes,gl,in,ja,pin}` (dizi: `n83{cn,cnsy,gl,glce,glfcc,in,ja,pgl}`),
  each with a build.prop and a vintf manifest. Other differences: citsensorservice,
  `camerabooster.json`, `default_cloud.json`, `device_info_qr_config.yml`.

## What this means for a ruan target

* Kernel, modules and dtb are shared as they are. Ship the ruan ROM `dtbo.img` (it is also valid
  for dizi).
* Take blobs from the ruan ROM where the files differ: the telephony and GNSS stacks, the acdb,
  firmware, thermal, sar, qc*.xml and odm. Everything else is code-identical to what dizi ships.
* Tree work: re-add telephony (see the commits that dropped it: 82fd9ce, d21a049, f4be0ed, and the
  radio HALs in a6e5da9), add GNSS, and use per-SKU odm manifests.
