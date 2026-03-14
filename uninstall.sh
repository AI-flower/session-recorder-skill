#!/usr/bin/env bash
# ============================================================================
#  session-recorder — Uninstaller for Claude Code
#
#  Usage:
#    bash uninstall.sh              # Interactive uninstall
#    bash uninstall.sh --force      # Skip confirmations
#    bash uninstall.sh --clean-all  # Also remove /tmp session data
#
#  What it does:
#    1. Removes plugin files from ~/.claude/plugins/cache/local/session-recorder/
#    2. Removes entry from ~/.claude/plugins/installed_plugins.json
#    3. Removes entry from ~/.claude/settings.json enabledPlugins
#    4. Cleans up any legacy manual hooks (from pre-1.6.0 installs)
#    5. Optionally removes user preferences
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
PLUGIN_KEY="${PLUGIN_NAME}@local"
PLUGIN_DIR="${HOME}/.claude/plugins/cache/local/${PLUGIN_NAME}"
SETTINGS_FILE="${HOME}/.claude/settings.json"
INSTALLED_PLUGINS_FILE="${HOME}/.claude/plugins/installed_plugins.json"
PREFS_FILE="${HOME}/.claude/memory/session-recorder-preferences.json"
FORCE=false
CLEAN_ALL=false

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        --clean-all) CLEAN_ALL=true ;;
    esac
done

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

# ── Deregister plugin from Claude Code plugin system ──────────────────────
deregister_plugin() {
    if ! command -v python3 &>/dev/null; then
        error "python3 required for safe JSON editing. Please deregister plugin manually."
        return
    fi

    info "Deregistering plugin from Claude Code plugin system ..."

    python3 << PYEOF
import json, os

plugin_key = "${PLUGIN_KEY}"
plugin_name = "${PLUGIN_NAME}"
settings_path = "${SETTINGS_FILE}"
installed_plugins_path = "${INSTALLED_PLUGINS_FILE}"

# ── Step 1: Remove from installed_plugins.json ──
if os.path.isfile(installed_plugins_path):
    with open(installed_plugins_path, "r") as f:
        installed = json.load(f)
    # Support both v1 (flat) and v2 (nested under "plugins") formats
    if "version" in installed and "plugins" in installed:
        plugins = installed["plugins"]
    else:
        plugins = installed
    if plugin_key in plugins:
        del plugins[plugin_key]
        if "plugins" in installed:
            installed["plugins"] = plugins
        with open(installed_plugins_path, "w") as f:
            json.dump(installed, f, indent=2, ensure_ascii=False)
        print(f"  [OK] Removed {plugin_key} from installed_plugins.json")
    else:
        print(f"  [--] {plugin_key} not found in installed_plugins.json (already removed)")
else:
    print("  [--] installed_plugins.json not found")

# ── Step 2: Update settings.json ──
if not os.path.isfile(settings_path):
    print("  [--] settings.json not found")
else:
    with open(settings_path, "r") as f:
        settings = json.load(f)

    changed = False

    # Remove from enabledPlugins
    enabled = settings.get("enabledPlugins", {})
    if plugin_key in enabled:
        del enabled[plugin_key]
        changed = True
        print(f"  [OK] Removed {plugin_key} from enabledPlugins")
    else:
        print(f"  [--] {plugin_key} not in enabledPlugins")

    # Remove hooks written by install.sh (both current and legacy entries)
    hooks = settings.get("hooks", {})
    for hook_event in list(hooks.keys()):
        original_len = len(hooks[hook_event])
        hooks[hook_event] = [
            entry for entry in hooks[hook_event]
            if not any(plugin_name in h.get("command", "")
                       for h in entry.get("hooks", []))
        ]
        if len(hooks[hook_event]) != original_len:
            changed = True
            print(f"  [OK] Removed {hook_event} hook from settings.json")
        if not hooks[hook_event]:
            del hooks[hook_event]
    if not hooks and "hooks" in settings:
        del settings["hooks"]

    if changed:
        with open(settings_path, "w") as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)
        print("  [OK] settings.json updated")
    else:
        print("  [--] No changes needed in settings.json")
PYEOF

    if [[ $? -eq 0 ]]; then
        success "Plugin deregistered."
    else
        error "Failed to deregister plugin. Please edit ${SETTINGS_FILE} and ${INSTALLED_PLUGINS_FILE} manually."
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

# ── Clean up session data ──────────────────────────────────────────────────
clean_session_data() {
    info "Cleaning up session data..."

    # Clean /tmp session directories
    local tmp_dirs=(/tmp/.session-recorder-* /tmp/.session-recorder)
    for dir in "${tmp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if confirm "  Remove ${dir}?"; then
                rm -rf "$dir"
                success "  Removed ${dir}"
            fi
        fi
    done

    info "Note: .session-recorder/ directories in project folders are NOT removed."
    info "Remove them manually if needed: find / -name .session-recorder -type d 2>/dev/null"
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

    # Step 2: Deregister plugin
    deregister_plugin

    # Step 3: Remove preferences (optional)
    echo ""
    remove_preferences

    # Step 4: Clean up runtime session data (optional)
    if $CLEAN_ALL; then
        echo ""
        clean_session_data
    fi

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
