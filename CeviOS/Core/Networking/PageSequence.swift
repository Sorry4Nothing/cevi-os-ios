/// Collects pages of a cursor pagination (newest first). `next` is the cursor for the next, older page;
/// `nil` means the end.
nonisolated struct PageSequence<Element: Sendable>: Sendable {
    private(set) var items: [Element] = []
    private(set) var next: String?
    private(set) var isAtEnd = false

    /// Appends an older page. Afterwards `next` stands for the following page.
    mutating func append(_ page: [Element], next: String?) {
        items.append(contentsOf: page)
        self.next = next
        isAtEnd = next == nil
    }
}
