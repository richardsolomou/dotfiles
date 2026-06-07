#!/bin/bash
# Team configuration for the rs-sprint-planning skill.
#
# Every value can be overridden by exporting the matching environment variable
# before invoking the skill, or by editing the defaults below. Scripts source
# this file; the SKILL.md inline commands source it too.
#
# Defaults target the AI Gateway team. To run the update for another team,
# export the variables before invoking, e.g.:
#
#   export SPRINT_TEAM_SLUG="team-ai-observability"
#   export SPRINT_TEAM_NAME="AI Observability"
#   export SPRINT_PROJECT_NUMBER="123"
#   export SPRINT_GOALS_URL="https://posthog.com/teams/ai-observability#goals"
#   export SPRINT_COMMENT_HEADER="# Team AI Observability"

# GitHub org that owns the team, project board, and repositories.
SPRINT_ORG="${SPRINT_ORG:-PostHog}"

# Repository holding the sprint issues and where the update is posted.
SPRINT_REPO="${SPRINT_REPO:-PostHog/posthog}"

# GitHub team slug under SPRINT_ORG (used for the members API).
SPRINT_TEAM_SLUG="${SPRINT_TEAM_SLUG:-team-ai-gateway}"

# Human-readable team name used in prose and prompts.
SPRINT_TEAM_NAME="${SPRINT_TEAM_NAME:-AI Gateway}"

# Project board number under SPRINT_ORG. Leave empty until the team creates a
# board: board-dependent steps (plan items, archive, goals) then skip cleanly
# and the plan is built from in-flight work and user input instead.
SPRINT_PROJECT_NUMBER="${SPRINT_PROJECT_NUMBER:-}"

# Goals page link included in the update (leave empty to omit).
SPRINT_GOALS_URL="${SPRINT_GOALS_URL:-https://posthog.com/teams/ai-gateway#goals}"

# Markdown heading that identifies this team's sprint comment. Matched as a
# whole line, so "# Team AI Gateway" will not collide with another team's
# heading.
SPRINT_COMMENT_HEADER="${SPRINT_COMMENT_HEADER:-# Team AI Gateway}"

# Space-separated GitHub handles used only if the members API call fails.
# Leave empty to fall back to asking the user.
SPRINT_FALLBACK_MEMBERS="${SPRINT_FALLBACK_MEMBERS:-richardsolomou brandonleung}"
