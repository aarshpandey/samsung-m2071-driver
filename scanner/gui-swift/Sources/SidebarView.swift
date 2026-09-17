import SwiftUI
import AppKit

public struct SidebarView: View {
    @ObservedObject var vm: ScannerViewModel
    
    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    
                    // MARK: - 1. Scanner Connection
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Scanner Device", systemImage: "scanner")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("USB")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                        }
                        
                        // Status badge
                        HStack(spacing: 6) {
                            Circle()
                                .fill(vm.isConnected ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            
                            Text(vm.connectionStatusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: { vm.checkConnection() }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help("Refresh connection status")
                        }
                        .padding(.vertical, 2)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    
                    // MARK: - 2. Scan Preset & Mode
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Scan Settings", systemImage: "slider.horizontal.3")
                            .font(.headline)
                        
                        // Color Mode Picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Color Mode")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $vm.scanMode) {
                                ForEach(ScanMode.allCases) { mode in
                                    Label(mode.displayName, systemImage: mode.iconName)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        
                        // Resolution Picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resolution (DPI)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $vm.dpi) {
                                Text("75 DPI — Draft / Fast Preview").tag(75)
                                Text("150 DPI — Standard Web / Fast").tag(150)
                                Text("300 DPI — Document (Recommended)").tag(300)
                                Text("600 DPI — High Quality / Photo").tag(600)
                                Text("1200 DPI — Ultra High Resolution").tag(1200)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        
                        // Page Size
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Page Size")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $vm.pageSize) {
                                ForEach(PageSize.allCases) { size in
                                    Text(size.rawValue).tag(size)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        // Auto-Crop to Document Toggle
                        Toggle(isOn: $vm.autoCropToDocument) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Image(systemName: "crop")
                                        .foregroundColor(.accentColor)
                                    Text("Auto-Crop to Document")
                                        .font(.subheadline.weight(.medium))
                                }
                                Text("Detect document boundary & crop empty glass")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    
                    // MARK: - 3. Image Enhancements
                    DisclosureGroup(isExpanded: $vm.showEnhancements) {
                        VStack(spacing: 12) {
                            // Brightness
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Brightness")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(vm.brightness * 100))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $vm.brightness, in: -0.5...0.5)
                            }
                            
                            // Contrast
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Contrast")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1fx", vm.contrast))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $vm.contrast, in: 0.5...1.8)
                            }
                            
                            // Saturation (if color)
                            if vm.scanMode == .color {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Saturation")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(String(format: "%.1fx", vm.saturation))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $vm.saturation, in: 0.0...2.0)
                                }
                            }
                            
                            // Rotation & Crop Toggles
                            HStack {
                                Button(action: { vm.rotateLeft() }) {
                                    Label("90° Left", systemImage: "rotate.left")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                
                                Button(action: { vm.rotateRight() }) {
                                    Label("90° Right", systemImage: "rotate.right")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                
                                Spacer()
                                
                                Button(action: { vm.resetAdjustments() }) {
                                    Text("Reset")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                            .padding(.top, 4)
                            
                            // Auto-Crop / Boundary Detection Controls
                            HStack(spacing: 8) {
                                Button(action: { vm.autoDetectAndCropCurrent() }) {
                                    Label(vm.isCroppingEnabled ? "Re-detect Bounds" : "Auto-Crop Document",
                                          systemImage: "viewfinder")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(vm.pages.isEmpty && vm.previewImage == nil)
                                
                                if vm.isCroppingEnabled {
                                    Button(action: { vm.resetCrop() }) {
                                        Text("Revert Full Bed")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.orange)
                                    .help("Revert to uncropped flatbed scan")
                                }
                                
                                Spacer()
                            }
                            .padding(.top, 2)
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("Image Enhancements", systemImage: "wand.and.stars")
                            .font(.headline)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    
                    // MARK: - 4. Destination & File Name
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Save Destination", systemImage: "folder")
                            .font(.headline)
                        
                        // Output Format
                        VStack(alignment: .leading, spacing: 4) {
                            Text("File Format")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $vm.outputFormat) {
                                ForEach(OutputFormat.allCases) { fmt in
                                    Text(fmt.rawValue).tag(fmt)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            
                            if vm.outputFormat == .pdf {
                                Text(vm.pages.count > 1 ? "✓ All \(vm.pages.count) scanned pages will be saved into 1 multi-page PDF" : "Combines scanned pages into a single PDF document")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 1)
                            } else {
                                Text(vm.pages.count > 1 ? "✓ Saves \(vm.pages.count) individual images into this folder" : "Saves document as an image file")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 1)
                            }
                        }
                        
                        // Destination Folder
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Save To")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.accentColor)
                                Text(vm.outputFolder.lastPathComponent)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Choose...") {
                                    selectFolder()
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                        }
                        
                        // File prefix
                        VStack(alignment: .leading, spacing: 4) {
                            Text("File Name Prefix")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Prefix", text: $vm.filePrefix)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        // Automation checkboxes
                        Toggle("Open in Apple Preview automatically", isOn: $vm.autoOpenInPreview)
                            .font(.caption)
                        Toggle("Reveal in Finder after saving", isOn: $vm.revealInFinder)
                            .font(.caption)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
                .padding(14)
            }
            
            Divider()
            
            // MARK: - 5. Bottom Action Bar
            VStack(spacing: 10) {
                // Progress Bar (Active during scan)
                if vm.isScanning {
                    VStack(spacing: 4) {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(vm.statusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(vm.scanProgress * 100))%")
                                .font(.caption.monospacedDigit())
                        }
                        ProgressView(value: vm.scanProgress, total: 1.0)
                            .progressViewStyle(.linear)
                    }
                    .padding(.horizontal, 4)
                } else {
                    HStack {
                        Image(systemName: vm.hasUnsavedScans ? "exclamationmark.circle.fill" : "info.circle")
                            .font(.caption)
                            .foregroundColor(vm.hasUnsavedScans ? .orange : .secondary)
                        Text(vm.statusMessage)
                            .font(.caption)
                            .foregroundColor(vm.hasUnsavedScans ? .primary : .secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
                
                // Action Buttons
                VStack(spacing: 8) {
                    if vm.isScanning {
                        Button(action: { vm.cancelScan() }) {
                            Label("Cancel Scan", systemImage: "xmark.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        // Top Scan Row
                        HStack(spacing: 10) {
                            Button(action: { vm.startScan(isPreview: true) }) {
                                Label("Overview", systemImage: "eye")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .help("Scan quick low-resolution overview (Cmd+P)")
                            .keyboardShortcut("p", modifiers: .command)
                            
                            Button(action: { vm.startScan(isPreview: false) }) {
                                Label(vm.pages.isEmpty ? "Scan Document" : "Scan Next Page",
                                      systemImage: vm.pages.isEmpty ? "scanner.fill" : "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .help(vm.pages.isEmpty ? "Scan document at selected DPI (Cmd+N)" : "Scan next page and append to document (Cmd+N)")
                            .keyboardShortcut("n", modifiers: .command)
                        }
                        
                        // Bottom Save Row (prominent save button)
                        HStack(spacing: 8) {
                            Button(action: { vm.saveDocuments() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.down.fill")
                                    if vm.pages.isEmpty {
                                        Text("Save Document")
                                    } else if vm.outputFormat == .pdf {
                                        Text("Save PDF (\(vm.pages.count) \(vm.pages.count == 1 ? "page" : "pages"))")
                                    } else {
                                        Text("Save \(vm.pages.count) \(vm.outputFormat.rawValue) \(vm.pages.count == 1 ? "Image" : "Images")")
                                    }
                                }
                                .font(.headline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(vm.hasUnsavedScans ? .accentColor : .secondary)
                            .disabled(vm.pages.isEmpty)
                            .help("Save scanned pages to destination folder (Cmd+S)")
                            .keyboardShortcut("s", modifiers: .command)
                            
                            if !vm.pages.isEmpty {
                                Button(action: { vm.clearAllPages() }) {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                        .padding(.vertical, 7)
                                        .padding(.horizontal, 10)
                                }
                                .buttonStyle(.bordered)
                                .foregroundColor(.red.opacity(0.85))
                                .help("Clear all scanned pages and start fresh")
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Folder"
        if panel.runModal() == .OK, let url = panel.url {
            vm.outputFolder = url
        }
    }
}
