import CryptoKit
import SwiftUI
import UIKit

struct StoryAsset: Identifiable {
    let id: String
    let timestamp: Date
    let isVideo: Bool
}

/// Photos taken with the in-app camera during a night. They live only on this
/// device, in Application Support, one folder per night, and are never read from
/// or written to the user's photo library. The file name carries the moment the
/// photo was taken (milliseconds since 1970), which is what places it on the
/// night's BAC timeline.
nonisolated enum NightPhotoStore {
    static func assets(eventId: String) -> [StoryAsset] {
        let folder = folder(eventId: eventId)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name -> StoryAsset? in
            guard name.hasSuffix(".jpg"),
                  let millis = name.split(separator: "-").first.flatMap({ Double($0) }) else { return nil }
            return StoryAsset(id: id(eventId: eventId, name: name),
                              timestamp: Date(timeIntervalSince1970: millis / 1000), isVideo: false)
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    static func hasMedia(eventId: String) -> Bool { !assets(eventId: eventId).isEmpty }

    /// Saves a photo just taken for this night. Returns the new asset, or nil if
    /// the file could not be written.
    @discardableResult
    static func save(_ image: UIImage, eventId: String, takenAt date: Date = .now) -> StoryAsset? {
        let folder = folder(eventId: eventId)
        let files = FileManager.default
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var root = rootFolder
            try? root.setResourceValues(values)
            let name = "\(Int64(date.timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).jpg"
            guard let data = resized(image, maxSide: 2160).jpegData(compressionQuality: 0.85) else { return nil }
            try data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            return StoryAsset(id: id(eventId: eventId, name: name), timestamp: date, isVideo: false)
        } catch {
            NSLog("Could not save night photo: %@", error.localizedDescription)
            return nil
        }
    }

    static func delete(_ asset: StoryAsset) {
        guard let url = fileURL(for: asset.id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll(eventId: String) {
        try? FileManager.default.removeItem(at: folder(eventId: eventId))
    }

    static func deleteEverything() {
        try? FileManager.default.removeItem(at: rootFolder)
    }

    static func thumbnail(for id: String, size: CGSize) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                if let url = fileURL(for: id), let image = UIImage(contentsOfFile: url.path) {
                    let target = CGSize(width: size.width * 3, height: size.height * 3)
                    let thumb = image.preparingThumbnail(of: aspectFill(image.size, into: target)) ?? image
                    continuation.yield(thumb)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func exportImage(for id: String) async -> UIImage? {
        guard let url = fileURL(for: id) else { return nil }
        return await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path) }.value
    }

    // MARK: - Files

    private static var rootFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Night Photos", isDirectory: true)
    }

    private static func folderName(eventId: String) -> String {
        String(SHA256.hash(data: Data(eventId.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32))
    }

    private static func folder(eventId: String) -> URL {
        rootFolder.appendingPathComponent(folderName(eventId: eventId), isDirectory: true)
    }

    private static func id(eventId: String, name: String) -> String { "\(folderName(eventId: eventId))/\(name)" }

    private static func fileURL(for id: String) -> URL? {
        let parts = id.split(separator: "/")
        guard parts.count == 2, !parts.contains(where: { $0 == ".." }) else { return nil }
        return rootFolder.appendingPathComponent(String(parts[0]), isDirectory: true)
            .appendingPathComponent(String(parts[1]))
    }

    private static func aspectFill(_ size: CGSize, into target: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return target }
        let scale = max(target.width / size.width, target.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Camera

/// The system camera, photo-only. Hands back the captured image; nothing is
/// saved to the photo library.
struct NightCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: NightCameraPicker
        init(_ parent: NightCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
