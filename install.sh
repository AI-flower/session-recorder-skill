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
#    2. Merges SessionStart + PostToolUse hooks into ~/.claude/settings.json
#    3. Sets correct file permissions
#    4. Verifies installation
#
#  Requirements: bash 4+, python3 (for JSON merging)
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
PLUGIN_VERSION="1.4.0"

# Source: where install.sh lives (the repo/distribution directory)
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Target: Claude Code plugin cache
TARGET_DIR="${HOME}/.claude/plugins/cache/local/${PLUGIN_NAME}/${PLUGIN_VERSION}"

# Settings file
SETTINGS_FILE="${HOME}/.claude/settings.json"

# ── Pre-flight checks ──────────────────────────────────────────────────────
preflight() {
    # Check bash version
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        warn "Bash 4+ recommended (you have ${BASH_VERSION}). Proceeding anyway..."
    fi

    # Check python3 for JSON merging
    if ! command -v python3 &>/dev/null; then
        error "python3 is required for JSON configuration merging."
        error "Install Python 3 and try again."
        exit 1
    fi

    # Check source files exist
    if [[ ! -f "${SOURCE_DIR}/SKILL.md" ]]; then
        error "SKILL.md not found in ${SOURCE_DIR}"
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

        if [[ -f "${TARGET_DIR}/SKILL.md" ]]; then
            local ver
            ver=$(grep -o 'version: [0-9.]*' "${TARGET_DIR}/SKILL.md" 2>/dev/null | head -1 | awk '{print $2}')
            success "SKILL.md found (version: ${ver:-unknown})"
        else
            error "SKILL.md missing"
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

    # Check settings.json hooks
    if [[ -f "${SETTINGS_FILE}" ]]; then
        if grep -q "session-recorder" "${SETTINGS_FILE}" 2>/dev/null; then
            success "settings.json: session-recorder hooks registered"

            if grep -q "SessionStart" "${SETTINGS_FILE}" 2>/dev/null; then
                success "  SessionStart hook: configured"
            else
                warn "  SessionStart hook: NOT configured"
            fi

            if grep -q "PostToolUse" "${SETTINGS_FILE}" 2>/dev/null; then
                success "  PostToolUse hook: configured"
            else
                warn "  PostToolUse hook: NOT configured"
            fi
        else
            error "settings.json: no session-recorder hooks found"
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

    # Copy core files
    cp "${SOURCE_DIR}/SKILL.md" "${TARGET_DIR}/SKILL.md"
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

# ── Merge hooks into settings.json ──────────────────────────────────────────
merge_hooks() {
    info "Configuring hooks in ${SETTINGS_FILE} ..."

    # Build the hook commands using the actual target path
    local session_start_cmd="bash '${TARGET_DIR}/hooks/session-start'"
    local post_tool_use_cmd="python3 '${TARGET_DIR}/hooks/post-tool-use'"

    # Use python3 for reliable JSON merging
    python3 << PYEOF
import json, os, sys

settings_path = "${SETTINGS_FILE}"
plugin_name = "${PLUGIN_NAME}"
session_start_cmd = """${session_start_cmd}"""
post_tool_use_cmd = """${post_tool_use_cmd}"""

# Load or create settings
if os.path.isfile(settings_path):
    with open(settings_path, "r") as f:
        settings = json.load(f)
else:
    settings = {}

# Ensure hooks dict exists
if "hooks" not in settings:
    settings["hooks"] = {}

hooks = settings["hooks"]

# ── Helper: remove old session-recorder entries from a hook list ──
def remove_old_entries(hook_list):
    return [entry for entry in hook_list
            if not any(plugin_name in h.get("command", "")
                      for h in entry.get("hooks", []))]

# ── SessionStart hook ──
session_start_entry = {
    "matcher": "startup|resume|clear|compact",
    "hooks": [{
        "type": "command",
        "command": session_start_cmd
    }]
}

if "SessionStart" in hooks:
    hooks["SessionStart"] = remove_old_entries(hooks["SessionStart"])
    hooks["SessionStart"].append(session_start_entry)
else:
    hooks["SessionStart"] = [session_start_entry]

# ── PostToolUse hook ──
post_tool_use_entry = {
    "matcher": ".*",
    "hooks": [{
        "type": "command",
        "command": post_tool_use_cmd,
        "timeout": 3000
    }]
}

if "PostToolUse" in hooks:
    hooks["PostToolUse"] = remove_old_entries(hooks["PostToolUse"])
    hooks["PostToolUse"].append(post_tool_use_entry)
else:
    hooks["PostToolUse"] = [post_tool_use_entry]

# Write back
with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)

print("OK")
PYEOF

    if [[ $? -eq 0 ]]; then
        success "Hooks configured in settings.json."
    else
        error "Failed to configure hooks. Please check ${SETTINGS_FILE} manually."
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

    # Step 2: Configure hooks
    merge_hooks

    # Step 3: Create memory directory (for preferences)
    mkdir -p "${HOME}/.claude/memory"

    # Done
    echo ""
    echo -e "${BOLD}=== Installation Complete ===${NC}"
    echo ""
    success "Plugin installed to: ${TARGET_DIR}"
    success "Hooks configured in: ${SETTINGS_FILE}"
    echo ""
    info "Next steps:"
    echo "  1. Restart Claude Code (or start a new session)"
    echo "  2. session-recorder will activate automatically"
    echo "  3. Run 'bash install.sh --check' to verify"
    echo ""
}

main "$@"
