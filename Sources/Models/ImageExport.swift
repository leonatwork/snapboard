import AppKit

/// Point size describes the source's physical size; pixel dimensions describe its raster.
/// Keep them independent: a 2x capture must not become a 1x image or be resampled.
struct ImageExportGeometry {
    let pointSize: CGSize
    let pixelWidth: Int
    let pixelHeight: Int

    init?(pointSize: CGSize, pixelWidth: Int, pixelHeight: Int) {
        guard pointSize.width.isFinite, pointSize.height.isFinite,
              pointSize.width > 0, pointSize.height > 0,
              pixelWidth > 0, pixelHeight > 0 else { return nil }
        self.pointSize = pointSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

enum EditorExportError: LocalizedError, Equatable {
    case renderFailed
    case encodingFailed
    case clipboardFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: return L10n.tr("editor.export.renderFailed")
        case .encodingFailed: return L10n.tr("editor.export.encodingFailed")
        case .clipboardFailed: return L10n.tr("editor.export.clipboardFailed")
        }
    }
}

@MainActor
enum ImageExport {
    static func bitmap(image: NSImage) throws -> NSBitmapImageRep {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let geometry = ImageExportGeometry(
                pointSize: image.size, pixelWidth: cgImage.width, pixelHeight: cgImage.height
              ) else { throw EditorExportError.encodingFailed }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        // AppKit derives PNG/TIFF resolution from the ratio of pixels to points.
        bitmap.size = geometry.pointSize
        return bitmap
    }

    static func data(from bitmap: NSBitmapImageRep, using type: NSBitmapImageRep.FileType) throws -> Data {
        guard let data = bitmap.representation(using: type, properties: [:]) else {
            throw EditorExportError.encodingFailed
        }
        return data
    }
}
