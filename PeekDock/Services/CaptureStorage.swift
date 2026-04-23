import AppKit
import os.log

private let logger = Logger(subsystem: "dev.kemnix.peekdock", category: "Storage")

final class CaptureStorage {
    private let tempDirectory: URL
    private var sessionDirectory: URL?
    private var slideCount = 0

    init() {
        let tempDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents")
            .appendingPathComponent("PeekDock")
            .appendingPathComponent("temp")
        self.tempDirectory = tempDir

        // Create temp directory if it doesn't exist
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    func startSession() throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        let dirName = formatter.string(from: Date())

        let dir = tempDirectory.appendingPathComponent(dirName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        sessionDirectory = dir
        slideCount = 0
        logger.info("Session started: \(dir.path)")
        return dir.path
    }

    func save(image: CGImage) throws -> URL {
        guard let dir = sessionDirectory else {
            throw StorageError.noActiveSession
        }

        slideCount += 1
        let fileName = String(format: "slide_%03d.png", slideCount)
        let fileURL = dir.appendingPathComponent(fileName)

        let rep = NSBitmapImageRep(cgImage: image)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw StorageError.encodingFailed
        }

        try pngData.write(to: fileURL)
        logger.info("Saved: \(fileName)")
        return fileURL
    }

    func endSession() {
        sessionDirectory = nil
        slideCount = 0
        logger.info("Session ended")
    }

    func cleanupSession(at path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.removeItem(at: url)
            logger.info("Cleaned up session directory: \(url.path)")
        } catch {
            logger.error("Failed to cleanup session directory: \(error.localizedDescription)")
        }
    }

    var currentSlideCount: Int { slideCount }
}

enum StorageError: LocalizedError {
    case noActiveSession
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noActiveSession: "No active capture session"
        case .encodingFailed: "Failed to encode image as PNG"
        }
    }
}
