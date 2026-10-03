# node project template

```
mkdir ~/projects/newthing && cd ~/projects/newthing
nix flake init -t ~/nixos#node
direnv allow            # once per project; direnv refuses to run an unvetted .envrc
```

That's it. The shell activates on `cd` from then on. Edit `flake.nix` to change
the node major or add native build deps.

## Things worth knowing

**`npm install -g` fails here**, with `EACCES`. npm's global prefix points inside
the read-only nix store. Either use `npx <tool>`, or add the tool to `flake.nix`
where it's pinned and reproducible, or — if you really want a global install —
`npm config set prefix ~/.npm-global` and put that on PATH.

**Prebuilt native binaries are the other trap.** When npm downloads a `.node`
binary instead of compiling, it expects `/lib64/ld-linux-x86-64.so.2`, which
NixOS doesn't have, and fails with "No such file or directory" while pointing at
a file that exists. Fixes, in order: add the build deps to `flake.nix` and let it
compile, force a source build (`npm rebuild --build-from-source`), or wrap the
offender in `steam-run` as a last resort.

**`.direnv/` is already gitignored** in the oxton-nixos repo; add it to a new
project's `.gitignore` too.

**Don't commit `flake.lock` to throwaway projects**, but do commit it to anything
you want to build identically later — same reason the system config pins one.
