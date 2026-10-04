{ config, pkgs, lib, ... }:

{
  imports = [
    # Generated on the machine by `nixos-generate-config` during install, then
    # committed. Lives under hosts/<name>/ so that if there's ever a second Nix
    # box, each machine's hardware info is backed up here without the two
    # getting mixed up. There is deliberately no shared multi-host abstraction
    # — see "Per-host dirs" in README.md.
    ./hosts/oxton/hardware-configuration.nix
  ];

  ############################################################################
  # Unfree packages — REQUIRED, do not remove
  ############################################################################
  # Steam, 1Password and claude-code are all unfree. Without this the build
  # fails outright: "Package 'steam-unwrapped' has an unfree license".
  nixpkgs.config.allowUnfree = true;

  ############################################################################
  # Boot
  ############################################################################
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # RDNA3 (7900 XTX) benefits from a recent kernel + Mesa.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # zram swap (matches your current setup; no swap partition needed).
  zramSwap.enable = true;

  # DISK ENCRYPTION — DECIDED 2026-10-03: LUKS root + TPM2 auto-unlock.
  # You want unattended reboots AND encryption at rest. This board has a TPM 2.0
  # (/dev/tpm0), so the TPM hands over the key at boot with no passphrase at the
  # console and the machine comes back by itself after a power blip. The luks
  # device lands in hardware-configuration.nix when nixos-generate-config runs;
  # you enrol the TPM after first boot (see INSTALL.md step 11).

  # Required for TPM2 unlock in the initrd:
  boot.initrd.systemd.enable = true;

  # CAVEAT, know this going in: Secure Boot is disabled on this board, so PCR 7
  # measures "Secure Boot off". The TPM therefore protects you against someone
  # stealing the DRIVE (pull it, it is unreadable) but NOT against someone who
  # has the whole machine and boots their own media. Closing that gap needs
  # Secure Boot + signed UKIs (lanzaboote) — a separate project, not needed now.

  # ALWAYS keep a passphrase keyslot as recovery. TPM enrolment breaks on
  # firmware updates, CMOS resets and mainboard swaps; with no passphrase that
  # means losing the disk. Put the passphrase in 1Password before you enrol.

  ############################################################################
  # Networking / identity
  ############################################################################
  networking.hostName = "oxton";           # <- pick your hostname
  networking.networkmanager.enable = true; # simple; swap for systemd-networkd if you prefer static

  time.timeZone = "America/Toronto";
  i18n.defaultLocale = "en_CA.UTF-8";

  # Keyboard: Adv360 Pro remaps on-device (ZMK), so host layout is just plain us.
  console.keyMap = "us";

  ############################################################################
  # User
  ############################################################################
  users.users.liz = {
    isNormalUser = true;
    description = "liz";
    extraGroups = [
      "wheel"    # sudo
      "video" "render"  # GPU access (gaming + ROCm containers)
      "audio"
      "docker"
      "networkmanager"
    ];
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      # laptop that ssh's in (from your backed-up authorized_keys):
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPyj2rYITEt6zwfMjrHz0py6jxYPwRyvNMWUGqqSEmUx oldlaptop"
    ];
  };
  # Passwordless sudo for wheel is convenient on a personal box; remove if undesired.
  security.sudo.wheelNeedsPassword = true;

  ############################################################################
  # JOB 1 — SSH target + Tailscale
  ############################################################################
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
  services.tailscale.enable = true;
  # After install, run once:  sudo tailscale up
  # (auth is interactive; keep the key out of the repo)

  ############################################################################
  # Audio — pipewire. REQUIRED: mpd below is configured to output to pipewire,
  # so without this it talks to a server that doesn't exist. No sound anywhere,
  # games included.
  ############################################################################
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;   # 32-bit games
    pulse.enable = true;        # pulse-compatible clients

    # The Modius is the DAC everything should land on. Left to its own
    # devices wireplumber elected the Samson Meteor — a USB *microphone*
    # that also advertises a headphone-out sink — and audio vanished into
    # it. Raising priority.session makes the Modius win the default-sink
    # election outright instead of relying on
    # ~/.local/state/wireplumber/default-nodes, which is machine-local,
    # untracked, and does not survive a reinstall.
    #
    # Matched on node.name, which is built from USB vendor/product and so
    # is stable across reboots and port changes — not on the card index or
    # bus path, both of which move.
    #
    # This does NOT prevent switching sinks: the stored default still wins
    # when present, so wpctl/pulsemixer work as before. Priority is what
    # decides on a fresh install, or when that state is absent/cleared.
    # The Modius is USB — powered off, it simply isn't a candidate and the
    # next-highest sink takes over, which is the behaviour we want.
    wireplumber.extraConfig."50-modius-default" = {
      "monitor.alsa.rules" = [{
        matches = [{
          "node.name" =
            "alsa_output.usb-Schiit_Audio_Schiit_Unison_Modius_ES-00.analog-stereo";
        }];
        actions.update-props."priority.session" = 2000;
      }];
    };
  };
  security.rtkit.enable = true; # lets pipewire take realtime priority

  ############################################################################
  # Bluetooth
  ############################################################################
  # Adapter is the Intel AX200 combo card (lsusb 8087:0029). A2DP audio comes
  # from pipewire/wireplumber above, so nothing extra is needed for headphones.
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;   # so the DualSense can reconnect without you logging in
  };
  # `bluetoothctl` ships with bluez — no extra package. If you ever want a UI,
  # bluetuith is a small TUI and blueman is a GTK applet
  # (services.blueman.enable); deliberately leaving both out.

  # Firmware blobs for the AX200 (bluetooth AND wifi both need ibt-*/iwlwifi-*)
  # and the amdgpu. The generated hardware-configuration.nix normally sets this
  # with mkDefault; pinned here so it can't silently regress.
  hardware.enableRedistributableFirmware = true;

  ############################################################################
  # JOB 2 — home-network daemons (mpd)
  ############################################################################
  # NOTE on 26.05: musicDirectory / network.listenAddress / extraConfig are all
  # gone — mpd is declarative `settings` now (RFC42), and repeated blocks like
  # audio_output are a list of attrsets.
  services.mpd = {
    enable = true;
    user = "liz";
    openFirewall = true;   # opens 6600; don't also list it in the firewall below
    settings = {
      # the MASTER library on the HDD, not the small ~/music subset:
      music_directory = "/mnt/music";
      bind_to_address = "0.0.0.0";   # LAN + tailscale; firewall scopes it
      audio_output = [
        {
          type = "pipewire";
          name = "PipeWire Output";
        }
      ];
    };
  };
  # mDNS so other LAN devices can discover services by name (matches your avahi use)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = { enable = true; addresses = true; workstation = true; };
  };

  ############################################################################
  # JOB 3 — containerized ROCm compute / finetuning
  ############################################################################
  virtualisation.docker.enable = true;
  # The amdgpu kernel driver (loaded by hardware-configuration) exposes
  # /dev/kfd and /dev/dri. Run compute in the official image, e.g.:
  #   docker run --rm -it --device=/dev/kfd --device=/dev/dri \
  #     --group-add=video --ipc=host --shm-size 16G \
  #     rocm/pytorch
  # 7900 XTX is gfx1100 (ROCm-supported). No CUDA involved.

  ############################################################################
  # JOB 4 — Steam + AMD graphics
  ############################################################################
  hardware.graphics = {
    enable = true;
    enable32Bit = true;   # required for Steam / 32-bit games
    # RADV (Mesa) is the default Vulkan driver and what you want on RDNA3.
  };

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true; # Steam Big-Picture "console" session
    remotePlay.openFirewall = true;
  };
  programs.gamescope.enable = true;

  # Minimal graphical shell. Sway = stable/simple; swap for Hyprland if you like.
  # greetd gives a tiny login where you can pick a Steam session or a desktop.
  programs.sway.enable = true;
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd sway";
      user = "greeter";
    };
  };

  # sway + fuzzel configs, symlinked out of this repo.
  #
  # These two are plain config files rather than Nix expressions, and they stay
  # that way on purpose — ~/.config/sway points at a WRITABLE file in the repo,
  # so a keybind tweak is an edit plus `swaymsg reload`, with no rebuild in the
  # loop. home-manager was considered here and declined precisely because its
  # xdg.configFile would make these read-only store paths and put a full switch
  # in front of every experiment. See "No home-manager" in README.md.
  #
  # tmpfiles is what makes the symlinks declarative without that cost, which is
  # the whole trick: the files are imperative, their placement isn't. `L+`
  # means "create the symlink, replacing whatever is already there", so this is
  # self-healing and idempotent — and it retires a manual `ln -sfn` step that
  # otherwise has to be remembered on every fresh install.
  #
  # Mind the `+`: it deletes what it finds at that path first, including a real
  # directory with files in it. That's what makes it self-healing, and it also
  # means ~/.config/sway is now owned by this repo — anything hand-written
  # there gets destroyed on the next switch. Edit sway/ in the repo, never
  # through the symlink's old location.
  #
  # The `d` lines are not optional: tmpfiles creates missing parent directories
  # itself, but as root:root, which would leave a root-owned ~/.config/fuzzel
  # in a fresh home. Declaring them liz:users first avoids that.
  systemd.tmpfiles.rules = [
    "d /home/liz/.config               0755 liz users - -"
    "d /home/liz/.config/fuzzel        0755 liz users - -"
    "L+ /home/liz/.config/sway              - - - - /home/liz/nixos/sway"
    "L+ /home/liz/.config/fuzzel/fuzzel.ini - - - - /home/liz/nixos/sway/fuzzel.ini"
  ];

  # Wayland portals — file pickers, screen sharing, "open with" from apps.
  # Without these, screenshots/screen-share and some GTK dialogs fail quietly.
  xdg.portal = {
    enable = true;
    wlr.enable = true;                      # screencast on sway/wlroots
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Fonts — a bare NixOS ships almost none, and Claude Code's TUI leans on
  # box-drawing and icon glyphs. This saves you a confusing first hour of
  # wondering why the terminal looks broken.
  fonts.packages = with pkgs; [
    # Terminal face. Has to be monospace, and the Nerd variant carries the icon
    # glyphs starship's prompt and Claude Code's TUI draw with — Cormorant is a
    # display serif and can't do this job.
    nerd-fonts.jetbrains-mono
    # Broad fallback so arbitrary web pages don't render as tofu in firefox.
    noto-fonts
    noto-fonts-color-emoji
    # The one face you actually like. Not in nixpkgs — see pkgs/cormorant.nix
    # for why it's vendored instead of pulled from google-fonts.
    (callPackage ./pkgs/cormorant.nix { })
  ];

  programs.firefox.enable = true;

  ############################################################################
  # Secrets, auth, MFA
  ############################################################################
  # 1Password GUI + the `op` CLI. Unfree, hence allowUnfree above. You were on
  # 1password-beta; swap in _1password-gui-beta if you want to stay on beta.
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    # REQUIRED, and the bit everyone misses: without it the browser extension
    # can't unlock from the desktop app and system auth prompts fail.
    polkitPolicyOwners = [ "liz" ];
  };

  # libsecret store for whatever wants one (browser saved passwords, etc).
  # You had gnome-keyring on the old box; unlocked by your login password.
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  # Hardware security keys — DECIDED 2026-10-03: nothing to configure.
  # The YubiKey is used purely as an MFA/security key for a handful of web
  # services (github, google). WebAuthn/U2F in Firefox and Chromium works with
  # no extra config: systemd ships the fido udev rules and logind's uaccess
  # grants the active session access to the device.
  # services.pcscd.enable is therefore NOT needed. It would only be required if
  # you started using the key as a smartcard — GPG signing, PIV certs, or ssh
  # through gpg-agent. Uncomment then, not now:
  # services.pcscd.enable = true;

  # Your login/sudo password stays imperative (`passwd liz`, INSTALL step 9).
  # Do NOT switch to users.users.liz.hashedPassword — this repo is PUBLIC and
  # that would publish your password hash.

  ############################################################################
  # Firewall — LAN/tailscale scoped
  ############################################################################
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];             # ssh. mpd's 6600 comes from
                                          # services.mpd.openFirewall above.
    trustedInterfaces = [ "tailscale0" ]; # everything open over the tailnet
  };

  ############################################################################
  # Packages — this IS your "install packages ahead of time" step.
  # Lean base + the nice CLI utils you liked from omarchy. Curate freely.
  ############################################################################
  # Trimmed 2026-10-03 against measured closure sizes. No terminal listed here
  # on purpose: programs.sway provides foot (plus swaylock/swayidle/grim/wmenu).
  environment.systemPackages = with pkgs; [
    # Claude Code — from nixpkgs, NOT the curl|bash installer. See note below.
    # From unstable on purpose: 26.05 stopped backporting it. See note below.
    unstable.claude-code
    # core
    git vim neovim curl wget rsync tmux unzip
    # the "omarchy-nice" terminal set
    eza bat fd ripgrep fzf zoxide starship btop jq yazi
    # Wayland desktop plumbing. None of this comes with sway, and the first two
    # are the ones whose absence actually breaks things:
    wl-clipboard      # wl-copy/wl-paste ARE the clipboard. Without it nothing
                      # leaves the terminal and nvim's "+y silently no-ops.
    mako              # notification daemon — sway ships none, so notifications
                      # are dropped rather than queued.
    fuzzel            # app launcher / command palette, bound to Super+space
                      # (and Super+d) in sway/config. Replaces sway's bundled
                      # wmenu, which is prefix-match-only with no icons. Also
                      # the dmenu for the Super+Tab window switcher.
    adwaita-icon-theme # fuzzel's icons-enabled resolves .desktop icon names
                      # against an installed theme; with none present it draws
                      # blanks rather than falling back to text.
    slurp satty       # region select + annotate, to pair with sway's grim
    imv               # image viewer
    xdg-terminal-exec # lets apps open "the" terminal
    # Job 2 had a daemon and no way to talk to it. `mpc`, not mpc_cli.
    mpc
    pulsemixer       # TUI mixer over pipewire's pulse shim. pactl can set any
                     # volume you can name, but you can't *see* the sinks and
                     # per-app streams at once, which is the actual job.
    # dev / runtime you already use
    go uv docker-compose gh lazygit lazydocker

    ########################################################################
    # The oxton.net intake pipeline (~/projects/oxton-website/tools/intake)
    ########################################################################
    # It needs exactly three things on PATH, and nothing else:
    #   node     — the scripts are stdlib-only (node:fs/promises etc), no
    #              package.json, no npm tree. So any modern node works and
    #              there's nothing to pin. This is 24 LTS; nodejs_26 exists
    #              if you want to match the 25.8.0 mise was giving you.
    #   magick   — ImageMagick, above. The only external binary the .mjs
    #              files shell out to.
    #   llama-server — from llama-cpp, below.
    nodejs
    # serve.sh runs `exec llama-server -hf ...` straight off PATH, so this
    # drops in with NO change to your project. Vulkan to match what serve.sh
    # expects, and RADV is already there via hardware.graphics. The vulkan
    # build is in cache.nixos.org, so it's a download and not a compile.
    # Replaces the hand-built copy in ~/.local/opt/llama.cpp, which would not
    # have run here anyway (same ld-linux problem as any downloaded binary).
    # NOT tesseract: the pipeline does OCR with a vision model over HTTP on
    # 127.0.0.1:8017, and tesseract appears nowhere in oxton-website.
    (llama-cpp.override { vulkanSupport = true; })
    # sysadmin / debugging
    lsof socat whois exfatprogs imagemagick
    # GPU monitoring from the HOST (temp, utilisation, clocks). Deliberately
    # NOT rocminfo — 773 MiB that only duplicates what's already inside the
    # rocm/pytorch container where compute actually runs.
    rocmPackages.rocm-smi
    # gaming helpers. No protonup-qt: 1.7 GiB and the only Qt app in the whole
    # config, so nearly all of that was marginal rather than shared. Steam
    # ships Proton itself; protonup-qt only manages GE-Proton builds.
    mangohud
  ];

  programs.starship.enable = true;

  ############################################################################
  # Shell — the aliases and helpers from the old box.
  ############################################################################
  # These lived in omarchy's default/bash/rc, which was under ~/.local/share
  # and so is NOT in pre-wipe-sep-2026 (the backup took dotfiles, not .local).
  # Reconstructed 2026-10-03 from ~/aliases.md — the notes you wrote
  # documenting exactly what omarchy shadowed — plus the four personal aliases
  # from the old ~/.bashrc. Every tool referenced here is in systemPackages.
  programs.bash.shellAliases = {
    # eza. `ls` is YOUR override from the old .bashrc (grid, all files), not
    # omarchy's long-format default — the .bashrc redefined it after sourcing
    # omarchy's rc, so the override is what you were actually typing against.
    ls = "eza -a --icons=auto --color=auto";
    lsa = "eza -lh --all --group-directories-first --icons=auto";
    lt = "eza --tree --level=2 --long --git --icons=auto";
    lta = "eza --tree --level=2 --long --git --all --icons=auto";
    lst = "eza -a --tree --level=2 --git --icons=auto --color=auto";
    # agents, minus the permission prompts
    cc = "claude --dangerously-skip-permissions";
    cx = "codex --yolo";
  };

  # Gives `z`/`zi`. The cd wrapper below is what actually gets used.
  programs.zoxide = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.bash.interactiveShellInit = ''
    # cd, wrapped the way omarchy had it: a real path is a plain cd and
    # zoxide never sees it; anything else is a frecency jump that prints
    # where it landed. `builtin cd` so this can't recurse into itself.
    zd() {
      if [ $# -eq 0 ]; then
        builtin cd ~ && return
      elif [ -d "$1" ]; then
        builtin cd "$1"
      else
        z "$1" && printf '→ %s\n' "$PWD"
      fi
    }
    alias cd='zd'

    # ff: fuzzy-find a file with a syntax-highlighted preview.
    # eff: same, then open the pick in $EDITOR.
    ff() { fzf --preview 'bat --style=numbers --color=always {}' "$@"; }
    eff() {
      local file
      file=$(ff) && [ -n "$file" ] && "''${EDITOR:-nvim}" "$file"
    }

    # man pages rendered through bat. `man` itself is not aliased — this is
    # the MANPAGER env var, which is why man just looks different.
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
    export MANROFFOPT="-c"

    export EDITOR=nvim
    # Dropped from the old rc on the way over: the `. ~/.local/bin/env` line
    # (a curl-installer artifact, no such file here) and two BUN_INSTALL
    # exports, one of which pointed at a /tmp dir that no longer exists.
    export PATH="$HOME/.local/bin:$PATH"
  '';

  # From the old ~/.bash_profile: an SSH login lands in tmux, so a dropped
  # connection doesn't take the work with it. Falls through to a plain shell
  # if tmux won't start — a broken tmux must never lock you out of job 1.
  # Only login shells read this, so `ssh oxton <cmd>`, scp and rsync skip it.
  programs.bash.loginShellInit = ''
    if [ -z "$TMUX" ] && [ -n "$SSH_CONNECTION" ]; then
      tmux attach-session -t main 2>/dev/null || tmux new-session -s main
    fi
  '';

  # Flakes + the new CLI on.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # direnv + nix-direnv. This is the replacement for mise, and it's a better
  # one: a per-project dev shell pins the NATIVE build dependencies too
  # (python3/pkg-config/libvips for anything going through node-gyp), which a
  # version manager never could — it only ever managed the node binary and
  # left the C libraries to the host distro.
  #
  # `cd` into a project with an .envrc and its tools appear, shadowing the
  # system ones on PATH; `cd` out and they're gone. nix-direnv caches the
  # shell so that's instant instead of re-evaluating the flake every time.
  # Start a new project with:  nix flake init -t ~/nixos#node
  programs.direnv.enable = true;

  ############################################################################
  # Why claude-code comes from nixpkgs (read this before "fixing" it)
  ############################################################################
  # The official `curl ... | bash` installer drops a dynamically-linked binary
  # that looks for /lib64/ld-linux-x86-64.so.2. NixOS has no such path, so it
  # fails with "No such file or directory" while the file sits right there.
  # Same trap for any downloaded prebuilt binary. In order of preference:
  #   1. the nixpkgs package above — update with `nix flake update`
  #   2. `nix run nixpkgs/nixos-unstable#claude-code` for a one-off newer build
  #   3. `steam-run ./some-binary` — Steam's FHS sandbox, works for any blob
  # It comes from pkgs.unstable (see the overlay in flake.nix), NOT the 26.05
  # branch: backports there stopped at 2.1.223 on 2026-08-06, so bumping the
  # stable input does nothing for this package. Updating now means updating the
  # nixpkgs-unstable input, which tracks releases within a day or two.
  # And let nix own updates: the built-in auto-updater can't write to the
  # read-only nix store, so stop it from trying.
  environment.sessionVariables.DISABLE_AUTOUPDATER = "1";

  ############################################################################
  # Set to the release you INSTALL from. Do not change casually afterwards.
  ############################################################################
  system.stateVersion = "26.05";

  # POST INSTALL STUFF
  # External Drive Mounting
  fileSystems."/mnt" = {
    device = "/dev/disk/by-uuid/fbed9d9b-ef80-4596-b3e7-578fc81bec84";
    fsType = "ext4";
    options = [ "nofail" "x-systemd.device-timeout=10s" ];
  };
}
