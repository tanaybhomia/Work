#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# Work Tracker GNOME Extension — Installer
# ──────────────────────────────────────────────────────────────

UUID="worktracker@tanay"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$UUID"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bold=$(tput bold); reset=$(tput sgr0)
c_ok=$(tput setaf 2); c_warn=$(tput setaf 3); c_err=$(tput setaf 1); c_info=$(tput setaf 4)

step() { echo -e "${bold}${c_info}==>${reset} $1"; }
ok()   { echo -e "  ${c_ok}✓${reset} $1"; }
warn() { echo -e "  ${c_warn}!${reset} $1"; }
err()  { echo -e "  ${c_err}✗${reset} $1"; }

echo ""
echo -e "${bold}Work Tracker — GNOME Extension Installer${reset}"
echo "────────────────────────────────────────────"

# ── 1. Create extension directory ────────────────────────────
step "Creating extension directory..."
mkdir -p "$EXT_DIR/schemas"
ok "Directory: $EXT_DIR"

# ── 2. Copy extension files ───────────────────────────────────
step "Copying extension files..."
cp "$SCRIPT_DIR/gnome-extension/extension.js" "$EXT_DIR/extension.js"
cp "$SCRIPT_DIR/gnome-extension/prefs.js"     "$EXT_DIR/prefs.js"
cp "$SCRIPT_DIR/gnome-extension/metadata.json" "$EXT_DIR/metadata.json"
cp "$SCRIPT_DIR/gnome-extension/schemas/org.gnome.shell.extensions.worktracker.gschema.xml" \
   "$EXT_DIR/schemas/"
ok "Files copied."

# ── 3. Compile GSettings schema ───────────────────────────────
step "Compiling GSettings schema..."
if glib-compile-schemas "$EXT_DIR/schemas/"; then
    ok "Schema compiled."
else
    err "Schema compilation failed. Is glib2 installed?"
    exit 1
fi

# ── 4. Enable extension ───────────────────────────────────────
step "Enabling extension..."
if gnome-extensions enable "$UUID" 2>/dev/null; then
    ok "Extension enabled: $UUID"
else
    warn "Could not auto-enable (shell may not be running yet). Run manually:"
    echo "       gnome-extensions enable $UUID"
fi

# ── 5. Done ───────────────────────────────────────────────────
echo ""
echo -e "${bold}${c_ok}Done!${reset}"
echo ""
echo "  ┌─────────────────────────────────────────────────────┐"
echo "  │  On Wayland (GNOME 45+):                            │"
echo "  │    Log out and back in to activate the extension.   │"
echo "  │                                                     │"
echo "  │  On X11:                                            │"
echo "  │    Press Alt+F2, type 'r', press Enter.             │"
echo "  └─────────────────────────────────────────────────────┘"
echo ""
echo "  Then start a session:  work start"
echo "  Open preferences:      gnome-extensions prefs $UUID"
echo ""
