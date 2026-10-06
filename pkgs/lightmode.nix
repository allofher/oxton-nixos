# candle / flashbang — evening screen mode, and the schedule that drives it.
#
#   candle     warm tint (gammastep 1600K) + monitor backlight to 40%
#   flashbang  no tint + backlight back to 100%
#
# Brightness goes over DDC/CI because this monitor ignores gamma dimming — the
# backlight is the only thing that actually gets darker. The tint is a gammastep
# process run as the candle-warmth user service (configuration.nix); on Wayland
# the tint lasts exactly as long as that process does.
#
# Schedule: `lightmode auto` runs at 07:00 and 16:00 (and at sway login) and
# applies flashbang by day, candle from 16:00 to 07:00. Typing candle or
# flashbang yourself records the mode against today, and `auto` honours that
# instead of the clock until the next 07:00. A "day" runs 07:00 to 07:00 so a
# candle at 1am still counts as the night before, rather than cancelling the
# whole next day's schedule.
{ writeShellApplication, writeShellScriptBin, symlinkJoin, ddcutil, coreutils, systemd }:

let
  lightmode = writeShellApplication {
    name = "lightmode";
    runtimeInputs = [ ddcutil coreutils systemd ];
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/lightmode"
      day() { date -d '-7 hours' +%F; }

      # By model, not --bus 10: i2c bus numbers are assigned at boot.
      backlight() { ddcutil --model 'LG ULTRAGEAR' setvcp 10 "$1"; }

      apply() {
        case "$1" in
          candle)    systemctl --user start candle-warmth.service; backlight 40 ;;
          flashbang) systemctl --user stop candle-warmth.service; backlight 100 ;;
        esac
      }

      case "''${1:-}" in
        candle|flashbang)
          mkdir -p "$(dirname "$state")"
          echo "$(day) $1" > "$state"
          apply "$1"
          ;;
        auto)
          d="" mode=""
          read -r d mode 2>/dev/null < "$state" || true
          if [ "$d" != "$(day)" ]; then
            h=$(date +%-H)
            if [ "$h" -ge 16 ] || [ "$h" -lt 7 ]; then mode=candle; else mode=flashbang; fi
          fi
          apply "$mode"
          ;;
        *)
          echo "usage: lightmode candle|flashbang|auto" >&2
          exit 2
          ;;
      esac
    '';
  };
in
symlinkJoin {
  name = "lightmode";
  paths = [
    lightmode
    (writeShellScriptBin "candle" ''exec ${lightmode}/bin/lightmode candle'')
    (writeShellScriptBin "flashbang" ''exec ${lightmode}/bin/lightmode flashbang'')
  ];
}
