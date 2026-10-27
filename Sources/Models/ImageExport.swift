import AppKit
import ImageIO
import UniformTypeIdentifiers

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
    private let pixels: CGImage
    private let resolution: [String: Any]

    init(image: NSImage) throws {
        guard image.size.width > 0, image.size.height > 0,
              image.size.width.isFinite, image.size.height.isFinite,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageExportError.renderingFailed
        }
        pixels = cgImage
        resolution = [
            kCGImagePropertyDPIWidth as String: 72 * CGFloat(cgImage.width) / image.size.width,
            kCGImagePropertyDPIHeight as String: 72 * CGFloat(cgImage.height) / image.size.height
        ]
    }

    func pngData() throws -> Data {
        try encodedData(type: .png)
    }

    private func encodedData(type: UTType) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else {
            throw ImageExportError.encodingFailed
        }
        // A bitmap's point size alone does not reliably produce PNG resolution metadata.
        // ImageIO writes explicit DPI for both formats, including PNG's pixels/metre chunk.
        CGImageDestinationAddImage(destination, pixels, resolution as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageExportError.encodingFailed
        }
        return data as Data
    }

    func pasteboardItem() throws -> NSPasteboardItem {
        let png = try pngData()
        let tiff = try encodedData(type: .tiff)
        let item = NSPasteboardItem()
        // PNG first, TIFF as fallback. Encode both before touching the user's clipboard.
        guard item.setData(png, forType: .png), item.setData(tiff, forType: .tiff) else {
            throw ImageExportError.clipboardFailed
        }
        return item
    }
}
