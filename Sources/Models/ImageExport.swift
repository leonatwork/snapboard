import AppKit
import ImageIO

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
    private let cgImage: CGImage
    private let resolution: [CFString: Any]

    init(image: NSImage) throws {
        guard image.size.width > 0, image.size.height > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageExportError.renderingFailed
        }
        self.cgImage = cgImage
        resolution = [
            kCGImagePropertyDPIWidth: 72 * CGFloat(cgImage.width) / image.size.width,
            kCGImagePropertyDPIHeight: 72 * CGFloat(cgImage.height) / image.size.height
        ]
        bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = image.size
    }

    func pngData() throws -> Data {
        // NSBitmapImageRep's point size is retained by TIFF, but its PNG encoder
        // does not reliably emit a pHYs chunk. Supply both axes explicitly to ImageIO.
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else {
            throw ImageExportError.encodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, resolution as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageExportError.encodingFailed
        }
        return data as Data
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
