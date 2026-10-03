# Pre-install checklist (run on the CURRENT omarchy box, before wiping)

Do these in order. Nothing here is destructive until step 6 (writing the USB), and
that only touches the USB stick.

## 0. Reattach and VERIFY the backup  ← NOT DONE, do not skip
As of **2026-10-03 the HDD is not plugged in** — `lsblk` shows only `nvme0n1` and
`/mnt` is empty. A backup was made on 2026-09-06 at `/mnt/pre-wipe-sep-2026/` on
`sda`, plus the 235G music master at `/mnt/music`, but none of that is confirmable
while the drive is detached.

Plug `sda` back in, then actually look at it:
```
lsblk                                  # expect sda ~3.6T to reappear
ls  /mnt/pre-wipe-sep-2026/
du -sh /mnt/pre-wipe-sep-2026/ /mnt/music/
ls  /mnt/pre-wipe-sep-2026/.ssh/       # the keys INSTALL.md step 3 restores
ls  /mnt/pre-wipe-sep-2026/projects/
```
You are about to wipe the only copy of everything on `nvme0n1` (337G in use). Do
not proceed on the assumption that a backup you cannot see is intact.

`sda` is a SEPARATE physical drive from the wipe target, so the install never
touches it — you unplug it in step 7 purely to make choosing the wrong disk
impossible.

## 1. Push this config repo to GitHub  ← DONE 2026-10-03
Live at **https://github.com/allofher/oxton-nixos** (public). An unauthenticated
`git clone` over HTTPS is confirmed working, which is exactly what INSTALL.md step 7
does from the live environment — no tokens or security keys needed mid-install.

Public was deliberate: there are no secrets in this repo. The ssh key in it is a
*public* key, Tailscale auth is interactive (`tailscale up`), and the LUKS
passphrase lives in 1Password. **Keep it that way** — if you ever need a real
secret in here, use `sops-nix` or `agenix` rather than flipping the repo private
and assuming that covers you.

If you commit anything else before the wipe, remember to `git push` it.

## 2. De-risk: build the config in a VM first  ← recommended
This catches an eval error or a bad option name *while you still have a working
machine*. The alternative is finding out from a failed `nixos-install` with your old
OS already gone.

Nix is not installed on this box yet. Install it (Determinate installer), then:
```
# configuration.nix imports ./hardware-configuration.nix, which doesn't exist
# yet — give the import something to resolve so the flake can evaluate:
cat > ~/nixos/hardware-configuration.nix <<'STUB'
{ ... }:
{
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
}
STUB

nixos-rebuild build-vm --flake ~/nixos#oxton
./result/bin/run-oxton-vm

rm ~/nixos/hardware-configuration.nix   # throwaway — the real one is generated
                                        # on the machine during install
```
This validates the *logical* config — packages resolve, services and units are
defined, greetd/sway come up. It tells you nothing about your actual disks, the GPU,
or TPM unlock, all of which are hardware-specific. Don't skip the real verification
in INSTALL.md step 11.

## 3. Note things you'll need during/after install (write them on your laptop)
- Config repo: `https://github.com/allofher/oxton-nixos`
- Your Tailscale admin console URL (to remove the stale `omarchy` node later)
- 1Password access from your laptop — **this is where the LUKS passphrase goes**;
  the emergency kit is also at `/mnt/1Password Emergency Kit...pdf` on the HDD
- Hostname you want (config says `oxton`; this box is currently `omarchy`)

## 4. Identify the USB stick — CAREFULLY
Before plugging the USB in:
```
lsblk
```
Note what's there (`sda` = HDD, `nvme0n1` = system). Then plug the USB in and run
`lsblk` again. The NEW device that appeared is your USB (likely `/dev/sdb`, maybe
8–64G). **Write that device name down. Do not confuse it with `sda`, your 3.6T HDD.**

## 5. (Optional) verify the ISO
```
cd ~/downloads
sha256sum nixos-graphical-26.05.8954.a5cc6f2c37bf-x86_64-linux.iso
```
Compare against the hash on nixos.org/download if you kept it.

## 6. Write the ISO to the USB  ← destroys the USB's contents (only the USB)
Replace `sdX` with the USB device from step 4. **Triple-check it is the USB.**
```
sudo dd if=~/downloads/nixos-graphical-26.05.8954.a5cc6f2c37bf-x86_64-linux.iso \
  of=/dev/sdX bs=4M status=progress oflag=sync
sync
```

## 7. Unmount and physically disconnect the HDD
Only after step 0 is genuinely done.
```
sudo umount /mnt
```
Then **power off and unplug the HDD (`sda`) cable** before installing. With it
physically absent it's impossible to select the wrong disk. You reconnect it after
the first successful boot to restore your files.

## 8. Reboot into the USB
Reboot, hit the boot-menu key (often F8/F11/F12/Del for your board), pick the USB.

You're now in the NixOS live environment → follow `INSTALL.md`.
