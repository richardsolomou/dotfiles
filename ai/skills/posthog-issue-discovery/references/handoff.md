# Fix prompt

Return one concise, self-contained prompt inside a single `text` code block per confirmed defect. Use short prose with only the details needed to implement and validate the fix. Substitute verified facts into this shape; omit irrelevant fields rather than leaving placeholders.

```text
Fix ISSUE-01: <symptom-focused title> in <repository root or remote>.

Problem: <trigger or preconditions, actual behavior, and intended behavior>. <Verified cause and the execution path that establishes it, with relevant file paths and symbols>. Inspected at <commit SHA>; <relevant uncommitted differences, if any>.

Reproduce: <minimal input and steps, or a deterministic failing scenario>. Observed: <actual result>. Expected: <required outcome and the existing contract or behavior that supports it>.

Evidence: <PostHog host and project ID, application/environment filters, absolute time bounds and timezone, compact decisive results with affected population and denominator where available>. <Essential successful query or tool arguments and evidence link, if needed>. <Reproduction or code-trace result, and material measurement limitations>.

Existing work: <concise result of checking relevant issues, open and recently merged PRs, and current code, with links where relevant and check timestamp>.

Acceptance: <observable outcomes covering the failing case, relevant edge cases, and behavior that must continue to work>. <Affected sibling paths or compatibility constraints, if relevant>.

Implement and validate the fix under the repository's guidance. Choose the implementation. Use the evidence above as context; no separate discovery or diagnosis phase is needed. If the current checkout contradicts this evidence, surface the discrepancy rather than applying an obsolete fix. Do not commit, push, or create a PR unless asked.
```

Give the implementation agent the established cause and required behavior, not a suggested solution. Exclude speculative hypotheses, alternative designs, investigation assignments, and unrelated queries. Acceptance criteria describe observable results, not code structure or a particular test implementation.

Do not hide unresolved diagnosis behind the closing instruction: if another investigation is needed to determine what is broken or why, the finding is not ready for this format. The prompt must contain the decisive evidence itself; links are supporting references. Put necessary queries inside the outer block as plain text without nested fences. Do not write prompts to disk.
