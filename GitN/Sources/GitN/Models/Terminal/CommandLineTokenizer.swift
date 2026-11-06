import Foundation

/// Splits a shell command line into tokens with awareness of quoting and
/// escaping, and locates the token under the cursor for completion.
///
/// Per SPEC §7.2, this must not split on whitespace naïvely: it handles single
/// quotes, double quotes, backslash escapes, and reports the active token plus
/// the exact replacement range so a suggestion replaces only that token.
enum CommandLineTokenizer {
    struct Token: Equatable {
        /// The literal text as typed (including quotes).
        let raw: String
        /// The unquoted/unescaped value.
        let value: String
        /// Range in the original string (by Character offset).
        let start: Int
        let end: Int
        /// True when the token is inside an unterminated quote.
        let isOpenQuoted: Bool
        /// The quote character in effect (" or ' or nil).
        let quote: Character?
    }

    struct Analysis: Equatable {
        let tokens: [Token]
        /// Index into `tokens` of the token the cursor sits in/at the end of,
        /// or nil when the cursor is in whitespace starting a new token.
        let activeTokenIndex: Int?
        /// The command word (first token's value), if any.
        let commandWord: String?
        /// Zero-based position of the active token among command arguments
        /// (0 = command itself, 1 = first arg, ...).
        let activeArgumentPosition: Int?
    }

    /// Tokenize up to `cursor` (Character offset). Only the current command is
    /// considered: anything before an unquoted `|`, `;`, `&&`, `||` is dropped so
    /// suggestions apply to the command being typed, not an earlier one.
    static func analyze(_ line: String, cursor: Int) -> Analysis {
        let chars = Array(line)
        let clampedCursor = max(0, min(cursor, chars.count))

        // Find the start of the current command (after the last unquoted
        // separator before the cursor).
        let commandStart = currentCommandStart(chars, upTo: clampedCursor)

        var tokens: [Token] = []
        var i = commandStart
        var activeTokenIndex: Int? = nil

        while i < clampedCursor {
            // Skip whitespace between tokens.
            while i < clampedCursor, chars[i] == " " || chars[i] == "\t" { i += 1 }
            if i >= clampedCursor { break }

            let tokenStart = i
            var raw = ""
            var value = ""
            var quote: Character? = nil
            var isOpenQuoted = false

            while i < clampedCursor {
                let c = chars[i]
                if let q = quote {
                    if c == q {
                        quote = nil
                        raw.append(c)
                        i += 1
                    } else if c == "\\", q == "\"", i + 1 < clampedCursor {
                        raw.append(c)
                        raw.append(chars[i + 1])
                        value.append(chars[i + 1])
                        i += 2
                    } else {
                        raw.append(c)
                        value.append(c)
                        i += 1
                    }
                } else if c == " " || c == "\t" {
                    break
                } else if c == "\"" || c == "'" {
                    quote = c
                    raw.append(c)
                    i += 1
                } else if c == "\\", i + 1 < clampedCursor {
                    raw.append(c)
                    raw.append(chars[i + 1])
                    value.append(chars[i + 1])
                    i += 2
                } else {
                    raw.append(c)
                    value.append(c)
                    i += 1
                }
            }
            if quote != nil { isOpenQuoted = true }

            let token = Token(
                raw: raw,
                value: value,
                start: tokenStart,
                end: i,
                isOpenQuoted: isOpenQuoted,
                quote: quote
            )
            tokens.append(token)

            // The cursor is in/at the end of this token when it ends exactly at
            // the cursor and the cursor is not preceded by whitespace.
            if i == clampedCursor {
                activeTokenIndex = tokens.count - 1
            }
        }

        // If the cursor sits right after whitespace, we're starting a new token.
        if clampedCursor > commandStart,
           clampedCursor <= chars.count,
           clampedCursor > 0,
           (chars[clampedCursor - 1] == " " || chars[clampedCursor - 1] == "\t") {
            activeTokenIndex = nil
        }

        let commandWord = tokens.first?.value
        let activeArgumentPosition: Int? = {
            guard let idx = activeTokenIndex else {
                return tokens.isEmpty ? 0 : tokens.count
            }
            return idx
        }()

        return Analysis(
            tokens: tokens,
            activeTokenIndex: activeTokenIndex,
            commandWord: commandWord,
            activeArgumentPosition: activeArgumentPosition
        )
    }

    /// Index of the first character of the current command segment, i.e. just
    /// after the last unquoted pipe/semicolon/&&/|| before the cursor.
    private static func currentCommandStart(_ chars: [Character], upTo cursor: Int) -> Int {
        var start = 0
        var quote: Character? = nil
        var i = 0
        while i < cursor {
            let c = chars[i]
            if let q = quote {
                if c == q { quote = nil }
                i += 1
                continue
            }
            if c == "\"" || c == "'" {
                quote = c
                i += 1
                continue
            }
            if c == "|" || c == ";" || c == "&" {
                // Any of | || ; & && resets the command segment.
                i += 1
                // Skip a second operator char (|| or &&).
                if i < cursor, chars[i] == c { i += 1 }
                start = i
                continue
            }
            i += 1
        }
        return start
    }
}
