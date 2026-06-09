import AppKit

/// Snapshot/restore of the general pasteboard so synthetic copy/paste
/// (selection grab at hotkey time, Cmd+V when applying an edit) never
/// clobbers the user's clipboard.
enum PasteboardSnapshot {
    /// Copy every item's data for every type so the clipboard can be restored later.
    static func take() -> [NSPasteboardItem] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if !items.isEmpty {
            pb.writeObjects(items)
        }
    }
}
