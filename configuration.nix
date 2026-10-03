{ config, pkgs, lib, ... }:

{
  imports = [
    # Generated on the machine by `nixos-generate-config` during install.
    # It doesn't exist yet — create/commit it after the first install.
    ./hardware-configuration.nix
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
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
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
    claude-code
    # core
    git vim neovim curl wget rsync tmux
    # the "omarchy-nice" terminal set
    eza bat fd ripgrep fzf zoxide starship btop jq yazi
    # dev / runtime you already use
    go uv docker-compose
    # GPU monitoring from the HOST (temp, utilisation, clocks). Deliberately
    # NOT rocminfo — 773 MiB that only duplicates what's already inside the
    # rocm/pytorch container where compute actually runs.
    rocmPackages.rocm-smi
    # gaming helpers. No protonup-qt: 1.7 GiB and the only Qt app in the whole
    # config, so nearly all of that was marginal rather than shared. Steam
    # ships Proton itself; protonup-qt only manages GE-Proton builds.
    mangohud
  ];

  # Nicer shell prompt/utils are configured per-user later; keeping this minimal.
  programs.starship.enable = true;

  # Flakes + the new CLI on.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  ############################################################################
  # Why claude-code comes from nixpkgs (read this before "fixing" it)
  ############################################################################
  # The official `curl ... | bash` installer drops a dynamically-linked binary
  # that looks for /lib64/ld-linux-x86-64.so.2. NixOS has no such path, so it
  # fails with "No such file or directory" while the file sits right there.
  # Same trap for any downloaded prebuilt binary. In order of preference:
  #   1. the nixpkgs package above — update by bumping the flake input
  #   2. `nix run nixpkgs/<newer-rev>#claude-code` for a newer build
  #   3. `steam-run ./some-binary` — Steam's FHS sandbox, works for any blob
  # And let nix own updates: the built-in auto-updater can't write to the
  # read-only nix store, so stop it from trying.
  environment.sessionVariables.DISABLE_AUTOUPDATER = "1";

  ############################################################################
  # Set to the release you INSTALL from. Do not change casually afterwards.
  ############################################################################
  system.stateVersion = "26.05";
}
