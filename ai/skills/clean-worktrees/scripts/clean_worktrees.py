"""Bounded, read-only-by-default cleanup of local agent worktrees. Python 3.12+."""

import argparse
import json
import os
import plistlib
import shutil
import signal
import sqlite3
import stat
import subprocess
import tempfile
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path

GENERATED = {
    "node_modules",
    ".venv",
    "__pycache__",
    ".next",
    ".nuxt",
    ".output",
    ".turbo",
    ".pytest_cache",
    ".ruff_cache",
    ".mypy_cache",
    ".svelte-kit",
    ".parcel-cache",
    ".vite",
    ".tanstack",
}
ROOT_CACHES = GENERATED | {".flox/cache"}
SCANNERS = {
    "StorageManagementService",
    "mds",
    "mds_stores",
    "mdworker",
    "mdworker_shared",
}
STOP = threading.Event()


class Keep(RuntimeError):
    pass


def run(args, timeout=120):
    result = subprocess.run(args, capture_output=True, timeout=timeout, check=False)
    if result.returncode or result.stderr.strip():
        raise RuntimeError(result.stderr.decode(errors="replace").strip()[:500])
    return result.stdout


def git(path, *args):
    return run(["git", "--no-optional-locks", "-C", str(path), *args])


def inside(value, parent):
    return value == str(parent) or value.startswith(str(parent) + "/")


def safe(path, root):
    return path != root and path.is_relative_to(root) and path.resolve() == path


@dataclass(frozen=True)
class Candidate:
    path: Path
    primary: Path | None
    scope: Path
    locked: bool


def metadata(path):
    text = (path / ".git").read_text().strip()
    if not text.startswith("gitdir: "):
        raise RuntimeError("unknown .git file")
    directory = (path / text[8:]).resolve()
    common = (directory / (directory / "commondir").read_text().strip()).resolve()
    if common.name != ".git":
        raise RuntimeError("unsupported Git common directory")
    if Path((directory / "gitdir").read_text().strip()) != path / ".git":
        raise RuntimeError("Git worktree backlink differs")
    return common.parent, (directory / "locked").exists()


def children(path):
    return (
        sorted(p for p in path.iterdir() if p.is_dir() and not p.is_symlink())
        if path.is_dir()
        else []
    )


def discover(home, repos):
    paths = {}
    t3 = home / ".t3/worktrees"
    for entry in children(t3):
        if (entry / ".git").exists():
            paths[entry] = t3
        else:
            paths.update((p, entry) for p in children(entry))
    known = set(repos)
    if not repos:
        dev = home / "dev"
        for parent in [dev, *children(dev)]:
            known.update(p for p in children(parent) if (p / ".git").is_dir())
    for path in paths:
        try:
            known.add(metadata(path)[0])
        except (OSError, RuntimeError):
            pass
    # Git registration also finds Claude worktrees outside the usual dev depth.
    registered = {}
    for repo in sorted(known):
        raw = git(repo, "worktree", "list", "--porcelain", "-z")
        for record in raw.split(b"\0\0"):
            fields = record.split(b"\0")
            names = [os.fsdecode(f[9:]) for f in fields if f.startswith(b"worktree ")]
            if not names:
                continue
            path = Path(names[0])
            registered[path] = (repo, any(f.startswith(b"locked") for f in fields))
            for parent in path.parents:
                if parent.name == "worktrees" and parent.parent.name == ".claude":
                    if path.exists():
                        paths[path] = parent
                    break
        scope = repo / ".claude/worktrees"
        paths.update((p, scope) for p in children(scope))
    result = []
    for path, scope in sorted(paths.items()):
        primary, locked = registered.get(path, (None, False))
        if repos and primary not in repos:
            continue
        result.append(Candidate(path, primary, scope, locked))
    return result


def t3_paths(home):
    db = home / ".t3/userdata/statev2.sqlite"
    if not (home / ".t3").exists():
        return set(), set()
    with closing(sqlite3.connect(db.as_uri() + "?mode=ro", uri=True)) as connection:
        connection.execute("BEGIN")
        threads = {
            row[0]: json.loads(row[1])
            for row in connection.execute(
                "SELECT thread_id,payload_json FROM orchestration_v2_projection_threads"
            )
        }
        for row in connection.execute(
            "SELECT thread_id,worktree_path,archived_at,deleted_at,settled_override,"
            "pinned_at,snoozed_until FROM projection_threads"
        ):
            threads.setdefault(
                row[0],
                dict(
                    zip(
                        (
                            "id",
                            "worktreePath",
                            "archivedAt",
                            "deletedAt",
                            "settledOverride",
                            "pinnedAt",
                            "snoozedUntil",
                        ),
                        row,
                    )
                ),
            )
        busy = {
            r[0]
            for r in connection.execute(
                "SELECT thread_id FROM orchestration_v2_projection_runs "
                "WHERE status IN ('preparing','queued','starting','running','waiting')"
            )
        }
        busy.update(
            r[0]
            for r in connection.execute(
                "SELECT thread_id FROM orchestration_v2_projection_runtime_requests WHERE status='pending'"
            )
        )
        protected = {
            r[0]
            for r in connection.execute(
                "SELECT workspace_root FROM projection_projects WHERE deleted_at IS NULL"
            )
            if r[0]
        }
        protected.update(
            r[0]
            for r in connection.execute(
                "SELECT worktree_path FROM orchestration_v2_thread_launch_workflows "
                "WHERE worktree_path IS NOT NULL AND status NOT IN ('completed','failed','cancelled')"
            )
        )
        if connection.execute(
            "SELECT 1 FROM scheduled_tasks WHERE enabled=1 LIMIT 1"
        ).fetchone():
            raise RuntimeError(
                "enabled T3 schedules need inspection before automated cleanup"
            )
    referenced = set()
    for thread_id, thread in threads.items():
        required = {
            "id",
            "worktreePath",
            "deletedAt",
            "archivedAt",
            "settledOverride",
            "snoozedUntil",
        }
        if (
            not isinstance(thread, dict)
            or not required.issubset(thread)
            or thread["id"] != thread_id
        ):
            raise RuntimeError("unknown T3 thread payload schema")
        path = thread.get("worktreePath")
        if not path:
            continue
        referenced.add(path)
        if thread_id in busy or (
            not thread.get("deletedAt")
            and not thread.get("archivedAt")
            and (
                thread.get("pinnedAt")
                or thread.get("snoozedUntil")
                or thread.get("settledOverride") != "settled"
            )
        ):
            protected.add(path)
    return protected, referenced


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)


def process_paths(home):
    paths = set()
    command = ""
    for line in (
        run(["lsof", "-nP", "-Fpcn"], timeout=60).decode(errors="replace").splitlines()
    ):
        if line.startswith("c"):
            command = line[1:]
        elif line.startswith("n/") and command not in SCANNERS:
            paths.add(line[1:].removesuffix(" (deleted)"))
    for entry in (home / ".claude/sessions").glob("*.json"):
        session = json.loads(entry.read_text())
        try:
            os.kill(int(session["pid"]), 0)
        except ProcessLookupError:
            continue
        if session.get("cwd"):
            paths.add(session["cwd"])
    references = run(["ps", "-axo", "command"]).decode(errors="replace")
    for directory in (
        home / "Library/LaunchAgents",
        Path("/Library/LaunchAgents"),
        Path("/Library/LaunchDaemons"),
    ):
        for entry in directory.glob("*.plist"):
            with entry.open("rb") as stream:
                references += "\n" + "\n".join(strings(plistlib.load(stream)))
    cron = subprocess.run(["crontab", "-l"], capture_output=True, check=False)
    if cron.returncode and not (
        cron.returncode == 1 and b"no crontab for" in cron.stderr
    ):
        raise RuntimeError("cannot inspect user crontab")
    references += "\n" + cron.stdout.decode(errors="replace")
    return paths, references


class Activity:
    def __init__(self, home, min_age):
        self.home = home
        self.min_age = min_age
        self.lock = threading.Lock()
        self.checked = 0
        self.paths = set()
        self.references = ""

    def __call__(self, path):
        # Share the expensive OS scan; read transactional T3 state on every check.
        with self.lock:
            protected, referenced = t3_paths(self.home)
            if time.monotonic() - self.checked > 5:
                self.paths, self.references = process_paths(self.home)
                self.checked = time.monotonic()
            if (
                any(inside(p, path) for p in protected | self.paths)
                or str(path) in self.references
            ):
                return (
                    "active thread, project, process, or service references this path"
                )
        created = getattr(path.stat(), "st_birthtime", path.stat().st_mtime)
        if (
            not any(inside(p, path) for p in referenced)
            and time.time() - created < self.min_age
        ):
            return "recent unreferenced workspace or backup"
        return None


def delete_tree(root):
    if root.is_symlink() or root.resolve() != root:
        raise RuntimeError("refusing symlink deletion root")

    def retry(function, name, error):
        if not isinstance(error, PermissionError):
            raise error
        path = Path(name)
        for directory in (path.parent, path):
            if (
                directory.is_relative_to(root)
                and not directory.is_symlink()
                and directory.is_dir()
            ):
                info = directory.stat()
                if info.st_uid != os.getuid():
                    raise error
                directory.chmod(info.st_mode | stat.S_IRWXU)
        if function in (os.open, os.scandir):
            shutil.rmtree(path, onexc=retry)
        else:
            function(name)

    shutil.rmtree(root, onexc=retry)


def generated(relative, extra):
    return any(part in GENERATED for part in relative.parts) or any(
        relative == p or relative.is_relative_to(p)
        for p in map(Path, (*extra, ".flox/cache"))
    )


def retained(path, head, branch):
    if (
        branch.startswith("refs/heads/")
        and git(path, "rev-parse", "--verify", branch).decode().strip() == head
    ):
        return True
    return bool(
        git(
            path,
            "for-each-ref",
            "--format=%(refname)",
            "--contains=" + head,
            "refs/heads",
            "refs/remotes",
        ).strip()
    )


def inspect(candidate, extra):
    path = candidate.path
    if not safe(path, candidate.scope) or not (path / ".git").is_file():
        raise Keep("not a canonical linked Git worktree")
    if candidate.primary is None:
        raise Keep("not registered with a verified primary repository")
    try:
        primary, locked = metadata(path)
    except (OSError, RuntimeError) as error:
        raise Keep("broken or ambiguous Git metadata: " + str(error)) from error
    if primary != candidate.primary or primary == path or primary.is_relative_to(path):
        raise Keep("no verified independent primary repository")
    if locked or candidate.locked:
        raise Keep("Git worktree is locked")
    status = git(
        path,
        "status",
        "--porcelain=v1",
        "-z",
        "--ignored=matching",
        "--untracked-files=normal",
    )
    entries = [entry for entry in status.split(b"\0") if entry]
    dirty = any(not entry.startswith(b"!! ") for entry in entries)
    unknown = False
    caches = set()
    for entry in entries:
        if not entry.startswith(b"!! "):
            continue
        if not entry.endswith(b"/"):
            unknown = True
            continue
        relative = Path(os.fsdecode(entry[3:]).rstrip("/"))
        target = path / relative
        if (
            not generated(relative, extra)
            or not target.is_dir()
            or not safe(target, path)
        ):
            unknown = True
        elif "__pycache__" not in relative.parts:
            caches.add(relative)
    for name in ROOT_CACHES | set(extra):
        relative = Path(name)
        target = path / relative
        if not target.is_dir() or not safe(target, path):
            continue
        check = subprocess.run(
            ["git", "-C", str(path), "check-ignore", "-q", "--", name],
            capture_output=True,
            check=False,
        )
        if check.returncode not in (0, 1) or check.stderr:
            raise RuntimeError("cannot verify ignored cache")
        if check.returncode == 0:
            caches.add(relative)
    verified = set()
    for relative in sorted(caches, key=lambda p: (len(p.parts), str(p))):
        if any(parent in verified for parent in relative.parents):
            continue
        if any(
            (parent / ".git").exists()
            for parent in (path / relative, *(path / relative).parents)
            if parent != path and parent.is_relative_to(path)
        ):
            raise Keep("generated directory contains a nested repository boundary")
        verified.add(relative)
    verified = sorted(verified)
    if verified and git(
        path, "--literal-pathspecs", "ls-files", "-z", "--", *map(str, verified)
    ):
        raise Keep("generated directory contains tracked files")
    head, branch = (
        git(path, "rev-parse", "HEAD", "--symbolic-full-name", "HEAD")
        .decode()
        .splitlines()
    )
    reason = (
        "uncommitted or untracked files"
        if dirty
        else (
            "ignored files may contain local data"
            if unknown
            else (
                "HEAD has no retaining branch"
                if not retained(path, head, branch)
                else None
            )
        )
    )
    return reason, verified, head, branch


def process(candidate, protected, apply, extra):
    row = {"path": str(candidate.path), "outcome": "kept", "trimmed": []}
    if STOP.is_set():
        row["reason"] = "interrupted before inspection"
        return row
    try:
        reason = protected(candidate.path)
        if reason:
            row["reason"] = reason
            return row
        reason, caches, head, branch = inspect(candidate, extra)
        row.update(
            reason=reason or "inactive, clean, and commits retained by Git refs",
            head=head,
            branch=branch,
        )
        action = "trim" if reason and caches else "remove" if not reason else None
        if not action:
            return row
        if not apply:
            row.update(outcome="would-" + action, trimmed=list(map(str, caches)))
            return row
        if STOP.is_set():
            row["reason"] = "interrupted before mutation"
            return row
        fresh = protected(candidate.path)
        if fresh:
            row["reason"] = fresh
            return row
        # Recheck source and cache ownership after activity checks, before deletion.
        reason2, caches2, head2, branch2 = inspect(candidate, extra)
        if (reason, caches, head, branch) != (reason2, caches2, head2, branch2):
            raise RuntimeError("worktree changed during inspection")
        for relative in caches:
            delete_tree(candidate.path / relative)
            row["trimmed"].append(str(relative))
        if action == "remove":
            git(candidate.primary, "worktree", "remove", "--", str(candidate.path))
            if candidate.path.exists():
                raise RuntimeError("worktree directory remains")
            if not retained(candidate.primary, head, branch):
                raise RuntimeError("retaining Git ref disappeared during cleanup")
            row["outcome"] = "removed"
        else:
            row["outcome"] = "trimmed"
    except Keep as error:
        row["reason"] = str(error)
    except (
        OSError,
        RuntimeError,
        subprocess.SubprocessError,
        ValueError,
        sqlite3.Error,
        KeyError,
        TypeError,
    ) as error:
        row.update(outcome="error", reason=str(error))
    return row


def recover(path, protected, apply, min_age):
    row = {"path": str(path), "outcome": "kept"}
    if STOP.is_set():
        row["reason"] = "interrupted before inspection"
        return row
    try:
        if not safe(path, path.parent) or not path.is_dir():
            row["reason"] = "not a canonical backup directory"
            return row
        if time.time() - path.stat().st_mtime < min_age:
            row["reason"] = "recent recovery backup"
            return row
        reason = protected(path)
        if reason:
            row["reason"] = reason
        elif not apply:
            row["outcome"] = "would-remove-backup"
        elif not STOP.is_set():
            delete_tree(path)
            row["outcome"] = "removed-backup"
    except (
        OSError,
        RuntimeError,
        subprocess.SubprocessError,
        ValueError,
        sqlite3.Error,
        KeyError,
        TypeError,
    ) as error:
        row.update(outcome="error", reason=str(error))
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply", action="store_true", help="perform cleanup; default is read-only"
    )
    parser.add_argument(
        "--only", choices=("worktrees", "recovery", "all"), default="worktrees"
    )
    parser.add_argument(
        "--repo",
        type=Path,
        action="append",
        default=[],
        help="restrict worktrees to this primary repo (repeatable)",
    )
    parser.add_argument(
        "--generated",
        action="append",
        default=[],
        help="additional disposable ignored directory; requires exactly one --repo",
    )
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument(
        "--min-age-hours",
        type=float,
        default=1,
        help="retain recent unreferenced workspaces and backups",
    )
    args = parser.parse_args()
    if not 1 <= args.workers <= 16 or args.min_age_hours < 0:
        parser.error("workers must be 1–16 and minimum age nonnegative")
    if args.generated and len(args.repo) != 1:
        parser.error("--generated requires exactly one --repo")
    for name in args.generated:
        path = Path(name)
        if (
            path.is_absolute()
            or not path.parts
            or ".." in path.parts
            or ".git" in path.parts
        ):
            parser.error(
                "generated paths must be relative directories without .. or .git"
            )
    home = Path.home().resolve()
    repos = [p.expanduser().resolve(strict=True) for p in args.repo]
    activity = Activity(home, args.min_age_hours * 3600)
    # Fail before scheduling mutations if any required activity source is unavailable.
    t3_paths(home)
    activity.paths, activity.references = process_paths(home)
    activity.checked = time.monotonic()
    candidates = discover(home, repos) if args.only != "recovery" else []
    backups = children(home / ".t3/recovery") if args.only != "worktrees" else []
    directory = Path(tempfile.mkdtemp(prefix="clean-worktrees-"))
    report = directory / "report.json"
    started = time.monotonic()
    before = os.statvfs(home)
    data = {
        "apply": args.apply,
        "startedAt": time.time(),
        "freeBytesBefore": before.f_bavail * before.f_frsize,
        "results": [],
    }

    def save():
        temporary = report.with_suffix(".tmp")
        temporary.write_text(json.dumps(data, indent=2) + "\n")
        temporary.replace(report)

    def interrupt(signum, frame):
        STOP.set()
        print("Stopping new cleanup actions; waiting for in-flight work…", flush=True)

    signal.signal(signal.SIGINT, interrupt)
    save()
    print(
        f"Inspecting {len(candidates)} worktrees and {len(backups)} backups; report: {report}",
        flush=True,
    )
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = [
            pool.submit(process, candidate, activity, args.apply, tuple(args.generated))
            for candidate in candidates
        ]
        jobs += [
            pool.submit(recover, path, activity, args.apply, args.min_age_hours * 3600)
            for path in backups
        ]
        for future in as_completed(jobs):
            row = future.result()
            data["results"].append(row)
            save()
            print(row["outcome"], row["path"], row.get("reason", ""), flush=True)
    after = os.statvfs(home)
    data.update(
        freeBytesAfter=after.f_bavail * after.f_frsize,
        elapsedSeconds=round(time.monotonic() - started, 2),
        interrupted=STOP.is_set(),
    )
    data["netFreeBytes"] = data["freeBytesAfter"] - data["freeBytesBefore"]
    data["counts"] = dict(Counter(row["outcome"] for row in data["results"]))
    save()
    print(
        json.dumps(
            {key: value for key, value in data.items() if key != "results"}, indent=2
        )
    )
    return 1 if STOP.is_set() or data["counts"].get("error") else 0


if __name__ == "__main__":
    raise SystemExit(main())
