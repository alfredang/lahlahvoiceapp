import Foundation

/// Sends spoken edits to LahLah Video, the course video editor, through its `lahlahvideo://` link.
///
/// Words go to LahLah Video instead of being typed when either:
/// - LahLah Video is the app in front, or
/// - the sentence starts with "Video," or "LahLah Video" (so it works from any app).
///
/// LahLah Video parses the command itself ("split here", "add crossfade", "export for TikTok").
public enum LahLahVideoCommands {
    public static let bundleID = "com.tertiaryinfotech.lahlahvideo"

    /// "LahLah Video" in the ways speech recognition tends to write it, with or without a comma.
    private static let appWake = #"^(?i)\s*(?:hey\s+|ok(?:ay)?\s+)?(?:lah\s*-?\s*lah|la\s*-?\s*la|lala)\s+video\b[\s,.:;!-]*"#
    /// A bare "Video" needs a comma or colon after it, so "Video calls are…" is still typed.
    private static let shortWake = #"^(?i)\s*video\s*[,:;]\s*"#

    /// The command for LahLah Video, or nil when the words should be typed as usual.
    public static func command(from raw: String, frontmostBundleID: String?) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        for pattern in [appWake, shortWake] {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return clean(String(text[range.upperBound...]))
            }
        }
        if frontmostBundleID == bundleID { return clean(text) }
        return nil
    }

    /// `lahlahvideo://command?text=…`
    public static func url(for command: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "lahlahvideo"
        parts.host = "command"
        parts.queryItems = [URLQueryItem(name: "text", value: command)]
        return parts.url
    }

    private static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return trimmed.isEmpty ? nil : trimmed
    }
}
