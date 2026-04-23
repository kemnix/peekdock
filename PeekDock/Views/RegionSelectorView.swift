import SwiftUI
import AppKit

/// Full-window overlay showing a Zoom screenshot. User drags to select a crop region.
struct RegionSelectorView: View {
    let snapshot: NSImage
    let zoomWindowSize: CGSize?  // Zoomウィンドウの実際のサイズ
    let onConfirm: (CGRect) -> Void  // normalized rect (0–1)
    let onCancel: () -> Void
    @Environment(LocalizationManager.self) private var l10n

    @State private var selection: SelectionRegion?
    @State private var dragStart: CGPoint?  // ドラッグ開始時のマウス位置
    @State private var dragCurrent: CGPoint?  // 現在のマウス位置
    @State private var resizeHandle: ResizeHandle?
    @State private var selectionStartOrigin: CGPoint?  // 選択範囲の初期位置

    struct SelectionRegion {
        var rect: CGRect
        var isDragging: Bool = false
        var isResizing: Bool = false
    }

    enum ResizeHandle {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private var currentRect: CGRect? {
        if let selection = selection {
            return selection.rect
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Zoom screenshot as background
                Image(nsImage: snapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Dim everything outside selection
                if let rect = currentRect {
                    // Dark overlay with cutout
                    Rectangle()
                        .fill(.black.opacity(0.5))
                        .reverseMask {
                            Rectangle()
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }

                    // Selection border
                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)

                    // Resize handles
                    resizeHandles(for: rect)
                }

                // Instructions
                VStack {
                    Text(currentRect == nil
                         ? l10n.t("region.instructions.initial")
                         : l10n.t("region.instructions.active"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(.top, 20)
                    Spacer()
                }

                // Confirm / Cancel buttons (always visible)
                VStack {
                    Spacer()
                    HStack(spacing: 16) {
                        Button(l10n.t("region.cancel")) { onCancel() }
                        Button(l10n.t("region.confirm")) { confirmSelection(in: geo.size) }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value, in: geo.size)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        dragCurrent = nil
                        selectionStartOrigin = nil
                        resizeHandle = nil
                        if var selection = selection {
                            selection.isDragging = false
                            selection.isResizing = false
                            self.selection = selection
                        }
                    }
            )
            // Listen for Enter key from KeyWindow
            .onReceive(NotificationCenter.default.publisher(for: .regionSelectorConfirm)) { _ in
                if currentRect != nil {
                    confirmSelection(in: geo.size)
                }
            }
            .onAppear {
                initializeDefaultSelection(in: geo.size)
            }
            .onChange(of: geo.size) { _, newSize in
                if selection == nil {
                    initializeDefaultSelection(in: newSize)
                }
            }
        }
    }

    private func initializeDefaultSelection(in viewSize: CGSize) {
        let aspectRatio: CGFloat = 16 / 9
        let imageFrame = renderedImageFrame(in: viewSize)
        let width = imageFrame.width * 0.95
        let height = width / aspectRatio
        let x = imageFrame.minX + (imageFrame.width - width) / 2
        let y = imageFrame.minY + (imageFrame.height - height) / 2
        selection = SelectionRegion(rect: CGRect(x: x, y: y, width: width, height: height))
    }

    private func resizeHandles(for rect: CGRect) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 12, height: 12)
                .position(x: rect.minX, y: rect.minY)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 12, height: 12)
                .position(x: rect.maxX, y: rect.minY)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 12, height: 12)
                .position(x: rect.minX, y: rect.maxY)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 12, height: 12)
                .position(x: rect.maxX, y: rect.maxY)
        }
    }

    private func handleDrag(_ value: DragGesture.Value, in viewSize: CGSize) {
        guard selection != nil else { return }

        let location = value.location
        let imageFrame = renderedImageFrame(in: viewSize)

        // Check if we're touching a resize handle or inside the selection
        if let rect = currentRect {
            let handleRadius: CGFloat = 15

            // Only check handles if we haven't already determined drag type
            if resizeHandle == nil && !(selection?.isDragging ?? false) {
                if distance(location, to: CGPoint(x: rect.minX, y: rect.minY)) < handleRadius {
                    resizeHandle = .topLeft
                } else if distance(location, to: CGPoint(x: rect.maxX, y: rect.minY)) < handleRadius {
                    resizeHandle = .topRight
                } else if distance(location, to: CGPoint(x: rect.minX, y: rect.maxY)) < handleRadius {
                    resizeHandle = .bottomLeft
                } else if distance(location, to: CGPoint(x: rect.maxX, y: rect.maxY)) < handleRadius {
                    resizeHandle = .bottomRight
                } else if rect.contains(location) {
                    // Clicking inside the selection - prepare to move
                    dragStart = location
                    selectionStartOrigin = selection!.rect.origin
                    selection!.isDragging = true
                    self.selection = selection!
                    return
                }
            }
        }

        // Handle resize
        if let handle = resizeHandle {
            let rect = selection!.rect
            selection!.isResizing = true

            switch handle {
            case .topLeft:
                let newX = max(imageFrame.minX, location.x)
                let newY = max(imageFrame.minY, location.y)
                let newWidth = rect.maxX - newX
                let newHeight = rect.maxY - newY
                if newWidth > 50 && newHeight > 50 {
                    selection!.rect = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
                }
            case .topRight:
                let newMaxX = min(imageFrame.maxX, location.x)
                let newY = max(imageFrame.minY, location.y)
                let newWidth = newMaxX - rect.minX
                let newHeight = rect.maxY - newY
                if newWidth > 50 && newHeight > 50 {
                    selection!.rect = CGRect(x: rect.minX, y: newY, width: newWidth, height: newHeight)
                }
            case .bottomLeft:
                let newX = max(imageFrame.minX, location.x)
                let newMaxY = min(imageFrame.maxY, location.y)
                let newWidth = rect.maxX - newX
                let newHeight = newMaxY - rect.minY
                if newWidth > 50 && newHeight > 50 {
                    selection!.rect = CGRect(x: newX, y: rect.minY, width: newWidth, height: newHeight)
                }
            case .bottomRight:
                let newMaxX = min(imageFrame.maxX, location.x)
                let newMaxY = min(imageFrame.maxY, location.y)
                let newWidth = newMaxX - rect.minX
                let newHeight = newMaxY - rect.minY
                if newWidth > 50 && newHeight > 50 {
                    selection!.rect = CGRect(x: rect.minX, y: rect.minY, width: newWidth, height: newHeight)
                }
            }

            self.selection = selection!
            return
        }

        // Handle move
        if selection!.isDragging, let start = dragStart, let originalOrigin = selectionStartOrigin {
            let dx = location.x - start.x
            let dy = location.y - start.y

            let newOrigin = CGPoint(
                x: max(imageFrame.minX, min(originalOrigin.x + dx, imageFrame.maxX - selection!.rect.width)),
                y: max(imageFrame.minY, min(originalOrigin.y + dy, imageFrame.maxY - selection!.rect.height))
            )

            selection!.rect = CGRect(
                x: newOrigin.x,
                y: newOrigin.y,
                width: selection!.rect.width,
                height: selection!.rect.height
            )

            self.selection = selection!
        }

        dragCurrent = location
    }

    private func distance(_ p1: CGPoint, to p2: CGPoint) -> CGFloat {
        let dx = p1.x - p2.x
        let dy = p1.y - p2.y
        return sqrt(dx * dx + dy * dy)
    }

    private func renderedImageFrame(in viewSize: CGSize) -> CGRect {
        let imageAspect = snapshot.size.width / snapshot.size.height
        let viewAspect = viewSize.width / viewSize.height
        if imageAspect > viewAspect {
            let w = viewSize.width
            let h = w / imageAspect
            return CGRect(x: 0, y: (viewSize.height - h) / 2, width: w, height: h)
        } else {
            let h = viewSize.height
            let w = h * imageAspect
            return CGRect(x: (viewSize.width - w) / 2, y: 0, width: w, height: h)
        }
    }

    private func confirmSelection(in viewSize: CGSize) {
        guard let rect = currentRect else { return }

        let imageFrame = renderedImageFrame(in: viewSize)
        let renderedOrigin = imageFrame.origin
        let renderedSize = imageFrame.size

        // Clamp selection to rendered image bounds
        let clampedX = max(rect.minX - renderedOrigin.x, 0)
        let clampedY = max(rect.minY - renderedOrigin.y, 0)
        let clampedW = min(rect.width, renderedSize.width - clampedX)
        let clampedH = min(rect.height, renderedSize.height - clampedY)

        // Normalize to 0–1
        let normalized = CGRect(
            x: clampedX / renderedSize.width,
            y: clampedY / renderedSize.height,
            width: clampedW / renderedSize.width,
            height: clampedH / renderedSize.height
        )

        onConfirm(normalized)
    }
}

// MARK: - Reverse mask helper

extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(
            Rectangle()
                .overlay(
                    mask()
                        .blendMode(.destinationOut)
                )
        )
    }
}
