#!/usr/bin/env bash
# install-local.sh - install a from-source build where a manual install belongs: /usr/local.
#
# Steps:
#   codesign the build with a STABLE self-signed cert (so macOS Accessibility/Screen-Recording
#   grants survive rebuilds) -> stop/uninstall old service -> install binary into PREFIX/bin
#   -> refresh the passwordless `--load-sa` sudoers entry (hash of the SIGNED binary)
#   -> load the scripting addition -> start the launchd service.
#
# Run via `make install-local` (which builds first). Honours:
#   PREFIX      install location (default /usr/local; the binary goes in PREFIX/bin)
#   YABAI_CERT  code-signing identity: (part of) a name or a SHA-1 hash, as listed by
#               `security find-identity -v -p codesigning`   (default yabai-cert)
#
# PREFIX/bin must hold the first yabai on PATH: yabairc runs `sudo yabai --load-sa`, and
# the sudoers entry only covers the binary installed here.
#
# The default needs a `yabai-cert` Code Signing identity in your keychain. Create one once:
#   Keychain Access -> Certificate Assistant -> Create a Certificate
#     Name: yabai-cert   Identity Type: Self Signed Root   Certificate Type: Code Signing
# or use an Apple-issued one, e.g. YABAI_CERT="Apple Development" (see `mise run install`).
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  cat >&2 <<'EOF'
error: run this as your normal user, NOT with sudo (`make install-local`, not `sudo make ...`).
It elevates only the steps that need root and will prompt for your password.
Running the whole thing as root signs against root's keychain, writes a `root` sudoers
entry, and makes --load-sa look for the wrong per-user SA socket (SUDO_UID=0) -> it fails.
EOF
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${PREFIX:-/usr/local}"
YABAI_CERT="${YABAI_CERT:-yabai-cert}"
BIN_SRC="$root/bin/yabai"
BIN_DIR="$PREFIX/bin"
BIN_DST="$BIN_DIR/yabai"
SUDOERS="/private/etc/sudoers.d/yabai"

# /usr/local is root-owned. Elevate file operations only when PREFIX is not user-writable,
# so a PREFIX under $HOME does not end up holding root-owned files.
existing_dir="$BIN_DIR"
while [ ! -d "$existing_dir" ]; do existing_dir="$(dirname "$existing_dir")"; done
in_prefix() { if [ -w "$existing_dir" ]; then "$@"; else sudo "$@"; fi; }

if [ "${1:-}" = "--uninstall" ]; then
  echo "==> uninstalling $BIN_DST"
  "$BIN_DST" --stop-service 2>/dev/null || true
  "$BIN_DST" --uninstall-service 2>/dev/null || true
  sudo "$BIN_DST" --uninstall-sa 2>/dev/null || true
  in_prefix rm -f "$BIN_DST"
  sudo rm -f "$SUDOERS"
  echo "==> removed binary, service, scripting-addition, and sudoers entry"
  exit 0
fi

[ -x "$BIN_SRC" ] || { echo "error: $BIN_SRC not built — run 'make' first" >&2; exit 1; }

first_on_path="$(command -v yabai || true)"
if [ -n "$first_on_path" ] && [ "$first_on_path" != "$BIN_DST" ]; then
  cat >&2 <<EOF
error: another yabai comes first on PATH: $first_on_path
\`sudo yabai --load-sa\` (yabairc) would run that copy, but the passwordless sudoers entry
gets pinned to $BIN_DST. Remove the other copy, then re-run:
  brew uninstall yabai      (if it is a Homebrew formula)
  rm $first_on_path      (otherwise, e.g. a copy from an earlier install-local)
EOF
  exit 1
fi

echo "==> codesigning with '$YABAI_CERT' (stable identity -> Accessibility persists across rebuilds)"
if ! "$root/scripts/codesign" "$BIN_SRC" "$YABAI_CERT"; then
  cat >&2 <<EOF

error: could not sign with code-signing identity '$YABAI_CERT'.
Pick one from the list above with YABAI_CERT=..., or create a self-signed one once:
  Keychain Access -> Certificate Assistant -> Create a Certificate
    Name: yabai-cert   Identity Type: Self Signed Root   Certificate Type: Code Signing
EOF
  exit 1
fi
codesign --verify --verbose "$BIN_SRC"

# Use the fresh build, not PATH: the service must be re-registered for $BIN_DST even when
# no yabai is installed any more (e.g. the previous copy was just removed).
echo "==> stopping any existing service"
"$BIN_SRC" --stop-service 2>/dev/null || true
"$BIN_SRC" --uninstall-service 2>/dev/null || true

echo "==> installing $BIN_SRC -> $BIN_DST"
in_prefix mkdir -p "$BIN_DIR"
in_prefix rm -f "$BIN_DST"            # clear any prior symlink (e.g. from a dev `ln -s`)
in_prefix install -m 0755 "$BIN_SRC" "$BIN_DST"

echo "==> refreshing $SUDOERS (passwordless --load-sa, pinned to the SIGNED binary's hash)"
hash="$(shasum -a 256 "$BIN_DST" | cut -d' ' -f1)"
printf '%s ALL=(root) NOPASSWD: sha256:%s %s --load-sa\n' "$(whoami)" "$hash" "$BIN_DST" \
  | sudo tee "$SUDOERS" >/dev/null
sudo chmod 0440 "$SUDOERS"
sudo visudo -cf "$SUDOERS"           # validate; aborts if the entry is malformed

echo "==> loading scripting addition"
sudo "$BIN_DST" --load-sa

echo "==> starting launchd service"
"$BIN_DST" --start-service

cat <<EOF

==> done. yabai is signed ($YABAI_CERT), installed at $BIN_DST, SA loaded, service running.
    First run after a NEW signature or install location: grant Accessibility once
    (System Settings -> Privacy & Security -> Accessibility). It will persist from now on.
EOF
