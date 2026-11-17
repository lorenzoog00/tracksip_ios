//
//  PhotoFramingTests.swift
//  siptrackTests
//

import Testing
import CoreGraphics
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct PhotoFramingTests {
    private let phone = CGSize(width: 393, height: 852)      // story view on an iPhone
    private let export = CGSize(width: 360, height: 640)     // exported story video

    @Test func landscapePhotoIsShownWhole() {
        #expect(!PhotoFraming.fills(imageSize: CGSize(width: 4032, height: 3024), frame: phone))
        #expect(!PhotoFraming.fills(imageSize: CGSize(width: 4032, height: 3024), frame: export))
    }

    @Test func standardPortraitPhotoIsShownWhole() {
        // 3:4 portrait on a 9:19.5 screen would lose about 40% to cropping.
        #expect(!PhotoFraming.fills(imageSize: CGSize(width: 3024, height: 4032), frame: phone))
        #expect(!PhotoFraming.fills(imageSize: CGSize(width: 3024, height: 4032), frame: export))
    }

    @Test func photoMatchingTheFrameFills() {
        #expect(PhotoFraming.fills(imageSize: CGSize(width: 1080, height: 1920), frame: export))
        #expect(PhotoFraming.fills(imageSize: CGSize(width: 1179, height: 2556), frame: phone))
    }

    @Test func fillsOnlyWithinTwelvePercentCrop() {
        // 9:16 photo on a 9:19.5 screen loses ~18%: shown whole.
        #expect(!PhotoFraming.fills(imageSize: CGSize(width: 1080, height: 1920), frame: phone))
        // Within 12%: fills.
        #expect(PhotoFraming.fills(imageSize: CGSize(width: 1000, height: 1950), frame: phone))
    }

    @Test func degenerateSizesFill() {
        #expect(PhotoFraming.fills(imageSize: .zero, frame: phone))
        #expect(PhotoFraming.fills(imageSize: CGSize(width: 100, height: 100), frame: .zero))
    }
}
