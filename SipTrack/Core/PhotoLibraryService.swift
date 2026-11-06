import Photos
import AVFoundation
import UIKit

struct StoryAsset: Identifiable {
    let id: String
    let timestamp: Date
    let isVideo: Bool
}

@MainActor
enum PhotoLibraryService {
    static var status: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    static func requestAccess() async -> PHAuthorizationStatus {
        guard status == .notDetermined else { return status }
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static func hasMedia(from start: Date, to end: Date) -> Bool? {
        guard status != .notDetermined else { return nil }
        return !assets(from: start, to: end).isEmpty
    }

    static func assets(from start: Date, to end: Date) -> [StoryAsset] {
        guard status == .authorized || status == .limited, start <= end else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@ AND (mediaType == %d OR mediaType == %d)",
            start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var assets: [StoryAsset] = []
        for index in 0..<result.count {
            let asset = result.object(at: index)
            guard let date = asset.creationDate, !asset.mediaSubtypes.contains(.photoScreenshot) else { continue }
            assets.append(StoryAsset(id: asset.localIdentifier, timestamp: date, isVideo: asset.mediaType == .video))
        }
        return assets
    }

    static func thumbnail(for id: String, size: CGSize, allowsNetwork: Bool = true) -> AsyncStream<UIImage> {
        guard let asset = asset(for: id) else { return AsyncStream { $0.finish() } }
        return images(for: asset, size: size, highQuality: false, allowsNetwork: allowsNetwork)
    }

    static func exportImage(for id: String) async -> UIImage? {
        guard let asset = asset(for: id) else { return nil }
        for await image in images(for: asset, size: CGSize(width: 1080, height: 1920), highQuality: true) {
            return image
        }
        return nil
    }

    static func video(for id: String) async -> AVPlayerItem? {
        guard let asset = asset(for: id), asset.mediaType == .video else { return nil }
        let manager = PHImageManager.default()
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        let stream = AsyncStream<AVPlayerItem> { continuation in
            let request = manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                if let item { continuation.yield(item) }
                continuation.finish()
            }
            continuation.onTermination = { _ in manager.cancelImageRequest(request) }
        }
        for await item in stream { return item }
        return nil
    }

    static func pickMore(completion: @escaping @MainActor () -> Void) {
        guard status == .limited, let controller = PresentationAnchor.topMost() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller) { _ in
            Task { @MainActor in completion() }
        }
    }

    private static func asset(for id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    private static func images(for asset: PHAsset, size: CGSize, highQuality: Bool, allowsNetwork: Bool = true) -> AsyncStream<UIImage> {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = highQuality ? .highQualityFormat : .opportunistic
        options.resizeMode = highQuality ? .exact : .fast
        options.isNetworkAccessAllowed = allowsNetwork
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let request = manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, info in
                let degraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                let cancelled = info?[PHImageCancelledKey] as? Bool ?? false
                if let image, !cancelled, !highQuality || !degraded { continuation.yield(image) }
                if !degraded || cancelled || info?[PHImageErrorKey] != nil { continuation.finish() }
            }
            continuation.onTermination = { _ in manager.cancelImageRequest(request) }
        }
    }
}
