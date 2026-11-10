#!/usr/bin/env bash
# Integration test against the running yabai: a tiled window that its app orders out on
# close must leave the bsp tree, and come back into it when ordered in again.
# Needs a bsp space, and Accessibility for the terminal (to press the close button).
# It opens, closes and reopens one test window on the current space.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p bin
swiftc -O hide_on_close.swift -o bin/hide-on-close

tiled() { yabai -m query --windows --window "$wid" | jq -r '."split-type" != "none" and (."is-floating" | not)'; }
fail=0
check() {
    local what=$1 want=$2 got
    got=$(tiled)
    if [ "$got" = "$want" ]; then echo "ok    $what (tiled=$got)"; else echo "FAIL  $what (tiled=$got, want $want)"; fail=1; fi
}

out=$(mktemp)
./bin/hide-on-close --reshow-after 4 --quit-after 30 > "$out" &
pid=$!
trap 'kill $pid 2>/dev/null || true; rm -f "$out"' EXIT

for _ in $(seq 50); do grep -q '^window ' "$out" && break; sleep 0.1; done
wid=$(awk '/^window /{print $2}' "$out")
sleep 1
echo "yabai $(yabai --version), test window $wid"
check "shown: tiled" true

osascript -e 'tell application "System Events" to tell (first process whose unix id is '"$pid"')' \
          -e 'click (first button of window "hide-on-close" whose subrole is "AXCloseButton")' -e 'end tell' > /dev/null
sleep 1
check "closed (ordered out): not tiled" false

for _ in $(seq 80); do grep -q '^ordered in' "$out" && break; sleep 0.1; done
sleep 1
check "reshown (ordered in): tiled" true

exit $fail
