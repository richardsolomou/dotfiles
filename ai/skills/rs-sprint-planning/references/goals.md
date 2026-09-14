# Goals Workflow

Steps for `/rs-sprint-planning goals`. They run independently of the main sprint planning workflow; step references such as "Step 1" and "Step 2" point at the main workflow in `SKILL.md`.

## Step G1: Fetch Team Members

Follow Step 2 (Fetch Team Members) from the main workflow.

## Step G2: Determine Current User

```bash
gh api user --jq .login
```

This user's section is highlighted in the output. If the API call fails, fall back to the output of `git config user.email` and match against team member handles.

## Step G3: Fetch Current Sprint Plan

1. Detect the current sprint using Step 1 (Detect Sprint Context) from the main workflow.

2. Fetch the team's comment from the current sprint issue:

   ```bash
   ~/.agents/skills/rs-sprint-planning/scripts/fetch-previous-comment.sh <current_number>
   ```

3. If the result is "NOT_FOUND", skip this step (no sprint plan exists yet). The output will rely solely on board data from Step G4.

4. If a comment is found, parse the **Plan** section to extract each team member's planned items. Each item may be plain text or a `[title](url)` link.

## Step G4: Fetch Board Goals

Run the helper script to fetch In Progress and Todo items with assignee data:

```bash
~/.agents/skills/rs-sprint-planning/scripts/fetch-board-goals.sh
```

This returns a JSON array of items, each with `id`, `title`, `status`, `url`, `type`, `number`, and `assignees` fields.

## Step G5: Merge and Display

Merge the sprint plan (Step G3) with the project board (Step G4) into a single view per team member.

**Merge strategy:**

1. Start from the sprint plan items as the baseline for each person.
2. For each board item, check if it matches a plan item by URL, issue/PR number, or keyword similarity in the title.
3. Matched items: use the board item's status (In Progress / Todo) and URL, preserving the plan's item description.
4. Unmatched plan items (not on the board): include as-is from the plan, without a status subheading.
5. Unmatched board items (not in the plan): append under a **"New (not in sprint plan):"** subheading.
6. If no sprint plan exists (Step G3 returned NOT_FOUND), display board items only, grouped by status as before.

**Output format:**

```markdown
## Team Goals - {SPRINT_TEAM_NAME}

[Project Board](https://github.com/orgs/{SPRINT_ORG}/projects/{SPRINT_PROJECT_NUMBER})

**--> @currentuser** (you)

**In Progress:**
- [Item from plan that's in progress on board](url)

**Todo:**
- [Item from plan that's todo on board](url)

**Other planned:**
- Item from plan not on board

**New (not in sprint plan):**
- [Board item not in plan](url) - In Progress

---

@teammate

**In Progress:**
- [Their item](url)

---

### Unassigned
- [Orphaned item](url) - In Progress
- Draft board item title - Todo
```

**Display rules:**

- Current user appears first with `**-->**` prefix and `(you)` suffix; other members alphabetical; only members with at least one item.
- Items with URLs use `[title](url)` links; DraftIssues show plain text; items with multiple assignees appear under each.
- Unassigned items at the bottom in their own section; side quests from the sprint plan under their own heading per person.
