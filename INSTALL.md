# Install guide (run inside the NixOS 26.05 live environment)

Assumes the HDD (`sda`) is physically unplugged, so the ONLY disk is `nvme0n1`.

> **Encryption: decided.** This guide installs a **LUKS-encrypted root with TPM2
> auto-unlock**. You get encryption at rest *and* unattended reboots — the TPM
> releases the key at boot, nothing is typed at the console, and the machine comes
> back on its own after a power blip. You set a passphrase during install (step 4)
> and enrol the TPM after first boot (step 11). The passphrase stays as your
> recovery path. If you'd rather skip encryption entirely, see the sidebar at the
> bottom.

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

## 3. Partition the nvme (GPT: EFI + LUKS root)
```
sudo -i                       # become root for the rest
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 2GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart root 2GiB 100%
```
**2GiB ESP, not 1GiB.** NixOS keeps a kernel + initrd in `/boot` for *every*
generation you can roll back to. 1GiB fills up and then rebuilds start failing.
(Your old Arch box used 2G for one kernel — NixOS needs the headroom more.)

## 4. Format — this is where you set the LUKS passphrase
```
mkfs.fat -F32 -n boot /dev/nvme0n1p1
cryptsetup luksFormat /dev/nvme0n1p2
```
`luksFormat` prompts you to type `YES` and then set a passphrase.

> **Put this passphrase in 1Password now, before you continue.** It is your only
> recovery path if TPM unlock ever breaks (firmware update, CMOS reset, mainboard
> swap). Losing it means losing the disk. Your 1Password emergency kit is also on
> the HDD backup if you need to get in from the laptop.

Then open it and make the filesystem:
```
cryptsetup open /dev/nvme0n1p2 cryptroot
mkfs.ext4 -L nixos /dev/mapper/cryptroot
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
This creates `/mnt/etc/nixos/hardware-configuration.nix` — disk UUIDs, the
`boot.initrd.luks.devices` entry for your encrypted root, and kernel modules for
the 5800X / 7900 XTX. You keep this file; you discard the generated
`configuration.nix` in favour of your repo's.

Sanity-check that it picked up the LUKS device:
```
grep -A3 luks /mnt/etc/nixos/hardware-configuration.nix
```
If that comes back empty, stop and sort it out — the system won't boot without it.

## 7. Pull in your flake config
```
nix-shell -p git   # drops you in a shell with git
# HTTPS deliberately: there's no ssh key in the live ISO, and the HDD with
# your old one is unplugged. Swapped to ssh in first-boot step 6.
git clone https://github.com/allofher/oxton-nixos /mnt/home/liz/nixos
# bring the freshly generated hardware config into the repo:
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/home/liz/nixos/
exit   # leave nix-shell
```

> **If you made the repo private:** plain `git clone` over HTTPS will fail, and your
> SSH key is on the HDD you just unplugged. Use the GitHub device flow instead —
> it works fine with 2FA and hardware security keys:
> ```
> nix-shell -p git gh
> gh auth login     # pick HTTPS, "login with a web browser"
> ```
> It prints an 8-character code; type it at github.com/login/device on your laptop
> or phone. Then `gh repo clone allofher/oxton-nixos /mnt/home/liz/nixos`.

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
Remove the USB when it powers down. **This first boot will ask for the LUKS
passphrase** — that's expected; the TPM isn't enrolled yet. After that you land at
the `tuigreet` login → log in as `liz` → `sway` (or pick the Steam session).

## 11. Enrol the TPM so future boots are unattended
This is the step that buys you the unattended reboot. Run it once, on the
installed system:
```
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p2
```
It asks for your existing passphrase, then adds a TPM-backed keyslot *alongside*
it. Note the flag is `--tpm2-pcrs` (PCRs, plural) — easy to typo.

**Verify before you trust it:** `reboot` and confirm the machine comes up to the
login prompt with nothing typed. Then check both keyslots are present:
```
sudo cryptsetup luksDump /dev/nvme0n1p2 | grep -E 'Keyslot|tpm2'
```
You want to see your passphrase slot *and* a systemd-tpm2 token. If only the TPM
slot survived, you have no recovery path — fix that immediately.

---

# First-boot tasks (after you're logged into the new system)

1. **Reconnect the HDD** and mount it at `/mnt`. It is a **USB-attached** 3.6T ext4
   drive, so it will NOT appear in the generated `hardware-configuration.nix` (that
   file is generated with the drive unplugged). You have to declare it:

   **This step stays manual on purpose — it is a safety interlock, not an
   oversight.** The drive is deliberately absent for the whole destructive part
   of the install, and is reconnected and identified by hand only once the
   partitioning and formatting are behind you. That removes any window in which
   a `fileSystems` entry or an automount could aim at the wrong device while a
   formatter is still in play. Do not "tidy" this into something automatic, and
   do not move it earlier in the guide.

   ```nix
   # in configuration.nix
   fileSystems."/mnt" = {
     device = "/dev/disk/by-uuid/<uuid from `lsblk -f`>";
     fsType = "ext4";
     options = [ "nofail" "x-systemd.device-timeout=10s" ];
   };
   ```

   **`nofail` is not optional here.** Without it, a removable drive that is absent or
   slow to enumerate makes systemd block on the mount unit and the boot stalls — which
   is exactly the unattended-reboot property the TPM work was for. `nofail` plus a short
   device timeout means a missing drive degrades to "mpd doesn't start" instead of
   "the machine doesn't come back".

   Use the **UUID**, not `/dev/sda1`: this drive has already been `sda` and not-`sda`
   twice in a month depending on what else was plugged in.

   `mpd` reads the master library from `/mnt/music` (235G, confirmed present) and won't
   start cleanly without it.
2. **Tailscale:** `sudo tailscale up` → authenticate in the browser. Then remove the
   stale `omarchy` node in the Tailscale admin console.
3. **Restore your data** from the backup:
   ```
   rsync -aH /mnt/pre-wipe-sep-2026/.ssh/     ~/.ssh/
   rsync -aH /mnt/pre-wipe-sep-2026/projects/ ~/projects/

   # Claude Code state — DON'T skip this. Your auth, every past transcript, and
   # ~/.claude/projects/-home-liz/memory/ (MEMORY.md + the memory files) all live
   # here. Without it you re-auth and start from zero memory.
   rsync -aH /mnt/pre-wipe-sep-2026/.claude/  ~/.claude/
   cp -a     /mnt/pre-wipe-sep-2026/.claude.json ~/

   rsync -aH /mnt/pre-wipe-sep-2026/.codex/   ~/.codex/
   rsync -aH /mnt/pre-wipe-sep-2026/.config/ghostty/ ~/.config/ghostty/

   # other dotfiles as you want them — don't bulk-copy omarchy's configs
   ```
   Check these actually exist in the backup during PREINSTALL step 0 — the backup
   was made with `/mnt` detached since, so none of it is confirmed. If `.claude/`
   isn't in there, copy it off the nvme before you wipe.
4. **Fix laptop known_hosts:** on your LAPTOP, `ssh-keygen -R oxton` (and the IP),
   then reconnect and accept the new host key.
5. **Verify the four jobs:**
   - ssh in from the laptop
   - `systemctl status mpd` and point a client at `oxton:6600`
   - `docker run --rm --device=/dev/kfd --device=/dev/dri rocm/pytorch rocminfo | head`
   - launch Steam, confirm a game runs
6. **Switch the git remote to SSH.** Install step 7 (*Pull in your flake
   config*, above the reboot) cloned over HTTPS on purpose — in
   the live ISO there is no key yet and the HDD holding your old one is
   unplugged. Now that you have a key, move the remote over, because git picks
   its auth from the URL scheme: an `https://` remote never looks at `~/.ssh`
   at all, it looks for a credential helper, and there isn't one. The symptom
   is `git push` prompting for a GitHub username (which would also fail — the
   web password hasn't been accepted for git since 2021).
   ```
   cd ~/nixos
   git remote set-url origin git@github.com:allofher/oxton-nixos.git
   ssh -T git@github.com     # expect: "Hi allofher! You've successfully authenticated"
   ```
   If that `ssh -T` fails, the key isn't on the account yet — `gh auth login`,
   then `gh ssh-key add ~/.ssh/id_ed25519.pub -t oxton`.

   Note `gh auth status` reporting `Git operations protocol: ssh` does **not**
   do this for you. That preference only applies to URLs `gh` generates later;
   it never rewrites a remote that already exists.

   This one is genuinely a per-machine step, not a repo setting: the remote URL
   lives in `.git/config`, which isn't tracked, so it can't be committed and
   won't survive a reinstall.
7. **Commit the hardware config** so the repo is complete:
   ```
   cd ~/nixos && git add hardware-configuration.nix && git commit -m "add hardware config" && git push
   ```
8. **Link the sway + fuzzel configs.** There's no home-manager here, so these
   two live in the repo but are NOT deployed by `nixos-rebuild`. Without the
   symlinks sway silently falls back to the stock `/etc/sway/config` and you
   get `wmenu` on Super+d instead of fuzzel on Super+space:
   ```
   mkdir -p ~/.config/fuzzel
   ln -sfn ~/nixos/sway ~/.config/sway
   ln -sfn ~/nixos/sway/fuzzel.ini ~/.config/fuzzel/fuzzel.ini
   ```
   Then `swaymsg reload`. Check it took with `sway --validate --config
   ~/.config/sway/config` and `fuzzel --check-config`.

Day-to-day after this: edit files in `~/nixos`, then
`sudo nixos-rebuild switch --flake ~/nixos#oxton`.

---

## Sidebar: unencrypted root
If you decide against encryption after all, it's simpler — no passphrase, no TPM
enrolment, no recovery footgun. Replace steps 3–5 with:
```
parted /dev/nvme0n1 -- mklabel gpt
parted /dev/nvme0n1 -- mkpart ESP fat32 1MiB 2GiB
parted /dev/nvme0n1 -- set 1 esp on
parted /dev/nvme0n1 -- mkpart root ext4 2GiB 100%
mkfs.fat -F32 -n boot /dev/nvme0n1p1
mkfs.ext4 -L nixos /dev/nvme0n1p2
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot && mount /dev/disk/by-label/boot /mnt/boot
```
Then skip steps 10's passphrase prompt and step 11 entirely, and remove
`boot.initrd.systemd.enable` from `configuration.nix`. The tradeoff: anyone who
walks off with the machine or the drive reads everything on it, including your
`~/.ssh` keys and Tailscale node credentials.
