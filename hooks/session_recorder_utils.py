"""Shared utilities for session-recorder hooks."""

import os
import json
import sys
import fcntl
from datetime import datetime, timezone

MAX_CONTENT_SIZE = 50000  # 50KB limit per content field
MAX_LOG_SIZE = 10 * 1024 * 1024  # 10MB
_MAX_LOG_FILE_SIZE = MAX_LOG_SIZE  # backward compat alias


def _tmp_fallback_dir():
    """Return per-user tmp directory for session-recorder."""
    return f"/tmp/.session-recorder-{os.getuid()}/"


def get_log_dir(cwd):
    """Find existing session-recorder log directory (do NOT create)."""
    d = os.path.join(cwd, ".session-recorder")
    if os.path.isdir(d):
        return d
    tmp_d = _tmp_fallback_dir()
    if os.path.isdir(tmp_d):
        return tmp_d
    return None


def get_or_create_log_dir(cwd):
    """Find or create session-recorder log directory."""
    d = os.path.join(cwd, ".session-recorder")
    if os.path.isdir(d):
        return d
    tmp_d = _tmp_fallback_dir()
    if os.path.isdir(tmp_d):
        return tmp_d
    try:
        os.makedirs(d, exist_ok=True)
        return d
    except OSError:
        try:
            os.makedirs(tmp_d, exist_ok=True)
            return tmp_d
        except OSError:
            return None


def now_ts():
    """Return current UTC timestamp in ISO 8601 format."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def append_log(log_dir, entry):
    """Append a JSON entry to session-log.jsonl with file locking."""
    if "content" in entry:
        content_str = str(entry.get("content", ""))
        if len(content_str) > MAX_CONTENT_SIZE:
            entry = dict(entry)  # shallow copy to avoid mutating caller's dict
            entry["content"] = content_str[:MAX_CONTENT_SIZE] + "...[truncated]"
            entry["content_truncated"] = True

    log_file = os.path.join(log_dir, "session-log.jsonl")
    line = json.dumps(entry, ensure_ascii=False) + "\n"

    try:
        if os.path.getsize(log_file) > MAX_LOG_SIZE:
            log_hook_error("utils", f"session-log.jsonl exceeds {MAX_LOG_SIZE} bytes")
    except OSError:
        pass

    fd = os.open(log_file, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        os.write(fd, line.encode("utf-8"))
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def read_log(log_dir):
    """Read all entries from session-log.jsonl."""
    log_file = os.path.join(log_dir, "session-log.jsonl")
    entries = []
    if os.path.isfile(log_file):
        file_size = os.path.getsize(log_file)
        with open(log_file, "rb") as f:
            if file_size > _MAX_LOG_FILE_SIZE:
                f.seek(file_size - _MAX_LOG_FILE_SIZE)
                f.readline()  # skip partial first line
            for line in f:
                line = line.decode("utf-8", errors="replace").strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
    return entries


def has_report(log_dir):
    """Check if a report already exists in the reports directory."""
    reports_dir = os.path.join(log_dir, "reports")
    if not os.path.isdir(reports_dir):
        return False
    return any(f.endswith(".json") for f in os.listdir(reports_dir))


def read_stdin(max_bytes=65536):
    """Read and parse stdin JSON with enforced size limit."""
    try:
        raw = sys.stdin.buffer.read(max_bytes)
    except AttributeError:
        raw = sys.stdin.read(max_bytes).encode("utf-8")
    if not raw:
        return None
    return json.loads(raw.decode("utf-8", errors="replace"))


def check_log_size(log_dir, max_bytes=_MAX_LOG_FILE_SIZE):
    """Warn to stderr if session-log.jsonl exceeds max_bytes. Non-blocking."""
    log_file = os.path.join(log_dir, "session-log.jsonl")
    try:
        size = os.path.getsize(log_file)
        if size > max_bytes:
            mb = size / (1024 * 1024)
            sys.stderr.write(
                f"[session-recorder] warning: session-log.jsonl is {mb:.1f}MB "
                f"(>{max_bytes // (1024 * 1024)}MB)\n"
            )
    except OSError:
        pass


def log_hook_error(hook_name, error):
    """Write error to stderr for debugging. Non-blocking."""
    try:
        sys.stderr.write(f"[session-recorder:{hook_name}] {error}\n")
    except Exception:
        pass
