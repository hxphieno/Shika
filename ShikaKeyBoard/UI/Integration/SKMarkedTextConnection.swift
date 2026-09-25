import UIKit

/// Owns only the marked range created by this keyboard, never surrounding text.
@MainActor
final class SKMarkedTextConnection {
    private(set) var isEditing = false
    private var markedDocument: UUID?

    func updateComposition(_ text: String, in proxy: UITextDocumentProxy) {
        if text.isEmpty {
            guard let markedDocument else { return }
            guard markedDocument == documentID(in: proxy) else { self.markedDocument = nil; return }
            edit {
                proxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
                proxy.unmarkText()
            }
            self.markedDocument = nil
        } else {
            guard let document = documentID(in: proxy) else { return }
            edit { proxy.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0)) }
            markedDocument = document
        }
    }

    func insert(_ text: String, in proxy: UITextDocumentProxy) {
        if let markedDocument, markedDocument == documentID(in: proxy) {
            edit {
                proxy.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
                proxy.unmarkText()
            }
            self.markedDocument = nil
        } else {
            edit { proxy.insertText(text) }
        }
    }
    func deleteBackward(in proxy: UITextDocumentProxy) { edit { proxy.deleteBackward() } }

    /// A host cursor/focus change ends our ownership. Preserve visible text;
    /// do not erase an old range through a proxy that may now point elsewhere.
    func releaseComposition(in proxy: UITextDocumentProxy) {
        guard let markedDocument else { return }
        if markedDocument == documentID(in: proxy) { edit { proxy.unmarkText() } }
        self.markedDocument = nil
    }

    private func documentID(in proxy: UITextDocumentProxy) -> UUID? {
        // The public Objective-C getter can return nil while the extension is
        // attaching/detaching, despite its nonnull annotation. Read it without
        // Swift's unconditional NSUUID -> UUID bridge, which traps on nil.
        proxy.perform(#selector(getter: UITextDocumentProxy.documentIdentifier))?.takeUnretainedValue() as? UUID
    }

    private func edit(_ body: () -> Void) {
        let wasEditing = isEditing
        isEditing = true
        defer { isEditing = wasEditing }
        body()
    }
}
