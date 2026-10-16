# Report format

The user is reading the report now and will pick what to fix next, so write for a person scanning a ranked list. Do not write standalone prompts for other agents. Substitute verified facts; omit fields that do not apply rather than leaving placeholders.

## Shape

Open with two lines. First: project name and ID, host, the absolute UTC windows, and how many defects are fix-ready and how many are verified only. Second: what PostHog had already surfaced, as counts of inbox reports by status, open health issues, and scout emissions in the window.

Then a ranked summary table:

```markdown
| # | Defect | Where | Impact | Cause |
| --- | --- | --- | --- | --- |
| 1 | <symptom-focused title> | <surface>, <application or service> | <affected count of denominator, window> | `<path>:<line>` or not traced |
```

Then one section per defect, in the same order:

```markdown
### 1. <symptom-focused title>

**What happens:** <trigger or preconditions, actual behavior, intended behavior, and who is affected>.

**Evidence:** <absolute bounds and timezone, application and environment filters, decisive results with denominators, PostHog links>. <Measurement limitations that matter.>

**Cause:** <repository and inspected ref; the execution path that produces the failure, with `path:line` references; the reproduction or deterministic trace>. For a verified-only defect: <what is established, and the single step that would trace it>.

**Existing work:** <inbox report state, error-tracking issue status and assignee, related GitHub issues and PRs, or "none found">.
```

Include a query only when it is decisive and a link would not reproduce it, as a `sql` block inside the section. Describe the required behavior, not an implementation; the fix is designed when the user picks the defect.

## Coverage

Close the findings with a compact coverage table, one row per surface: the tool or query that checked it, the window, and the result, or why it had no live data, was skipped, or was incomplete. Below it, give each significant rejected lead and each existing inbox report a one-line disposition: rejected with evidence, known noise, fixed on main with the deploy confirmed or unconfirmed, duplicate of active work, or blocked with the missing access or unresolved question.

## Next step

End by asking which defects to fix. Once the user picks, fix them in this conversation under the owning repository's guidance, starting from the cause above rather than repeating discovery; if the checkout now contradicts the evidence, say so before changing code. If the user asks to hand a defect to another agent or thread instead, write it a self-contained brief that repeats the project, bounds, evidence, cause, and expected behavior, since that agent cannot see this conversation.

Keep personal information out: prefer aggregates to event samples, and do not name individual users or distinct IDs unless the user asks.
