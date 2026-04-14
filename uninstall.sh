#!/usr/bin/env bash
# ============================================================================
#  session-recorder — Uninstaller for Claude Code & Codex CLI
#
#  Usage:
#    bash uninstall.sh              # Interactive uninstall
#    bash uninstall.sh --force      # Skip confirmations
#    bash uninstall.sh --clean-all  # Also remove /tmp session data
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
FORCE=false
CLEAN_ALL=false

# Claude Code paths
CLAUDE_DIR="${HOME}/.claude"
CC_PLUGIN_DIR="${CLAUDE_DIR}/plugins/cache/local/${PLUGIN_NAME}"
CC_SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
CC_INSTALLED_PLUGINS_FILE="${CLAUDE_DIR}/plugins/installed_plugins.json"
CC_PREFS_FILE="${CLAUDE_DIR}/memory/session-recorder-preferences.json"

# Codex CLI paths
CODEX_DIR="${HOME}/.codex"
CX_PLUGIN_DIR="${CODEX_DIR}/plugins/${PLUGIN_NAME}"
CX_HOOKS_FILE="${CODEX_DIR}/hooks.json"
CX_AGENTS_FILE="${CODEX_DIR}/AGENTS.md"
CX_PREFS_FILE="${CODEX_DIR}/session-recorder-preferences.json"

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        --clean-all) CLEAN_ALL=true ;;
    esac
done

confirm() {
    if $FORCE; then return 0; fi
    local msg="$1"
    read -rp "${msg} [y/N] " answer
    [[ "${answer}" =~ ^[Yy]$ ]]
}

# ============================================================================
#  Claude Code cleanup
# ============================================================================

uninstall_claude_code() {
    info "Removing from Claude Code ..."

    # Remove plugin files
    if [[ -d "${CC_PLUGIN_DIR}" ]]; then
        rm -rf "${CC_PLUGIN_DIR}"
        success "Plugin files removed: ${CC_PLUGIN_DIR}"
    fi

    # Deregister from settings/plugins
    if command -v python3 &>/dev/null; then
        python3 << PYEOF
import json, os

plugin_key = "${PLUGIN_KEY}"
plugin_name = "${PLUGIN_NAME}"
settings_path = "${CC_SETTINGS_FILE}"
installed_plugins_path = "${CC_INSTALLED_PLUGINS_FILE}"

# Remove from installed_plugins.json
if os.path.isfile(installed_plugins_path):
    with open(installed_plugins_path) as f:
        installed = json.load(f)
    plugins = installed.get("plugins", installed)
    if plugin_key in plugins:
        del plugins[plugin_key]
        if "plugins" in installed:
            installed["plugins"] = plugins
        with open(installed_plugins_path, "w") as f:
            json.dump(installed, f, indent=2, ensure_ascii=False)
        print(f"  [OK] Removed from installed_plugins.json")

# Remove from settings.json
if os.path.isfile(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
    changed = False
    enabled = settings.get("enabledPlugins", {})
    if plugin_key in enabled:
        del enabled[plugin_key]
        changed = True
    hooks = settings.get("hooks", {})
    for event in list(hooks.keys()):
        orig = len(hooks[event])
        hooks[event] = [e for e in hooks[event]
                        if not any(plugin_name in h.get("command","")
                                   for h in e.get("hooks",[]))]
        if len(hooks[event]) != orig:
            changed = True
        if not hooks[event]:
            del hooks[event]
    if not hooks and "hooks" in settings:
        del settings["hooks"]
    if changed:
        with open(settings_path, "w") as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)
        print(f"  [OK] Cleaned settings.json")
PYEOF
    fi

    # Remove preferences
    if [[ -f "${CC_PREFS_FILE}" ]]; then
        if confirm "  Remove Claude Code preferences?"; then
            rm -f "${CC_PREFS_FILE}"
            success "Preferences removed."
        fi
    fi

    success "Claude Code cleanup done."
}

# ============================================================================
#  Codex CLI cleanup
# ============================================================================

uninstall_codex() {
    info "Removing from Codex CLI ..."

    # Remove plugin files
    if [[ -d "${CX_PLUGIN_DIR}" ]]; then
        rm -rf "${CX_PLUGIN_DIR}"
        success "Plugin files removed: ${CX_PLUGIN_DIR}"
    fi

    # Remove hooks from hooks.json
    if [[ -f "${CX_HOOKS_FILE}" ]] && command -v python3 &>/dev/null; then
        python3 -c "
import json
plugin_name = '${PLUGIN_NAME}'
with open('${CX_HOOKS_FILE}') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
for event in list(hooks.keys()):
    hooks[event] = [e for e in hooks[event]
                    if not any(plugin_name in h.get('command','')
                               for h in e.get('hooks',[]))]
    if not hooks[event]:
        del hooks[event]
data['hooks'] = hooks
with open('${CX_HOOKS_FILE}', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print('  [OK] Removed hooks from hooks.json')
" 2>/dev/null
    fi

    # Remove session-recorder block from AGENTS.md
    if [[ -f "${CX_AGENTS_FILE}" ]]; then
        python3 -c "
import re
with open('${CX_AGENTS_FILE}') as f:
    content = f.read()
content = re.sub(r'\n?<!-- session-recorder:start -->.*?<!-- session-recorder:end -->\n?', '', content, flags=re.DOTALL)
with open('${CX_AGENTS_FILE}', 'w') as f:
    f.write(content.strip() + '\n' if content.strip() else '')
print('  [OK] Removed session-recorder from AGENTS.md')
" 2>/dev/null
    fi

    # Remove preferences
    if [[ -f "${CX_PREFS_FILE}" ]]; then
        if confirm "  Remove Codex preferences?"; then
            rm -f "${CX_PREFS_FILE}"
            success "Preferences removed."
        fi
    fi

    success "Codex CLI cleanup done."
}

# ============================================================================
#  Clean session data
# ============================================================================

clean_session_data() {
    info "Cleaning up session data..."
    local tmp_dirs=(/tmp/.session-recorder-* /tmp/.session-recorder)
    for dir in "${tmp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if confirm "  Remove ${dir}?"; then
                rm -rf "$dir"
                success "  Removed ${dir}"
            fi
        fi
    done
    info "Note: .session-recorder/ in project folders are NOT removed."
}

# ============================================================================
#  Main
# ============================================================================

main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   session-recorder uninstaller               ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    local has_cc=false
    local has_cx=false
    [[ -d "${CC_PLUGIN_DIR}" || -f "${CC_SETTINGS_FILE}" ]] && has_cc=true
    [[ -d "${CX_PLUGIN_DIR}" || -f "${CX_HOOKS_FILE}" ]] && has_cx=true

    if ! $has_cc && ! $has_cx; then
        info "No session-recorder installation found."
        exit 0
    fi

    if ! $FORCE; then
        local platforms=""
        $has_cc && platforms="Claude Code"
        $has_cx && { [[ -n "$platforms" ]] && platforms="${platforms} & "; platforms="${platforms}Codex CLI"; }
        echo -e "${YELLOW}This will remove session-recorder from ${platforms}.${NC}"
        echo ""
        if ! confirm "Proceed with uninstall?"; then
            info "Uninstall cancelled."
            exit 0
        fi
        echo ""
    fi

    $has_cc && uninstall_claude_code && echo ""
    $has_cx && uninstall_codex && echo ""

    if $CLEAN_ALL; then
        clean_session_data
        echo ""
    fi

    echo -e "${BOLD}=== Uninstall Complete ===${NC}"
    echo ""
    success "session-recorder has been removed."
    info "Restart your AI coding tool for changes to take effect."
    echo ""
}

main "$@"
