#!/usr/bin/env bash
# ============================================================================
#  session-recorder — Uninstaller for Claude Code
#
#  Usage:
#    bash uninstall.sh            # Interactive uninstall
#    bash uninstall.sh --force    # Skip confirmations
#
#  What it does:
#    1. Removes plugin files from ~/.claude/plugins/cache/local/session-recorder/
#    2. Removes session-recorder hooks from ~/.claude/settings.json
#    3. Optionally removes user preferences
#
#  Requirements: python3 (for JSON editing)
# ============================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Configuration ───────────────────────────────────────────────────────────
PLUGIN_NAME="session-recorder"
PLUGIN_DIR="${HOME}/.claude/plugins/cache/local/${PLUGIN_NAME}"
SETTINGS_FILE="${HOME}/.claude/settings.json"
PREFS_FILE="${HOME}/.claude/memory/session-recorder-preferences.json"
FORCE=false

[[ "${1:-}" == "--force" ]] && FORCE=true

# ── Confirm helper ──────────────────────────────────────────────────────────
confirm() {
    if $FORCE; then return 0; fi
    local msg="$1"
    read -rp "${msg} [y/N] " answer
    [[ "${answer}" =~ ^[Yy]$ ]]
}

# ── Remove plugin files ────────────────────────────────────────────────────
remove_plugin_files() {
    if [[ -d "${PLUGIN_DIR}" ]]; then
        info "Found plugin directory: ${PLUGIN_DIR}"
        local versions
        versions=$(ls -1 "${PLUGIN_DIR}" 2>/dev/null || true)
        if [[ -n "${versions}" ]]; then
            echo "  Installed versions: ${versions}"
        fi
        if confirm "  Remove all plugin files?"; then
            rm -rf "${PLUGIN_DIR}"
            success "Plugin files removed."
        else
            info "Skipped plugin file removal."
            return 1
        fi
    else
        info "No plugin files found (already removed)."
    fi
}

# ── Remove hooks from settings.json ────────────────────────────────────────
remove_hooks() {
    if [[ ! -f "${SETTINGS_FILE}" ]]; then
        info "No settings.json found."
        return
    fi

    if ! grep -q "${PLUGIN_NAME}" "${SETTINGS_FILE}" 2>/dev/null; then
        info "No session-recorder hooks in settings.json."
        return
    fi

    info "Found session-recorder hooks in settings.json."

    if ! confirm "  Remove hooks from settings.json?"; then
        info "Skipped hook removal."
        return
    fi

    if ! command -v python3 &>/dev/null; then
        error "python3 required for safe JSON editing. Please remove hooks manually."
        return
    fi

    python3 << 'PYEOF'
import json, os

settings_path = os.path.expanduser("~/.claude/settings.json")
plugin_name = "session-recorder"

with open(settings_path, "r") as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
changed = False

for hook_type in list(hooks.keys()):
    original_len = len(hooks[hook_type])
    hooks[hook_type] = [
        entry for entry in hooks[hook_type]
        if not any(plugin_name in h.get("command", "")
                   for h in entry.get("hooks", []))
    ]
    if len(hooks[hook_type]) != original_len:
        changed = True
    # Remove empty hook arrays
    if not hooks[hook_type]:
        del hooks[hook_type]

# Remove empty hooks dict
if not hooks and "hooks" in settings:
    del settings["hooks"]

if changed:
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
    print("OK")
else:
    print("NO_CHANGE")
PYEOF

    if [[ $? -eq 0 ]]; then
        success "Hooks removed from settings.json."
    else
        error "Failed to edit settings.json. Please remove hooks manually."
    fi
}

# ── Remove user preferences ────────────────────────────────────────────────
remove_preferences() {
    if [[ -f "${PREFS_FILE}" ]]; then
        info "Found user preferences: ${PREFS_FILE}"
        if confirm "  Remove user preferences? (domain familiarity data will be lost)"; then
            rm -f "${PREFS_FILE}"
            success "User preferences removed."
        else
            info "Kept user preferences."
        fi
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   session-recorder uninstaller               ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    if ! $FORCE; then
        echo -e "${YELLOW}This will remove session-recorder from Claude Code.${NC}"
        echo ""
        if ! confirm "Proceed with uninstall?"; then
            info "Uninstall cancelled."
            exit 0
        fi
        echo ""
    fi

    # Step 1: Remove plugin files
    remove_plugin_files

    # Step 2: Remove hooks
    remove_hooks

    # Step 3: Remove preferences (optional)
    echo ""
    remove_preferences

    # Done
    echo ""
    echo -e "${BOLD}=== Uninstall Complete ===${NC}"
    echo ""
    success "session-recorder has been removed."
    info "Restart Claude Code for changes to take effect."
    info "Session logs in .session-recorder/ directories are NOT removed (your data)."
    echo ""
}

main "$@"
