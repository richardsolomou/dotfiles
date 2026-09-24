"""Find open PostHog bot PRs requested from or owned by a team."""

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

PULL_REQUESTS_QUERY = """
query($owner: String!, $repo: String!, $cursor: String) {
  repository(owner: $owner, name: $repo) {
    pullRequests(states: OPEN, first: 50, after: $cursor, orderBy: {field: CREATED_AT, direction: DESC}) {
      totalCount
      pageInfo { hasNextPage endCursor }
      nodes {
        number url title isDraft headRefName headRefOid
        author { __typename login }
        reviewRequests(first: 100) {
          pageInfo { hasNextPage }
          nodes { requestedReviewer { __typename ... on Team { slug } } }
        }
        files(first: 100) {
          pageInfo { hasNextPage endCursor }
          nodes { path }
        }
      }
    }
  }
}
"""

MORE_FILES_QUERY = """
query($owner: String!, $repo: String!, $number: Int!, $cursor: String!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      files(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes { path }
      }
    }
  }
}
"""


def graphql(query: str, variables: dict[str, Any]) -> dict[str, Any]:
    payload = json.dumps({"query": query, "variables": variables})
    result = subprocess.run(
        ["gh", "api", "graphql", "--input", "-"],
        input=payload,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "GitHub GraphQL request failed")
    data = json.loads(result.stdout)
    if data.get("errors"):
        raise RuntimeError(json.dumps(data["errors"]))
    return data["data"]["repository"]


def all_files(pr: dict[str, Any], owner: str, repo: str) -> list[str]:
    connection = pr["files"]
    paths = [node["path"] for node in connection["nodes"]]
    while connection["pageInfo"]["hasNextPage"]:
        response = graphql(
            MORE_FILES_QUERY,
            {
                "owner": owner,
                "repo": repo,
                "number": pr["number"],
                "cursor": connection["pageInfo"]["endCursor"],
            },
        )
        connection = response["pullRequest"]["files"]
        paths.extend(node["path"] for node in connection["nodes"])
    return paths


def resolve_owners(paths: set[str]) -> dict[str, Any]:
    if not paths:
        return {}
    result = subprocess.run(
        ["hogli", "owners:resolve", "--json"],
        input="\n".join(sorted(paths)) + "\n",
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "hogli owners:resolve failed")
    return json.loads(result.stdout)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="PostHog/posthog")
    parser.add_argument("--team", default="team-context-mcp")
    parser.add_argument(
        "--max-pages", type=int, help="Limit discovery for a read-only probe"
    )
    args = parser.parse_args()

    if not Path("owners.yaml").is_file() or not Path(".codex/with-flox").is_file():
        parser.error("run from the PostHog repository root through .codex/with-flox")
    owner, separator, repo = args.repo.partition("/")
    if not separator or not owner or not repo:
        parser.error("--repo must be OWNER/REPO")
    if args.max_pages is not None and args.max_pages < 1:
        parser.error("--max-pages must be positive")

    bot_prs: list[dict[str, Any]] = []
    cursor = None
    pages = 0
    total = 0
    while True:
        response = graphql(
            PULL_REQUESTS_QUERY, {"owner": owner, "repo": repo, "cursor": cursor}
        )
        connection = response["pullRequests"]
        total = connection["totalCount"]
        pages += 1
        for pr in connection["nodes"]:
            if pr["author"] != {"__typename": "Bot", "login": "posthog"}:
                continue
            if pr["reviewRequests"]["pageInfo"]["hasNextPage"]:
                raise RuntimeError(
                    f"PR #{pr['number']} has more than 100 review requests"
                )
            pr["paths"] = all_files(pr, owner, repo)
            bot_prs.append(pr)
        page = connection["pageInfo"]
        if not page["hasNextPage"] or (
            args.max_pages is not None and pages >= args.max_pages
        ):
            complete = not page["hasNextPage"]
            break
        cursor = page["endCursor"]

    resolved = resolve_owners({path for pr in bot_prs for path in pr["paths"]})
    matches = []
    for pr in bot_prs:
        requested_teams = [
            reviewer["requestedReviewer"]["slug"]
            for reviewer in pr["reviewRequests"]["nodes"]
            if reviewer["requestedReviewer"]
            and reviewer["requestedReviewer"]["__typename"] == "Team"
        ]
        owned_paths = [
            path
            for path in pr["paths"]
            if args.team in (resolved.get(path) or {}).get("owners", [])
        ]
        if args.team not in requested_teams and not owned_paths:
            continue
        matches.append(
            {
                "number": pr["number"],
                "url": pr["url"],
                "title": pr["title"],
                "draft": pr["isDraft"],
                "head_ref": pr["headRefName"],
                "head_sha": pr["headRefOid"],
                "requested_teams": requested_teams,
                "owned_paths": owned_paths,
            }
        )

    sys.stdout.write(
        json.dumps(
            {
                "repo": args.repo,
                "team": args.team,
                "open_prs": total,
                "bot_prs_scanned": len(bot_prs),
                "complete": complete,
                "matches": matches,
            }
        )
        + "\n"
    )


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, RuntimeError) as error:
        sys.stderr.write(f"find-prs: {error}\n")
        raise SystemExit(1) from error
