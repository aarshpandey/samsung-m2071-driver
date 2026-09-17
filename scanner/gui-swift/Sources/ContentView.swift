import SwiftUI
import AppKit

public struct ContentView: View {
    @StateObject private var vm = ScannerViewModel()
    
    public var body: some View {
        HStack(spacing: 0) {
            // Main Document Preview Stage (Left / Center)
            CanvasView(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Scanner Controls & Presets Sidebar (Right)
            SidebarView(vm: vm)
                .frame(width: 350)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Connection status
                Button(action: { vm.checkConnection() }) {
                    Label("Check Status", systemImage: "arrow.clockwise")
                }
                .help("Refresh scanner connection status")
                
                Divider()
                
                // Add Page
                Button(action: { vm.startScan(isPreview: false) }) {
                    Label(vm.pages.isEmpty ? "Scan Document" : "Add Page",
                          systemImage: vm.pages.isEmpty ? "scanner" : "plus.circle")
                }
                .help("Scan page and append to document")
                .disabled(vm.isScanning)
                
                // Rotate tools
                Button(action: { vm.rotateLeft() }) {
                    Label("Rotate Left", systemImage: "rotate.left")
                }
                .help("Rotate current page 90° counter-clockwise")
                .disabled(vm.pages.isEmpty && vm.previewImage == nil)
                
                Button(action: { vm.rotateRight() }) {
                    Label("Rotate Right", systemImage: "rotate.right")
                }
                .help("Rotate current page 90° clockwise")
                .disabled(vm.pages.isEmpty && vm.previewImage == nil)
                
                // Auto-Crop button
                Button(action: {
                    if vm.isCroppingEnabled {
                        vm.resetCrop()
                    } else {
                        vm.autoDetectAndCropCurrent()
                    }
                }) {
                    Label(vm.isCroppingEnabled ? "Revert Crop" : "Auto-Crop",
                          systemImage: vm.isCroppingEnabled ? "crop.rotate" : "crop")
                }
                .help(vm.isCroppingEnabled ? "Revert to full flatbed scan" : "Detect document boundary and crop glass edges")
                .disabled(vm.pages.isEmpty && vm.previewImage == nil)
                
                // Delete Page
                if !vm.pages.isEmpty {
                    Button(action: { vm.deletePage(at: vm.selectedPageIndex) }) {
                        Label("Delete Page", systemImage: "trash")
                    }
                    .help("Delete currently selected page")
                }
                
                Divider()
                
                // Save Button
                Button(action: { vm.saveDocuments() }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .help("Save document to chosen folder")
                .disabled(vm.pages.isEmpty)
                
                // Open in Preview if saved
                if let lastURL = vm.lastSavedURL {
                    Button(action: {
                        NSWorkspace.shared.open(lastURL)
                    }) {
                        Label("Open in Preview", systemImage: "arrow.up.forward.app")
                    }
                    .help("Open last saved document in Preview")
                }
            }
        }
    }
}
