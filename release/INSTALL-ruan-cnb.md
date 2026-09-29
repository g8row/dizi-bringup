# Evolution X 12.2 (Android 17) for the Redmi Pad Pro 5G / POCO Pad 5G (ruan) – unofficial

**Device:** Redmi Pad Pro 5G / POCO Pad 5G, codename `ruan` (SM7435). Not for the Wi-Fi model (`dizi`).

**This is the first Android 17 build for ruan.** It is built from the working dizi (Wi-Fi model) ROM plus the
5G model's modem, GPS and telephony parts, but it has not run on a ruan yet. Expect problems,
especially with calls, mobile data, SMS and GPS. Please send logs (see below) whatever happens,
including "it works".

## Before you start

- **Unlock the bootloader** with Xiaomi's official tool. This wipes the tablet.
- **Install Android platform-tools** (`adb` and `fastboot`) on a PC or Mac.
- **Update HyperOS first:** the tablet should run HyperOS **OS3.0.303.0 or newer** (Android 16 firmware).
  The ROM reuses the firmware partitions (modem, bootloader, TrustZone) already on the tablet.
- **Back up your data.** A first install wipes everything.
- **Never relock the bootloader** while this ROM is installed. That would brick the tablet.
- Keep Xiaomi's fastboot ROM for ruan at hand to go back (see the end).

## First install (recovery + sideload, the usual Evolution X way)

Downloads: `boot.img`, `dtbo.img`, `vendor_boot.img`, `recovery.img` and the ROM zip
`EvolutionX-…-ruan-12.2-Unofficial.zip`.

1. Reboot to the bootloader: power off, then hold **power + volume down**. Connect over USB.
2. Flash the recovery-side images:
   ```
   fastboot flash boot boot.img
   fastboot flash dtbo dtbo.img
   fastboot flash vendor_boot vendor_boot.img
   fastboot flash recovery recovery.img
   fastboot reboot recovery
   ```
3. In recovery, choose **Factory reset → Format data / factory reset** and confirm.
4. Go back and choose **Apply update → Apply from ADB**. On the computer run:
   ```
   adb sideload EvolutionX-…-ruan-12.2-Unofficial.zip
   ```
   The transfer may stop at about 47% on the computer; that's normal.
   Wait until recovery reports success.
5. **Reboot system now.** The first boot takes a few minutes. Google apps are included.

### Alternative: fastboot package

Unpack `EvolutionX-…-ruan-fastboot.zip`, boot to the bootloader, and run `./flash-ruan.sh`.
It flashes everything from fastboot and wipes data; type `yes` when asked.

## Sending logs

The log scripts need USB debugging. Turn on
*Settings → About tablet → tap Build number 7 times*, then *Settings → System → Developer options →
USB debugging*, connect the tablet and allow the computer when the tablet asks.

Reproduce the problem, then right away run from the fastboot package folder:

- **Windows:** double-click `collect-logs.bat` (put `adb.exe`, `AdbWinApi.dll` and `AdbWinUsbApi.dll`
  from platform-tools next to it, or have adb on PATH). It makes a `logs-ruan-….zip`.
- **Linux / macOS:** `./collect-logs.sh`. It makes a `logs-ruan-….tar.gz`.

If the tablet does not boot, boot it to recovery (power + volume up), choose *Advanced → Enable ADB*,
and run the same script there.

The logs can contain your phone number, IMEI, SIM and network details and Wi-Fi names. Send them
only to the maintainer, with a short note of what you did and what went wrong.

## What to test

- SIM detected (both slots if you have two SIMs), signal bars, network name.
- Mobile data (4G/5G), calls (incoming and outgoing, audio both ways), SMS, VoLTE if your carrier has it.
- GPS (a maps app outdoors).
- Everything that works on the Wi-Fi model should work too: display, touch, pen, speakers,
  cameras, Wi-Fi, Bluetooth, sensors, charging, sleep.

## Updating

- **Recovery:** reboot to recovery, choose *Apply update → Apply from ADB*, and sideload the new zip.
  No format is needed. This keeps your data.
- **Fastboot package:** `./flash-ruan.sh --keep` keeps your data.

Updates only install over builds signed with the same keys, i.e. this ROM's own releases.

## Getting back to HyperOS

Flash Xiaomi's fastboot ROM for ruan with its `flash_all.sh` (**not** `flash_all_lock.sh`).
