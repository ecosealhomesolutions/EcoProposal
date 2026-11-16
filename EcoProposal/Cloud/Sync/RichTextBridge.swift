import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Converts the iPad's rich-text notes (RTF) to and from the simple HTML the
/// website's editor uses: paragraphs with bold, italic and underline.
/// Hand-rolled on purpose: Apple's HTML import needs WebKit on the main thread
/// and its export uses CSS classes the web editor ignores.
enum RichTextBridge {

    // MARK: - RTF → HTML (upload)

    static func html(fromRTF rtf: Data?, plainText: String) -> String {
        #if canImport(UIKit)
        if let rtf,
           let attr = try? NSAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return html(from: attr)
        }
        #endif
        return plainText
            .components(separatedBy: "\n")
            .map { "<p>\(escape($0))</p>" }
            .joined()
    }

    #if canImport(UIKit)
    private static func html(from attr: NSAttributedString) -> String {
        var paragraphs: [String] = [""]
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { attrs, range, _ in
            let text = (attr.string as NSString).substring(with: range)
            let font = attrs[.font] as? UIFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let bold = traits.contains(.traitBold)
            let italic = traits.contains(.traitItalic)
            let underline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0

            let pieces = text.components(separatedBy: "\n")
            for (i, piece) in pieces.enumerated() {
                if i > 0 { paragraphs.append("") }
                guard !piece.isEmpty else { continue }
                var chunk = escape(piece)
                if underline { chunk = "<u>\(chunk)</u>" }
                if italic { chunk = "<em>\(chunk)</em>" }
                if bold { chunk = "<strong>\(chunk)</strong>" }
                paragraphs[paragraphs.count - 1] += chunk
            }
        }
        if paragraphs.count > 1, paragraphs.last == "" { paragraphs.removeLast() }
        return paragraphs.map { "<p>\($0)</p>" }.joined()
    }
    #endif

    // MARK: - HTML → RTF (download)

    /// Returns RTF for the iPad editor, or nil when the HTML has no formatting
    /// worth keeping (the plain-text copy is used then).
    static func rtf(fromHTML html: String) -> Data? {
        #if canImport(UIKit)
        let base = UIFont.systemFont(ofSize: 16)
        let out = NSMutableAttributedString()
        var bold = 0, italic = 0, underline = 0
        var anyFormatting = false
        var needsBreak = false

        func font() -> UIFont {
            var traits: UIFontDescriptor.SymbolicTraits = []
            if bold > 0 { traits.insert(.traitBold) }
            if italic > 0 { traits.insert(.traitItalic) }
            guard !traits.isEmpty, let d = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
            return UIFont(descriptor: d, size: base.pointSize)
        }
        func append(_ text: String) {
            guard !text.isEmpty else { return }
            if needsBreak, out.length > 0 {
                out.append(NSAttributedString(string: "\n", attributes: [.font: base]))
            }
            needsBreak = false
            var attrs: [NSAttributedString.Key: Any] = [.font: font(), .foregroundColor: UIColor.label]
            if underline > 0 { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: unescape(text), attributes: attrs))
        }

        var i = html.startIndex
        var textStart = i
        while i < html.endIndex {
            if html[i] == "<", let close = html[i...].firstIndex(of: ">") {
                append(String(html[textStart..<i]))
                let tag = html[html.index(after: i)..<close].lowercased()
                let name = tag.split(whereSeparator: { $0 == " " || $0 == "/" }).first.map(String.init) ?? ""
                let closing = tag.hasPrefix("/")
                switch name {
                case "strong", "b": bold += closing ? -1 : 1; anyFormatting = true
                case "em", "i":     italic += closing ? -1 : 1; anyFormatting = true
                case "u":           underline += closing ? -1 : 1; anyFormatting = true
                case "p", "div", "h1", "h2", "h3", "li":
                    if closing { needsBreak = true }
                    else if name == "li" { append("• ") }
                case "br":
                    out.append(NSAttributedString(string: "\n", attributes: [.font: base]))
                default:
                    break
                }
                bold = max(bold, 0); italic = max(italic, 0); underline = max(underline, 0)
                i = html.index(after: close)
                textStart = i
            } else {
                i = html.index(after: i)
            }
        }
        append(String(html[textStart..<html.endIndex]))

        guard anyFormatting, out.length > 0 else { return nil }
        return try? out.data(
            from: NSRange(location: 0, length: out.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        #else
        return nil
        #endif
    }

    // MARK: - Entities

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
