#!/usr/bin/env python3
"""Delete Claude Code desktop sessions archived longer than N days (both profiles)."""

import argparse
import glob
import json
import os
import shutil
import sys
from datetime import datetime

PROFILES = [
    ("Claude", "~/Library/Application Support/Claude", "~/.claude"),
    ("Claude Personal", "~/Library/Application Support/Claude-2", "~/.claude-personal"),
]

LOG_PATH = "~/Library/Logs/claude-session-cleaner.log"
STATE_PATH = "~/.local/state/claude-session-cleaner.json"


def expand(path):
    return os.path.expanduser(path)


def to_epoch(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        seconds = float(value)
        return seconds / 1000.0 if seconds > 1e11 else seconds
    text = str(value).strip()
    if text.isdigit():
        seconds = float(text)
        return seconds / 1000.0 if seconds > 1e11 else seconds
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def iter_sessions(profile):
    name, app_dir, config_dir = profile
    pattern = os.path.join(expand(app_dir), "claude-code-sessions", "*", "*", "local_*.json")
    for meta_path in sorted(glob.glob(pattern)):
        try:
            with open(meta_path, "r", encoding="utf-8") as handle:
                meta = json.load(handle)
        except (OSError, ValueError):
            continue
        yield name, expand(config_dir), meta_path, meta


def remove(path, dry_run, removed):
    if os.path.islink(path):
        return 0
    if os.path.isdir(path):
        size = sum(
            os.path.getsize(os.path.join(root, f))
            for root, _, files in os.walk(path)
            for f in files
            if os.path.isfile(os.path.join(root, f))
        )
        if not dry_run:
            shutil.rmtree(path)
        removed.append(("dir", path, size))
        return size
    if os.path.isfile(path):
        size = os.path.getsize(path)
        if not dry_run:
            os.remove(path)
        removed.append(("file", path, size))
        return size
    return 0


def read_state():
    try:
        with open(expand(STATE_PATH), "r", encoding="utf-8") as handle:
            data = json.load(handle)
            return float(data.get("lastDeleteAt") or 0)
    except (OSError, ValueError, TypeError):
        return 0.0


def write_state(epoch, sessions, size):
    path = expand(STATE_PATH)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump({"lastDeleteAt": epoch, "sessions": sessions, "bytes": size}, handle)
    os.replace(tmp, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=3)
    parser.add_argument("--min-interval-hours", type=int, default=72)
    parser.add_argument("--apply", action="store_true", help="actually delete (default: dry run)")
    parser.add_argument("--profile", choices=["claude", "personal"], help="limit to one profile")
    parser.add_argument("--ignore-interval", action="store_true", help="ignore the 3-day guard")
    args = parser.parse_args()

    now = datetime.now().timestamp()
    cutoff = now - args.days * 86400
    dry_run = not args.apply
    per_profile = {}
    total_files = 0
    total_bytes = 0

    if not dry_run and not args.ignore_interval:
        last = read_state()
        if last and now - last < args.min_interval_hours * 3600:
            next_ok = datetime.fromtimestamp(last + args.min_interval_hours * 3600)
            line = (
                f"[{datetime.now():%Y-%m-%d %H:%M:%S}] SKIPPED: last deletion at "
                f"{datetime.fromtimestamp(last):%Y-%m-%d %H:%M:%S}, next allowed "
                f"{next_ok:%Y-%m-%d %H:%M:%S}"
            )
            print(line)
            try:
                with open(expand(LOG_PATH), "a", encoding="utf-8") as handle:
                    handle.write(line + "\n")
            except OSError:
                pass
            return

    for profile in PROFILES:
        name, config_dir, _, _ = profile[0], profile[2], None, None
        if args.profile == "claude" and name != "Claude":
            continue
        if args.profile == "personal" and name != "Claude Personal":
            continue
        count = 0
        size_sum = 0
        for prof_name, cfg, meta_path, meta in iter_sessions(profile):
            if meta.get("isArchived") is not True:
                continue
            stamp = to_epoch(meta.get("lastActivityAt") or meta.get("createdAt"))
            if stamp is None or stamp >= cutoff:
                continue
            session_id = meta.get("sessionId") or ""
            cli_id = meta.get("cliSessionId") or ""
            if not session_id.startswith("local_") or not cli_id:
                continue

            removed = []
            size = 0
            for projects_root in glob.glob(os.path.join(cfg, "projects", "*")):
                for candidate in (
                    os.path.join(projects_root, cli_id + ".jsonl"),
                    os.path.join(projects_root, cli_id),
                ):
                    if os.path.exists(candidate):
                        size += remove(candidate, dry_run, removed)
                if not dry_run and os.path.isdir(projects_root) and not os.listdir(projects_root):
                    os.rmdir(projects_root)
            for extra in (
                os.path.join(cfg, "session-env", cli_id),
                os.path.join(cfg, "file-history", cli_id),
            ):
                if os.path.exists(extra):
                    size += remove(extra, dry_run, removed)
            size += remove(meta_path, dry_run, removed)

            if removed:
                count += 1
                size_sum += size
        per_profile[name] = (count, size_sum)
        total_files += count
        total_bytes += size_sum

    stamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = [
        f"[{stamp}] {'DRY RUN' if dry_run else 'DELETED'} archived>{args.days}d: "
        + ", ".join(f"{k}: {v[0]} sessions / {v[1] / 1048576:.1f} MB" for k, v in per_profile.items())
        + f" | total {total_files} sessions / {total_bytes / 1048576:.1f} MB"
    ]
    for line in lines:
        print(line)
    try:
        os.makedirs(os.path.dirname(expand(LOG_PATH)), exist_ok=True)
        with open(expand(LOG_PATH), "a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError as exc:
        print(f"log write failed: {exc}", file=sys.stderr)
    if not dry_run and total_files > 0:
        write_state(now, total_files, total_bytes)


if __name__ == "__main__":
    main()
