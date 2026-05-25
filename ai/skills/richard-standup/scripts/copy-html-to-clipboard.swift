#!/usr/bin/env swift
// Copies HTML content from stdin to clipboard as rich text.
// Links inside list items break Slack's list rendering when using <a> tags,
// so we use [text](url) markdown-style syntax instead. The script parses
// HTML first (for list/bold formatting), then converts [text](url) markers
// into proper NSAttributedString link attributes.
//
// Usage: swift copy-html-to-clipboard.swift <<'EOF'
// <ul><li>Some item ([link text](https://example.com))</li></ul>
// EOF

import AppKit
import Foundation

let htmlContent = FileHandle.standardInput.readDataToEndOfFile()
guard let htmlString = String(data: htmlContent, encoding: .utf8), !htmlString.isEmpty else {
    fputs("Error: No HTML content provided on stdin\n", stderr)
    exit(1)
}

guard let data = htmlString.data(using: .utf8),
      let attributed = try? NSMutableAttributedString(
          data: data,
          options: [
              .documentType: NSAttributedString.DocumentType.html,
              .characterEncoding: String.Encoding.utf8.rawValue,
          ],
          documentAttributes: nil
      )
else {
    fputs("Error: Failed to parse HTML content\n", stderr)
    exit(1)
}

// Find [text](url) patterns and replace with linked text
let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
if let regex = try? NSRegularExpression(pattern: pattern) {
    // Process matches in reverse order to preserve indices
    let fullRange = NSRange(location: 0, length: attributed.length)
    let matches = regex.matches(in: attributed.string, range: fullRange).reversed()

    for match in matches {
        guard let textRange = Range(match.range(at: 1), in: attributed.string),
              let urlRange = Range(match.range(at: 2), in: attributed.string),
              let url = URL(string: String(attributed.string[urlRange]))
        else { continue }

        let linkText = String(attributed.string[textRange])
        let replacement = NSMutableAttributedString(string: linkText)

        // Copy existing attributes from the match location
        let existingAttrs = attributed.attributes(at: match.range.location, effectiveRange: nil)
        replacement.addAttributes(existingAttrs, range: NSRange(location: 0, length: replacement.length))
        replacement.addAttribute(.link, value: url, range: NSRange(location: 0, length: replacement.length))

        attributed.replaceCharacters(in: match.range, with: replacement)
    }
}

guard let rtfData = try? attributed.data(
    from: NSRange(location: 0, length: attributed.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
) else {
    fputs("Error: Failed to generate RTF data\n", stderr)
    exit(1)
}

let plainText = attributed.string

let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setData(rtfData, forType: .rtf)
pasteboard.setString(plainText, forType: .string)

print("Copied to clipboard as rich text")
