# Pre-install checklist (run on the CURRENT omarchy box, before wiping)

Do these in order. Nothing here is destructive until step 6 (writing the USB), and
that only touches the USB stick.

## 0. Reattach and VERIFY the backup  ← DONE 2026-10-03, backup confirmed good
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

## 2. De-risk: evaluate the config  ← DONE 2026-10-03, PASSING

Nix is installed on this box (Determinate Nix 3.23.0 / 2.35.2) and the full system
closure evaluates clean — no errors, no warnings. It took three fixes to get there,
every one of which would otherwise have blown up mid-install:

| Found | Why it mattered |
|---|---|
| `services.mpd.extraConfig` removed in 26.05 (RFC42) | hard eval failure; `musicDirectory` and `network.listenAddress` renamed too |
| `noto-fonts-emoji` → `noto-fonts-color-emoji` | hard eval failure |
| `pkgs.greetd.tuigreet` → `pkgs.tuigreet` | greetd would point at a nonexistent attr |

Plus two found by reading, before nix was even installed: missing
`nixpkgs.config.allowUnfree` (Steam is unfree — `nixos-install` would have failed
outright) and `services.pipewire` never enabled while mpd outputs to it.

Install size: 185 derivations to build, 1710 paths to fetch, **4.0 GiB download /
9.9 GiB unpacked**. Budget bandwidth accordingly.

To re-run it after any config change:
```
bash <(curl -s ...)  # no — just re-run the eval directly:
cd ~/nixos
git add -N hardware-configuration.nix   # only if you've made a local stub
nix build --dry-run .#nixosConfigurations.oxton.config.system.build.toplevel
```
Two things that trip this up: flakes only see **git-tracked** files, so an untracked
`hardware-configuration.nix` is invisible (`git add -N` fixes it — intent-to-add,
which keeps it out of commits); and the stub must be deleted afterwards so it can
never shadow the real generated file.

`flake.lock` is committed, pinning nixpkgs to `774debe7` (2026-10-02). The install
gets exactly what was verified here, not whatever the channel moves to.

### Old note: full VM boot (optional, not done)
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

## 4. Identify the USB stick — by ATTRIBUTE, never by name

> **Kernel device names are not stable, and this already bit us.** In September
> `sda` was the 3.6T HDD. On 2026-10-03, with the HDD unplugged, `sda` was the
> **USB stick**. Anything in these notes that says "sda = HDD" is only true for
> the session it was written in. Never `dd` to a name you assumed.

Identify by what the device *is*:
```
lsblk -o NAME,SIZE,TYPE,TRAN,RM,HOTPLUG,FSTYPE,LABEL,MODEL,SERIAL,MOUNTPOINTS
```
The USB stick is the one where **`TRAN=usb` and `RM=1`** (removable), with a
plausible flash size and a flash-drive `MODEL`. The nvme reads `TRAN=nvme`, and
the HDD reads `TRAN=sata` at ~3.6T. Cross-check the `SERIAL` against the stick
if you have two USB devices attached.

Confirmed example from 2026-10-03:
```
sda  57.6G disk usb 1 1 exfat Untitled "USB Flash Drive" 7446121107142579
```
`TRAN=usb`, `RM=1`, 57.6G, flash-drive model string → that is the USB.

## 5. (Optional) verify the ISO
```
cd ~/downloads
sha256sum nixos-graphical-26.05.8954.a5cc6f2c37bf-x86_64-linux.iso
```
Compare against the hash on nixos.org/download if you kept it.

## 6. Write the ISO to the USB  ← destroys the USB's contents (only the USB)
Re-run the `lsblk` from step 4 **immediately before this command** and confirm the
target by `TRAN=usb` + `RM=1` + size + serial. Write to the **whole device**
(`/dev/sdX`), not a partition (`/dev/sdX1`).
```
sudo dd if=~/downloads/nixos-graphical-26.05.8954.a5cc6f2c37bf-x86_64-linux.iso \
  of=/dev/sdX bs=4M status=progress oflag=sync conv=fsync
sync
```
Then verify the write actually landed, rather than trusting it:
```
sudo cmp -n 3843686400 \
  ~/downloads/nixos-graphical-26.05.8954.a5cc6f2c37bf-x86_64-linux.iso /dev/sdX \
  && echo "WRITE VERIFIED"
```
ISO sha256, confirmed against releases.nixos.org on 2026-10-03:
`4fe1e5f85166506bebb17831ec07c8db3593c2bf393fc1bb649acb4993439f21`

## 7. Unmount and physically disconnect the HDD
Only after step 0 is genuinely done.
```
sudo umount /mnt
```
Then **power off and unplug the HDD cable** before installing — identify it as the
~3.6T `TRAN=sata` disk, not by device name (see the warning in step 4). With it
physically absent it's impossible to select the wrong disk. You reconnect it after
the first successful boot to restore your files.

## 8. Reboot into the USB
Reboot, hit the boot-menu key (often F8/F11/F12/Del for your board), pick the USB.

You're now in the NixOS live environment → follow `INSTALL.md`.
