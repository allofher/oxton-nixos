# pre-nix — inventory of the Arch/omarchy box before the wipe

Captured 2026-09-06 on `omarchy` (the machine this config replaces). Kept here so
the inventory survives the wipe along with the config, rather than living only on
the backup HDD. Reference material only — nothing here is used by the build.

| File | What it is |
|---|---|
| `pre-wipe-packages-explicit.txt` | 174 explicitly-installed packages — the useful list for deciding what to port into `environment.systemPackages` |
| `pre-wipe-packages-all.txt` | 1092 packages including dependencies — for archaeology when something's missing |
| `pre-wipe-packages-aur.txt` | AUR packages — **empty**, nothing was installed from the AUR |
| `pre-wipe-systemd-enabled.txt` | 29 enabled system units |
| `pre-wipe-systemd-user-enabled.txt` | 13 enabled user units |

## Things in here worth porting deliberately

System units already covered by `configuration.nix`: `sshd`, `tailscaled`,
`avahi-daemon`, `docker`, plus a firewall (`ufw` there, `networking.firewall` here).

**Not yet covered** — decide whether you want them:
- `cups` / `cups-browsed` — printing
- `bluetooth` — `hardware.bluetooth.enable`
- `snapper-*` timers + `limine-snapper-sync` — btrfs snapshots, tied to the old
  Limine+btrfs layout. Not portable as-is; NixOS generations cover most of what
  you used this for.

User units: `mpd` moves to a system service here. These are yours and have no
NixOS equivalent — recover them from the HDD backup if you still want them:
- `oxton-intake-watch`, `oxton-taildrop` — your own scripts
- `hyprsunset-scheduler` — the night-light scheduler (see also the known issue
  that gamma dimming never worked on the external monitor)
- `omarchy-recover-internal-monitor`, `elephant`, `swayosd-server` — omarchy-specific
