import SwiftUI
import UniformTypeIdentifiers

struct ReviewView: View {
    @Environment(LocalizationManager.self) private var l10n
    @State var session: ReviewSession
    let onSave: (ReviewExportOptions) -> Void
    let onCancel: () -> Void

    @State private var isShowingDirectoryPicker = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Main content
            HSplitView {
                // Left: Slide list
                slideList
                    .frame(minWidth: 150, maxWidth: 220)

                // Right: Preview (larger)
                preview
            }
            .frame(minWidth: 800, minHeight: 500)

            Divider()

            // Bottom: Export options
            exportOptions
                .frame(height: 100)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            isFocused = true
        }
    }

    private var slideList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(l10n.t("review.slides"))
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                Text(l10n.t("review.selectedCount", session.selectedSlides.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(Color.gray.opacity(0.2))

            // Slide thumbnails
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(session.slides.enumerated()), id: \.element.id) { index, slide in
                        SlideThumbnailRow(
                            slide: slide,
                            index: index,
                            isSelected: session.selectedIndex == index
                        )
                        .onTapGesture {
                            session.selectedIndex = index
                            session.toggleSelection(at: index)
                        }
                    }
                }
            }
            .scrollDisabled(session.slides.isEmpty)
        }
        .background(Color.black)
    }

    private var preview: some View {
        ZStack {
                if let selectedIndex = session.selectedIndex,
                   selectedIndex < session.slides.count {
                    let slide = session.slides[selectedIndex]
                    let image = NSImage(cgImage: slide.image, size: NSSize(width: slide.image.width, height: slide.image.height))

                    GeometryReader { geometry in
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                    }
                } else {
                    Text(session.slides.isEmpty ? l10n.t("review.empty") : l10n.t("review.selectToPreview"))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.6))
    }

    private var exportOptions: some View {
        HStack(alignment: .bottom, spacing: 32) {
            // Export format
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("review.exportFormat"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))

                Picker("", selection: $session.exportFormat) {
                    Text(l10n.t("review.format.separatePngs")).tag(ExportFormat.separatePngs)
                    Text(l10n.t("review.format.combinedPdf")).tag(ExportFormat.combinedPdf)
                }
                .pickerStyle(.menu)
                .tint(Color.accentColor)
                .frame(width: 180)
            }

            // Destination
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("review.saveLocation"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 10) {
                    Text(session.destinationDirectory?.lastPathComponent ?? l10n.t("review.selectFolder"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 240, alignment: .leading)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    Button(l10n.t("button.choose")) {
                        isShowingDirectoryPicker = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 16) {
                Button(l10n.t("button.cancel"), action: onCancel)
                    .buttonStyle(.bordered)
                    .foregroundStyle(.white.opacity(0.6))
                    .controlSize(.regular)

                Button(l10n.t("button.save")) {
                    guard let destination = session.destinationDirectory else { return }
                    let options = ReviewExportOptions(
                        slides: session.selectedSlides,
                        format: session.exportFormat,
                        destination: destination
                    )
                    onSave(options)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(session.selectedSlides.isEmpty || session.destinationDirectory == nil)
                .opacity(session.selectedSlides.isEmpty || session.destinationDirectory == nil ? 0.5 : 1.0)
                .controlSize(.regular)
            }
        }
        .fileImporter(
            isPresented: $isShowingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    session.destinationDirectory = url
                }
            case .failure(let error):
                print("Directory selection failed: \(error)")
            }
        }
    }
}

struct SlideThumbnailRow: View {
    @Environment(LocalizationManager.self) private var l10n
    let slide: SlideItem
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Button(action: {}) {
                Image(systemName: slide.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(slide.isSelected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(l10n.t("review.spaceToToggle"))
            .controlSize(.small)

            // Thumbnail
            let image = NSImage(cgImage: slide.image, size: NSSize(width: slide.image.width, height: slide.image.height))
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .opacity(slide.isSelected ? 1.0 : 0.4)

            // Index
            Text("\(index + 1)")
                .font(.caption)
                .foregroundStyle(.white.opacity(slide.isSelected ? 1.0 : 0.5))
                .frame(width: 20)

            Spacer()
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
}

extension Notification.Name {
    static let toggleSelection = Notification.Name("toggleSelection")
}

// Handle keyboard shortcuts
extension ReviewView {
    func handleKeyPress(_ key: String) {
        guard let selectedIndex = session.selectedIndex else { return }

        switch key {
        case " ":
            session.toggleSelection(at: selectedIndex)
            NotificationCenter.default.post(name: .toggleSelection, object: nil)
        case "\u{F700}", "\u{F702}": // Up Arrow, Left Arrow
            if selectedIndex > 0 {
                session.selectedIndex = selectedIndex - 1
            }
        case "\u{F701}", "\u{F703}": // Down Arrow, Right Arrow
            if selectedIndex < session.slides.count - 1 {
                session.selectedIndex = selectedIndex + 1
            }
        default:
            break
        }
    }
}
