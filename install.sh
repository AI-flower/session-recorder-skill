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
PLUGIN_VERSION="1.7.0"
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
    # Check bash version (3+ required; no bash 4+ features used)
    if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
        error "Bash 3+ is required (you have ${BASH_VERSION})."
        error "Please upgrade bash and try again."
        exit 1
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

        if [[ -x "${TARGET_DIR}/hooks/user-prompt-submit" ]]; then
            success "user-prompt-submit hook: executable"
        else
            error "user-prompt-submit hook: missing or not executable"
        fi

        if [[ -x "${TARGET_DIR}/hooks/stop" ]]; then
            success "stop hook: executable"
        else
            error "stop hook: missing or not executable"
        fi

        if [[ -x "${TARGET_DIR}/hooks/session-end" ]]; then
            success "session-end hook: executable"
        else
            error "session-end hook: missing or not executable"
        fi

        if [[ -f "${TARGET_DIR}/hooks/session_recorder_utils.py" ]]; then
            success "session_recorder_utils.py: present"
        else
            error "session_recorder_utils.py: missing"
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
plugins = data.get('plugins', data)
sys.exit(0 if '${PLUGIN_KEY}' in plugins else 1)
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

    # Check hooks in settings.json
    if [[ -f "${SETTINGS_FILE}" ]]; then
        if python3 -c "
import json, sys, os
with open('${SETTINGS_FILE}') as f:
    settings = json.load(f)
hooks = settings.get('hooks', {})
def has_hook(event):
    return any('${PLUGIN_NAME}' in h.get('command','') for entry in hooks.get(event,[]) for h in entry.get('hooks',[]))
found = [e for e in ['SessionStart','PostToolUse','UserPromptSubmit','Stop','SessionEnd'] if has_hook(e)]
missing = [e for e in ['SessionStart','PostToolUse','UserPromptSubmit','Stop','SessionEnd'] if not has_hook(e)]
if missing:
    print(f'  Missing: {missing}', file=sys.stderr)
    sys.exit(1)

# Validate hook paths exist on disk
import shlex
def get_hook_paths(event):
    paths = []
    for entry in hooks.get(event, []):
        for h in entry.get('hooks', []):
            cmd = h.get('command', '')
            try:
                parts = shlex.split(cmd)
                for p in parts:
                    if '${PLUGIN_NAME}' not in p and os.path.sep in p:
                        paths.append(p)
            except ValueError:
                pass
    return paths

invalid = []
for event in ['SessionStart','PostToolUse','UserPromptSubmit','Stop','SessionEnd']:
    for p in get_hook_paths(event):
        if not os.path.exists(p):
            invalid.append(f'{event}: {p}')

if invalid:
    for path in invalid:
        print(f'  Invalid hook path: {path}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
            success "settings.json: all 5 hooks registered (paths valid)"
        else
            error "settings.json: hooks issue (missing or invalid paths, run install.sh to fix)"
        fi
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
copy_files_to() {
    local dest="$1"
    info "Copying plugin files to ${dest} ..."

    # Create target directory structure
    mkdir -p "${dest}/.claude-plugin"
    mkdir -p "${dest}/hooks"
    mkdir -p "${dest}/references"
    mkdir -p "${dest}/skills/session-recorder"

    # Copy core files (fail fast on missing files)
    local critical_files=(
        "skills/session-recorder/SKILL.md"
        ".claude-plugin/plugin.json"
        "hooks/session-start"
        "hooks/post-tool-use"
        "hooks/user-prompt-submit"
        "hooks/stop"
        "hooks/session-end"
        "hooks/session_recorder_utils.py"
        "hooks/run-hook.cmd"
        "hooks/hooks.json"
    )
    for f in "${critical_files[@]}"; do
        if [[ ! -f "${SOURCE_DIR}/${f}" ]]; then
            error "Missing critical source file: ${f}"
            exit 1
        fi
        cp "${SOURCE_DIR}/${f}" "${dest}/${f}" || {
            error "Failed to copy: ${f}"
            exit 1
        }
    done

    # Copy references
    for f in "${SOURCE_DIR}/references/"*; do
        [[ -f "$f" ]] && cp "$f" "${dest}/references/"
    done

    # Set permissions
    chmod +x "${dest}/hooks/session-start"
    chmod +x "${dest}/hooks/post-tool-use"
    chmod +x "${dest}/hooks/user-prompt-submit"
    chmod +x "${dest}/hooks/stop"
    chmod +x "${dest}/hooks/session-end"
    chmod +x "${dest}/hooks/run-hook.cmd"

    success "Plugin files copied (${#critical_files[@]} critical files verified)."
}

# ── Register plugin via native plugin system ─────────────────────────────────
register_plugin() {
    info "Registering plugin in Claude Code plugin system ..."

    python3 << PYEOF
import json, os, sys, fcntl
from datetime import datetime, timezone

def read_json_locked(path):
    """Read JSON file with shared lock."""
    if not os.path.isfile(path):
        return {}
    with open(path, "r") as f:
        fcntl.flock(f, fcntl.LOCK_SH)
        try:
            return json.load(f)
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)

def write_json_locked(path, data):
    """Write JSON file with exclusive lock."""
    with open(path, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            json.dump(data, f, indent=2, ensure_ascii=False)
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)

plugin_key = "${PLUGIN_KEY}"
plugin_name = "${PLUGIN_NAME}"
plugin_version = "${PLUGIN_VERSION}"
install_path = "${TARGET_DIR}"
settings_path = "${SETTINGS_FILE}"
installed_plugins_path = "${INSTALLED_PLUGINS_FILE}"
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

# ── Step 1: Register in installed_plugins.json ──
os.makedirs(os.path.dirname(installed_plugins_path), exist_ok=True)

installed = read_json_locked(installed_plugins_path)

# Support both v1 (flat) and v2 (nested under "plugins") formats
if "version" in installed and "plugins" in installed:
    # v2 format: {"version": 2, "plugins": {...}}
    plugins = installed["plugins"]
else:
    # v1 format (flat) or empty — migrate to v2
    plugins = {k: v for k, v in installed.items() if k not in ("version", "plugins")}
    installed = {"version": 2, "plugins": plugins}

# Preserve installedAt if upgrading
existing = plugins.get(plugin_key, [])
installed_at = existing[0].get("installedAt", now) if existing else now

plugins[plugin_key] = [{
    "scope": "project",
    "installPath": install_path,
    "version": plugin_version,
    "installedAt": installed_at,
    "lastUpdated": now,
    "projectPath": os.path.expanduser("~")
}]

installed["plugins"] = plugins

write_json_locked(installed_plugins_path, installed)

print(f"  [OK] Registered {plugin_key} in installed_plugins.json")

# ── Step 2: Update settings.json ──
settings = read_json_locked(settings_path)

# ── Step 2a: Clean up old hooks entries for this plugin ──
hooks = settings.get("hooks", {})
for hook_event in list(hooks.keys()):
    original_len = len(hooks[hook_event])
    hooks[hook_event] = [
        entry for entry in hooks[hook_event]
        if not any(plugin_name in h.get("command", "")
                   for h in entry.get("hooks", []))
    ]
    if len(hooks[hook_event]) != original_len:
        print(f"  [OK] Cleaned old {hook_event} hook entry")
    if not hooks[hook_event]:
        del hooks[hook_event]

# ── Step 2b: Write hooks directly into settings.json ──
# Claude Code only auto-discovers hooks from managed plugin registries.
# For local/@local plugins, hooks MUST be in settings.json to work.
session_start_entry = {
    "matcher": "startup|resume|clear|compact",
    "hooks": [{
        "type": "command",
        "command": f'"{install_path}/hooks/run-hook.cmd" session-start',
        "async": False
    }]
}
post_tool_use_entry = {
    "matcher": ".*",
    "hooks": [{
        "type": "command",
        "command": f'python3 "{install_path}/hooks/post-tool-use"',
        "async": True
    }]
}
user_prompt_entry = {
    "hooks": [{
        "type": "command",
        "command": f'python3 "{install_path}/hooks/user-prompt-submit"',
        "async": True
    }]
}
stop_entry = {
    "hooks": [{
        "type": "command",
        "command": f'python3 "{install_path}/hooks/stop"',
        "async": False
    }]
}
session_end_entry = {
    "hooks": [{
        "type": "command",
        "command": f'python3 "{install_path}/hooks/session-end"',
        "timeout": 10
    }]
}

hooks.setdefault("SessionStart", []).append(session_start_entry)
hooks.setdefault("PostToolUse", []).append(post_tool_use_entry)
hooks.setdefault("UserPromptSubmit", []).append(user_prompt_entry)
hooks.setdefault("Stop", []).append(stop_entry)
hooks.setdefault("SessionEnd", []).append(session_end_entry)
settings["hooks"] = hooks
print(f"  [OK] Wrote hooks to settings.json (SessionStart, PostToolUse, UserPromptSubmit, Stop, SessionEnd)")

# Enable plugin
settings.setdefault("enabledPlugins", {})[plugin_key] = True

write_json_locked(settings_path, settings)

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
TEMP_INSTALL_DIR=""

cleanup_on_failure() {
    if [[ -n "${TEMP_INSTALL_DIR}" && -d "${TEMP_INSTALL_DIR}" ]]; then
        rm -rf "${TEMP_INSTALL_DIR}"
    fi
    # Restore backup if exists
    if [[ -d "${TARGET_DIR}.bak" ]]; then
        mv "${TARGET_DIR}.bak" "${TARGET_DIR}"
        warn "Restored previous installation from backup."
    fi
}

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

    # Set up atomic install: copy to temp dir first, move to final location only on success
    TEMP_INSTALL_DIR=$(mktemp -d)
    trap cleanup_on_failure EXIT

    # Step 1: Copy files to temp dir
    copy_files_to "${TEMP_INSTALL_DIR}"

    # Step 2: Register plugin (might fail — temp dir gets cleaned up via trap)
    register_plugin

    # Step 3: All good — move to final location atomically
    if [[ -d "${TARGET_DIR}" ]]; then
        mv "${TARGET_DIR}" "${TARGET_DIR}.bak"
    fi
    mkdir -p "$(dirname "${TARGET_DIR}")"
    mv "${TEMP_INSTALL_DIR}" "${TARGET_DIR}"
    TEMP_INSTALL_DIR=""  # Prevent cleanup
    rm -rf "${TARGET_DIR}.bak" 2>/dev/null || true

    # Clear trap
    trap - EXIT

    # Step 4: Create memory directory (for preferences)
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
