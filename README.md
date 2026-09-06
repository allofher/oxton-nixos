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

## TODO / decisions
- [ ] Hostname (`oxton`?)
- [ ] Disk encryption strategy (none / LUKS+TPM2 / LUKS+initrd-ssh) — see comment in configuration.nix
- [ ] Confirm laptop pubkey in `users.users.liz.openssh.authorizedKeys`
- [ ] Bump channel to latest stable if desired
- [ ] Sway vs Hyprland for the desktop session
