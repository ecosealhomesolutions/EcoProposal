import SwiftUI

#if canImport(UIKit) && os(iOS)
import UIKit

/// WYSIWYG notes editor with bold / italic / underline. Wraps `UITextView` and
/// binds two representations of the same text: RTF bytes (persisted, carries
/// formatting into the PDF) and a plain-text mirror (search/sync/fallback).
///
/// Formatting is offered two ways: a toolbar row above the keyboard (B / I / U)
/// and the system text edit menu (`allowsEditingTextAttributes`).
struct RichTextEditor: UIViewRepresentable {
    @Binding var rtfData: Data?
    @Binding var plainText: String
    var placeholder: String = ""
    var minHeight: CGFloat = 120

    static let defaultFont = UIFont.systemFont(ofSize: 16)

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.allowsEditingTextAttributes = true
        textView.font = Self.defaultFont
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false   // grows with the Form row
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.inputAccessoryView = context.coordinator.makeFormatBar(for: textView)

        if let rtfData, let restored = Self.attributedString(fromRTF: rtfData) {
            textView.attributedText = restored
        } else if !plainText.isEmpty {
            textView.attributedText = NSAttributedString(
                string: plainText,
                attributes: [.font: Self.defaultFont, .foregroundColor: UIColor.label]
            )
        }
        context.coordinator.updatePlaceholder(in: textView, placeholder: placeholder)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        // Only push model → view when the change didn't originate from typing,
        // otherwise the cursor jumps to the end on every keystroke.
        guard !context.coordinator.isEditing else { return }
        let current = Self.rtf(from: textView.attributedText)
        if rtfData != current, let rtfData,
           let restored = Self.attributedString(fromRTF: rtfData) {
            textView.attributedText = restored
        }
        context.coordinator.updatePlaceholder(in: textView, placeholder: placeholder)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(minHeight, fit.height))
    }

    // MARK: - RTF conversion

    static func rtf(from attributed: NSAttributedString) -> Data? {
        guard attributed.length > 0 else { return nil }
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    static func attributedString(fromRTF data: Data) -> NSAttributedString? {
        try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        private let parent: RichTextEditor
        private(set) var isEditing = false
        private var placeholderLabel: UILabel?

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            isEditing = true
            parent.rtfData = RichTextEditor.rtf(from: textView.attributedText)
            parent.plainText = textView.text ?? ""
            updatePlaceholder(in: textView, placeholder: parent.placeholder)
            textView.invalidateIntrinsicContentSize()
            isEditing = false
        }

        // MARK: Placeholder

        func updatePlaceholder(in textView: UITextView, placeholder: String) {
            if placeholderLabel == nil, !placeholder.isEmpty {
                let label = UILabel()
                label.text = placeholder
                label.font = RichTextEditor.defaultFont
                label.textColor = .placeholderText
                label.numberOfLines = 0
                label.translatesAutoresizingMaskIntoConstraints = false
                textView.addSubview(label)
                NSLayoutConstraint.activate([
                    label.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
                    label.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
                    label.widthAnchor.constraint(equalTo: textView.widthAnchor),
                ])
                placeholderLabel = label
            }
            placeholderLabel?.isHidden = !(textView.text?.isEmpty ?? true)
        }

        // MARK: Format bar

        func makeFormatBar(for textView: UITextView) -> UIToolbar {
            let bar = UIToolbar()
            bar.sizeToFit()
            let bold = UIBarButtonItem(
                image: UIImage(systemName: "bold"), style: .plain,
                target: self, action: #selector(toggleBold)
            )
            let italic = UIBarButtonItem(
                image: UIImage(systemName: "italic"), style: .plain,
                target: self, action: #selector(toggleItalic)
            )
            let underline = UIBarButtonItem(
                image: UIImage(systemName: "underline"), style: .plain,
                target: self, action: #selector(toggleUnderline)
            )
            let done = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: textView, action: #selector(UIResponder.resignFirstResponder)
            )
            bar.items = [bold, italic, underline, .flexibleSpace(), done]
            self.textView = textView
            return bar
        }

        private weak var textView: UITextView?

        @objc private func toggleBold() { toggleTrait(.traitBold) }
        @objc private func toggleItalic() { toggleTrait(.traitItalic) }

        /// Flips the given font trait on the selection, or on the typing
        /// attributes when the selection is empty (affects text typed next).
        private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
            guard let textView else { return }
            let range = textView.selectedRange

            func toggled(_ font: UIFont) -> UIFont {
                var traits = font.fontDescriptor.symbolicTraits
                if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
                guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else { return font }
                return UIFont(descriptor: descriptor, size: font.pointSize)
            }

            if range.length > 0 {
                let text = NSMutableAttributedString(attributedString: textView.attributedText)
                text.enumerateAttribute(.font, in: range) { value, subrange, _ in
                    let font = (value as? UIFont) ?? RichTextEditor.defaultFont
                    text.addAttribute(.font, value: toggled(font), range: subrange)
                }
                textView.attributedText = text
                textView.selectedRange = range
            } else {
                let font = (textView.typingAttributes[.font] as? UIFont) ?? RichTextEditor.defaultFont
                textView.typingAttributes[.font] = toggled(font)
            }
            textViewDidChange(textView)
        }

        @objc private func toggleUnderline() {
            guard let textView else { return }
            let range = textView.selectedRange

            if range.length > 0 {
                let text = NSMutableAttributedString(attributedString: textView.attributedText)
                // If any part of the selection is underlined, remove it everywhere;
                // otherwise underline the whole selection.
                var hasUnderline = false
                text.enumerateAttribute(.underlineStyle, in: range) { value, _, stop in
                    if let style = value as? Int, style != 0 { hasUnderline = true; stop.pointee = true }
                }
                if hasUnderline {
                    text.removeAttribute(.underlineStyle, range: range)
                } else {
                    text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                }
                textView.attributedText = text
                textView.selectedRange = range
            } else {
                let current = (textView.typingAttributes[.underlineStyle] as? Int) ?? 0
                textView.typingAttributes[.underlineStyle] =
                    current == 0 ? NSUnderlineStyle.single.rawValue : 0
            }
            textViewDidChange(textView)
        }
    }
}
#else
/// Non-iOS fallback: a plain text editor without formatting.
struct RichTextEditor: View {
    @Binding var rtfData: Data?
    @Binding var plainText: String
    var placeholder: String = ""
    var minHeight: CGFloat = 120

    var body: some View {
        TextField(placeholder, text: $plainText, axis: .vertical)
            .lineLimit(4...12)
    }
}
#endif
