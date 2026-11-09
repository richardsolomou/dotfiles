---
name: coding-standards
description: "Language standards and completion checks for Rust, Go, shell scripts, Markdown, and dependency changes. Use when writing or changing any of those, and before committing them."
---

# Coding Standards

## Rust

- If `cargo shear` wants to remove a dependency, use it properly or remove it. Investigate before adding ignores. Verify Cargo features enable code that exists and is used.
- If a struct derives `Deserialize` or `Serialize`, use `serde_json::from_value()` and `to_value()`. Never extract fields by hand.
- Before completing, run `cargo fmt`, `cargo clippy --all-targets --all-features -- -D warnings`, and `cargo shear`, and fix everything they report.

## Go

- Before completing, run `gofmt`, `go vet ./...`, the repo's linter (`golangci-lint run` when configured), and `go test -race ./...` on the touched packages, and fix everything they report.
- Every goroutine has an owner that can stop it: pass a `context.Context`, and make cancellation and shutdown observable in tests.
- Wrap errors with `%w` and the operation that failed. Never discard an error without a comment saying why it is safe.

## Shell

- Use plain `echo`, with no custom logging methods. When warnings and errors matter, copy the helpers from <https://github.com/PostHog/template/tree/main/bin/helpers> and source them as <https://github.com/PostHog/template/blob/main/bin/fmt> does.
- Commands for the user to paste must survive line-by-line pasting: no inline `#` comments, no variables carried over from an earlier paste, and destructive paths that fail closed (`${var:?}`).

## Markdown

- Run `markdownlint` on every file you edit and fix what it reports.
- Never add hard line breaks or wrap lines. Preserve the existing line structure.

## Dependencies

- No new dependencies for one-liners. Prefer battle-tested libraries over trendy ones.
- Write down why you added a dependency, and what replaces one you removed.
