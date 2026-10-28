import importlib.util
import sqlite3
import subprocess
import sys
import tempfile
import time
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "clean_worktrees", Path(__file__).with_name("clean_worktrees.py")
)
clean = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = clean
spec.loader.exec_module(clean)


def git(repo, *args):
    return subprocess.check_output(
        ["git", "-C", str(repo), *args], stderr=subprocess.PIPE
    )


def fixture(root):
    repo = root / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    git(repo, "config", "user.email", "test@example.invalid")
    git(repo, "config", "user.name", "Test")
    (repo / ".gitignore").write_text("node_modules/\n.env\n.flox/\n")
    (repo / "source").write_text("keep\n")
    git(repo, "add", ".")
    git(repo, "commit", "-qm", "initial")
    path = root / ".t3/worktrees/project/test"
    path.parent.mkdir(parents=True)
    git(repo, "worktree", "add", "-qb", "test", str(path))
    return repo, path, clean.Candidate(path, repo, path.parent, False)


def run_case(change, expected, apply=True, protected=lambda path: None):
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp).resolve()
        repo, path, candidate = fixture(root)
        change(repo, path)
        row = clean.process(candidate, protected, apply, ())
        assert row["outcome"] == expected, row
        return row


def test_dry_run_preserves_worktree():
    run_case(lambda repo, path: None, "would-remove", apply=False)


def test_clean_worktree_removed_and_branch_retained():
    with tempfile.TemporaryDirectory() as temp:
        repo, path, candidate = fixture(Path(temp).resolve())
        head = git(path, "rev-parse", "HEAD")
        clean.process(candidate, lambda path: None, True, ())
        assert not path.exists()
        assert git(repo, "rev-parse", "test") == head


def test_dirty_source_retained():
    run_case(lambda repo, path: (path / "source").write_text("unique"), "kept")


def test_untracked_source_retained():
    run_case(lambda repo, path: (path / "new").write_text("unique"), "kept")


def test_unique_ignored_file_retained():
    run_case(lambda repo, path: (path / ".env").write_text("private"), "kept")


def test_clean_worktree_with_ignored_dependencies_removed():
    def change(repo, path):
        cache = path / "node_modules/package"
        cache.mkdir(parents=True)
        (cache / "file").write_text("generated")

    run_case(change, "removed")


def test_broken_metadata_retained():
    with tempfile.TemporaryDirectory() as temp:
        _repo, path, candidate = fixture(Path(temp).resolve())
        (path / ".git").write_text("gitdir: /nonexistent/worktree\n")
        row = clean.process(candidate, lambda path: None, True, ())
        assert row["outcome"] == "kept", row
        assert (path / "source").exists()


def test_active_worktree_retained():
    run_case(lambda repo, path: None, "kept", protected=lambda path: "active process")


def test_activity_rechecked_before_mutation():
    calls = []

    def protected(path):
        calls.append(path)
        return "newly active" if len(calls) > 1 else None

    run_case(lambda repo, path: None, "kept", protected=protected)


def test_locked_worktree_retained():
    run_case(lambda repo, path: git(repo, "worktree", "lock", str(path)), "kept")


def test_detached_unreferenced_commit_retained():
    def change(repo, path):
        git(path, "checkout", "--detach", "-q")
        (path / "source").write_text("unreferenced commit")
        git(path, "commit", "-qam", "unique")

    run_case(change, "kept")


def test_ignored_readonly_cache_trimmed_but_dirty_source_retained():
    def change(repo, path):
        (path / "source").write_text("unique")
        cache = path / "node_modules/package"
        cache.mkdir(parents=True)
        (cache / "file").write_text("generated")
        cache.chmod(0o500)

    with tempfile.TemporaryDirectory() as temp:
        repo, path, candidate = fixture(Path(temp).resolve())
        change(repo, path)
        row = clean.process(candidate, lambda path: None, True, ())
        assert row["outcome"] == "trimmed", row
        assert (path / "source").read_text() == "unique"
        assert not (path / "node_modules").exists()


def test_tracked_cache_not_trimmed():
    def change(repo, path):
        cache = path / "node_modules"
        cache.mkdir()
        (cache / "file").write_text("source")
        git(path, "add", "-f", "node_modules/file")

    run_case(change, "kept")


def test_symlink_cache_target_untouched():
    with tempfile.TemporaryDirectory() as temp:
        repo, path, candidate = fixture(Path(temp).resolve())
        outside = repo / "data"
        outside.mkdir()
        (outside / "unique").write_text("keep")
        (path / "node_modules").symlink_to(outside, target_is_directory=True)
        row = clean.process(candidate, lambda path: None, True, ())
        assert row["outcome"] == "kept", row
        assert (outside / "unique").read_text() == "keep"


def test_primary_repo_retained():
    with tempfile.TemporaryDirectory() as temp:
        repo, _path, candidate = fixture(Path(temp).resolve())
        candidate = clean.Candidate(repo, repo, repo.parent, False)
        row = clean.process(candidate, lambda path: None, True, ())
        assert row["outcome"] == "kept", row
        assert (repo / "source").exists()


def test_discovery_distinguishes_containers_and_standalone_repos():
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp).resolve()
        _repo, path, _candidate = fixture(root)
        standalone = root / ".t3/worktrees/standalone"
        standalone.mkdir()
        git(standalone, "init", "-q")
        (standalone / "nested").mkdir()
        candidates = clean.discover(root, [])
        assert {c.path for c in candidates} == {path, standalone}


def test_recovery_opt_in_does_not_follow_symlinks():
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp).resolve()
        outside = root / "outside"
        outside.mkdir()
        recovery = root / ".t3/recovery"
        recovery.mkdir(parents=True)
        link = recovery / "backup"
        link.symlink_to(outside, target_is_directory=True)
        row = clean.recover(link, lambda path: None, True, 0)
        assert row["outcome"] == "kept", row
        assert outside.exists()


def test_missing_t3_schema_fails_closed():
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp).resolve()
        (root / ".t3/userdata").mkdir(parents=True)
        (root / ".t3/userdata/statev2.sqlite").touch()
        try:
            clean.t3_paths(root)
        except sqlite3.Error:
            return
        raise AssertionError("unknown T3 state must stop cleanup")


def test_path_boundary_does_not_protect_sibling():
    assert not clean.inside("/work/tree-other/file", Path("/work/tree"))


def state_fixture(root):
    db = root / ".t3/userdata/statev2.sqlite"
    db.parent.mkdir(parents=True)
    connection = sqlite3.connect(db)
    connection.executescript("""
        CREATE TABLE orchestration_v2_projection_threads(thread_id,payload_json);
        CREATE TABLE projection_threads(thread_id,worktree_path,archived_at,deleted_at,settled_override,pinned_at,snoozed_until);
        CREATE TABLE orchestration_v2_projection_runs(thread_id,status);
        CREATE TABLE orchestration_v2_projection_runtime_requests(thread_id,status);
        CREATE TABLE projection_projects(workspace_root,deleted_at);
        CREATE TABLE orchestration_v2_thread_launch_workflows(worktree_path,status);
        CREATE TABLE scheduled_tasks(enabled);
    """)
    return connection


def test_t3_shared_path_protected_if_any_thread_is_open():
    import json

    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp).resolve()
        with state_fixture(root) as connection:
            for name, archived in (("done", "yesterday"), ("open", None)):
                # Historical payloads omit pinnedAt when no pin is set.
                payload = {
                    "id": name,
                    "worktreePath": "/shared",
                    "archivedAt": archived,
                    "deletedAt": None,
                    "settledOverride": None,
                    "snoozedUntil": None,
                }
                connection.execute(
                    "INSERT INTO orchestration_v2_projection_threads VALUES (?,?)",
                    (name, json.dumps(payload)),
                )
        protected, _ = clean.t3_paths(root)
        assert "/shared" in protected


def test_enabled_schedule_stops_automation():
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp).resolve()
        with state_fixture(root) as connection:
            connection.execute("INSERT INTO scheduled_tasks VALUES (1)")
        try:
            clean.t3_paths(root)
        except RuntimeError as error:
            assert "schedules" in str(error)
            return
        raise AssertionError("enabled schedules need manual inspection")


def test_process_service_and_project_paths_protected():
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp).resolve()
        workspace = root / "workspace"
        workspace.mkdir()
        activity = clean.Activity(root, 0)
        activity.checked = time.monotonic()
        for paths, references in (
            ({str(workspace / "file")}, ""),
            (set(), str(workspace / "bin/service")),
        ):
            activity.paths, activity.references = paths, references
            assert activity(workspace)


def test_cancelled_run_does_not_start_mutation():
    clean.STOP.set()
    try:
        run_case(lambda repo, path: None, "kept")
    finally:
        clean.STOP.clear()


def test_recovery_backup_removed_when_explicitly_selected():
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp).resolve()
        backup = root / ".t3/recovery/old"
        backup.mkdir(parents=True)
        (backup / "data").write_text("backup")
        row = clean.recover(backup, lambda path: None, True, 0)
        assert row["outcome"] == "removed-backup", row
        assert not backup.exists()


if __name__ == "__main__":
    for name in sorted(n for n in globals() if n.startswith("test_")):
        globals()[name]()
        print(name, "OK")
