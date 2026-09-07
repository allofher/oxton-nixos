# Install guide (run inside the NixOS 26.05 live environment)

Assumes the HDD (`sda`) is physically unplugged, so the ONLY disk is `nvme0n1`.

> **Encryption decision (top-level choice):** this guide's main path installs an
> **unencrypted** root — simplest, and it boots unattended so you can reboot the
> box remotely and just ssh back in. That's a reasonable choice for a home
> machine behind a locked door. If you want encryption at rest, use LUKS + TPM2
> auto-unlock instead (so it still boots unattended) — see the sidebar at the
> bottom. Pick one before partitioning.

## 1. Get online
- Wired: usually automatic.
- Wi-Fi: use the desktop's network applet, or `nmtui` in a terminal.
Test: `ping -c1 github.com`

## 2. Confirm the target disk
```
lsblk
```
You should see ONLY `nvme0n1` (plus the USB you booted from). If you see a 3.6T
disk, STOP — the HDD is still connected; power off and unplug it.

## 3. Partition the nvme (GPT: EFI + root)
```
sudo -i                       # become root for the rest
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart root ext4 1GiB 100%
```

## 4. Format
```
mkfs.fat -F32 -n boot /dev/nvme0n1p1
mkfs.ext4 -L nixos /dev/nvme0n1p2
```

## 5. Mount
```
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot
```

## 6. Generate the hardware config
```
nixos-generate-config --root /mnt
```
This creates `/mnt/etc/nixos/hardware-configuration.nix` (disk UUIDs, kernel
modules for your 5800X/7900 XTX). You keep this file; you discard the generated
`configuration.nix` in favor of your repo's.

## 7. Pull in your flake config
```
nix-shell -p git   # drops you in a shell with git
git clone https://github.com/<you>/oxton-nixos /mnt/home/liz/nixos
# bring the freshly generated hardware config into the repo:
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/home/liz/nixos/
exit   # leave nix-shell
```

## 8. Install from the flake
```
nixos-install --flake /mnt/home/liz/nixos#oxton
```
- Pulls nixpkgs (needs network), builds the system, installs the bootloader.
- At the end it prompts for the **root** password — set one.

## 9. Set your user password (so you can log in / sudo)
```
nixos-enter --root /mnt -c 'passwd liz'
```

## 10. Reboot
```
reboot
```
Remove the USB when it powers down. You should land at the `tuigreet` login →
log in as `liz` → `sway` (or pick the Steam session).

---

# First-boot tasks (after you're logged into the new system)

1. **Reconnect the HDD** (power off, plug `sda` back in, boot). It should mount;
   if not, add it to `hardware-configuration.nix` or mount by label.
2. **Tailscale:** `sudo tailscale up` → authenticate in the browser. Then remove
   the stale `omarchy` node in the Tailscale admin console.
3. **Restore your data** from the backup:
   ```
   rsync -aH /mnt/pre-wipe-sep-2026/.ssh/ ~/.ssh/
   rsync -aH /mnt/pre-wipe-sep-2026/projects/ ~/projects/
   # dotfiles/.config as you want them — don't bulk-copy omarchy configs
   ```
4. **Fix laptop known_hosts:** on your LAPTOP, `ssh-keygen -R oxton` (and the IP),
   then reconnect and accept the new host key.
5. **Verify the four jobs:**
   - ssh in from the laptop
   - `systemctl status mpd` and point a client at `oxton:6600`
   - `docker run --rm --device=/dev/kfd --device=/dev/dri rocm/pytorch rocminfo | head`
   - launch Steam, confirm a game runs
6. **Commit the hardware config** so the repo is complete:
   ```
   cd ~/nixos && git add hardware-configuration.nix && git commit -m "add hardware config" && git push
   ```

Day-to-day after this: edit files in `~/nixos`, then
`sudo nixos-rebuild switch --flake ~/nixos#oxton`.

---

## Sidebar: encrypted root (LUKS + TPM2 auto-unlock)
If you chose encryption, replace steps 3–5 with:
```
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 1GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart root 1GiB 100%
mkfs.fat -F32 -n boot /dev/nvme0n1p1
cryptsetup luksFormat /dev/nvme0n1p2
cryptsetup open /dev/nvme0n1p2 cryptroot
mkfs.ext4 -L nixos /dev/mapper/cryptroot
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot && mount /dev/disk/by-label/boot /mnt/boot
```
`nixos-generate-config` will add the `luks` device to your hardware config.
After first boot, enrol the TPM for unattended unlock:
```
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-prs=7 /dev/nvme0n1p2
```
and set `boot.initrd.systemd.enable = true;` in configuration.nix.
