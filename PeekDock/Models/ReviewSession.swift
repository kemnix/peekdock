import Foundation
import AppKit

@Observable
final class ReviewSession: ObservableObject {
    var slides: [SlideItem] = []
    var selectedIndex: Int?
    var exportFormat: ExportFormat = .separatePngs
    var destinationDirectory: URL?

    var selectedSlides: [SlideItem] {
        slides.filter { $0.isSelected }
    }

    func loadSlides(from directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])

        slides = try files
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> SlideItem? in
                guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    return nil
                }
                return SlideItem(id: UUID(), image: cgImage, isSelected: true, originalPath: url)
            }

        if !slides.isEmpty {
            selectedIndex = 0
        }
    }

    func moveSlide(from source: IndexSet, to destination: Int) {
        slides.move(fromOffsets: source, toOffset: destination)
    }

    func toggleSelection(at index: Int) {
        guard index < slides.count else { return }
        slides[index].isSelected.toggle()
    }

    func removeSlide(at index: Int) {
        slides.remove(at: index)
        if let selected = selectedIndex, selected >= slides.count {
            selectedIndex = slides.isEmpty ? nil : slides.count - 1
        }
    }
}

struct SlideItem: Identifiable {
    let id: UUID
    let image: CGImage
    var isSelected: Bool
    let originalPath: URL
}

enum ExportFormat {
    case separatePngs
    case combinedPdf

    var displayName: String {
        switch self {
        case .separatePngs: return "Separate PNGs"
        case .combinedPdf: return "Combined PDF"
        }
    }
}
