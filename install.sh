#!/usr/bin/env bash
# ============================================================================
#  session-recorder — One-click installer for Claude Code & Codex CLI
#
#  Usage:
#    bash install.sh            # Install / upgrade (auto-detects platform)
#    bash install.sh --check    # Check current installation status
#    bash install.sh --codex    # Force install for Codex CLI only
#    bash install.sh --claude   # Force install for Claude Code only
#
#  What it does:
#    Claude Code:
#      1. Copies plugin files to ~/.claude/plugins/cache/local/session-recorder/
#      2. Registers plugin in ~/.claude/plugins/installed_plugins.json
#      3. Enables plugin in ~/.claude/settings.json (enabledPlugins)
#      4. Writes hooks to settings.json
#
#    Codex CLI:
#      1. Copies plugin files to ~/.codex/plugins/session-recorder/
#      2. Writes hooks to ~/.codex/hooks.json
#      3. Installs SKILL.md content into ~/.codex/AGENTS.md
#      4. Enables codex_hooks feature in config.toml (if needed)
#
#  Requirements: bash 3+, python3
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
PLUGIN_VERSION="1.8.0"
PLUGIN_KEY="${PLUGIN_NAME}@local"

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Claude Code paths
CLAUDE_DIR="${HOME}/.claude"
CC_TARGET_DIR="${CLAUDE_DIR}/plugins/cache/local/${PLUGIN_NAME}/${PLUGIN_VERSION}"
CC_SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
CC_INSTALLED_PLUGINS_FILE="${CLAUDE_DIR}/plugins/installed_plugins.json"

# Codex CLI paths
CODEX_DIR="${HOME}/.codex"
CX_TARGET_DIR="${CODEX_DIR}/plugins/${PLUGIN_NAME}/${PLUGIN_VERSION}"
CX_HOOKS_FILE="${CODEX_DIR}/hooks.json"
CX_AGENTS_FILE="${CODEX_DIR}/AGENTS.md"
CX_CONFIG_FILE="${CODEX_DIR}/config.toml"

# ── Platform Detection ─────────────────────────────────────────────────────
detect_platform() {
    local has_claude=false
    local has_codex=false
    [[ -d "${CLAUDE_DIR}" ]] && has_claude=true
    [[ -d "${CODEX_DIR}" ]] && has_codex=true

    if $has_claude && $has_codex; then
        echo "both"
    elif $has_codex; then
        echo "codex"
    elif $has_claude; then
        echo "claude-code"
    else
        echo "none"
    fi
}

# ── Pre-flight checks ──────────────────────────────────────────────────────
preflight() {
    if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
        error "Bash 3+ is required (you have ${BASH_VERSION})."
        exit 1
    fi

    if ! command -v python3 &>/dev/null; then
        error "python3 is required."
        exit 1
    fi

    if [[ ! -f "${SOURCE_DIR}/skills/session-recorder/SKILL.md" ]]; then
        error "skills/session-recorder/SKILL.md not found in ${SOURCE_DIR}"
        exit 1
    fi

    if [[ ! -d "${SOURCE_DIR}/hooks" ]]; then
        error "hooks/ directory not found in ${SOURCE_DIR}"
        exit 1
    fi
}

# ── Copy plugin files (shared by both platforms) ───────────────────────────
copy_files_to() {
    local dest="$1"
    info "Copying plugin files to ${dest} ..."

    mkdir -p "${dest}/.claude-plugin"
    mkdir -p "${dest}/hooks"
    mkdir -p "${dest}/references"
    mkdir -p "${dest}/skills/session-recorder"

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

    for f in "${SOURCE_DIR}/references/"*; do
        [[ -f "$f" ]] && cp "$f" "${dest}/references/"
    done

    chmod +x "${dest}/hooks/session-start"
    chmod +x "${dest}/hooks/post-tool-use"
    chmod +x "${dest}/hooks/user-prompt-submit"
    chmod +x "${dest}/hooks/stop"
    chmod +x "${dest}/hooks/session-end"
    chmod +x "${dest}/hooks/run-hook.cmd"

    success "Plugin files copied (${#critical_files[@]} critical files verified)."
}

# ============================================================================
#  CLAUDE CODE specific functions
# ============================================================================

register_claude_code_plugin() {
    info "Registering plugin in Claude Code ..."

    python3 << PYEOF
import json, os, sys, fcntl
from datetime import datetime, timezone

def read_json_locked(path):
    if not os.path.isfile(path):
        return {}
    with open(path, "r") as f:
        fcntl.flock(f, fcntl.LOCK_SH)
        try:
            return json.load(f)
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)

def write_json_locked(path, data):
    with open(path, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            json.dump(data, f, indent=2, ensure_ascii=False)
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)

plugin_key = "${PLUGIN_KEY}"
plugin_name = "${PLUGIN_NAME}"
plugin_version = "${PLUGIN_VERSION}"
install_path = "${CC_TARGET_DIR}"
settings_path = "${CC_SETTINGS_FILE}"
installed_plugins_path = "${CC_INSTALLED_PLUGINS_FILE}"
now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")

# Step 1: Register in installed_plugins.json
os.makedirs(os.path.dirname(installed_plugins_path), exist_ok=True)
installed = read_json_locked(installed_plugins_path)
if "version" in installed and "plugins" in installed:
    plugins = installed["plugins"]
else:
    plugins = {k: v for k, v in installed.items() if k not in ("version", "plugins")}
    installed = {"version": 2, "plugins": plugins}

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

# Step 2: Update settings.json
settings = read_json_locked(settings_path)

# Clean old hooks
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

# Write new hooks
hooks.setdefault("SessionStart", []).append({
    "matcher": "startup|resume|clear|compact",
    "hooks": [{"type": "command",
               "command": f'"{install_path}/hooks/run-hook.cmd" session-start',
               "async": False}]
})
hooks.setdefault("PostToolUse", []).append({
    "matcher": ".*",
    "hooks": [{"type": "command",
               "command": f'python3 "{install_path}/hooks/post-tool-use"',
               "async": True}]
})
hooks.setdefault("UserPromptSubmit", []).append({
    "hooks": [{"type": "command",
               "command": f'python3 "{install_path}/hooks/user-prompt-submit"',
               "async": True}]
})
hooks.setdefault("Stop", []).append({
    "hooks": [{"type": "command",
               "command": f'python3 "{install_path}/hooks/stop"',
               "async": False}]
})
hooks.setdefault("SessionEnd", []).append({
    "hooks": [{"type": "command",
               "command": f'python3 "{install_path}/hooks/session-end"',
               "timeout": 10}]
})
settings["hooks"] = hooks
print(f"  [OK] Wrote hooks to settings.json (5 events)")

settings.setdefault("enabledPlugins", {})[plugin_key] = True
write_json_locked(settings_path, settings)
print(f"  [OK] Enabled {plugin_key} in settings.json")
PYEOF

    if [[ $? -eq 0 ]]; then
        success "Claude Code plugin registered."
    else
        error "Failed to register plugin."
        exit 1
    fi
}

check_claude_code() {
    echo -e "${BOLD}--- Claude Code ---${NC}"

    if [[ -d "${CC_TARGET_DIR}" ]]; then
        success "Plugin directory: ${CC_TARGET_DIR}"
        for hook in session-start post-tool-use user-prompt-submit stop session-end; do
            if [[ -x "${CC_TARGET_DIR}/hooks/${hook}" ]]; then
                success "  ${hook}: executable"
            else
                error "  ${hook}: missing or not executable"
            fi
        done
    else
        warn "Plugin directory not found: ${CC_TARGET_DIR}"
    fi

    if [[ -f "${CC_SETTINGS_FILE}" ]]; then
        python3 -c "
import json, sys
with open('${CC_SETTINGS_FILE}') as f:
    s = json.load(f)
enabled = s.get('enabledPlugins', {}).get('${PLUGIN_KEY}')
hooks = s.get('hooks', {})
hook_count = sum(1 for e in ['SessionStart','PostToolUse','UserPromptSubmit','Stop','SessionEnd']
                 if any('${PLUGIN_NAME}' in h.get('command','')
                        for entry in hooks.get(e,[]) for h in entry.get('hooks',[])))
print(f'  enabledPlugins: {\"enabled\" if enabled else \"NOT enabled\"}')
print(f'  hooks registered: {hook_count}/5')
" 2>/dev/null || warn "Could not parse settings.json"
    fi
    echo ""
}

install_claude_code() {
    local target_dir="${CC_TARGET_DIR}"

    if [[ ! -d "${CLAUDE_DIR}" ]]; then
        mkdir -p "${CLAUDE_DIR}"
    fi

    if [[ -d "${target_dir}" ]]; then
        warn "Existing Claude Code installation found"
        read -rp "  Overwrite? [Y/n] " answer
        if [[ "${answer}" =~ ^[Nn]$ ]]; then
            info "Skipped Claude Code installation."
            return
        fi
    fi

    # Clean up old versions
    local cache_dir="${CLAUDE_DIR}/plugins/cache/local/${PLUGIN_NAME}"
    if [[ -d "${cache_dir}" ]]; then
        for version_dir in "${cache_dir}"/*/; do
            local dir_version
            dir_version=$(basename "${version_dir}")
            [[ "${dir_version}" == "${PLUGIN_VERSION}" ]] && continue
            [[ ! "${dir_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue
            warn "Found old version: ${dir_version}"
            read -rp "  Remove? [y/N] " answer
            [[ "${answer}" =~ ^[Yy]$ ]] && rm -rf "${version_dir}" && success "  Removed ${dir_version}"
        done
    fi

    # Atomic install
    local temp_dir
    temp_dir=$(mktemp -d)
    copy_files_to "${temp_dir}"

    register_claude_code_plugin

    if [[ -d "${target_dir}" ]]; then
        rm -rf "${target_dir}.bak" 2>/dev/null || true
        mv "${target_dir}" "${target_dir}.bak"
    fi
    mkdir -p "$(dirname "${target_dir}")"
    mv "${temp_dir}" "${target_dir}"
    rm -rf "${target_dir}.bak" 2>/dev/null || true

    mkdir -p "${CLAUDE_DIR}/memory"

    success "Claude Code installation complete: ${target_dir}"
}

# ============================================================================
#  CODEX CLI specific functions
# ============================================================================

register_codex_hooks() {
    info "Writing hooks to ${CX_HOOKS_FILE} ..."

    python3 << PYEOF
import json, os

hooks_path = "${CX_HOOKS_FILE}"
install_path = "${CX_TARGET_DIR}"
plugin_name = "${PLUGIN_NAME}"

# Read existing hooks.json or start fresh
existing = {}
if os.path.isfile(hooks_path):
    with open(hooks_path) as f:
        existing = json.load(f)

hooks = existing.get("hooks", {})

# Remove old session-recorder entries
for event in list(hooks.keys()):
    hooks[event] = [e for e in hooks[event]
                    if not any(plugin_name in h.get("command", "")
                               for h in e.get("hooks", []))]
    if not hooks[event]:
        del hooks[event]

# SessionStart (no compact event on Codex)
hooks.setdefault("SessionStart", []).append({
    "matcher": "startup|resume|clear",
    "hooks": [{"type": "command",
               "command": f'"{install_path}/hooks/run-hook.cmd" session-start',
               "timeout": 15}]
})

# PostToolUse (Codex: only fires for Bash tool)
hooks.setdefault("PostToolUse", []).append({
    "matcher": ".*",
    "hooks": [{"type": "command",
               "command": f'python3 "{install_path}/hooks/post-tool-use"',
               "async": True, "timeout": 10}]
})

# UserPromptSubmit
hooks.setdefault("UserPromptSubmit", []).append({
    "hooks": [{"type": "command",
               "command": f'python3 "{install_path}/hooks/user-prompt-submit"',
               "async": True, "timeout": 10}]
})

# Stop (includes SessionEnd fallback for Codex)
hooks.setdefault("Stop", []).append({
    "hooks": [{"type": "command",
               "command": f'python3 "{install_path}/hooks/stop"',
               "timeout": 15}]
})

# No SessionEnd — Codex does not support it

existing["hooks"] = hooks
with open(hooks_path, "w") as f:
    json.dump(existing, f, indent=2, ensure_ascii=False)

print(f"  [OK] Wrote 4 hooks to {hooks_path} (SessionStart, PostToolUse, UserPromptSubmit, Stop)")
print(f"  [--] SessionEnd: skipped (not supported by Codex CLI)")
PYEOF

    if [[ $? -eq 0 ]]; then
        success "Codex hooks registered."
    else
        error "Failed to write hooks.json."
        exit 1
    fi
}

install_codex_agents_md() {
    info "Installing SKILL.md into AGENTS.md ..."

    local skill_file="${1}/skills/session-recorder/SKILL.md"
    local marker_start="<!-- session-recorder:start -->"
    local marker_end="<!-- session-recorder:end -->"

    if [[ -f "${CX_AGENTS_FILE}" ]]; then
        # Remove existing session-recorder block
        python3 -c "
import re
with open('${CX_AGENTS_FILE}', 'r') as f:
    content = f.read()
content = re.sub(r'<!-- session-recorder:start -->.*?<!-- session-recorder:end -->\n?', '', content, flags=re.DOTALL)
with open('${CX_AGENTS_FILE}', 'w') as f:
    f.write(content)
" 2>/dev/null
    fi

    # Append session-recorder block
    {
        echo ""
        echo "${marker_start}"
        echo "# Session Recorder Plugin"
        echo ""
        cat "${skill_file}"
        echo ""
        echo "${marker_end}"
    } >> "${CX_AGENTS_FILE}"

    local size
    size=$(wc -c < "${CX_AGENTS_FILE}" | tr -d ' ')
    if [[ "${size}" -gt 32768 ]]; then
        warn "AGENTS.md is ${size} bytes (Codex default limit: 32768)."
        warn "Consider increasing project_doc_max_bytes in config.toml."
    fi

    success "AGENTS.md updated (${size} bytes)."
}

enable_codex_hooks_feature() {
    if [[ ! -f "${CX_CONFIG_FILE}" ]]; then
        warn "config.toml not found at ${CX_CONFIG_FILE}"
        return
    fi

    if grep -q 'codex_hooks' "${CX_CONFIG_FILE}" 2>/dev/null; then
        info "codex_hooks already configured in config.toml"
        return
    fi

    python3 << PYEOF
config_path = "${CX_CONFIG_FILE}"
with open(config_path, "r") as f:
    content = f.read()

if "[features]" in content:
    content = content.replace("[features]", "[features]\ncodex_hooks = true", 1)
else:
    content += "\n[features]\ncodex_hooks = true\n"

with open(config_path, "w") as f:
    f.write(content)

print("  [OK] Enabled codex_hooks in config.toml")
PYEOF
}

check_codex() {
    echo -e "${BOLD}--- Codex CLI ---${NC}"

    if [[ -d "${CX_TARGET_DIR}" ]]; then
        success "Plugin directory: ${CX_TARGET_DIR}"
        for hook in session-start post-tool-use user-prompt-submit stop; do
            if [[ -x "${CX_TARGET_DIR}/hooks/${hook}" ]]; then
                success "  ${hook}: executable"
            else
                error "  ${hook}: missing or not executable"
            fi
        done
    else
        warn "Plugin directory not found: ${CX_TARGET_DIR}"
    fi

    if [[ -f "${CX_HOOKS_FILE}" ]]; then
        python3 -c "
import json
with open('${CX_HOOKS_FILE}') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
count = sum(1 for e in ['SessionStart','PostToolUse','UserPromptSubmit','Stop']
            if any('${PLUGIN_NAME}' in h.get('command','')
                   for entry in hooks.get(e,[]) for h in entry.get('hooks',[])))
print(f'  hooks.json: {count}/4 hooks registered')
" 2>/dev/null || warn "Could not parse hooks.json"
    else
        warn "hooks.json not found"
    fi

    if [[ -f "${CX_AGENTS_FILE}" ]]; then
        if grep -q 'session-recorder:start' "${CX_AGENTS_FILE}" 2>/dev/null; then
            success "AGENTS.md: session-recorder content installed"
        else
            warn "AGENTS.md exists but no session-recorder content"
        fi
    else
        warn "AGENTS.md not found"
    fi

    if [[ -f "${CX_CONFIG_FILE}" ]]; then
        if grep -q 'codex_hooks.*=.*true' "${CX_CONFIG_FILE}" 2>/dev/null; then
            success "config.toml: codex_hooks enabled"
        else
            warn "config.toml: codex_hooks not enabled"
        fi
    fi
    echo ""
}

install_codex() {
    local target_dir="${CX_TARGET_DIR}"

    if [[ -d "${target_dir}" ]]; then
        warn "Existing Codex installation found"
        read -rp "  Overwrite? [Y/n] " answer
        if [[ "${answer}" =~ ^[Nn]$ ]]; then
            info "Skipped Codex installation."
            return
        fi
    fi

    # Clean up old versions
    local plugin_dir="${CODEX_DIR}/plugins/${PLUGIN_NAME}"
    if [[ -d "${plugin_dir}" ]]; then
        for version_dir in "${plugin_dir}"/*/; do
            local dir_version
            dir_version=$(basename "${version_dir}")
            [[ "${dir_version}" == "${PLUGIN_VERSION}" ]] && continue
            [[ ! "${dir_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue
            warn "Found old version: ${dir_version}"
            read -rp "  Remove? [y/N] " answer
            [[ "${answer}" =~ ^[Yy]$ ]] && rm -rf "${version_dir}" && success "  Removed ${dir_version}"
        done
    fi

    # Copy files
    local temp_dir
    temp_dir=$(mktemp -d)
    copy_files_to "${temp_dir}"

    # Register hooks
    register_codex_hooks

    # Install AGENTS.md
    install_codex_agents_md "${temp_dir}"

    # Enable hooks feature
    enable_codex_hooks_feature

    # Move to final location
    if [[ -d "${target_dir}" ]]; then
        rm -rf "${target_dir}.bak" 2>/dev/null || true
        mv "${target_dir}" "${target_dir}.bak"
    fi
    mkdir -p "$(dirname "${target_dir}")"
    mv "${temp_dir}" "${target_dir}"
    rm -rf "${target_dir}.bak" 2>/dev/null || true

    success "Codex CLI installation complete: ${target_dir}"
}

# ============================================================================
#  Check mode
# ============================================================================

check_installation() {
    echo -e "${BOLD}=== session-recorder Installation Status (v${PLUGIN_VERSION}) ===${NC}"
    echo ""

    local platform
    platform=$(detect_platform)

    case "$platform" in
        claude-code) check_claude_code ;;
        codex)       check_codex ;;
        both)        check_claude_code; check_codex ;;
        none)        warn "Neither ~/.claude nor ~/.codex found." ;;
    esac

    # Common checks
    if [[ -f "${HOME}/.agents/skills/find-skills/SKILL.md" ]]; then
        success "find-skills dependency: installed"
    else
        warn "find-skills dependency: not installed (will auto-install on first use)"
    fi
}

# ============================================================================
#  Main
# ============================================================================

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

    preflight

    # Determine target platform
    local force_platform="${1:-}"
    local platform

    if [[ "$force_platform" == "--codex" ]]; then
        platform="codex"
    elif [[ "$force_platform" == "--claude" ]]; then
        platform="claude-code"
    else
        platform=$(detect_platform)
    fi

    info "Detected platform: ${platform}"
    echo ""

    case "$platform" in
        claude-code)
            install_claude_code
            echo ""
            echo -e "${BOLD}=== Installation Complete ===${NC}"
            echo ""
            info "Next steps:"
            echo "  1. Restart Claude Code"
            echo "  2. session-recorder will activate automatically"
            echo "  3. Run 'bash install.sh --check' to verify"
            ;;
        codex)
            install_codex
            echo ""
            echo -e "${BOLD}=== Installation Complete ===${NC}"
            echo ""
            info "Next steps:"
            echo "  1. Restart Codex CLI"
            echo "  2. session-recorder will activate automatically"
            echo "  3. Run 'bash install.sh --check' to verify"
            ;;
        both)
            echo -e "  ${BOLD}[1]${NC} Claude Code only"
            echo -e "  ${BOLD}[2]${NC} Codex CLI only"
            echo -e "  ${BOLD}[3]${NC} Both platforms"
            echo ""
            read -rp "Install for which platform? [1/2/3] " choice
            echo ""

            case "$choice" in
                1) install_claude_code ;;
                2) install_codex ;;
                3|"")
                    install_claude_code
                    echo ""
                    install_codex
                    ;;
                *)
                    error "Invalid choice: ${choice}"
                    exit 1
                    ;;
            esac
            echo ""
            echo -e "${BOLD}=== Installation Complete ===${NC}"
            echo ""
            info "Restart your AI coding tool for changes to take effect."
            echo "  Run 'bash install.sh --check' to verify."
            ;;
        none)
            error "Neither ~/.claude nor ~/.codex found."
            error "Install Claude Code or Codex CLI first."
            exit 1
            ;;
    esac

    echo ""
}

main "$@"
