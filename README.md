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

- [x] **Sway, not Hyprland** (2026-10-03). Deliberate: the graphical session is
      mostly a host for gamescope, sway's stable-channel version needs no extra
      flake input or cachix, and Hyprland's fast-moving breaking config changes
      are a variable worth not having during a migration. greetd+tuigreet instead
      of the old box's SDDM — no Qt/GNOME login stack on a mostly-headless box.
      Hyprland was considered as a second greetd session and declined: the point
      of this rebuild is less bloat, not more.
- [x] **Bluetooth: yes** (2026-10-03). `hardware.bluetooth` + `powerOnBoot` for the
      DualSense, A2DP via pipewire, and `enableRedistributableFirmware` which the
      AX200 needs for bluetooth *and* wifi. No blueman/bluetuith — bluetoothctl
      ships with bluez.
- [x] **YubiKey needs no config** (2026-10-03). Used purely as an MFA/security key
      for a few web services, and WebAuthn/U2F works out of the box via systemd's
      udev rules. `services.pcscd` left off; only needed for smartcard use.
- [x] **Trimmed against measured closure sizes** (2026-10-03): dropped protonup-qt
      (1.7 GiB, sole Qt app in the config), rocminfo (773 MiB, duplicates the
      rocm/pytorch container), ghostty (sway ships foot), and a redundant foot
      entry. Install went 4.0 → **3.8 GiB download**, 9.9 → **9.0 GiB unpacked**.
      Kept gnome-keyring and rocm-smi.
- [x] **Config evaluates clean** (2026-10-03) — see PREINSTALL step 2 for the five
      bugs this caught, and `flake.lock` pinning nixpkgs to `774debe7`.

## Still open
- [ ] Printing (`cups`) was enabled on the old box and is not in this config yet.
      Bluetooth is now done. See `pre-nix/README.md`.

## Blocking before the wipe
- [ ] **Push this repo to GitHub.** INSTALL.md step 7 clones it from inside the
      installer; if it only exists on the nvme, the wipe destroys it. See
      PREINSTALL.md step 1.
- [ ] **Reattach and verify the HDD backup.** As of 2026-10-03 `sda` is not plugged
      in, so `/mnt/pre-wipe-sep-2026` and the 235G `/mnt/music` master can't be
      confirmed. Do not wipe until you have eyes on that backup.
