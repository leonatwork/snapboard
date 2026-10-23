import AppKit
import ImageIO
import UniformTypeIdentifiers

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
        let uti: CFString
        switch type {
        case .png: uti = UTType.png.identifier as CFString
        case .tiff: uti = UTType.tiff.identifier as CFString
        default:
            guard let data = bitmap.representation(using: type, properties: [:]) else {
                throw EditorExportError.encodingFailed
            }
            return data
        }
        guard let cgImage = bitmap.cgImage, bitmap.size.width > 0, bitmap.size.height > 0 else {
            throw EditorExportError.encodingFailed
        }
        // NSBitmapImageRep does not reliably write the resolution; set it explicitly via ImageIO
        // (points are 1/72 inch, so DPI = 72 * pixels / points).
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72.0 * Double(cgImage.width) / Double(bitmap.size.width),
            kCGImagePropertyDPIHeight: 72.0 * Double(cgImage.height) / Double(bitmap.size.height),
        ]
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, uti, 1, nil) else {
            throw EditorExportError.encodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EditorExportError.encodingFailed }
        return output as Data
    }
}
