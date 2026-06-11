---
name: rs-copy
description: "Copy the content you just generated (a prompt, draft reply, message, doc) to the macOS clipboard as rich text, so pasting into Slack, Gmail, or docs renders clean formatting with no markdown source artifacts."
disable-model-invocation: true
---

# Copy as Rich Text

Take the content you just produced and put it on the clipboard as rich text. Pasting into Slack, Gmail, docs, or any rich-text field then renders proper headings, lists, bold, and links — with no stray `>`, `#`, `*`, backticks, or leading whitespace. Plain-text fields receive the clean plain-text version automatically, so this is safe for prompts and chat inputs too.

Use this right after generating a deliverable the user wants to paste somewhere.

## How it works

The clipboard format apps read on paste is **RTF (rich text)**, not HTML or markdown. You author HTML; the bundled script converts it to RTF via `NSAttributedString` and puts **both RTF and plain text** on the pasteboard. Slack reads the RTF and renders real formatting. HTML is only the intermediate you hand to the converter — it never gets pasted anywhere.

```text
content you generated  →  (you author) HTML  →  script: HTML→RTF  →  clipboard (RTF + plain text)  →  paste ✓
```

This is the same script `rs-standup` uses to paste formatted bullets into the Slack canvas, so it's proven against Slack.

## Workflow

### Step 1: Identify the Content

Copy the **most recent deliverable you produced at the user's request** — the actual artifact (the prompt, draft reply, message, doc, snippet), not your commentary about it. Strip any framing like "Here's the draft:" or trailing "Let me know if…".

If it's genuinely ambiguous which block to copy (several candidates, or the last turn was discussion rather than a deliverable), ask the user which one — briefly — before proceeding.

### Step 2: Convert to Clean HTML

Render the content as semantic HTML, not markdown source:

- Headings → `<h1>`–`<h3>`; paragraphs → `<p>`; line breaks → `<br>`.
- Lists → `<ul>`/`<ol>` with `<li>`; nest by nesting the lists.
- Bold → `<b>` (or `<strong>`); italic → `<i>` (or `<em>`).
- Inline code → `<code>`; code blocks → `<pre><code>…</code></pre>`.
- Blockquotes → `<blockquote>` — never a literal leading `>`.
- Links → the `[text](url)` marker, **not** `<a>` tags. The script converts these markers into real links; `<a>` inside a list item breaks list rendering when pasted into Slack.

Do not emit raw markdown (`#`, `*`, `>`, leading indentation). The whole point is that the pasted result carries formatting, not source syntax.

### Step 3: Copy to Clipboard

Pipe the HTML to the bundled script via a heredoc:

```bash
swift scripts/copy-html-to-clipboard.swift <<'EOF'
<h2>Draft reply</h2>
<p>Thanks for flagging this — I dug into it and here's what I found:</p>
<ul>
<li>The retry only fires on <code>5xx</code>, so the timeout slips through.</li>
<li>Fix is in <code>client.go</code> ([see the PR](https://github.com/example/repo/pull/1)).</li>
</ul>
<blockquote>Shipping behind a flag first.</blockquote>
EOF
```

The script sets both RTF and plain text on the pasteboard and prints `Copied to clipboard as rich text`.

### Step 4: Report

Confirm it's copied as rich text (e.g. "Copied as rich text — paste anywhere"). No need to re-print the content the user just saw.

## Notes

- macOS only — relies on `swift` (AppKit `NSPasteboard`), which ships with Xcode command-line tools.
- For the links-in-lists deep dive and the `[text](url)` rationale, see the header comment in `scripts/copy-html-to-clipboard.swift`.
