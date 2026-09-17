import Foundation
import AppKit
import Vision
import CoreGraphics

/// DocumentDetector: Native Computer Vision & Edge Analysis for Document Detection on Scanner Beds
/// Uses Apple Vision (Neural Engine / VNDetectRectanglesRequest) + Text Union + Luminance Edge Analysis.
public class DocumentDetector {
    
    /// Detect the bounding box of a document placed on the flatbed scanner.
    /// Returns normalized CGRect (0.0 to 1.0) with (0,0) at top-left, suitable for ImageFilters.
    public static func detectDocumentBounds(image: NSImage) -> CGRect? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else {
            return nil
        }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 60 && height > 60 else { return nil }
        
        // METHOD 1: Apple Vision Rectangle Detection (Hardware-accelerated)
        let rectRequest = VNDetectRectanglesRequest()
        rectRequest.minimumConfidence = 0.35
        rectRequest.minimumAspectRatio = 0.1
        rectRequest.maximumAspectRatio = 1.0
        rectRequest.minimumSize = 0.1
        rectRequest.maximumObservations = 6
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([rectRequest])
        
        if let results = rectRequest.results, !results.isEmpty {
            // Find candidate rectangles that are distinct from the full scanner bed
            var candidates: [CGRect] = []
            for obs in results {
                let box = obs.boundingBox // Vision: (0,0) bottom-left
                let normX = box.minX
                let normY = 1.0 - box.maxY
                let normW = box.width
                let normH = box.height
                
                // Exclude full-frame borders (e.g., scanner bed outer edge > 98% in both dimensions)
                if normW < 0.98 || normH < 0.98 || normX > 0.015 || normY > 0.015 {
                    candidates.append(CGRect(x: normX, y: normY, width: normW, height: normH))
                }
            }
            
            if let best = candidates.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }) {
                // Check if this candidate is significantly smaller than the entire bed
                let areaFraction = best.width * best.height
                if areaFraction >= 0.02 && areaFraction < 0.96 {
                    let padX: CGFloat = 0.012
                    let padY: CGFloat = 0.012
                    let finalX = max(0.0, best.origin.x - padX)
                    let finalY = max(0.0, best.origin.y - padY)
                    let finalW = min(1.0 - finalX, best.width + padX * 2)
                    let finalH = min(1.0 - finalY, best.height + padY * 2)
                    return CGRect(x: finalX, y: finalY, width: finalW, height: finalH)
                }
            }
        }
        
        // METHOD 2: Fast Text Bounding Box Union (for receipts, notes, cards, book pages)
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        try? handler.perform([textRequest])
        
        if let textResults = textRequest.results, textResults.count >= 2 {
            var minX: CGFloat = 1.0
            var maxX: CGFloat = 0.0
            var minY: CGFloat = 1.0
            var maxY: CGFloat = 0.0
            
            for obs in textResults {
                let box = obs.boundingBox
                let normTopY = 1.0 - box.maxY
                let normBottomY = 1.0 - box.minY
                minX = min(minX, box.minX)
                maxX = max(maxX, box.maxX)
                minY = min(minY, normTopY)
                maxY = max(maxY, normBottomY)
            }
            
            let textW = maxX - minX
            let textH = maxY - minY
            // If text is concentrated in a portion of the flatbed (not taking up the full page)
            if textW > 0.08 && textH > 0.05 && (textW < 0.92 || textH < 0.92 || minX > 0.04 || minY > 0.04) {
                let padX: CGFloat = 0.035
                let padY: CGFloat = 0.035
                let finalX = max(0.0, minX - padX)
                let finalY = max(0.0, minY - padY)
                let finalW = min(1.0 - finalX, textW + padX * 2)
                let finalH = min(1.0 - finalY, textH + padY * 2)
                return CGRect(x: finalX, y: finalY, width: finalW, height: finalH)
            }
        }
        
        // METHOD 3: Edge Contrast & Background Luminance Scan
        let w = bitmap.pixelsWide
        let h = bitmap.pixelsHigh
        let step = max(2, min(w, h) / 250)
        
        // Sample flatbed perimeter
        var bgLums: [Double] = []
        for x in stride(from: 0, to: w, by: step * 4) {
            if let c1 = bitmap.colorAt(x: x, y: 0) { bgLums.append(c1.brightnessComponent) }
            if let c2 = bitmap.colorAt(x: x, y: h - 1) { bgLums.append(c2.brightnessComponent) }
        }
        for y in stride(from: 0, to: h, by: step * 4) {
            if let c1 = bitmap.colorAt(x: 0, y: y) { bgLums.append(c1.brightnessComponent) }
            if let c2 = bitmap.colorAt(x: w - 1, y: y) { bgLums.append(c2.brightnessComponent) }
        }
        
        let avgBgLum = bgLums.isEmpty ? 1.0 : bgLums.reduce(0, +) / Double(bgLums.count)
        
        var minPxX = w
        var maxPxX = 0
        var minPxY = h
        var maxPxY = 0
        
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                if let col = bitmap.colorAt(x: x, y: y) {
                    let lum = col.brightnessComponent
                    if abs(lum - avgBgLum) > 0.12 {
                        if x < minPxX { minPxX = x }
                        if x > maxPxX { maxPxX = x }
                        if y < minPxY { minPxY = y }
                        if y > maxPxY { maxPxY = y }
                    }
                }
            }
        }
        
        if minPxX < maxPxX && minPxY < maxPxY {
            let docW = CGFloat(maxPxX - minPxX) / width
            let docH = CGFloat(maxPxY - minPxY) / height
            let docX = CGFloat(minPxX) / width
            let docY = CGFloat(minPxY) / height
            
            // If the content is distinctly smaller than the whole flatbed
            if docW > 0.10 && docH > 0.10 && (docW < 0.95 || docH < 0.95 || docX > 0.03 || docY > 0.03) {
                let pad: CGFloat = 0.015
                let finalX = max(0.0, docX - pad)
                let finalY = max(0.0, docY - pad)
                let finalW = min(1.0 - finalX, docW + pad * 2)
                let finalH = min(1.0 - finalY, docH + pad * 2)
                return CGRect(x: finalX, y: finalY, width: finalW, height: finalH)
            }
        }
        
        return nil
    }
}
