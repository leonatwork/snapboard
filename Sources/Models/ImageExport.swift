import AppKit

enum ImageExportError: LocalizedError {
    case renderingFailed
    case encodingFailed
    case clipboardFailed

    var errorDescription: String? {
        switch self {
        case .renderingFailed: return L10n.tr("editor.exportError.rendering")
        case .encodingFailed: return L10n.tr("editor.exportError.encoding")
        case .clipboardFailed: return L10n.tr("editor.exportError.clipboard")
        }
    }
}

/// Encodes the original pixel grid with the rendered image's source point size.
/// Both clipboard formats and the saved PNG use the same bitmap resolution.
@MainActor
struct ImageExport {
    private let bitmap: NSBitmapImageRep

    init(image: NSImage) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageExportError.renderingFailed
        }
        bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = image.size
    }

    func pngData() throws -> Data {
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ImageExportError.encodingFailed
        }
        return data
    }

    func pasteboardItem() throws -> NSPasteboardItem {
        let png = try pngData()
        guard let tiff = bitmap.representation(using: .tiff, properties: [:]) else {
            throw ImageExportError.encodingFailed
        }
        let item = NSPasteboardItem()
        // PNG first, TIFF as fallback. Encode both before touching the user's clipboard.
        guard item.setData(png, forType: .png), item.setData(tiff, forType: .tiff) else {
            throw ImageExportError.clipboardFailed
        }
        return item
    }
}
