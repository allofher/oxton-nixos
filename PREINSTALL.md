# Pre-install checklist (run on the CURRENT omarchy box, before wiping)

Do these in order. Nothing here is destructive until step 5 (writing the USB),
and that only touches the USB stick.

## 0. Confirm the backup is complete
Already done — full backup lives at `/mnt/pre-wipe-sep-2026/` on the HDD (`sda`),
plus your 235G music master at `/mnt/music`. `sda` is a SEPARATE physical drive
from the wipe target (`nvme0n1`). Nothing on `sda` gets touched.

## 1. Push this config repo to GitHub  ← critical
You clone this during the install, so it MUST be on GitHub first.
```
cd ~/nixos
gh repo create oxton-nixos --private --source=. --remote=origin --push
```
Verify from your phone/laptop that the repo is visible on github.com.

## 2. Note things you'll need during/after install (write them on your laptop)
- GitHub repo URL for this config
- Your Tailscale admin console URL (to remove the stale `omarchy` node later)
- 1Password access from your laptop (emergency kit is also at `/mnt/1Password Emergency Kit...pdf`)
- New hostname you want (default in config: `oxton`)

## 3. Identify the USB stick — CAREFULLY
Before plugging the USB in:
```
lsblk
```
Note what's there (`sda` = HDD, `nvme0n1` = system). Then plug the USB in and:
```
lsblk
```
The NEW device that appeared is your USB (likely `/dev/sdb`, maybe 8–64G).
**Write that device name down. Do not confuse it with `sda` (your 3.6T HDD).**

## 4. (Optional) verify the ISO
```
cd ~/downloads
# compare against the hash on nixos.org/download if you kept it
sha256sum nixos-graphical-26.05.8954.a5cc6f2c37bf-x86_64-linux.iso
```

## 5. Write the ISO to the USB  ← destroys the USB's contents (only the USB)
Replace `sdX` with the USB device from step 3. **Triple-check it is the USB.**
```
sudo dd if=~/downloads/nixos-graphical-26.05.8954.a5cc6f2c37bf-x86_64-linux.iso \
  of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

## 6. Unmount and physically disconnect the HDD
```
sudo umount /mnt
```
Then **power off and unplug the HDD (`sda`) cable** before installing. With it
physically absent, it's impossible to select the wrong disk. You'll reconnect it
after the first successful boot to restore your files.

## 7. Reboot into the USB
Reboot, hit the boot-menu key (often F8/F11/F12/Del for your board), pick the USB.

You're now in the NixOS live environment → follow `INSTALL.md`.
