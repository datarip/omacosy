#!/usr/bin/env bash
# System-level tweaks for the omarchy look.
#
#   (no args) / --take   record the pre-omacosy values, then auto-hide the
#                        native menu bar and release the four-finger swipes
#                        to omacosy-gesture.
#   --release            put the native menu bar and the four-finger swipes
#                        back to their pre-omacosy values, or to macOS's own
#                        defaults when the manifest has no record.
#
# install.sh and `omacosy-toggle on` take; uninstall.sh and
# `omacosy-toggle off` release.

set -euo pipefail

# Record each key's PRE-omacosy value (type + value, ABSENT if unset)
# into the install manifest, once — release restores exactly that
# instead of guessing Apple's defaults.
MANIFEST="${MANIFEST:-$HOME/.local/state/omacosy/manifest}"
mkdir -p "$(dirname "$MANIFEST")"
touch "$MANIFEST"
record_default() { # domain key
  grep -q "^default $1 $2 " "$MANIFEST" && return 0
  local t v
  if v="$(defaults read "$1" "$2" 2>/dev/null)"; then
    t="$(defaults read-type "$1" "$2" 2>/dev/null | awk '{print $3}')"
    printf 'default %s %s %s %s\n' "$1" "$2" "${t:-string}" "$v" >> "$MANIFEST"
  else
    printf 'default %s %s ABSENT ABSENT\n' "$1" "$2" >> "$MANIFEST"
  fi
}

# The keys this script owns, each with the value macOS itself uses when
# the manifest holds no pre-omacosy record (absent, or recorded ABSENT).
OWNED=(
  "NSGlobalDomain _HIHideMenuBar boolean false"
  "NSGlobalDomain SLSMenuBarUseBlurredAppearance boolean true"
  "com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture integer 2"
  "com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture integer 2"
  "com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture integer 2"
  "com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture integer 2"
  "com.apple.dock showMissionControlGestureEnabled boolean true"
)

take() {
  record_default NSGlobalDomain _HIHideMenuBar
  record_default NSGlobalDomain SLSMenuBarUseBlurredAppearance
  record_default com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture
  record_default com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture
  record_default com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture
  record_default com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture
  record_default com.apple.dock showMissionControlGestureEnabled

  # One bar, not two: auto-hide the native menu bar (sketchybar takes the top).
  # cfprefsd must be killed so the OS re-reads the pref without a logout.
  defaults write NSGlobalDomain _HIHideMenuBar -bool true
  # "Show menu bar background": Tahoe (26.0-26.2+, unfixed) sometimes
  # reveals the auto-hidden menu bar WITHOUT its glass material — text
  # soup over whatever sits in the strip. An opaque background keeps
  # even a wedged reveal readable. killall SystemUIServer resets a
  # wedge; a Focus mode's menu-bar item is one known trigger.
  defaults write NSGlobalDomain SLSMenuBarUseBlurredAppearance -bool true
  killall cfprefsd 2>/dev/null || true
  sleep 1
  killall SystemUIServer 2>/dev/null || true

  echo "macos-defaults: menu bar set to auto-hide (log out/in if it doesn't apply immediately)"

  # The 4-finger swipes belong to omacosy-gesture (workspaces + the
  # omacosy overview). Left enabled, the SYSTEM also fires Mission
  # Control / Spaces on the same gesture — MC opens on top of the
  # overview and eats every click and keystroke (and SCK captures catch
  # windows mid-MC-zoom). Trackpad -> More Gestures equivalents: off.
  defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture -int 0
  defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture -int 0
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture -int 0 2>/dev/null || true
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture -int 0 2>/dev/null || true
  defaults write com.apple.dock showMissionControlGestureEnabled -bool false
  echo "macos-defaults: 4-finger swipes released to omacosy-gesture (Dock restart applies)"
}

release() {
  local rec domain key fallback_type fallback_value line type value
  for rec in "${OWNED[@]}"; do
    # shellcheck disable=SC2086
    set -- $rec
    domain=$1 key=$2 fallback_type=$3 fallback_value=$4
    line="$(grep "^default $domain $key " "$MANIFEST" 2>/dev/null | tail -1 || true)"
    if [ -n "$line" ]; then
      type="$(printf '%s\n' "$line" | awk '{print $4}')"
      value="$(printf '%s\n' "$line" | cut -d' ' -f5-)"
      if [ "$type" = ABSENT ]; then type=$fallback_type; value=$fallback_value; fi
    else
      # No record: this install never ran the take path. Use macOS's default.
      type=$fallback_type; value=$fallback_value
    fi
    # defaults read prints a boolean as 1/0, which is how it was recorded,
    # but defaults write takes only words. An ABSENT record that predates the
    # key is WRITTEN, not deleted: on current macOS a deleted four-finger key
    # leaves the swipe off until the user toggles it by hand.
    if [ "$type" = boolean ]; then
      case "$value" in 1|true|TRUE|yes) value=true ;; *) value=false ;; esac
    fi
    defaults write "$domain" "$key" "-$type" "$value"
  done
  killall cfprefsd 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true
  killall Dock 2>/dev/null || true
  echo "macos-defaults: native menu bar and 4-finger swipes restored"
}

case "${1:-take}" in
  take|--take)       take ;;
  release|--release) release ;;
  *) echo "usage: macos-defaults.sh [--take|--release]" >&2; exit 2 ;;
esac
