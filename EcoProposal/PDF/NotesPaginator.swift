import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Prepares proposal notes for PDF rendering: decodes the RTF (or falls back to
/// plain text), normalizes fonts to print size while preserving bold / italic /
/// underline, splits the result into page-sized chunks with TextKit, and converts
/// each chunk to a SwiftUI `AttributedString` that `ImageRenderer` can draw.
enum NotesPaginator {
    static let pdfFontSize: CGFloat = 11

    /// One entry per PDF page, ready to hand to `NotesPageView`.
    static func pageChunks(rtf: Data?, plain: String, contentSize: CGSize) -> [AttributedString] {
        #if canImport(UIKit)
        let normalized = normalizedText(rtf: rtf, plain: plain)
        guard normalized.length > 0 else { return [] }
        return paginate(normalized, into: contentSize).map(swiftUIAttributed)
        #else
        let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [AttributedString(trimmed)]
        #endif
    }

    #if canImport(UIKit)

    /// Decodes the stored note and rewrites every font to the PDF point size,
    /// keeping only the traits that matter (bold/italic) plus underline. Editor
    /// text is 16pt on screen; contracts print at 11pt.
    private static func normalizedText(rtf: Data?, plain: String) -> NSAttributedString {
        let source: NSAttributedString
        if let rtf,
           let decoded = try? NSAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            source = decoded
        } else {
            source = NSAttributedString(string: plain)
        }

        let output = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: output.length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3

        output.enumerateAttributes(in: fullRange) { attributes, range, _ in
            let sourceFont = (attributes[.font] as? UIFont) ?? UIFont.systemFont(ofSize: pdfFontSize)
            let traits = sourceFont.fontDescriptor.symbolicTraits
            var font = UIFont.systemFont(ofSize: pdfFontSize)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(
                traits.intersection([.traitBold, .traitItalic])
            ) {
                font = UIFont(descriptor: descriptor, size: pdfFontSize)
            }

            var cleaned: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph,
            ]
            if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
                cleaned[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            output.setAttributes(cleaned, range: range)
        }
        return output
    }

    /// Classic TextKit pagination: keep adding page-sized text containers to a
    /// layout manager; each container absorbs as much text as fits, and the glyph
    /// range it was given maps back to the characters for that page.
    private static func paginate(_ text: NSAttributedString, into size: CGSize) -> [NSAttributedString] {
        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        var chunks: [NSAttributedString] = []
        var consumedGlyphs = 0
        while consumedGlyphs < layoutManager.numberOfGlyphs {
            let container = NSTextContainer(size: size)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)

            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.length == 0 { break } // safety: container too small to fit anything
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            chunks.append(storage.attributedSubstring(from: charRange))
            consumedGlyphs = NSMaxRange(glyphRange)
        }
        return chunks
    }

    /// Converts a normalized chunk into a SwiftUI-native `AttributedString`.
    /// `ImageRenderer` draws pure SwiftUI content, so UIKit font attributes must
    /// be re-expressed as SwiftUI `Font` / underline attributes.
    private static func swiftUIAttributed(_ chunk: NSAttributedString) -> AttributedString {
        var result = AttributedString()
        chunk.enumerateAttributes(in: NSRange(location: 0, length: chunk.length)) { attributes, range, _ in
            let substring = (chunk.string as NSString).substring(with: range)
            var run = AttributedString(substring)

            var font = Font.system(size: pdfFontSize)
            if let uiFont = attributes[.font] as? UIFont {
                let traits = uiFont.fontDescriptor.symbolicTraits
                if traits.contains(.traitBold) { font = font.bold() }
                if traits.contains(.traitItalic) { font = font.italic() }
            }
            run.font = font
            if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
                run.underlineStyle = .single
            }
            result.append(run)
        }
        return result
    }

    #endif
}
