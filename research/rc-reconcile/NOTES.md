# init.qcom.rc / init.target.rc reconciliation for dizi

Inputs:
- stock: `stock/dump/vendor/etc/init/hw/init.{qcom,target}.rc` (HyperOS, dizi)
- current: `trees/staging/rootdir/etc/init.{qcom,target}.rc`. These are garnet's
  files, unchanged since the fork. `git log -- rootdir/etc/` shows no dizi commit
  touching them; every dizi commit touched init.dizi.rc, init.recovery.qcom.rc
  or rootdir/bin only. The built copies in out/ are byte-identical to the tree.
- built vendor: `evox/out/target/product/dizi/vendor/{bin,bin/hw,etc/init}`
- SELinux: plat + mapping + vendor + odm CIL from out/, queried with a small
  CIL evaluator (attributes and set expressions expanded). Real AVCs from
  `logs/build-19/selinux/avc-raw.txt` (b19, permissive) back up the results.
- Stock runtime state: `recon/getprop.txt` (init.svc.*, props).

Checks on the proposed files:
- `host_init_verifier` (single-file mode, vendor+system passwd, all
  property_contexts) passes for both files.
- Service names are unique across system, system_ext, product, odm and vendor
  rc files, if you assume the proposed files are installed. The only
  duplicates left are the intentional `override`s in init.dizi.rc and zygote.
  The current build also has a real duplicate, `vendor.msm_irqbalance` in
  init.qcom.rc and init.qti.kernel.rc. It is gone now.
- Every `start`/`enable`/`stop` target is defined somewhere.
- Every kept service binary exists in our vendor and has an init domain
  transition in our policy (checked via file_contexts and typetransition).

The proposed init.qcom.rc is stock with lines removed, plus 2 small additions.
The proposed init.target.rc is stock with lines removed, plus 4 LineageOS
blocks from the current tree.

---

## init.qcom.rc

### Kept from stock (and differences from current)

| Block | Note |
|---|---|
| imports ufs, usb, target, factory | `init.qcom.test.rc` dropped (not in our build or in stock) |
| early-init: tracefs, symlinks, UFS clk/hibern8 off, kmsg, `modprobe msm_11ad_proxy` | the module is in our vendor_dlkm and vendor_ramdisk; stock loads it |
| init: legacy sdcard symlinks, memory/bg cgroup | cgroup v1 path; a harmless ENOENT on v2, same as stock and current |
| early-boot: memlock, early_boot.sh, lcd_density, pfm licences | `init.qti.can.sh` dropped (missing) |
| boot: BT/rfkill/tty perms, persist dirs, wifi.interface, a2dp offload, conntrack liberal, dload, dsi_display, backlight, persist display/vpp/hvdcp dirs, coresight perms | the current tree lacks the stock `reset_source_sink` chown/chmod; restored. The `vendor_qdss` group exists in vendor/etc/group |
| boot: `write /sys/block/sda/queue/discard_max_bytes` | **kept on purpose**, see SELinux below |
| post-fs-data: data dirs (misc, ssrdump, display, media, tz, qtee, camera, tombstones, ramdump, bluetooth, bsplog/*, wifi/*, connectivity (cnd), audio, fm, perfd, iop, qti-logkit, swap, vpp, tui), `vold.post_fs_data_done`, dm read_ahead | `/data/vendor/camera` and `/data/vendor/audio` go back to **0770** (stock). The current tree uses garnet's 0777. The camera provider runs as cameraserver in group camera/audio, so 0770 is enough |
| services: qcomsysd (+persist triggers), vendor.ssr_setup, vendor.ss_ramdump, qcom-c_core-sh, qcom-c_main-sh, vendor.qrtr-ns, irsc_util, vendor.wigig_supplicant, cnss-daemon (+shutdown trigger), ssgqmigd, mlid, qcom-sh, qcom-post-boot, wifi-sdio-on, wifi-crda, hostapd_fst, vendor.ssr_diag, vendor.power_off_alarm, bugreport | all binaries present, all have domains. `ss_ramdump` goes back to the stock single `group` line. The current tree has a second `group system` line that overrides the first and silently drops root/media_rw/everybody |
| property triggers: ssr/pil/ramdump/rawdump, boot_completed (UFS back on, lmkd.reinit, cvp boot), core_pattern (persist.debug.trace), media target, opengles, gpu freqs, `ro.vendor.radio.noril -> ro.radio.noril` | the atfwd/rild triggers were removed. The noril mirror is harmless: it is a no-op until ro.vendor.radio.noril is set |
| `on charger`: start qcom-post-boot | the stock `setprop persist.sys.usb.config mass_storage` was dropped (garnet dropped it too). init.qcom.usb.rc already handles charger-mode USB |

### Added (not in stock)

| Block | Why |
|---|---|
| `on charger`: chown the panel0/panel1 backlight to system | from the current tree. `on boot` does not run in off-mode charging, and the charger UI (`vendor.charger` = health-service.qti --charger, user system) sets the brightness |
| header comment | lists which services are defined elsewhere |

### Removed vs stock

| Removed | Reason |
|---|---|
| `on early-init && property:ro.debuggable=1` debugfs mount + `setprop ro.product.debugfs_restrictions.enabled false` + keep_debugfs | AOSP `init-debug.rc` already handles debugfs on debuggable builds. The `ro.` setprop fails because the prop is already set. vendor_init has no `mounton` on debugfs (we checked) |
| `/dev/socket/qmux_radio`, `ro.telephony.call_ring.multiple` | QCRIL/telephony |
| `chmod 0755 /system/bin/ip` | /system is read-only and not SUID in AOSP, so it is a no-op. vendor_init has no setattr on system_file |
| remoteproc0/1/2 coredump writes (post-fs-data), ruan remoteproc3 block | debug ramdumps only. The ruan block is for another board |
| `/data/vendor/radio`, `modem_config`, qcril db copies, `prebuilt_db_support`, `copy_complete`, the `mbn_copy_completed` trigger | telephony |
| `/data/vendor/secure_element`, `/data/vendor/nfc`, `nqnfcinfo`, `esepmdaemon` | NFC/eSE |
| `iop`, `qmiproxy`, `move_wifi_data`, `wigignpt` (+trigger), `sensingdaemon`, `dhcpcd_*`/`iprenew_*` (wlan, bond0, p2p, wigig0, bt-pan), `ptt_socket_app`, `ptt_ffbm`, `wifi_ftmd` + pronto insmod, `qti-testscripts` (+start), `qvop-daemon`, `vendor.atfwd` (+2 triggers), `battery_monitor`, `vendor.ril-daemon2/3`, `profiler_daemon`, `diag_mdlog_start/stop`, `qlogd` (+triggers), `vm_bms`, `vendor.msm_irqbal_lb`, `vendor.msm_irqbl_sdm630`, `vendor.LKCore-dbg/rel`, `qseeproxydaemon`, `poweroffhandler`, `vendor.hbtp`, `chre` (+trigger), rild.libpath trigger | the binary or config is missing from our build (most are missing from stock too), or it is telephony |
| `service charger /system/bin/charger` | no such binary in our system. Off-mode charging comes from `vendor.charger` in android.hardware.health-service.qti.rc |
| `service wpa_supplicant` | **duplicate**: our supplicant is defined in `vendor/etc/init/android.hardware.wifi.supplicant-service.rc` (AIDL, socket wpa_wlan0). The stock QCOM definition (socket vendor_wpa_wlan0, `-puse_p2p_group_interface=1`) must not be added back |
| `service time_daemon` | **duplicate** of `init.time_daemon.rc` (garnet commit acd3877 removed it for the same reason) |
| `service vendor.msm_irqbalance` | **duplicate** of `init.qti.kernel.rc` (identical definition). The current build has both, so init logs a duplicate-service error |
| `start wcnss-service` in the vold.decrypt trigger | no such service |

### Removed vs current (garnet-only content)

| Removed | Reason |
|---|---|
| `enable vendor.qcrild/qcrild2/dataqti/dataadpl` (garnet ce35584) | telephony. dataqti.rc/dataadpl.rc are still shipped but stay `disabled` |
| `vendor.display.mixer_resolution` from `persist.sys.miui_resolution` (2 places) | MIUI framework prop, never set on our ROM. Not in dizi stock |
| `/data/vendor/modem` (+diag_logs 0777), `/dev/smd8` perms | modem |
| `/data/vendor/camera/offlinelog` 0777, `/dev/camlog`, `/dev/mi_exception_log`, `/proc/mi_log/*` | MIUI logging, not in dizi stock |
| `/data/vendor/mac_addr` | no consumer in our vendor (grep of bin/lib64). cnss-daemon reads persist `wlan_mac.bin` itself |
| `/data/vendor/qrtr`, `service qrtr-lookup` + `start qrtr-lookup` at boot_completed | stock does not run it. It has **no SELinux domain**, so it runs as `u:r:init`. That causes the b19 denials (`execute_no_trans`, `qipcrtr_socket` create/read/write), and in enforcing mode init refuses to start it |
| `ntag5_tool` | NFC, binary missing |
| remoteproc4 recovery + remoteproc2/3/4 coredump in the ramdump trigger | garnet remoteproc numbering, debug only |
| `-S wigigsvc` on vendor.wigig_supplicant | garnet change; stock dizi has no `-S` |
| diag_mdlog (auto) start/stop + `persist.vendor.radio.diag_log_trriger` triggers, `vendor.diag.tcpdump` + triggers, `logcatlog` start | diag_mdlog and /vendor/bin/tcpdump are not in our vendor |
| boot_completed debugfs mount/keep_debugfs, `cooling_device39..50` chmod 0666 | debug/modem (4Rx/2Rx is a modem antenna cooling device). The keep_debugfs setprop causes the b19 `vendor_init read persist.dbg.keep_debugfs_mounted` denial |

---

## init.target.rc

### Kept from stock

| Block | Note |
|---|---|
| import init.qti.kernel.rc | |
| early-init: printk_devkmsg, MEMTAG_OPTIONS | the current tree also writes `/dev/memcg/camera/provider/...soft_limit`: garnet only, dropped |
| init: bootdevice symlink, auto_hibern8, start logd | the stock `chmod 0666 /dev/uhid` was dropped (see risks) |
| fs: early mount, persist perms, persist/data, rescue mount, logfs mount | the logfs (sde64) and rescue (sda16) partitions exist on dizi |
| late-fs | |
| post-fs-data: /vendor/data/tombstones (a no-op on RO /vendor, kept as stock), `vendor.qti.qcc.oper.mode 4`, `cnss/fs_ready 1`, torch/switch LED perms, `/data/vendor/wlan_logs 0770 system wifi` | qcc goes back to stock **4** (current: 3, plus `qdma.oper.mode 3`, which stock never sets). `fs_ready` is at the stock post-fs-data point instead of garnet's early-boot. LEDs are 0664 instead of stock 0666: owner system is enough |
| early-boot: start vendor.sensors, verity_update_state | |
| boot: audio-app cpus **4-7** (stock; current 0-7), camera-daemon cpuset, trusted_touch, hyp_core_ctl, vendor.usb.controller, thermal_message boost/balance_mode, tcp_mtu_probing | tcp_mtu_probing sits at top level in stock, so it belongs to `on boot` |
| charger: firmware mount + adsp boot; `on charger` power_off_alarm, sys.usb.controller, wait udc, sys.usb.configfs 1 | the stock offlinelog setprop was dropped |
| pd_mapper, per_mgr, per_proxy (+triggers), mdm_launcher, shutdown trigger, pcie boot_option | |

### Kept from current (LineageOS/garnet, still needed on dizi)

| Block | Why |
|---|---|
| touch `gesture_{single,double}_tap_enabled`, `gesture_double_tap_state` chown/chmod | used by hardware/xiaomi sensors v2 (`Sensor.h`), which is enabled by `ro.vendor.sensors.xiaomi.{single,double}_tap=true` in props/vendor.prop. The HAL runs as system |
| `on charger`: `qcom_lpm/parameters/sleep_disabled 0` | LineageOS change so off-mode charging can reach low-power modes |
| `on property:sys.boot_completed=1`: `chmod 440 /proc/net/unix` | garnet 0b61ef1 (banking-app root detection). vendor_init has setattr on proc_net |

### Removed vs stock

| Removed | Reason |
|---|---|
| `/dev/mi_display/disp_feature` (fs, early-boot) | displayfeature HAL not in our build. ueventd-odm.rc already sets `/dev/mi_display/*` |
| `/dev/xlog` 0666 | MIUI log device. ueventd.qcom.rc sets 0660 system audio |
| `on fs && sku=taro` spunvm mount | dizi is sku=parrot, so it never triggers |
| post-fs `/dev/miev` (misight) | no misight in our build. It causes the b19 `vendor_init getattr device:chr_file /dev/miev` denial |
| post-fs `setrlimit 8` | redundant with init.qcom.rc early-boot (garnet f7bf097) |
| `persist.sys.offlinelog.*` setprops | MIUI, system-owned persist props |
| SarNV writes/chmod 0666 and **chmod 0707** on `/mnt/vendor/persist/rfs/msm/mpss` | modem SAR. 0707 on persist rfs is dangerous |
| `mi_serial` + post-fs trigger | `init.mi.serial.sh` is not in our vendor. It only mirrors persist serial/MAC files into ro.ril.oem.* props. The BT HAL reads `/mnt/vendor/persist/wlan/bt_mac.bin` itself, and cnss-daemon reads `wlan_mac.bin` |
| `cnss_diag` service + triggers, the CIT debuggable block (enables cnss_diag and tcpdump) | cnss_diag is not in our vendor (garnet 3a24d78 dropped it too) |
| ruan eSIM blocks | another board, telephony |
| `sys.tp.grip_enable` -> `/proc/tp_grip_area` | only set by the MIUI framework |
| `fatal_err_check` | `check_fatal_err.sh` is not in our vendor |
| `vendor.post_boot.parsed` -> `enable/start vendor.qvirtmgr` | there is no such service (ours is `vendor.vm-mgr` in vmmgr.rc). init.dizi.rc also uses this trigger, and that does not conflict |
| wifiSarTool(_v2), openwifi_L/closewifi_L, wifiFtmdaemon, myftmftm, wdsdaemon, blueduttest, btclose, vendor.tcpdump/sniffer (vendor_tcpdump), start/stoppktlog (iwpriv) and all their triggers | factory/RF-test tools, binaries not in our vendor |
| `persist.ro.ril.oem.btmac -> ro.ril.oem.btmac` | display mirror for MIUI. The BT HAL sets and reads the persist prop itself |

### Removed vs current (garnet-only content)

| Removed | Reason |
|---|---|
| imports of `hw/init.mi_thermald.rc`, `hw/init.batterysecret.rc`, `/system/etc/init/init.factory.rc`, `init.charge_logger.rc` | none of these paths exist. init.mi_thermald.rc lives in /vendor/etc/init and is auto-loaded (see gaps for batterysecret) |
| cpuset `foreground/boost`, `cpuctl/{background,top-app}/cpu.shares` 0666 | legacy/MIUI. powerhint.json does not use them, and 0666 is unsafe |
| persist `haptics`, `audio`, `qca6490`, `camera` mkdirs | these already exist on the persist partition. Stock does not create them. qca6490 is garnet's Wi-Fi chip |
| `/data/vendor/{thermal,thermal/config}` | init.mi_thermald.rc creates them |
| `/data/vendor/perfspy`, `/dev/ir_spi`, `/data/vendor/nfc`, `/data/vendor/qxwz` | garnet/IR/NFC/MIUI |
| extended torch/flash/switch 0-3 LED list (including the typo `brightnesssss`) | stock list used instead |
| `/data/vendor/wlan_logs 0777 root shell` | stock `0770 system wifi` |
| `mi_display/disp-DSI-*` sysfs perms | no consumer in our build (stock does not set them either) |
| thermal_message sconfig/charger_temp/board_sensor_temp_comp/cpu_nolimit_temp/flash_state chowns | sconfig is already chowned by init.mi_thermald.rc (on fs), and parts' ThermalUtils only needs sconfig. The rest are MIUI |
| `perf_helper/mimd/mimdtrigger`, gpu_plaid, `cpuctl/misc`, ufscld/ufsfbs chowns | MIUI mimd/cld HALs, not in our build |
| `/dev/xiaomi-touch` chown/chmod | already in init.dizi.rc (duplicate) |
| `fod_longpress_gesture_enabled` | no FOD on dizi |
| `on property:vendor.display.lcd_density=560/640` -> `dalvik.vm.heapgrowthlimit` | commented out in stock. **Behaviour change**, see risks |
| spkcal (crus/aw/fsalgo) calibration copy block | garnet amps. dizi uses SIA amps (sipa.bin). Not in stock |
| `on property:ro.debuggable=1 start vendor.tcpdump`, tcpdump/sniffer services + triggers | /vendor/bin/tcpdump is not in our vendor |
| `vendor.nv_mac`, `vendor.bt_wdsdaemon` (+triggers), `fatal_err_check` | binaries missing |
| migt/metis module parameter chmod 0666/0777 block, `/dev/migt`, `/dev/metis`, `/dev/miev` | MIUI scheduler modules (not loaded on dizi, per recon/modules.txt), world-writable |
| `sys.lmkd.memory.compact` compaction, `sys.volume.*` -> `vendor.volume.*` mirrors | MIUI framework props |
| `on boot` `qcom-battery/input_suspend` chown/chmod 774 | ueventd.qcom.rc already sets `input_suspend 0660 system system` |

---

## SELinux notes (write/chmod/chown on sysfs/proc/configfs)

All commands in these two files run as **vendor_init**. On our policy,
vendor_init may write and setattr generic `sysfs`, most vendor sysfs types,
`proc_net`, `cgroup`, `kmsg_device`, `debugfs_tracing_debug`, touch/LED/graphics
sysfs, and mnt_vendor/persist dirs. So almost everything kept is allowed. The
items that are denied or noteworthy:

| Item | Context | Stock has it? | Status |
|---|---|---|---|
| `write .../sda/queue/discard_max_bytes` | **u:r:init** from `/system/etc/init/hw/init.rc:1232` (`/dev/sys/block/by-name/userdata`) | the AOSP line is not in the vendor rc | **Denied** (b19: `init sysfs:file open/write`). Our vendor_init copy in init.qcom.rc is *allowed*. It does the real work and is why it is kept. To silence the AOSP line: label the UFS block queue (e.g. genfscon under `/devices/platform/soc/1d84000.ufshc/.../block/sda/queue` as a vendor type) and `allow init <type>:file w_file_perms`, or `dontaudit init sysfs:file { open write }` |
| `chown/chmod /proc/last_kmsg` | **u:r:init** from `/system/etc/init/hw/init.rc:644-645` | not in any stock vendor rc | **Denied** (b19: `init proc:file setattr`). This is not an rc problem. /proc/last_kmsg has no genfscon label. Fix in device sepolicy: add a `proc_last_kmsg` type with `genfscon proc /last_kmsg`, then `allow init proc_last_kmsg:file setattr` (and read for dumpstate), or dontaudit |
| `write /proc/sys/kernel/core_pattern` (on `persist.debug.trace=1`) | vendor_init -> `usermodehelper` | yes (and current) | **Denied** if triggered. Debug only. Kept as stock |
| qrtr-lookup (current) | init (no domain) | no | removed; this was the main init-domain denial source in b19 |
| `/dev/miev` chmod (current and stock) | vendor_init -> `device` | yes | removed |
| keep_debugfs setprop (current) | vendor_init read `default_prop` | stock has an early-init variant | removed |
| `chmod /system/bin/ip` | vendor_init -> system_file setattr (not allowed); EROFS first in practice | yes | removed |
| remoteproc coredump writes | generic sysfs, allowed | yes | removed anyway (debug) |
| tracefs `chmod 0755 /sys/kernel/tracing` | debugfs_tracing_debug setattr, allowed | yes | kept |
| coresight `chown -h vendor_qdss` | vendor_sysfs_qdss_dev/sysfs file setattr, allowed | yes | kept. Note that `-h` targets a symlink only if the last component is a link. Here it is not |
| `chmod 440 /proc/net/unix` | proc_net setattr, allowed | no (Lineage) | kept |
| `/dev/uhid 0666` (stock) | allowed, but world-writable uhid | yes | removed. ueventd gives 0660 uhid:uhid. The sensors HAL already has group uhid |

Not caused by these files, but visible in the same b19 log:
- `vendor_init set persist.mm.enable.prefetch` / `persist.vendor.ssr.restart_level`
  at 0.85 s (pid 1). These come from **build.prop loading**, not from an rc file.
  Fix: label the props in vendor property_contexts, or drop them from vendor.prop.
- `vendor_qti_init_shell` configfs `coresight-stm:p_ost.policy` mkdir: from
  `init.qti.kernel.sh`/debug scripts, not from these rc files.
- **init.dizi.rc**: `vendor.usb_attach` (seclabel `vendor_qti_init_shell`) writes
  the USB `mode` node: `vendor_qti_init_shell -> vendor_sysfs_usb_device:file write`
  is **denied** by our policy. This needs
  `allow vendor_qti_init_shell vendor_sysfs_usb_device:file w_file_perms;` before
  enforcing. Otherwise the USB-recovery hack silently fails in enforcing mode.

## init.dizi.rc: conflicts with the proposed files

- No service-name conflicts. `vendor.audio-hal` and `vendor.sensors-hal-multihal`
  are proper `override`s.
- `/dev/xiaomi-touch` was chowned in both current init.target.rc and init.dizi.rc.
  The proposed init.target.rc drops its copy.
- `vendor.post_boot.parsed`: init.dizi.rc copies/writes cpusets. Stock's
  qvirtmgr use of the same trigger is removed. No conflict.
- init.dizi.rc sets foreground cpus 0-6 and background 0-1. init.target.rc now sets
  audio-app 4-7 (stock) instead of 0-7. The cpusets are independent.
- `sconfig 20` at boot_completed agrees with init.mi_thermald.rc's chown.

## Risks / behaviour changes to watch on the first boot

1. **dalvik heapgrowthlimit.** The current tree's `vendor.display.lcd_density=640`
   trigger sets `dalvik.vm.heapgrowthlimit 512m` at runtime, and
   init.qcom.early_boot.sh sets that density on dizi (stock getprop shows 640).
   The proposed files drop the trigger (stock has it commented out). The
   build-time value of **192m** then takes effect. Stock runs 256m (heapsize
   512m). Set `dalvik.vm.heapgrowthlimit` explicitly in the device props before
   or with this change (see the PLAN "Dalvik heap A/B" item). Otherwise large
   apps may OOM sooner than on b19.
2. **qcc oper mode 3 -> 4** and qdma oper mode no longer set: matches stock.
   qcc-trd/qdmastats read it. Watch for qcc-trd errors.
3. **audio-app cpuset 0-7 -> 4-7**: matches stock. Low risk. Check audio
   underruns during the audio tests.
4. **/data/vendor/camera and /data/vendor/audio 0777 -> 0770**: existing dirs on a
   dirty flash keep their old mode (mkdir does not chmod existing dirs). A clean
   flash gets 0770. If the camera or audio HAL logs EACCES on these, revert to 0777.
5. `cnss/fs_ready` moves from early-boot to post-fs-data (stock timing). This
   should help WLAN cold-boot calibration find /data earlier. Check that Wi-Fi comes up.
6. vendor.wigig_supplicant and `msm_11ad_proxy` are kept as in stock (disabled,
   and the module is present). Drop both if the module load logs errors.
7. The stock `on charger` `setprop sys.usb.configfs 1` duplicates
   init.qcom.usb.rc. It is harmless, but test off-mode charging once.

## Out-of-scope gaps found on the way

- **batterysecret is shipped but never started.** `vendor/bin/batterysecret` and
  its SELinux domain are in our build, but no rc defines the service. The current
  init.target.rc imports a nonexistent `/vendor/etc/init/hw/init.batterysecret.rc`.
  Stock runs it (init.svc.batterysecret=running; it starts at boot_completed and in
  charger mode, and handles the PD adapter-verify nodes). Fix: add stock
  `vendor/etc/init/init.batterysecret.rc` to proprietary-files.txt. It
  auto-loads from /vendor/etc/init, so no import is needed. Relevant to the
  33 W fast-charge check. (`charge_logger` is logging only, so skip it.)
- Telephony rc files still shipped in vendor/etc/init: dataqti.rc, dataadpl.rc,
  netmgrd.rc, modemManager.rc, port-bridge.rc, dpmQmiMgr.rc, vendor.dpmd.rc,
  ipacm.rc. dataqti is disabled, but modemManager, netmgrd and port-bridge are `class main`.
  Consider dropping them from the blob list for a Wi-Fi-only device.
- init.qcom.usb.rc in our build is the CAF source version (2022-2024 header,
  `zygote-start` gadget setup), not the stock file. It was not touched here.
- The stock getprop shows `sys.usb.controller=dummy_udc.0` even though stock
  init.target.rc sets vendor.usb.controller a600000.dwc3. This may matter for the
  USB-attach investigation.
