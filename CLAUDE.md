# Working in this repo

This repo *is* the machine. Editing a file here changes nothing until it is built,
switched, and committed. Every step below exists because skipping it has already
bitten us.

## The loop — all five steps, every time

1. **Edit** the `.nix` files.
2. **Build:** `nixos-rebuild build --flake ~/nixos#oxton` — catches eval errors without
   touching the running system.
3. **Switch:** `sudo nixos-rebuild switch --flake ~/nixos#oxton`. Liz runs this herself
   (sudo password); ask with `! sudo nixos-rebuild switch --flake /home/liz/nixos#oxton`.
4. **Verify** — see below. "The build succeeded" is not verification.
5. **Commit and push.** The repo is the install source; an uncommitted change is a
   change that does not survive a reinstall.

Do not report a config task as done before step 5.

## Verification

Check the *specific thing that was asked for*, on the running system:

```bash
claude --version                    # or whatever the change was supposed to affect
systemctl status <unit>
```

And confirm the running system is actually this config — these paths must match:

```bash
readlink /run/current-system
nix build --no-link --print-out-paths ~/nixos#nixosConfigurations.oxton.config.system.build.toplevel
```

If they differ, the booted generation predates the edits. **A reboot does not apply
config changes** — only `switch` (now) or `boot` (next boot) does. Rebooting to pick up
a missed `switch` just re-activates the same generation, which is exactly how we lost an
hour on 2026-10-04.

Ignore the `result` symlink when reasoning about what's running. It's gitignored and
records some past `nixos-rebuild build`, not the current generation.

## Before saying "done"

Run `git status -sb` and read **all** of it:

- modified files — commit them
- **untracked directories** — `sway/` sat untracked and invisible for a day; `??` lines
  matter as much as `M` lines
- `## master...origin/master [ahead N]` — push

A dirty tree at the end of a task means the task isn't finished.

## Don't re-derive these

- `claude-code` comes from `pkgs.unstable` (overlay in `flake.nix`), not 26.05 — stable
  backports stopped at 2.1.223. `nix flake update nixpkgs-unstable` to bump it. The long
  comment in `configuration.nix` explains why; read it before "fixing" it.
- Identify disks by `TRAN`/`RM`/`MODEL`/`SERIAL`, never by device name. `sda` has been
  both the 3.6T HDD and a USB stick.
- No secrets in this repo, ever — it's public. sops-nix/agenix if that changes.
- `README.md` holds the settled decisions and the open-items list. Check it before
  proposing something; several things there were explicitly declined.
