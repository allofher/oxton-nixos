# wallpaper — the San Juan River photo with live rain, fog and ripples on top.
#
# mpvpaper shows the photo and runs sway/wallpaper/rain.glsl over it every
# frame. mpv only redraws when a new frame arrives, so the lavfi filter loops
# the single image into a 30fps stream; that stream is the shader's clock.
#
# Gaming: while Steam is running the shader is stopped outright, freeing the
# GPU, and swaybg's static copy of the photo (sway/config) shows through.
# When Steam exits the shader comes back. Steam keeps running in the tray after
# its window closes, so it has to be quit (Steam > Exit) to count as closed.
#
# Run as the wallpaper user service (configuration.nix), bound to the sway
# session. Files are read from the repo, not the store, so tweaking the shader
# is an edit plus `systemctl --user restart wallpaper`, no rebuild.
{ writeShellApplication, mpvpaper, procps, coreutils }:

writeShellApplication {
  name = "wallpaper";
  runtimeInputs = [ mpvpaper procps coreutils ];
  text = ''
    dir="$HOME/nixos/sway/wallpaper"
    opts="no-audio image-display-duration=inf"
    opts+=" vf=lavfi=[loop=loop=-1:size=1,fps=30] panscan=1.0"
    opts+=" glsl-shaders=$dir/rain.glsl"

    pid=""
    start() {
      mpvpaper -o "$opts" '*' "$dir/san-juan-river.jpg" &
      pid=$!
    }
    stop() {
      if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
      fi
      pid=""
    }
    trap 'stop; exit 0' TERM INT

    # Poll rather than subscribe: Steam can run with no window at all, so the
    # process is the only reliable signal. pgrep every few seconds costs nothing.
    while true; do
      if pgrep -x steam >/dev/null; then
        stop
      elif [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
        start                     # first run, Steam just exited, or mpvpaper died
      fi
      sleep 3 & wait $!           # wait, not plain sleep, so TERM lands at once
    done
  '';
}
