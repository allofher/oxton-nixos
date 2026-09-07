{ config, pkgs, lib, ... }:

{
  imports = [
    # Generated on the machine by `nixos-generate-config` during install.
    # It doesn't exist yet — create/commit it after the first install.
    ./hardware-configuration.nix
  ];

  ############################################################################
  # Boot
  ############################################################################
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # RDNA3 (7900 XTX) benefits from a recent kernel + Mesa.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # zram swap (matches your current setup; no swap partition needed).
  zramSwap.enable = true;

  # NOTE ON DISK ENCRYPTION — decide before install:
  #  - If you want an unattended box you can reboot remotely, either skip LUKS
  #    on root, OR keep LUKS + TPM2 auto-unlock (systemd-cryptenroll), OR set up
  #    initrd-ssh remote unlock. A LUKS root with a boot passphrase means the
  #    machine WON'T come back after a power blip until you're physically there.
  #  - hardware-configuration.nix will contain the luks/boot bits once generated.

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
  # JOB 2 — home-network daemons (mpd)
  ############################################################################
  services.mpd = {
    enable = true;
    user = "liz";
    # Point at the MASTER library on the HDD, not the small ~/music subset:
    musicDirectory = "/mnt/music";
    network.listenAddress = "0.0.0.0"; # LAN + tailscale; firewall scopes it
    extraConfig = ''
      audio_output {
        type "pipewire"
        name "PipeWire Output"
      }
    '';
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
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd sway";
      user = "greeter";
    };
  };

  ############################################################################
  # Firewall — LAN/tailscale scoped
  ############################################################################
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 6600 ];       # ssh, mpd
    trustedInterfaces = [ "tailscale0" ]; # everything open over the tailnet
  };

  ############################################################################
  # Packages — this IS your "install packages ahead of time" step.
  # Lean base + the nice CLI utils you liked from omarchy. Curate freely.
  ############################################################################
  environment.systemPackages = with pkgs; [
    # core
    git vim neovim curl wget rsync tmux
    # the "omarchy-nice" terminal set
    eza bat fd ripgrep fzf zoxide starship btop jq yazi
    # dev / runtime you already use
    go uv docker-compose
    # GPU / compute tooling (native, for monitoring/debug)
    rocmPackages.rocminfo rocmPackages.rocm-smi
    # gaming helpers
    mangohud protonup-qt
  ];

  # Nicer shell prompt/utils are configured per-user later; keeping this minimal.
  programs.starship.enable = true;

  # Flakes + the new CLI on.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  ############################################################################
  # Set to the release you INSTALL from. Do not change casually afterwards.
  ############################################################################
  system.stateVersion = "26.05";
}
