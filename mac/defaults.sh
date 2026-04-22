#!/usr/bin/env bash
# macOS system tweaks.
# Run once on a fresh machine. Safe to re-run — all writes are idempotent.
# Most changes take effect immediately; a few (Dock, Finder) need their service restarted.

set -eu

echo "Applying macOS defaults..."

# =============================================================================
# Finder
# =============================================================================
# Show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Show hidden files (Cmd+Shift+. toggles this at runtime anyway)
defaults write com.apple.finder AppleShowAllFiles -bool true

# Show path bar + status bar at bottom of Finder windows
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true

# Display full POSIX path as Finder window title
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Search current folder by default (not "This Mac")
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Disable warning when changing file extensions
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Keep folders on top when sorting alphabetically
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Don't write .DS_Store files on network / USB drives
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# New Finder windows open at $HOME
defaults write com.apple.finder NewWindowTarget -string "PfHm"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"

# =============================================================================
# Dock
# =============================================================================
# Smaller icon size
defaults write com.apple.dock tilesize -int 42

# Autohide dock with no delay + fast animation
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.3

# Don't rearrange Spaces based on most-recent-use (Aerospace requirement)
defaults write com.apple.dock mru-spaces -bool false

# Don't animate opening apps from the Dock
defaults write com.apple.dock launchanim -bool false

# Don't show recent apps section in Dock
defaults write com.apple.dock show-recents -bool false

# =============================================================================
# Menu bar (sketchybar replaces native bar; hide native)
# =============================================================================
defaults write NSGlobalDomain _HIHideMenuBar -bool false   # show in full-screen apps
# "Always hide" setting — controlled via System Settings > Control Center manually
# (no reliable defaults key; must be toggled in UI on first run)

# =============================================================================
# Keyboard
# =============================================================================
# Fast key repeat (good for vim navigation)
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Disable press-and-hold for accents (needed for vim-style key repeat)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Disable auto-capitalization + smart-quotes + auto-correct (terrible in code)
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# =============================================================================
# Trackpad
# =============================================================================
# Tap-to-click (no physical press needed)
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# =============================================================================
# Screenshots
# =============================================================================
# Save to ~/Screenshots instead of Desktop
mkdir -p "$HOME/Screenshots"
defaults write com.apple.screencapture location -string "$HOME/Screenshots"

# Drop the shadow around window screenshots
defaults write com.apple.screencapture disable-shadow -bool true

# =============================================================================
# Window / Mission Control
# =============================================================================
# Speed up window resize animation
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001

# Don't group windows by app in Mission Control (we tile, each window is its own)
defaults write com.apple.dock expose-group-apps -bool false

# =============================================================================
# Other
# =============================================================================
# Expand save + print dialogs by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true

# Save to disk (not iCloud) by default
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

# Show battery percentage in menu bar
defaults write com.apple.menuextra.battery ShowPercent -string "YES"

# =============================================================================
# Restart affected services so changes take effect
# =============================================================================
for app in "cfprefsd" "Dock" "Finder" "SystemUIServer"; do
    killall "$app" >/dev/null 2>&1 || true
done

echo ""
echo "macOS defaults applied."
echo ""
echo "A few things still need a manual toggle (no reliable defaults key):"
echo "  • Hide native menu bar: System Settings → Control Center → Menu Bar → Always hide"
echo "  • Accessibility grants: System Settings → Privacy & Security → Accessibility"
echo "      - skhd   (/opt/homebrew/bin/skhd)"
echo "      - AeroSpace (/Applications/AeroSpace.app)"
echo ""
echo "Log out and back in for some changes (trackpad, keyboard) to fully apply."
