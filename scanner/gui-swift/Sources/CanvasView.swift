import SwiftUI
import AppKit

public struct CanvasView: View {
    @ObservedObject var vm: ScannerViewModel
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background surface
                Color(NSColor.underPageBackgroundColor)
                    .ignoresSafeArea()
                
                if let image = vm.displayedImage ?? vm.rawScannedImage {
                    // Document Display
                    VStack {
                        Spacer()
                        
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(vm.zoomScale)
                            .offset(x: vm.accumulatedOffset.width + vm.dragOffset.width,
                                    y: vm.accumulatedOffset.height + vm.dragOffset.height)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if vm.zoomScale > 1.05 {
                                            vm.dragOffset = value.translation
                                        }
                                    }
                                    .onEnded { value in
                                        if vm.zoomScale > 1.05 {
                                            vm.accumulatedOffset.width += value.translation.width
                                            vm.accumulatedOffset.height += value.translation.height
                                            vm.dragOffset = .zero
                                        }
                                    }
                            )
                            .shadow(color: Color.black.opacity(0.22), radius: 16, x: 0, y: 8)
                            .padding(.top, 40)
                            .padding(.bottom, vm.pages.isEmpty ? 40 : 100)
                            .padding(.horizontal, 32)
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Floating Top Control Bar (Zoom Controls on Left, Document Info on Right)
                    VStack {
                        HStack(alignment: .center) {
                            // Top-Left: Zoom & View Controls
                            HStack(spacing: 5) {
                                Button(action: {
                                    withAnimation(.spring()) {
                                        vm.zoomScale = max(0.25, vm.zoomScale - 0.25)
                                    }
                                }) {
                                    Image(systemName: "minus.magnifyingglass")
                                        .font(.system(size: 11))
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("Zoom out (Cmd -)")
                                
                                Text("\(Int(vm.zoomScale * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 40)
                                
                                Button(action: {
                                    withAnimation(.spring()) {
                                        vm.zoomScale = min(3.0, vm.zoomScale + 0.25)
                                    }
                                }) {
                                    Image(systemName: "plus.magnifyingglass")
                                        .font(.system(size: 11))
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("Zoom in (Cmd +)")
                                
                                Divider().frame(height: 14)
                                
                                Button(action: {
                                    withAnimation(.spring()) {
                                        vm.zoomScale = 1.0
                                        vm.accumulatedOffset = .zero
                                        vm.dragOffset = .zero
                                    }
                                }) {
                                    Text("Fit")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 4)
                                        .frame(height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("Fit to window (Cmd 0)")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(18)
                            .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
                            
                            Spacer()
                            
                            // Top-Right: Document Metadata Pill
                            HStack(spacing: 8) {
                                Image(systemName: "doc.viewfinder")
                                    .foregroundColor(.secondary)
                                
                                if !vm.pages.isEmpty {
                                    Text("Page \(vm.selectedPageIndex + 1) of \(vm.pages.count)")
                                        .font(.caption.weight(.semibold))
                                    Text("•")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Overview Preview")
                                        .font(.caption.weight(.semibold))
                                    Text("•")
                                        .foregroundColor(.secondary)
                                }
                                
                                Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
                                    .font(.caption.monospacedDigit())
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text("\(vm.dpi) DPI")
                                    .font(.caption)
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(vm.scanMode.displayName)
                                    .font(.caption)
                                
                                if vm.isCroppingEnabled {
                                    Text("•")
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 3) {
                                        Image(systemName: "crop")
                                            .font(.caption2)
                                        Text("Auto-Cropped")
                                            .font(.caption2.weight(.medium))
                                    }
                                    .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(18)
                            .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        
                        Spacer()
                    }
                    
                    // Floating Multi-Page Thumbnail Strip & Navigation (Bottom Center)
                    if !vm.pages.isEmpty {
                        VStack {
                            Spacer()
                            
                            HStack(spacing: 8) {
                                // Previous page button
                                Button(action: {
                                    if vm.selectedPageIndex > 0 {
                                        vm.selectPage(at: vm.selectedPageIndex - 1)
                                    }
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 26, height: 26)
                                }
                                .buttonStyle(.plain)
                                .disabled(vm.selectedPageIndex == 0)
                                .opacity(vm.selectedPageIndex == 0 ? 0.35 : 1.0)
                                .help("Previous page")
                                
                                // Thumbnails list
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(vm.pages.enumerated()), id: \.element.id) { idx, page in
                                            Button(action: { vm.selectPage(at: idx) }) {
                                                ZStack(alignment: .topTrailing) {
                                                    Image(nsImage: page.displayedImage)
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fit)
                                                        .frame(width: 40, height: 54)
                                                        .background(Color.white)
                                                        .cornerRadius(4)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 4)
                                                                .strokeBorder(idx == vm.selectedPageIndex ? Color.accentColor : Color.secondary.opacity(0.25),
                                                                              lineWidth: idx == vm.selectedPageIndex ? 2.5 : 1)
                                                        )
                                                        .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
                                                    
                                                    // Page number badge
                                                    Text("\(idx + 1)")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .padding(.horizontal, 3)
                                                        .padding(.vertical, 1)
                                                        .background(idx == vm.selectedPageIndex ? Color.accentColor : Color.black.opacity(0.65))
                                                        .cornerRadius(3)
                                                        .padding(2)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                            .help("Select page \(idx + 1)")
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                                .frame(maxWidth: 280)
                                
                                // Next page button
                                Button(action: {
                                    if vm.selectedPageIndex < vm.pages.count - 1 {
                                        vm.selectPage(at: vm.selectedPageIndex + 1)
                                    }
                                }) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .frame(width: 26, height: 26)
                                }
                                .buttonStyle(.plain)
                                .disabled(vm.selectedPageIndex >= vm.pages.count - 1)
                                .opacity(vm.selectedPageIndex >= vm.pages.count - 1 ? 0.35 : 1.0)
                                .help("Next page")
                                
                                Divider().frame(height: 24)
                                
                                // Delete page
                                Button(action: { vm.deletePage(at: vm.selectedPageIndex) }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                        .foregroundColor(.red.opacity(0.85))
                                        .frame(width: 26, height: 26)
                                }
                                .buttonStyle(.plain)
                                .help("Delete this page")
                                
                                // Add/Scan Next Page
                                Button(action: { vm.startScan(isPreview: false) }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.accentColor)
                                        Text("Add Page")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.12))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                                .disabled(vm.isScanning)
                                .help("Scan next page and append to this document")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(24)
                            .shadow(color: Color.black.opacity(0.15), radius: 8, y: 3)
                            .padding(.bottom, 20)
                        }
                    }
                    
                } else {
                    // Empty State: Scanner Flatbed Glass Representation
                    VStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .frame(width: 280, height: 380)
                                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
                            
                            // Glass bed effect
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                                .frame(width: 260, height: 360)
                            
                            VStack(spacing: 14) {
                                Image(systemName: "scanner")
                                    .font(.system(size: 54, weight: .light))
                                    .foregroundColor(.accentColor)
                                
                                Text("No Document Scanned")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Place a document on the flatbed\nand click Scan Document or Overview")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: 220)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
