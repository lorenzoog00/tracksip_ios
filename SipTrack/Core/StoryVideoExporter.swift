import AVFoundation
import CoreGraphics
import CoreVideo
import SwiftUI
import UIKit

@MainActor
enum StoryVideoExporter {
    static func export(story: NightStory, state: NightStoryState, progress: (Double) -> Void) async throws -> URL {
        let moments = story.moments
        guard !moments.isEmpty else { throw StoryVideoError.emptyStory }
        let fps: Int32 = 30
        let counts = story.videoFrameCounts(framesPerSecond: Int(fps))
        let path = story.review.path
        let size = CGSize(width: 936, height: 108)
        let limit = story.review.ceiling.line
        let yMax = path.yMax(ceiling: limit)
        let spine = StoryVideoSpine(
            curve: path.cgPath(in: size, yMax: yMax),
            ceilingY: limit.map { path.point(at: path.start, bac: $0, in: size, yMax: yMax).y }
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Tracksip-\(UUID().uuidString).mp4")
        var finished = false
        defer {
            if !finished { try? FileManager.default.removeItem(at: url) }
        }
        let writer = try StoryMovieWriter(url: url, fps: fps, spine: spine)
        do {
            for (index, moment) in moments.enumerated() {
                try Task.checkCancellation()
                let image: UIImage?
                if let asset = moment.asset {
                    guard let photo = await PhotoLibraryService.exportImage(for: asset.id) else {
                        try Task.checkCancellation()
                        throw StoryVideoError.missingPhoto
                    }
                    image = photo
                } else {
                    image = nil
                }
                try Task.checkCancellation()
                let renderer = ImageRenderer(content: StoryCardView(
                    story: story, moment: moment, image: image, caption: state.captions[moment.id], showsSpine: false
                )
                .environment(\.dynamicTypeSize, .medium)
                .frame(width: 360, height: 640))
                renderer.scale = 3
                renderer.isOpaque = true
                guard let still = renderer.cgImage else { throw StoryVideoError.encoding }

                let count = counts[index]
                let nextTime = index + 1 < moments.count ? moments[index + 1].timestamp : moment.timestamp
                let points: [CGPoint]
                if moment.id == "end" || path.samples.isEmpty {
                    points = []
                } else {
                    points = (0..<count).map { frame in
                        let fraction = Double(frame) / Double(count)
                        let time = moment.timestamp.addingTimeInterval(nextTime.timeIntervalSince(moment.timestamp) * fraction)
                        return path.point(at: time, bac: story.review.bac(at: time), in: size, yMax: yMax)
                    }
                }
                // Finish writing this card before loading the next photo.
                try await writer.append(StoryVideoFrame(still: still, count: count, points: points))
                progress(Double(index + 1) / Double(moments.count + 1))
            }
            try await writer.finish()
            try Task.checkCancellation()
            progress(1)
            finished = true
            return url
        } catch {
            await writer.cancel()
            throw error
        }
    }
}

nonisolated private struct StoryVideoFrame: @unchecked Sendable {
    // The CGImage is immutable and the encoder only reads it.
    let still: CGImage
    let count: Int
    let points: [CGPoint]
}

nonisolated private struct StoryVideoSpine: @unchecked Sendable {
    let curve: CGPath
    let ceilingY: CGFloat?
}

nonisolated private enum StoryVideoError: LocalizedError {
    case emptyStory, missingPhoto, encoding

    var errorDescription: String? {
        switch self {
        case .emptyStory: "This night has no story to export."
        case .missingPhoto: "A photo or clip could not be loaded. Check your Photos access or internet connection and try again."
        case .encoding: "The video could not be created. Try again."
        }
    }
}

private actor StoryMovieWriter {
    private static let width = 1080
    private static let height = 1920

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let pool: CVPixelBufferPool
    private let fps: Int32
    private let spine: StoryVideoSpine
    private var index: Int64 = 0
    private var previousStill: CGImage?

    init(url: URL, fps: Int32, spine: StoryVideoSpine) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Self.width, AVVideoHeightKey: Self.height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Self.width, kCVPixelBufferHeightKey as String: Self.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        guard writer.canAdd(input) else { throw StoryVideoError.encoding }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? StoryVideoError.encoding }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else {
            writer.cancelWriting()
            throw StoryVideoError.encoding
        }
        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.pool = pool
        self.fps = fps
        self.spine = spine
    }

    func append(_ frame: StoryVideoFrame) async throws {
        let clock = ContinuousClock()
        let dissolveFrames = min(Int(fps) / 5, frame.count / 3)
        for step in 0..<frame.count {
            let deadline = clock.now.advanced(by: .seconds(10))
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, clock.now < deadline else {
                    throw writer.error ?? StoryVideoError.encoding
                }
                try await Task.sleep(for: .milliseconds(8))
            }
            try Task.checkCancellation()
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
                throw StoryVideoError.encoding
            }
            let dot = frame.points.isEmpty ? nil : frame.points[step]
            let previous = step < dissolveFrames ? previousStill : nil
            let blend = previous == nil ? 1 : CGFloat(step + 1) / CGFloat(dissolveFrames)
            guard Self.draw(frame.still, previous: previous, blend: blend,
                            in: buffer, width: Self.width, height: Self.height,
                            curve: spine.curve, ceilingY: spine.ceilingY, dot: dot),
                  adaptor.append(buffer, withPresentationTime: CMTime(value: index, timescale: fps)) else {
                throw writer.error ?? StoryVideoError.encoding
            }
            index += 1
        }
        previousStill = frame.still
    }

    func finish() async throws {
        try Task.checkCancellation()
        writer.endSession(atSourceTime: CMTime(value: index, timescale: fps))
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? StoryVideoError.encoding }
    }

    func cancel() {
        if writer.status == .writing { writer.cancelWriting() }
    }

    private nonisolated static func draw(_ image: CGImage, previous: CGImage?, blend: CGFloat,
                             in buffer: CVPixelBuffer, width: Int, height: Int,
                             curve: CGPath, ceilingY: CGFloat?, dot: CGPoint?) -> Bool {
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return false
        }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if let previous {
            context.draw(previous, in: bounds)
            context.setAlpha(blend * blend * (3 - 2 * blend))
        }
        context.draw(image, in: bounds)
        context.setAlpha(1)
        if let dot {
            context.translateBy(x: 72, y: 234)
            context.scaleBy(x: 1, y: -1)
            if let ceilingY {
                context.setStrokeColor(gray: 1, alpha: 0.4)
                context.setLineDash(phase: 0, lengths: [9, 12])
                context.move(to: CGPoint(x: 0, y: ceilingY))
                context.addLine(to: CGPoint(x: 936, y: ceilingY))
                context.strokePath()
            }
            context.setLineDash(phase: 0, lengths: [])
            context.setLineWidth(2)
            context.setStrokeColor(red: 1, green: 0.82, blue: 0.4, alpha: 0.27)
            context.addPath(curve)
            context.strokePath()
            context.saveGState()
            context.clip(to: CGRect(x: -2, y: -4, width: dot.x + 4, height: 116))
            context.setLineWidth(3)
            context.setStrokeColor(red: 1, green: 0.82, blue: 0.4, alpha: 1)
            context.addPath(curve)
            context.strokePath()
            context.restoreGState()
            context.setFillColor(gray: 1, alpha: 1)
            context.fillEllipse(in: CGRect(x: dot.x - 9, y: dot.y - 9, width: 18, height: 18))
        }
        return true
    }
}
