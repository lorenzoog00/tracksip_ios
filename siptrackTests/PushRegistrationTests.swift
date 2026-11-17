//
//  PushRegistrationTests.swift
//  siptrackTests
//

import Testing
import Foundation
import UserNotifications
@testable import siptrack

@MainActor
struct PushRegistrationTests {
    @Test func doesNotAskWithoutAnyRequest() {
        #expect(!PushRegistration.shouldAsk(sentCount: 0, incomingCount: 0, status: .notDetermined))
    }

    @Test func asksAfterSending() {
        #expect(PushRegistration.shouldAsk(sentCount: 1, incomingCount: 0, status: .notDetermined))
    }

    @Test func asksWhenARequestArrives() {
        #expect(PushRegistration.shouldAsk(sentCount: 0, incomingCount: 2, status: .notDetermined))
    }

    @Test func neverAsksOnceDecided() {
        #expect(!PushRegistration.shouldAsk(sentCount: 1, incomingCount: 1, status: .authorized))
        #expect(!PushRegistration.shouldAsk(sentCount: 1, incomingCount: 1, status: .denied))
    }

    @Test func tokenIsLowercaseHex() {
        let token = PushRegistration.hexString(Data([0x00, 0xAB, 0x0F, 0xFF]))
        #expect(token == "00ab0fff")
    }
}
