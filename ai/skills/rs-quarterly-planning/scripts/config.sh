#!/bin/bash
# Team configuration for the rs-quarterly-planning skill.
#
# Every value can be overridden by exporting the matching environment variable
# before invoking the skill, or by editing the defaults below. Scripts source
# this file; the SKILL.md inline commands source it too.
#
# Defaults target the AI Gateway team. To run quarterly planning for another
# team, export the variables before invoking, e.g.:
#
#   export QP_TEAM_SLUG="team-ai-observability"
#   export QP_TEAM_NAME="AI Observability"
#   export QP_TEAM_PAGE_SLUG="ai-observability"
#   export QP_BLITZSCALE_REVIEWER="timgl"

# GitHub org that owns the team and repositories.
QP_ORG="${QP_ORG:-PostHog}"

# GitHub team slug under QP_ORG (used for the members API).
QP_TEAM_SLUG="${QP_TEAM_SLUG:-team-ai-gateway}"

# Human-readable team name used in prose and prompts.
QP_TEAM_NAME="${QP_TEAM_NAME:-AI Gateway}"

# Team page folder slug under contents/teams/ in the posthog.com repo. Usually
# the team slug without the "team-" prefix.
QP_TEAM_PAGE_SLUG="${QP_TEAM_PAGE_SLUG:-ai-gateway}"

# Local checkout of the posthog.com repo, where the objectives PR is created.
QP_POSTHOG_COM_DIR="${QP_POSTHOG_COM_DIR:-$HOME/dev/posthog/posthog.com}"

# Path to the team's objectives page. Derived from the repo dir and page slug;
# override only if a team's page lives somewhere non-standard.
QP_OBJECTIVES_PATH="${QP_OBJECTIVES_PATH:-$QP_POSTHOG_COM_DIR/contents/teams/$QP_TEAM_PAGE_SLUG/objectives.mdx}"

# Goals page link included in the prep doc (leave empty to omit).
QP_GOALS_URL="${QP_GOALS_URL:-https://posthog.com/teams/ai-gateway#objectives}"

# GitHub handle of the Blitzscale member who reviews the objectives PR. Leave
# empty to be prompted at PR time.
QP_BLITZSCALE_REVIEWER="${QP_BLITZSCALE_REVIEWER:-}"

# Space-separated GitHub handles used only if the members API call fails.
# Leave empty to fall back to asking the user.
QP_FALLBACK_MEMBERS="${QP_FALLBACK_MEMBERS:-richardsolomou brandonleung}"
