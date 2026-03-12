#!/usr/bin/env bash
# ============================================================================
#  session-recorder — One-click installer for Claude Code
#
#  Usage:
#    bash install.sh            # Install / upgrade
#    bash install.sh --check    # Check current installation status
#
#  What it does:
#    1. Copies plugin files to ~/.claude/plugins/cache/local/session-recorder/
#    2. Registers plugin in ~/.claude/plugins/installed_plugins.json
#    3. Enables plugin in ~/.claude/settings.json (enabledPlugins)
#    4. Migrates away from old manual hooks (if upgrading from <=1.5.0)
#
#  Requirements: bash 4+, python3
# ============================================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Configuration ───────────────────────────────────────────────────────────
PLUGIN_NAME="session-recorder"
PLUGIN_VERSION="1.6.0"
PLUGIN_KEY="${PLUGIN_NAME}@local"

# Source: where install.sh lives (the repo/distribution directory)
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target: Claude Code plugin cache
TARGET_DIR="${HOME}/.claude/plugins/cache/local/${PLUGIN_NAME}/${PLUGIN_VERSION}"

# Settings and registry files
SETTINGS_FILE="${HOME}/.claude/settings.json"
INSTALLED_PLUGINS_FILE="${HOME}/.claude/plugins/installed_plugins.json"

# ── Pre-flight checks ──────────────────────────────────────────────────────
preflight() {
    # Check bash version
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        warn "Bash 4+ recommended (you have ${BASH_VERSION}). Proceeding anyway..."
    fi

    # Check python3
    if ! command -v python3 &>/dev/null; then
        error "python3 is required."
        error "Install Python 3 and try again."
        exit 1
    fi

    # Check source files exist
    if [[ ! -f "${SOURCE_DIR}/skills/session-recorder/SKILL.md" ]]; then
        error "skills/session-recorder/SKILL.md not found in ${SOURCE_DIR}"
        error "Run this script from the session-recorder directory."
        exit 1
    fi

    if [[ ! -d "${SOURCE_DIR}/hooks" ]]; then
        error "hooks/ directory not found in ${SOURCE_DIR}"
        exit 1
    fi

    # Check Claude Code directory exists
    if [[ ! -d "${HOME}/.claude" ]]; then
        warn "${HOME}/.claude does not exist. Creating it..."
        mkdir -p "${HOME}/.claude"
    fi
}

# ── Check mode ──────────────────────────────────────────────────────────────
check_installation() {
    echo -e "${BOLD}=== session-recorder Installation Status ===${NC}"
    echo ""

    # Check plugin files
    if [[ -d "${TARGET_DIR}" ]]; then
        success "Plugin directory exists: ${TARGET_DIR}"

        if [[ -f "${TARGET_DIR}/skills/session-recorder/SKILL.md" ]]; then
            local ver
            ver=$(grep -o 'version: [0-9.]*' "${TARGET_DIR}/skills/session-recorder/SKILL.md" 2>/dev/null | head -1 | awk '{print $2}')
            success "skills/session-recorder/SKILL.md found (version: ${ver:-unknown})"
        else
            error "skills/session-recorder/SKILL.md missing"
        fi

        if [[ -x "${TARGET_DIR}/hooks/session-start" ]]; then
            success "session-start hook: executable"
        else
            error "session-start hook: missing or not executable"
        fi

        if [[ -x "${TARGET_DIR}/hooks/post-tool-use" ]]; then
            success "post-tool-use hook: executable"
        else
            error "post-tool-use hook: missing or not executable"
        fi
    else
        error "Plugin directory not found: ${TARGET_DIR}"
    fi

    echo ""

    # Check installed_plugins.json
    if [[ -f "${INSTALLED_PLUGINS_FILE}" ]]; then
        if python3 -c "
import json, sys
with open('${INSTALLED_PLUGINS_FILE}') as f:
    data = json.load(f)
sys.exit(0 if '${PLUGIN_KEY}' in data else 1)
" 2>/dev/null; then
            success "installed_plugins.json: ${PLUGIN_KEY} registered"
        else
            error "installed_plugins.json: ${PLUGIN_KEY} NOT registered"
        fi
    else
        error "installed_plugins.json not found at ${INSTALLED_PLUGINS_FILE}"
    fi

    # Check enabledPlugins in settings.json
    if [[ -f "${SETTINGS_FILE}" ]]; then
        if python3 -c "
import json, sys
with open('${SETTINGS_FILE}') as f:
    settings = json.load(f)
enabled = settings.get('enabledPlugins', {})
sys.exit(0 if enabled.get('${PLUGIN_KEY}') == True else 1)
" 2>/dev/null; then
            success "settings.json: ${PLUGIN_KEY} enabled"
        else
            error "settings.json: ${PLUGIN_KEY} NOT in enabledPlugins"
        fi
    else
        error "settings.json not found at ${SETTINGS_FILE}"
    fi

    echo ""

    # Check dependencies
    if [[ -f "${HOME}/.agents/skills/find-skills/SKILL.md" ]]; then
        success "find-skills dependency: installed"
    else
        warn "find-skills dependency: not installed (will auto-install on first use)"
    fi

    if [[ -f "${HOME}/.claude/memory/session-recorder-preferences.json" ]]; then
        success "User preferences file: exists"
    else
        info "User preferences file: not yet created (will be created on first use)"
    fi
}

# ── Copy plugin files ───────────────────────────────────────────────────────
copy_files() {
    info "Copying plugin files to ${TARGET_DIR} ..."

    # Create target directory structure
    mkdir -p "${TARGET_DIR}/.claude-plugin"
    mkdir -p "${TARGET_DIR}/hooks"
    mkdir -p "${TARGET_DIR}/references"
    mkdir -p "${TARGET_DIR}/skills/session-recorder"

    # Copy core files
    cp "${SOURCE_DIR}/skills/session-recorder/SKILL.md" "${TARGET_DIR}/skills/session-recorder/SKILL.md"
    cp "${SOURCE_DIR}/.claude-plugin/plugin.json" "${TARGET_DIR}/.claude-plugin/plugin.json"

    # Copy hooks
    cp "${SOURCE_DIR}/hooks/session-start" "${TARGET_DIR}/hooks/session-start"
    cp "${SOURCE_DIR}/hooks/post-tool-use" "${TARGET_DIR}/hooks/post-tool-use"
    cp "${SOURCE_DIR}/hooks/run-hook.cmd" "${TARGET_DIR}/hooks/run-hook.cmd"
    cp "${SOURCE_DIR}/hooks/hooks.json" "${TARGET_DIR}/hooks/hooks.json"

    # Copy references
    for f in "${SOURCE_DIR}/references/"*; do
        [[ -f "$f" ]] && cp "$f" "${TARGET_DIR}/references/"
    done

    # Set permissions
    chmod +x "${TARGET_DIR}/hooks/session-start"
    chmod +x "${TARGET_DIR}/hooks/post-tool-use"
    chmod +x "${TARGET_DIR}/hooks/run-hook.cmd"

    success "Plugin files copied."
}

# ── Register plugin via native plugin system ─────────────────────────────────
register_plugin() {
    info "Registering plugin in Claude Code plugin system ..."

    python3 << PYEOF
import json, os, sys
from datetime import datetime, timezone

plugin_key = "${PLUGIN_KEY}"
plugin_name = "${PLUGIN_NAME}"
plugin_version = "${PLUGIN_VERSION}"
install_path = "${TARGET_DIR}"
settings_path = "${SETTINGS_FILE}"
installed_plugins_path = "${INSTALLED_PLUGINS_FILE}"
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

# ── Step 1: Register in installed_plugins.json ──
os.makedirs(os.path.dirname(installed_plugins_path), exist_ok=True)

if os.path.isfile(installed_plugins_path):
    with open(installed_plugins_path, "r") as f:
        installed = json.load(f)
else:
    installed = {}

# Preserve installedAt if upgrading
existing = installed.get(plugin_key, [])
installed_at = existing[0].get("installedAt", now) if existing else now

installed[plugin_key] = [{
    "scope": "user",
    "installPath": install_path,
    "version": plugin_version,
    "installedAt": installed_at,
    "lastUpdated": now
}]

with open(installed_plugins_path, "w") as f:
    json.dump(installed, f, indent=2, ensure_ascii=False)

print(f"  [OK] Registered {plugin_key} in installed_plugins.json")

# ── Step 2: Update settings.json ──
if os.path.isfile(settings_path):
    with open(settings_path, "r") as f:
        settings = json.load(f)
else:
    settings = {}

# Migration: remove old manually-written hooks (pre-1.6.0 installs)
hooks = settings.get("hooks", {})
migrated = False
for hook_event in list(hooks.keys()):
    original_len = len(hooks[hook_event])
    hooks[hook_event] = [
        entry for entry in hooks[hook_event]
        if not any(plugin_name in h.get("command", "")
                   for h in entry.get("hooks", []))
    ]
    if len(hooks[hook_event]) != original_len:
        migrated = True
    if not hooks[hook_event]:
        del hooks[hook_event]
if not hooks and "hooks" in settings:
    del settings["hooks"]
if migrated:
    print("  [OK] Migrated: removed old manual hooks from settings.json")

# Enable plugin
settings.setdefault("enabledPlugins", {})[plugin_key] = True

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print(f"  [OK] Enabled {plugin_key} in settings.json enabledPlugins")
PYEOF

    if [[ $? -eq 0 ]]; then
        success "Plugin registered."
    else
        error "Failed to register plugin. Check ${INSTALLED_PLUGINS_FILE} and ${SETTINGS_FILE} manually."
        exit 1
    fi
}

# ── Handle old version cleanup ──────────────────────────────────────────────
cleanup_old_versions() {
    local cache_dir="${HOME}/.claude/plugins/cache/local/${PLUGIN_NAME}"

    if [[ ! -d "${cache_dir}" ]]; then
        return
    fi

    for version_dir in "${cache_dir}"/*/; do
        local dir_version
        dir_version=$(basename "${version_dir}")

        # Skip current version
        if [[ "${dir_version}" == "${PLUGIN_VERSION}" ]]; then
            continue
        fi

        # Skip if not a version-like directory
        if [[ ! "${dir_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            continue
        fi

        warn "Found old version: ${dir_version}"
        read -rp "  Remove old version ${dir_version}? [y/N] " answer
        if [[ "${answer}" =~ ^[Yy]$ ]]; then
            rm -rf "${version_dir}"
            success "  Removed ${dir_version}"
        else
            info "  Kept ${dir_version}"
        fi
    done
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║   session-recorder installer v${PLUGIN_VERSION}          ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    # Check mode
    if [[ "${1:-}" == "--check" ]]; then
        check_installation
        exit 0
    fi

    # Pre-flight
    preflight

    # Check for existing installation
    if [[ -d "${TARGET_DIR}" ]]; then
        warn "Existing installation found at ${TARGET_DIR}"
        read -rp "Overwrite? [Y/n] " answer
        if [[ "${answer}" =~ ^[Nn]$ ]]; then
            info "Installation cancelled."
            exit 0
        fi
    fi

    # Clean up old versions
    cleanup_old_versions

    # Step 1: Copy files
    copy_files

    # Step 2: Register plugin (replaces old merge_hooks approach)
    register_plugin

    # Step 3: Create memory directory (for preferences)
    mkdir -p "${HOME}/.claude/memory"

    # Done
    echo ""
    echo -e "${BOLD}=== Installation Complete ===${NC}"
    echo ""
    success "Plugin installed to: ${TARGET_DIR}"
    success "Plugin registered in: ${INSTALLED_PLUGINS_FILE}"
    success "Plugin enabled in:    ${SETTINGS_FILE}"
    echo ""
    info "Next steps:"
    echo "  1. Restart Claude Code (or start a new session)"
    echo "  2. session-recorder will activate automatically"
    echo "  3. Run 'bash install.sh --check' to verify"
    echo ""
}

main "$@"
