import Foundation
import AppKit
import SwiftUI
import Combine


public enum ScanMode: String, CaseIterable, Identifiable {
    case color = "color"
    case gray = "gray"
    case lineart = "lineart"
    
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .color: return "Color (24-bit)"
        case .gray: return "Grayscale (8-bit)"
        case .lineart: return "Text / B&W (1-bit)"
        }
    }
    public var iconName: String {
        switch self {
        case .color: return "paintpalette"
        case .gray: return "circle.lefthalf.filled"
        case .lineart: return "doc.text"
        }
    }
}

public enum OutputFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF"
    case png = "PNG"
    case jpg = "JPEG"
    case tiff = "TIFF"
    
    public var id: String { rawValue }
    public var fileExtension: String {
        switch self {
        case .pdf: return "pdf"
        case .png: return "png"
        case .jpg: return "jpg"
        case .tiff: return "tiff"
        }
    }
}

public enum PageSize: String, CaseIterable, Identifiable {
    case a4 = "A4 (210 × 297 mm)"
    case letter = "US Letter (8.5 × 11 in)"
    case legal = "US Legal (8.5 × 14 in)"
    
    public var id: String { rawValue }
    public var engineCode: String {
        switch self {
        case .a4: return "a4"
        case .letter: return "letter"
        case .legal: return "legal"
        }
    }
}

public struct ScannedPage: Identifiable, Equatable {
    public let id: UUID
    public var rawImage: NSImage
    public var displayedImage: NSImage
    public var rotationAngle: Int
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var scanDPI: Int
    public var scanMode: ScanMode
    public var isCroppingEnabled: Bool
    public var cropRect: CGRect
    
    public init(rawImage: NSImage, dpi: Int, mode: ScanMode) {
        self.id = UUID()
        self.rawImage = rawImage
        self.displayedImage = rawImage
        self.rotationAngle = 0
        self.brightness = 0.0
        self.contrast = 1.0
        self.saturation = 1.0
        self.scanDPI = dpi
        self.scanMode = mode
        self.isCroppingEnabled = false
        self.cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    
    public static func == (lhs: ScannedPage, rhs: ScannedPage) -> Bool {
        return lhs.id == rhs.id
    }
}

@MainActor
public class ScannerViewModel: ObservableObject {
    // Connection
    @Published public var isConnected: Bool = false
    @Published public var connectionStatusText: String = "Checking device..."
    @Published public var isTestPatternMode: Bool = false
    
    // Scan Settings
    @Published public var scanMode: ScanMode = .color
    @Published public var dpi: Int = 300
    @Published public var pageSize: PageSize = .a4
    @Published public var outputFormat: OutputFormat = .pdf
    @Published public var autoCropToDocument: Bool = false
    
    // Save destination
    @Published public var outputFolder: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
    @Published public var filePrefix: String = "Scan"
    @Published public var autoOpenInPreview: Bool = true
    @Published public var revealInFinder: Bool = false
    
    // Image Adjustments
    @Published public var brightness: Double = 0.0 // -1.0 to 1.0
    @Published public var contrast: Double = 1.0   // 0.2 to 2.0
    @Published public var saturation: Double = 1.0 // 0.0 to 2.0
    @Published public var rotationAngle: Int = 0   // 0, 90, 180, 270
    @Published public var isCroppingEnabled: Bool = false
    @Published public var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    
    // Multi-page Document Management
    @Published public var pages: [ScannedPage] = []
    @Published public var selectedPageIndex: Int = 0
    @Published public var previewImage: NSImage? = nil
    @Published public var hasUnsavedScans: Bool = false
    @Published public var lastSavedURLs: [URL] = []
    
    // Scan Execution State
    @Published public var isScanning: Bool = false
    @Published public var scanProgress: Double = 0.0
    @Published public var statusMessage: String = "Ready"
    @Published public var rawScannedImage: NSImage? = nil
    @Published public var displayedImage: NSImage? = nil
    @Published public var lastSavedURL: URL? = nil
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var dragOffset: CGSize = .zero
    @Published public var accumulatedOffset: CGSize = .zero
    @Published public var showEnhancements: Bool = true
    
    private var activeProcess: Process? = nil
    private var activeInputPipe: Pipe? = nil
    private var cancellables = Set<AnyCancellable>()
    private var isSyncingPage: Bool = false
    
    public init() {
        if CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--test-pattern") {
            isTestPatternMode = true
        }
        checkConnection()
        
        if CommandLine.arguments.contains("--auto-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startScan(isPreview: true)
            }
        }
        
        // Re-process image whenever adjustments change
        Publishers.CombineLatest4($brightness, $contrast, $saturation, $rotationAngle)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyAdjustments()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerOverview"))
            .sink { [weak self] _ in
                self?.startScan(isPreview: true)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerScan"))
            .sink { [weak self] _ in
                self?.startScan(isPreview: false)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerSave"))
            .sink { [weak self] _ in
                self?.saveDocuments()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerZoomIn"))
            .sink { [weak self] _ in
                guard let self = self else { return }
                withAnimation(.spring()) {
                    self.zoomScale = min(3.0, self.zoomScale + 0.25)
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerZoomOut"))
            .sink { [weak self] _ in
                guard let self = self else { return }
                withAnimation(.spring()) {
                    self.zoomScale = max(0.25, self.zoomScale - 0.25)
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerZoomFit"))
            .sink { [weak self] _ in
                guard let self = self else { return }
                withAnimation(.spring()) {
                    self.zoomScale = 1.0
                    self.accumulatedOffset = .zero
                    self.dragOffset = .zero
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerAutoCrop"))
            .sink { [weak self] _ in
                self?.autoDetectAndCropCurrent()
            }
            .store(in: &cancellables)
    }
    
    // Locate the engine binary across App bundle, relative repo, and system paths
    public func getEnginePath() -> String? {
        let appBundlePath = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/samsung-scan-engine").path
        let possiblePaths: [String?] = [
            ProcessInfo.processInfo.environment["SAMSUNG_SCAN_ENGINE"],
            appBundlePath,
            "/Library/Printers/Samsung/Scanner/samsung-scan-engine",
            "/usr/local/bin/samsung-scan-engine",
            URL(fileURLWithPath: Bundle.main.bundlePath).deletingLastPathComponent().appendingPathComponent("bin/samsung-scan-engine").path,
            NSHomeDirectory() + "/Code/driver/scanner/bin/samsung-scan-engine"
        ]
        
        for path in possiblePaths {
            if let p = path, FileManager.default.isExecutableFile(atPath: p) {
                return p
            }
        }
        return nil
    }
    
    public func checkConnection() {
        if isTestPatternMode {
            isConnected = true
            connectionStatusText = "Simulation Mode Active"
            return
        }
        
        // USB Detection using engine --detect
        guard let engine = getEnginePath() else {
            isConnected = false
            connectionStatusText = "Engine Missing"
            return
        }
        
        Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: engine)
            proc.arguments = ["--detect"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            try? proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let detected = output.contains("Samsung") && !output.contains("No Samsung")
            
            await MainActor.run {
                self.isConnected = detected
                self.connectionStatusText = detected ? "Samsung Scanner Ready (USB)" : "No USB Scanner Found"
            }
        }
    }
    
    public func startScan(isPreview: Bool) {
        guard !isScanning else { return }
        
        guard let enginePath = getEnginePath() else {
            statusMessage = "Error: samsung-scan-engine executable not found!"
            return
        }
        
        isScanning = true
        scanProgress = 0.0
        statusMessage = isPreview ? "Scanning preview..." : "Scanning document..."
        
        let targetDpi = isPreview ? 75 : dpi
        let targetMode = scanMode.rawValue
        let tempPNG = NSTemporaryDirectory() + "scan_tmp_\(UUID().uuidString).png"
        
        var args = [
            "-d", String(targetDpi),
            "-m", targetMode,
            "-s", pageSize.engineCode,
            "-o", tempPNG,
            "--json-progress"
        ]
        
        if isTestPatternMode {
            args.append("--test-pattern")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: enginePath)
        process.arguments = args
        self.activeProcess = process
        
        let inPipe = Pipe()
        process.standardInput = inPipe
        self.activeInputPipe = inPipe
        
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        
        let fileHandle = outPipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let availableData = handle.availableData
            guard !availableData.isEmpty,
                  let text = String(data: availableData, encoding: .utf8) else { return }
            
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}") else { continue }
                if let data = trimmed.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let percent = json["percent"] as? Double {
                        Task { @MainActor in
                            self?.scanProgress = percent / 100.0
                            self?.statusMessage = "Scanning: \(Int(percent))%"
                        }
                    } else if let event = json["event"] as? String, event == "cancelled" {
                        Task { @MainActor in
                            self?.statusMessage = "Scan cancelled. Scanner carriage parked."
                            self?.isScanning = false
                        }
                    }
                }
            }
        }
        
        Task.detached {
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                await MainActor.run {
                    self.statusMessage = "Scan error: \(error.localizedDescription)"
                    self.isScanning = false
                }
                return
            }
            
            fileHandle.readabilityHandler = nil
            let success = (process.terminationStatus == 0) && FileManager.default.fileExists(atPath: tempPNG)
            
            await MainActor.run {
                self.isScanning = false
                self.activeProcess = nil
                
                if success, let image = NSImage(contentsOfFile: tempPNG) {
                    self.scanProgress = 1.0
                    
                    // Auto-detect Document Boundary if option is enabled
                    var detectedCrop: CGRect? = nil
                    if self.autoCropToDocument {
                        detectedCrop = DocumentDetector.detectDocumentBounds(image: image)
                        if let crop = detectedCrop {
                            self.isCroppingEnabled = true
                            self.cropRect = crop
                        }
                    }
                    
                    if isPreview {
                        self.previewImage = image
                        self.rawScannedImage = image
                        self.applyAdjustments()
                        if detectedCrop != nil {
                            self.statusMessage = "Overview ready (auto-cropped to document)."
                        } else {
                            self.statusMessage = "Overview ready. Adjust settings and click Scan Document."
                        }
                    } else {
                        var newPage = ScannedPage(rawImage: image, dpi: self.dpi, mode: self.scanMode)
                        newPage.rotationAngle = self.rotationAngle
                        newPage.brightness = self.brightness
                        newPage.contrast = self.contrast
                        newPage.saturation = self.saturation
                        newPage.isCroppingEnabled = self.isCroppingEnabled
                        newPage.cropRect = self.cropRect
                        
                        let crop = self.isCroppingEnabled ? self.cropRect : nil
                        newPage.displayedImage = ImageFilters.processImage(
                            original: image,
                            brightness: self.brightness,
                            contrast: self.contrast,
                            saturation: self.saturation,
                            rotationDegrees: self.rotationAngle,
                            cropNormalizedRect: crop
                        ) ?? image
                        
                        self.pages.append(newPage)
                        self.selectedPageIndex = self.pages.count - 1
                        self.previewImage = nil
                        self.rawScannedImage = image
                        self.displayedImage = newPage.displayedImage
                        self.hasUnsavedScans = true
                        
                        if detectedCrop != nil {
                            self.statusMessage = "Page \(self.pages.count) added (auto-cropped to document)!"
                        } else {
                            self.statusMessage = "Page \(self.pages.count) added! Click 'Save Document' or scan next page."
                        }
                        
                        NSSound(named: "Tink")?.play()
                    }
                } else {
                    self.statusMessage = "Scan cancelled or hardware error."
                }
            }
        }
    }
    
    public func cancelScan() {
        guard isScanning, let proc = activeProcess, proc.isRunning else {
            isScanning = false
            activeProcess = nil
            activeInputPipe = nil
            return
        }
        
        statusMessage = "Cancelling scan & parking scanner..."
        
        // 1. Send CANCEL command on stdin to tell engine to abort hardware
        if let inPipe = activeInputPipe {
            inPipe.fileHandleForWriting.write(Data("CANCEL\n".utf8))
        }
        
        // 2. Also send SIGINT (Ctrl+C) to trigger signal handler in engine
        proc.interrupt()
        
        // 3. Gracefully wait up to 6 seconds for engine to abort hardware and exit
        let p = proc
        Task.detached {
            var checks = 0
            while p.isRunning && checks < 60 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                checks += 1
            }
            if p.isRunning {
                p.terminate() // SIGTERM fallback if still running after 6s
            }
            await MainActor.run {
                self.isScanning = false
                self.statusMessage = "Scan cancelled. Scanner carriage parked."
                self.activeProcess = nil
                self.activeInputPipe = nil
            }
        }
    }
    
    public func selectPage(at index: Int) {
        guard index >= 0, index < pages.count else { return }
        selectedPageIndex = index
        let p = pages[index]
        isSyncingPage = true
        brightness = p.brightness
        contrast = p.contrast
        saturation = p.saturation
        rotationAngle = p.rotationAngle
        isCroppingEnabled = p.isCroppingEnabled
        cropRect = p.cropRect
        rawScannedImage = p.rawImage
        displayedImage = p.displayedImage
        isSyncingPage = false
    }
    
    public func deletePage(at index: Int) {
        guard index >= 0, index < pages.count else { return }
        pages.remove(at: index)
        if pages.isEmpty {
            selectedPageIndex = 0
            rawScannedImage = previewImage
            displayedImage = previewImage
            hasUnsavedScans = false
            statusMessage = "All pages removed."
        } else {
            let newIndex = min(index, pages.count - 1)
            selectPage(at: newIndex)
            statusMessage = "Page \(index + 1) removed. (\(pages.count) \(pages.count == 1 ? "page" : "pages") remaining)"
        }
    }
    
    public func clearAllPages() {
        pages.removeAll()
        selectedPageIndex = 0
        rawScannedImage = nil
        displayedImage = nil
        previewImage = nil
        hasUnsavedScans = false
        statusMessage = "Ready"
        resetAdjustments()
    }
    
    public func applyAdjustments() {
        if isSyncingPage { return }
        
        if !pages.isEmpty, selectedPageIndex >= 0, selectedPageIndex < pages.count {
            var page = pages[selectedPageIndex]
            page.brightness = brightness
            page.contrast = contrast
            page.saturation = saturation
            page.rotationAngle = rotationAngle
            page.isCroppingEnabled = isCroppingEnabled
            page.cropRect = cropRect
            
            let crop = isCroppingEnabled ? cropRect : nil
            page.displayedImage = ImageFilters.processImage(
                original: page.rawImage,
                brightness: brightness,
                contrast: contrast,
                saturation: saturation,
                rotationDegrees: rotationAngle,
                cropNormalizedRect: crop
            ) ?? page.rawImage
            
            pages[selectedPageIndex] = page
            displayedImage = page.displayedImage
        } else if let raw = previewImage ?? rawScannedImage {
            let crop = isCroppingEnabled ? cropRect : nil
            displayedImage = ImageFilters.processImage(
                original: raw,
                brightness: brightness,
                contrast: contrast,
                saturation: saturation,
                rotationDegrees: rotationAngle,
                cropNormalizedRect: crop
            )
        } else {
            displayedImage = nil
        }
    }
    
    public func autoDetectAndCropCurrent() {
        let targetImg: NSImage?
        if !pages.isEmpty && selectedPageIndex >= 0 && selectedPageIndex < pages.count {
            targetImg = pages[selectedPageIndex].rawImage
        } else {
            targetImg = rawScannedImage ?? previewImage
        }
        
        guard let img = targetImg else {
            statusMessage = "No scanned image to detect document on."
            return
        }
        
        if let detected = DocumentDetector.detectDocumentBounds(image: img) {
            isCroppingEnabled = true
            cropRect = detected
            applyAdjustments()
            statusMessage = "Document detected & auto-cropped!"
            NSSound(named: "Tink")?.play()
        } else {
            statusMessage = "Document fills flatbed (no cropping needed)."
        }
    }
    
    public func resetCrop() {
        isCroppingEnabled = false
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        applyAdjustments()
        statusMessage = "Crop reverted to full flatbed."
    }
    
    public func resetAdjustments() {
        brightness = 0.0
        contrast = 1.0
        saturation = 1.0
        rotationAngle = 0
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        isCroppingEnabled = false
        applyAdjustments()
    }
    
    public func rotateLeft() {
        rotationAngle = (rotationAngle - 90 + 360) % 360
        applyAdjustments()
    }
    
    public func rotateRight() {
        rotationAngle = (rotationAngle + 90) % 360
        applyAdjustments()
    }
    
    public func saveDocuments() {
        guard !pages.isEmpty else {
            statusMessage = "No pages to save. Scan a document first."
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let baseName = "\(filePrefix)_\(timestamp)"
        let ext = outputFormat.fileExtension
        
        do {
            if outputFormat == .pdf {
                // Multi-page PDF: combine all pages into 1 single PDF
                let targetURL = outputFolder.appendingPathComponent("\(baseName).pdf")
                let pageImages = pages.map { $0.displayedImage }
                try ImageFilters.exportMultiPagePDF(images: pageImages, to: targetURL)
                
                lastSavedURL = targetURL
                lastSavedURLs = [targetURL]
                hasUnsavedScans = false
                statusMessage = "Saved \(pages.count)-page PDF to \(targetURL.lastPathComponent)"
                
                NSSound(named: "Glass")?.play()
                if autoOpenInPreview {
                    NSWorkspace.shared.open(targetURL)
                }
                if revealInFinder {
                    NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                }
            } else {
                // Multiple images: all saved into the same outputFolder
                var savedURLs: [URL] = []
                if pages.count == 1 {
                    let targetURL = outputFolder.appendingPathComponent("\(baseName).\(ext)")
                    try ImageFilters.exportImage(image: pages[0].displayedImage, to: targetURL, format: ext, dpi: pages[0].scanDPI)
                    savedURLs.append(targetURL)
                } else {
                    for (index, page) in pages.enumerated() {
                        let pageFileName = "\(baseName)_Page_\(index + 1).\(ext)"
                        let targetURL = outputFolder.appendingPathComponent(pageFileName)
                        try ImageFilters.exportImage(image: page.displayedImage, to: targetURL, format: ext, dpi: page.scanDPI)
                        savedURLs.append(targetURL)
                    }
                }
                
                lastSavedURL = savedURLs.first
                lastSavedURLs = savedURLs
                hasUnsavedScans = false
                statusMessage = "Saved \(pages.count) \(outputFormat.rawValue) \(pages.count == 1 ? "image" : "images") to \(outputFolder.lastPathComponent)/"
                
                NSSound(named: "Glass")?.play()
                if autoOpenInPreview, let first = savedURLs.first {
                    NSWorkspace.shared.open(first)
                }
                if revealInFinder, let first = savedURLs.first {
                    NSWorkspace.shared.activateFileViewerSelecting([first])
                }
            }
        } catch {
            statusMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
