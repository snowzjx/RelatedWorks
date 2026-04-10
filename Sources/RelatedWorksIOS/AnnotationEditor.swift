import SwiftUI
import UIKit

struct AnnotationEditor: UIViewRepresentable {
    @Binding var text: String
    let paperIDs: [String]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .preferredFont(forTextStyle: .body)
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .sentences
        tv.text = text
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        guard !context.coordinator.isEditing else { return }
        if tv.text != text {
            tv.text = text
            tv.font = .preferredFont(forTextStyle: .body)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: AnnotationEditor
        weak var textView: UITextView?
        var isEditing = false

        // Suggestion state
        var suggestionBar: UIView?
        var currentAtRange: NSRange?

        init(_ parent: AnnotationEditor) { self.parent = parent }

        func textViewDidBeginEditing(_ tv: UITextView) {
            isEditing = true
            self.textView = tv
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            isEditing = false
            parent.text = tv.text
            hideSuggestions()
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            checkForMention(in: tv)
        }

        // MARK: - Mention detection

        private func checkForMention(in tv: UITextView) {
            guard let selectedRange = tv.selectedTextRange else { hideSuggestions(); return }
            let cursorPos = tv.offset(from: tv.beginningOfDocument, to: selectedRange.start)
            let text = tv.text as NSString
            guard cursorPos > 0 else { hideSuggestions(); return }

            var i = cursorPos - 1
            while i > 0 {
                let c = text.character(at: i)
                if c == "@".utf16.first! { break }
                if c == " ".utf16.first! || c == "\n".utf16.first! { hideSuggestions(); return }
                i -= 1
            }
            guard text.character(at: i) == "@".utf16.first! else { hideSuggestions(); return }

            let typed = text.substring(with: NSRange(location: i + 1, length: cursorPos - i - 1)).lowercased()
            let matches = parent.paperIDs.filter { typed.isEmpty || $0.lowercased().hasPrefix(typed) }
            guard !matches.isEmpty else { hideSuggestions(); return }

            currentAtRange = NSRange(location: i, length: cursorPos - i)
            showSuggestions(matches, in: tv)
        }

        // MARK: - Suggestion bar (horizontal scroll above keyboard)

        private func showSuggestions(_ items: [String], in tv: UITextView) {
            hideSuggestions()

            let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: tv.bounds.width, height: 44),
                                  inputViewStyle: .keyboard)
            bar.allowsSelfSizing = true

            let scroll = UIScrollView()
            scroll.showsHorizontalScrollIndicator = false
            scroll.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
                scroll.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
                scroll.topAnchor.constraint(equalTo: bar.topAnchor, constant: 6),
                scroll.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -6),
            ])

            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            ])

            for id in items {
                var config = UIButton.Configuration.filled()
                config.title = "@\(id)"
                config.baseForegroundColor = .systemBlue
                config.baseBackgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
                config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
                config.cornerStyle = .medium
                let btn = UIButton(configuration: config)
                btn.addAction(UIAction { [weak self] _ in
                    self?.insertMention(id)
                }, for: .touchUpInside)
                stack.addArrangedSubview(btn)
            }

            tv.inputAccessoryView = bar
            tv.reloadInputViews()
            suggestionBar = bar
        }

        private func hideSuggestions() {
            guard suggestionBar != nil else { return }
            textView?.inputAccessoryView = nil
            textView?.reloadInputViews()
            suggestionBar = nil
            currentAtRange = nil
        }

        private func insertMention(_ id: String) {
            guard let tv = textView, let atRange = currentAtRange else { return }
            let replacement = "@\(id) "
            let nsText = tv.text as NSString
            let newText = nsText.replacingCharacters(in: atRange, with: replacement)
            tv.text = newText
            // Move cursor after inserted mention
            let newPos = atRange.location + replacement.count
            if let pos = tv.position(from: tv.beginningOfDocument, offset: newPos) {
                tv.selectedTextRange = tv.textRange(from: pos, to: pos)
            }
            parent.text = tv.text
            hideSuggestions()
        }
    }
}
