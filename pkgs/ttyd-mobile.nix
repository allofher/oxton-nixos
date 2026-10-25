# ttyd's own web page, plus a phone viewport and a key bar (pkgs/ttyd-mobile.html).
#
# ttyd ships its page compiled into the binary, so we start ttyd on a unix
# socket inside the build and fetch it. Patching ttyd's page instead of keeping
# a copy means a ttyd upgrade brings its new frontend along automatically.
{ runCommand, ttyd, curl }:

runCommand "ttyd-mobile-index.html" { nativeBuildInputs = [ ttyd curl ]; } ''
  sock=$TMPDIR/ttyd.sock
  ttyd --interface "$sock" true &
  for _ in $(seq 100); do [ -S "$sock" ] && break; sleep 0.1; done
  curl -sf --unix-socket "$sock" http://localhost/ > page.html
  kill %1

  # Fails the build if ttyd's page stops looking the way we expect.
  substituteInPlace page.html --replace-fail '<meta charset="UTF-8">' \
    "<meta charset=\"UTF-8\">$(cat ${./ttyd-mobile.html})"
  cp page.html $out
''
