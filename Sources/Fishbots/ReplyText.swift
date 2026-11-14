#if canImport(AppKit)
import AppKit
typealias ReplyFont = NSFont
typealias ReplyColor = NSColor
#else
import UIKit
typealias ReplyFont = UIFont
typealias ReplyColor = UIColor
#endif

/// An agent's reply laid out for reading on the card: headings stand out in the fish's color, lists hang, bold and
/// code keep their weight, code blocks and tables stay apart. It reads the reply's markdown when the app has it;
/// from text already stripped of it, it still finds the lists and guesses the headings. The same on the Mac's card and
/// the iPhone's.
enum ReplyText {
    static func attributed(_ source: String, markdown: Bool, tint: ReplyColor, size: CGFloat = 13) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = ReplyColor(white: 1, alpha: 0.88)
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        func style(spacing: CGFloat = 5, before: CGFloat = 0, indent: CGFloat = 0, hang: CGFloat = 0) -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = 3
            p.paragraphSpacing = spacing
            p.paragraphSpacingBefore = before
            p.firstLineHeadIndent = indent
            p.headIndent = indent + hang
            return p
        }
        func add(_ s: NSAttributedString, _ p: NSParagraphStyle) {
            let line = NSMutableAttributedString(attributedString: s)
            line.append(NSAttributedString(string: "\n"))
            line.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: line.length))
            out.append(line)
        }
        func plain(_ s: String, _ font: ReplyFont, _ color: ReplyColor) -> NSAttributedString {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        }

        var inCode = false
        var blankBefore = true
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if markdown, line.hasPrefix("```") { inCode.toggle(); blankBefore = false; continue }
            if inCode {
                add(plain(raw, .monospacedSystemFont(ofSize: size - 1.5, weight: .regular), ReplyColor(white: 1, alpha: 0.72)), style(spacing: 1, indent: 10))
                continue
            }
            if line.isEmpty { blankBefore = true; continue }
            defer { blankBefore = false }
            let gap: CGFloat = blankBefore && out.length > 0 ? 7 : 0

            // a heading: "## …" in markdown; in plain text, a short line on its own that doesn't end a sentence
            var heading: String?
            if markdown, line.hasPrefix("#") {
                heading = String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            } else if !markdown, blankBefore, line.count < 64, !line.hasPrefix("•"), let last = line.last, !".!?:;,…)".contains(last),
                      i + 1 < lines.count, !lines[i + 1].trimmingCharacters(in: .whitespaces).isEmpty {
                heading = line
            }
            if let h = heading {
                add(inline(h, markdown: markdown, font: roundedFont(size + 1, .semibold), color: tint, tint: tint, size: size), style(spacing: 4, before: out.length > 0 ? 12 : 0))
                continue
            }
            // a table: its cells side by side (the separator row says nothing)
            if markdown, line.hasPrefix("|") {
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { continue }
                add(inline(cells.joined(separator: "   ·   "), markdown: true, font: .systemFont(ofSize: size - 0.5), color: body, tint: tint, size: size),
                    style(spacing: 3, before: gap, indent: 10))
                continue
            }
            // a list item: the mark hangs, the text lines up under itself
            var item: String?
            for mark in ["• ", "- ", "* ", "+ "] where line.hasPrefix(mark) && (markdown || mark == "• ") { item = String(line.dropFirst(mark.count)) }
            if item == nil, markdown, let dot = line.firstIndex(of: "."), line[..<dot].count <= 2, Int(line[..<dot]) != nil,
               line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " {
                let s = NSMutableAttributedString(attributedString: plain(String(line[...dot]) + "  ", .monospacedDigitSystemFont(ofSize: size, weight: .medium), tint))
                s.append(inline(String(line[line.index(dot, offsetBy: 2)...]), markdown: true, font: .systemFont(ofSize: size), color: body, tint: tint, size: size))
                add(s, style(spacing: 4, before: gap, indent: 4, hang: 20))
                continue
            }
            if let item {
                let depth = CGFloat(raw.prefix { $0 == " " }.count / 2) * 12
                let s = NSMutableAttributedString(attributedString: plain("•  ", .systemFont(ofSize: size, weight: .bold), tint))
                s.append(inline(item, markdown: markdown, font: .systemFont(ofSize: size), color: body, tint: tint, size: size, lead: !markdown))
                add(s, style(spacing: 4, before: gap, indent: 4 + depth, hang: 13))
                continue
            }
            add(inline(line, markdown: markdown, font: .systemFont(ofSize: size), color: body, tint: tint, size: size), style(before: gap))
        }
        // no empty line at the end
        if out.length > 0 { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        return out
    }

    /// The end of a reply in markdown, for the card's excerpt: its last lines (up to `lines` with text and about
    /// `chars` characters), keeping the empty lines between them (they say where a heading or a paragraph starts)
    /// and never starting in the middle of a code block. `cut`: there was more before.
    static func ending(of markdown: String, chars: Int, lines maxLines: Int) -> (text: String, cut: Bool) {
        let all = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var taken: [String] = []
        var total = 0, withText = 0
        for l in all.reversed() {
            let empty = l.trimmingCharacters(in: .whitespaces).isEmpty
            if !empty && (withText >= maxLines || total + l.count > chars) {
                if withText == 0 { taken.insert("…" + String(l.suffix(chars)), at: 0) }       // one huge line: its end
                break
            }
            taken.insert(l, at: 0)
            if !empty { withText += 1; total += l.count }
        }
        while let first = taken.first, first.trimmingCharacters(in: .whitespaces).isEmpty { taken.removeFirst() }
        // an odd number of fences: the excerpt starts inside a code block
        if taken.filter({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }).count % 2 == 1 { taken.insert("```", at: 0) }
        return (taken.joined(separator: "\n"), taken.count < all.count)
    }

    /// Bold, code and links inside a line. `lead`: in plain text, a list item's label ("Name: the rest") is bold.
    private static func inline(_ s: String, markdown: Bool, font: ReplyFont, color: ReplyColor, tint: ReplyColor, size: CGFloat, lead: Bool = false) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let bold = boldFont(font)
        guard markdown else {
            let out = NSMutableAttributedString(string: s, attributes: base)
            if lead, let colon = s.firstIndex(of: ":"), s[..<colon].count <= 40, !s[..<colon].contains(".") {
                out.addAttributes([.font: bold, .foregroundColor: ReplyColor.white], range: NSRange(s.startIndex...colon, in: s))
            }
            return out
        }
        let out = NSMutableAttributedString()
        var text = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        while !text.isEmpty {
            // the nearest of ** … ** and ` … `
            let b = text.range(of: "**"), c = text.range(of: "`")
            let next = [b, c].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
            guard let open = next else { out.append(NSAttributedString(string: text, attributes: base)); break }
            let mark = String(text[open])
            guard let close = text.range(of: mark, range: open.upperBound..<text.endIndex) else {
                out.append(NSAttributedString(string: text.replacingOccurrences(of: mark, with: ""), attributes: base)); break
            }
            out.append(NSAttributedString(string: String(text[..<open.lowerBound]), attributes: base))
            let inner = String(text[open.upperBound..<close.lowerBound])
            if mark == "`" {
                out.append(NSAttributedString(string: inner, attributes: [
                    .font: ReplyFont.monospacedSystemFont(ofSize: size - 1, weight: .regular),
                    .foregroundColor: mix(tint, .white, 0.55),
                    .backgroundColor: ReplyColor.white.withAlphaComponent(0.07)]))
            } else {
                out.append(NSAttributedString(string: inner, attributes: [.font: bold, .foregroundColor: ReplyColor.white]))
            }
            text = String(text[close.upperBound...])
        }
        return out
    }

    // MARK: - the two platforms

    private static func roundedFont(_ size: CGFloat, _ weight: ReplyFont.Weight) -> ReplyFont {
        let f = ReplyFont.systemFont(ofSize: size, weight: weight)
        #if canImport(AppKit)
        return f.fontDescriptor.withDesign(.rounded).flatMap { ReplyFont(descriptor: $0, size: size) } ?? f
        #else
        return f.fontDescriptor.withDesign(.rounded).map { ReplyFont(descriptor: $0, size: size) } ?? f
        #endif
    }

    private static func boldFont(_ f: ReplyFont) -> ReplyFont {
        #if canImport(AppKit)
        return NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
        #else
        return f.fontDescriptor.withSymbolicTraits(.traitBold).map { ReplyFont(descriptor: $0, size: f.pointSize) } ?? f
        #endif
    }

    /// `a` moved toward `b` by `t`.
    private static func mix(_ a: ReplyColor, _ b: ReplyColor, _ t: CGFloat) -> ReplyColor {
        #if canImport(AppKit)
        return a.blended(withFraction: t, of: b) ?? a
        #else
        var (r1, g1, b1, a1, r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0, 0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return ReplyColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
        #endif
    }
}
