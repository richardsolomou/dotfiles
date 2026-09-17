---
name: update-pr
description: "Update a pull request's title and description based on the actual changes in the PR. Uses the repo's PR template and conventional commit style titles."
---

# Update PR

Update the current branch's PR title and description to reflect the actual changes.

This skill is also the **single source of truth for how to write a PR title and body** — the title rules, the description structure, the length guidance, and the voice. Other skills that push code (`ship`, `address-pr-review`, `babysit`, `restack`) apply this skill as a sub-step instead of restating its rules. Per the global instructions, a PR's title and body must always reflect the current diff, so any push to a branch with an open PR ends with a refresh through this skill — automatically, without asking.

## Workflow

1. Resolve and pin the target PR once. Record the repository, PR number, base ref, and head SHA:

   ```sh
   repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   gh pr view --json number,title,body,baseRefName,headRefOid
   ```

2. Fetch the recorded base and PR head, verify the fetched head SHA, then read the immutable full diff:

   ```sh
   git fetch origin <baseRefName>
   git fetch origin pull/<number>/head
   test "$(git rev-parse FETCH_HEAD)" = "<headRefOid>"
   merge_base=$(git merge-base "origin/<baseRefName>" "<headRefOid>")
   git diff "$merge_base" "<headRefOid>"
   ```

3. Get the commit log for context on intent:

   ```sh
   git log --oneline "$merge_base".."<headRefOid>"
   ```

4. Check for a PR template in the repo:

   ```sh
   cat .github/pull_request_template.md 2>/dev/null
   ```

5. Write the PR title and description:

**Title rules:**

- Use conventional commit format: `<type>(<scope>): <description>`
- Keep under 72 characters
- Use lowercase description, no period at the end
- Types: the conventional commit types listed under Commit messages in the global instructions
- Scope is optional but encouraged

**Description rules:**

What good looks like for a straightforward PR. Use this density as a baseline, and expand when more context helps reviewers understand or validate the change:

```markdown
## Problem

`pytest` collection failed on master. `tools/traffic-sim/tests/__init__.py` made the directory a top-level `tests` package, shadowing the real one.

## Changes

Added `--ignore=tools/traffic-sim` to `pytest.ini`, matching the existing pattern for `tools/hogli`.

## How did you test this code?

Ran `pytest` from the repo root. Async migrations job passes locally.
```

Rules:

- Use the PR template if one exists. Fill every section. Write "N/A" for sections that don't apply. Don't add, omit, rename, or reorder sections. If no template, fall back to: Problem, Changes, How did you test this code?
- **Let the change determine the length.** A straightforward PR may need only a sentence per section; a complex PR may need several paragraphs or bullets. Include the context a reviewer needs to understand the problem, evaluate non-obvious decisions, assess risk and rollout, and reproduce the validation. Never cut useful information to hit a line or word target.
- **Don't recap the diff.** The diff is on the PR. Describe only what the diff cannot show: the why, the constraint, the alternative considered, the deferred follow-up.
- **Describe the state the PR leaves things in and the decisions made — never the journey.** No "old approach", "we pivoted", or draft-history narrative; that lives in the commits.
- **Tight vertical spacing.** One blank line between sections, none inside a bullet list, no trailing blanks or empty template sections left as gaps.
- Prefer short, direct sentences. Rewrite long sentences when that improves clarity, but do not omit useful detail to meet an arbitrary word count.
- Bullets over prose when listing more than one thing. Single sentences when listing one.
- Problem: the constraint, bug, or motivation, including impact and relevant background when they are not obvious.
- Changes: the intent, non-obvious decisions, important behavior, compatibility or rollout considerations, and explicitly deferred scope. Skip only details that are fully obvious from the title and diff.
- How did you test: name the tests added or run, manual scenarios exercised, and any validation gaps. Give enough detail for a reviewer to understand what was and was not verified.
- Claim only commands and scenarios observed in the current run or explicitly supplied by the user. Test files in the diff, commit messages, CI configuration, and an earlier PR body do not prove execution. If evidence is unavailable, ask what ran; when the workflow cannot pause, write `Not run` and state the exact validation gap.

After drafting, re-read for reviewer questions. Add missing context that affects correctness, risk, rollout, or validation; then delete only repetition, padding, and scene-setting that does not help answer those questions.

**Voice and tone (mandatory):**

Load the `tone` skill with `register: pr-description` before drafting anything. Apply that register and the common rules at the top of the doc.

No AI smell: no formulaic openers ("This PR…", "In this change…"), no closing sign-offs, no padding.

Immediately before updating, fetch the recorded PR number again and compare its `headRefOid` and `baseRefName` with the pinned values. If either moved, discard the draft and rebuild it from the new immutable target. Then update that captured repository and PR number without putting generated content in a shell command. Write the title and body to temporary files with the available file-writing tool, then build the API payload from those files:

```sh
jq -n --rawfile title /tmp/update-pr-title.txt --rawfile body /tmp/update-pr-body.md '{title: ($title | rtrimstr("\n")), body: ($body | rtrimstr("\n"))}' > /tmp/update-pr.json
gh api "repos/<captured-repo>/pulls/<captured-number>" --method PATCH --input /tmp/update-pr.json
gh pr view <captured-number> --repo <captured-repo> --json title,body | jq '{title,body}' > /tmp/update-pr-actual.json
diff -u /tmp/update-pr.json /tmp/update-pr-actual.json
```

- Do not create the temporary files with `echo`, `printf`, command interpolation, or an unquoted heredoc.
- Never substitute generated title or Markdown directly into a shell command, even inside quotes. Backticks, `$()`, quotes, and backslashes in generated content must remain data, not shell syntax.
- Do not report success unless the exact read-back comparison passes.
- Remove all four temporary files after verification.
