import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit

public class ImageFilters {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    public static func processImage(
        original: NSImage,
        brightness: Double,   // -1.0 to 1.0 (default 0.0)
        contrast: Double,     // 0.2 to 2.0 (default 1.0)
        saturation: Double,   // 0.0 to 2.0 (default 1.0)
        rotationDegrees: Int, // 0, 90, 180, 270
        cropNormalizedRect: CGRect? // normalized 0..1 coordinates (x, y, w, h)
    ) -> NSImage? {
        guard let tiffData = original.tiffRepresentation,
              let ciInput = CIImage(data: tiffData) else {
            return original
        }
        
        var current = ciInput
        
        // 1. Color Controls (Brightness, Contrast, Saturation)
        if brightness != 0.0 || contrast != 1.0 || saturation != 1.0 {
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(current, forKey: kCIInputImageKey)
                filter.setValue(brightness, forKey: kCIInputBrightnessKey)
                filter.setValue(contrast, forKey: kCIInputContrastKey)
                filter.setValue(saturation, forKey: kCIInputSaturationKey)
                if let output = filter.outputImage {
                    current = output
                }
            }
        }
        
        // 2. Rotation
        if rotationDegrees != 0 {
            let radians = CGFloat(rotationDegrees) * .pi / 180.0
            current = current.transformed(by: CGAffineTransform(rotationAngle: radians))
        }
        
        // 3. Crop
        if let normRect = cropNormalizedRect,
           normRect.width > 0.05 && normRect.height > 0.05 &&
           (normRect.width < 0.99 || normRect.height < 0.99 || normRect.origin.x > 0.01 || normRect.origin.y > 0.01) {
            let extent = current.extent
            let cropX = extent.origin.x + normRect.origin.x * extent.width
            let cropY = extent.origin.y + (1.0 - normRect.origin.y - normRect.height) * extent.height
            let cropW = normRect.width * extent.width
            let cropH = normRect.height * extent.height
            let targetRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
            current = current.cropped(to: targetRect)
        }
        
        guard let cgImage = ciContext.createCGImage(current, from: current.extent) else {
            return original
        }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
    
    public static func exportImage(
        image: NSImage,
        to destinationURL: URL,
        format: String, // "pdf", "png", "jpg", "tiff"
        dpi: Int = 300
    ) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            throw NSError(domain: "ImageFilters", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap representation"])
        }
        
        let ext = format.lowercased()
        switch ext {
        case "pdf":
            let pdfDoc = PDFDocument()
            guard let page = PDFPage(image: image) else {
                throw NSError(domain: "ImageFilters", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF page"])
            }
            pdfDoc.insert(page, at: 0)
            guard pdfDoc.write(to: destinationURL) else {
                throw NSError(domain: "ImageFilters", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to write PDF to \(destinationURL.path)"])
            }
            
        case "png":
            guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "ImageFilters", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to generate PNG"])
            }
            try pngData.write(to: destinationURL)
            
        case "jpg", "jpeg":
            guard let jpgData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                throw NSError(domain: "ImageFilters", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to generate JPEG"])
            }
            try jpgData.write(to: destinationURL)
            
        case "tiff", "tif":
            guard let tiffOut = bitmap.representation(using: .tiff, properties: [:]) else {
                throw NSError(domain: "ImageFilters", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to generate TIFF"])
            }
            try tiffOut.write(to: destinationURL)
            
        default:
            try tiffData.write(to: destinationURL)
        }
    }
    
    public static func exportMultiPagePDF(
        images: [NSImage],
        to destinationURL: URL
    ) throws {
        guard !images.isEmpty else {
            throw NSError(domain: "ImageFilters", code: 1, userInfo: [NSLocalizedDescriptionKey: "No pages to export"])
        }
        let pdfDoc = PDFDocument()
        for (index, img) in images.enumerated() {
            guard let page = PDFPage(image: img) else {
                throw NSError(domain: "ImageFilters", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create PDF page \(index + 1)"])
            }
            pdfDoc.insert(page, at: index)
        }
        guard pdfDoc.write(to: destinationURL) else {
            throw NSError(domain: "ImageFilters", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to write PDF to \(destinationURL.path)"])
        }
    }
}
