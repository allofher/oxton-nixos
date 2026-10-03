# oxton — NixOS desktop config

AMD Ryzen 7 5800X + Radeon RX 7900 XTX (RDNA3/gfx1100). Four jobs:
1. SSH target (+ Tailscale for remote access)
2. Home-network daemons (mpd)
3. Containerized ROCm compute / small-LM finetuning (docker + rocm/pytorch)
4. Steam gaming

## Files
- `flake.nix` — pins nixpkgs, defines `nixosConfigurations.oxton`
- `configuration.nix` — all logical config (pre-preparable)
- `hardware-configuration.nix` — **generated on the machine during install**, then committed
- `pre-nix/` — package + systemd inventory of the old Arch box, for reference

## Install flow (from the NixOS installer)
1. Partition the **nvme only** (see safety note). Mount under `/mnt`.
2. `nixos-generate-config --root /mnt` → produces `/mnt/etc/nixos/hardware-configuration.nix`
3. `git clone <this repo>` and copy in `flake.nix` + `configuration.nix`,
   keeping the freshly generated `hardware-configuration.nix`.
4. `nixos-install --flake .#oxton`
5. Reboot, `sudo tailscale up`, restore `~/.ssh` + `~/projects` from the HDD backup.

## De-risk before wiping (recommended)
Install Nix on the current machine and boot this config in a VM first:
```
# Determinate installer, then:
nixos-rebuild build-vm --flake ~/nixos#oxton
./result/bin/run-*-vm
```
Catches config errors while you still have a working machine.

## Decisions made
- [x] **Disk encryption: LUKS + TPM2 auto-unlock** (2026-10-03). Gets both
      encryption at rest and unattended reboots; board has a TPM 2.0. Passphrase
      kept as the recovery keyslot — it lives in 1Password. See INSTALL.md steps
      4 and 11, and the caveat in `configuration.nix` about Secure Boot being off.
- [x] **Laptop pubkey confirmed** — matches `~/.ssh/authorized_keys` on the old box
      (`ssh-ed25519 …SEmUx oldlaptop`).
- [x] **ESP sized 2GiB**, not 1GiB — NixOS keeps a kernel per generation in `/boot`.
- [x] **Channel: `nixos-26.05`** — matches the install ISO and is current stable.

- [x] **Hostname: `oxton`** (2026-10-03). Already set in configuration.nix. Means
      fixing the laptop's `known_hosts` and clearing the stale Tailscale node.

## Still open
- [ ] Sway vs Hyprland for the desktop session. Sway is in the config now because
      it's the boring stable choice; you came from Hyprland on omarchy, so switching
      back is a one-line change if you miss it.
- [ ] Printing (`cups`) and `bluetooth` were enabled on the old box and are not in
      this config yet — see `pre-nix/README.md`.

## Blocking before the wipe
- [ ] **Push this repo to GitHub.** INSTALL.md step 7 clones it from inside the
      installer; if it only exists on the nvme, the wipe destroys it. See
      PREINSTALL.md step 1.
- [ ] **Reattach and verify the HDD backup.** As of 2026-10-03 `sda` is not plugged
      in, so `/mnt/pre-wipe-sep-2026` and the 235G `/mnt/music` master can't be
      confirmed. Do not wipe until you have eyes on that backup.
