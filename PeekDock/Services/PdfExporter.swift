import Foundation
import AppKit
import PDFKit
import os.log

private let logger = Logger(subsystem: "dev.kemnix.peekdock", category: "PdfExporter")

final class PdfExporter {
    static func export(slides: [SlideItem], format: ExportFormat, destination: URL) throws {
        let selectedSlides = slides.filter { $0.isSelected }
        guard !selectedSlides.isEmpty else {
            throw ExportError.noSlidesSelected
        }

        let outputDirectory = destination
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        switch format {
        case .separatePngs:
            try exportSeparatePngs(slides: selectedSlides, destination: outputDirectory)
        case .combinedPdf:
            try exportCombinedPdf(slides: selectedSlides, destination: outputDirectory)
        }
    }

    private static func exportSeparatePngs(slides: [SlideItem], destination: URL) throws {
        let folderName = String(format: "slides_%@", timestamp())
        let folderURL = destination.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        for (index, slide) in slides.enumerated() {
            let fileName = String(format: "slide_%03d.png", index + 1)
            let fileURL = folderURL.appendingPathComponent(fileName)

            let rep = NSBitmapImageRep(cgImage: slide.image)
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                throw ExportError.pdfCreationFailed
            }

            try pngData.write(to: fileURL)
            logger.info("Exported: \(fileName)")
        }
    }

    private static func exportCombinedPdf(slides: [SlideItem], destination: URL) throws {
        let fileName = String(format: "slides_%@.pdf", timestamp())
        let fileURL = destination.appendingPathComponent(fileName)

        // Create a mutable PDF document
        let mutablePdf = PDFDocument()

        // Add all slides as pages
        for slide in slides {
            let pdfData = try createPdfData(from: slide.image)
            if let pdfDocument = PDFDocument(data: pdfData),
               let page = pdfDocument.page(at: 0) {
                mutablePdf.insert(page, at: mutablePdf.pageCount)
            }
        }

        guard let finalData = mutablePdf.dataRepresentation() else {
            throw ExportError.pdfCreationFailed
        }

        try finalData.write(to: fileURL)
        logger.info("Exported combined PDF: \(fileName)")
    }

    private static func createPdfData(from image: CGImage) throws -> Data {
        // Create NSImage from CGImage
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        // Create PDF page from image
        guard let pdfPage = PDFPage(image: nsImage) else {
            throw ExportError.pdfCreationFailed
        }

        let pdfDocument = PDFDocument()
        pdfDocument.insert(pdfPage, at: 0)

        guard let finalData = pdfDocument.dataRepresentation() else {
            throw ExportError.pdfCreationFailed
        }

        return finalData
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter.string(from: Date())
    }
}

enum ExportError: LocalizedError {
    case noSlidesSelected
    case pdfCreationFailed

    var errorDescription: String? {
        switch self {
        case .noSlidesSelected: MainActor.assumeIsolated { LocalizationManager.shared.t("error.noSlidesSelected") }
        case .pdfCreationFailed: MainActor.assumeIsolated { LocalizationManager.shared.t("error.pdfCreationFailed") }
        }
    }
}
