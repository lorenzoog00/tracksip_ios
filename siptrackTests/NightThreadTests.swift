//
//  NightThreadTests.swift
//  siptrackTests
//

import Testing
import Foundation
@testable import siptrack

// @MainActor: see CeilingCrossingTests.
@MainActor
struct NightThreadTests {

    // MARK: - Toggle math

    @Test func toggleMath() {
        let none: [Reaction: Int] = [:]
        let beer = ReactionMath.apply(counts: none, old: nil, new: .beer)
        #expect(beer == [.beer: 1])

        let water = ReactionMath.apply(counts: beer, old: .beer, new: .water)
        #expect(water == [.water: 1])

        let cleared = ReactionMath.apply(counts: water, old: .water, new: nil)
        #expect(cleared == [:])

        // Someone else's reactions stay put.
        let shared = ReactionMath.apply(counts: [.beer: 3, .water: 1], old: .beer, new: .water)
        #expect(shared == [.beer: 2, .water: 2])
    }

    @Test func toggleMathNeverNegative() {
        #expect(ReactionMath.apply(counts: [:], old: .beer, new: nil) == [:])
        #expect(ReactionMath.apply(counts: [.beer: 0], old: .beer, new: nil) == [:])
        #expect(ReactionMath.apply(counts: [.beer: -2], old: nil, new: .water) == [.water: 1])
    }

    // MARK: - Summary parse

    @Test func summaryParsesIntsAndDoubles() throws {
        let data: [String: Any] = [
            "reactions": ["beer": 3, "fire": Double(2), "laugh": Int64(1), "water": 0] as [String: Any],
            "reactors": ["a", "b"],
            "comment_count": Double(4),
            "latest_comments": [
                ["id": "c1", "uid": "a", "username": "ana", "text": "hi", "at": 1_700_000_000_000] as [String: Any],
                ["id": "c2", "uid": "b", "username": "beto", "text": "yo", "at": Double(1_700_000_060_000)] as [String: Any]
            ] as [[String: Any]]
        ]
        let summary = try #require(ThreadSummary.parse(data))
        // Keys from the old six-emoji set (fire, laugh) are ignored; zero counts too.
        #expect(summary.counts == [.beer: 3])
        #expect(summary.reactors == ["a", "b"])
        #expect(summary.commentCount == 4)
        #expect(summary.latest.map(\.id) == ["c1", "c2"])
        #expect(summary.latest.first?.username == "ana")
        #expect(summary.latest.first?.at == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(summary.latest.last?.isPending == false)
    }

    @Test func summaryIgnoresUnknownReactionKeys() throws {
        let data: [String: Any] = ["reactions": ["beer": 1, "skull": 5, "🍻": 2]]
        let summary = try #require(ThreadSummary.parse(data))
        #expect(summary.counts == [.beer: 1])
    }

    @Test func summaryMissingFieldsAreZero() throws {
        let summary = try #require(ThreadSummary.parse([:]))
        #expect(summary.counts.isEmpty)
        #expect(summary.reactors.isEmpty)
        #expect(summary.commentCount == 0)
        #expect(summary.latest.isEmpty)
        #expect(summary == ThreadSummary())
    }

    // MARK: - Night key

    @Test func nightKeyId() {
        let night = SharedNight(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000.1234),
            endedAt: nil,
            lastDrinkAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_086_400),
            samples: [],
            drinks: []
        )
        let key = NightKey(owner: "abc", night: night)
        #expect(key.startedAt == 1_700_000_000_123)
        #expect(key.id == "abc_1700000000123")
    }

    // MARK: - Mentions

    private func query(_ marked: String) -> String? {
        // "|" marks the cursor.
        let cursor = marked.firstIndex(of: "|").map { marked.distance(from: marked.startIndex, to: $0) }
            ?? marked.count
        let text = marked.replacingOccurrences(of: "|", with: "")
        return MentionText.activeQuery(in: text, cursor: cursor)
    }

    @Test func activeQuery() {
        #expect(query("hey @bo|") == "bo")
        #expect(query("@") == "")
        #expect(query("hey @|") == "")
        #expect(query("a@b") == nil)
        #expect(query("hey @bo |") == nil)
        #expect(query("hey bo|") == nil)
        #expect(query("") == nil)
        // Cursor in the middle of a name: the part before the cursor.
        #expect(query("@bo|to") == "bo")
    }

    @Test func segmentsHighlightOnlyMentionedNames() {
        let mentions = [ThreadMention(uid: "u1", username: "beto")]
        let parts = MentionText.segments("hi @beto and @lu, see a@beto", mentions: mentions)
        #expect(parts.map { $0.0 } == ["hi ", "@beto", " and @lu, see a@beto"])
        #expect(parts.map { $0.1 } == [false, true, false])
    }

    @Test func segmentsTrailingPunctuationAndNoMentions() {
        let mentions = [ThreadMention(uid: "u1", username: "beto")]
        let parts = MentionText.segments("@beto.", mentions: mentions)
        #expect(parts.map { $0.0 } == ["@beto", "."])
        #expect(parts.map { $0.1 } == [true, false])

        let plain = MentionText.segments("hey @beto", mentions: [])
        #expect(plain.map { $0.0 } == ["hey @beto"])
        #expect(plain.map { $0.1 } == [false])
    }

    // MARK: - Drink chips

    @Test func drinkChips() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func drink(_ name: String, _ minutes: Double) -> SharedDrink {
            SharedDrink(name: name, icon: name.lowercased(), at: start.addingTimeInterval(minutes * 60))
        }
        let drinks = [drink("Beer", 0), drink("Beer", 10), drink("Tequila", 20),
                      drink("Beer", 30), drink("Wine", 40)]
        let chips = DrinkSummary.chips(drinks)
        #expect(chips.map { $0.name } == ["Beer", "Tequila", "Wine"])
        #expect(chips.map { $0.count } == [3, 1, 1])
        #expect(chips.map { $0.icon } == ["beer", "tequila", "wine"])
        #expect(DrinkSummary.chips([]).isEmpty)
    }

    // MARK: - Reaction bar fit

    @Test func reactionBarShowsWhatWasUsed() {
        // Read-only bars show only reactions someone used, in allCases order.
        let layout = ReactionBarLayout.visible(counts: [.water: 1, .beer: 2], mine: .water)
        #expect(layout.shown == [.beer, .water])
        #expect(layout.hidden == 0)
        #expect(ReactionBarLayout.visible(counts: [:], mine: nil).shown.isEmpty)
        #expect(Reaction.allCases == [.beer, .water])
    }

    // MARK: - Comment sheet

    @Test func mentionSuggestionsOrderDedupeAndFilter() {
        func names(_ query: String, limit: Int = MentionSuggestions.defaultLimit) -> [String] {
            MentionSuggestions.candidates(
                query: query, owner: "ana", reacted: ["beto", "Lu"],
                commenters: ["beto", "carla", "me"], friends: ["Ana", "bruno", "zed"],
                me: "me", limit: limit
            ).map(\.username)
        }
        // Owner, reactors, commenters, friends; each once; never me; capped.
        #expect(names("") == ["ana", "beto", "Lu", "carla", "bruno"])
        #expect(names("", limit: 2) == ["ana", "beto"])
        // Prefix, case-insensitive.
        #expect(names("B") == ["beto", "bruno"])
        #expect(names("l") == ["Lu"])
        #expect(names("me").isEmpty)
        #expect(names("x").isEmpty)

        let sources = MentionSuggestions.candidates(
            query: "", owner: "ana", reacted: ["beto"], commenters: ["carla"], friends: ["ANA", "zed"], me: "me"
        ).map(\.source)
        #expect(sources == [.owner, .reacted, .commented, .friend])
    }

    @Test func mentionCompletionReplacesThePartialName() {
        let end = MentionSuggestions.complete("hey @bo", cursor: 7, with: "beto")
        #expect(end?.text == "hey @beto ")
        #expect(end?.cursor == 10)

        // Cursor inside a name: the whole name is replaced, the space reused.
        let middle = MentionSuggestions.complete("@boto rest", cursor: 3, with: "beto")
        #expect(middle?.text == "@beto rest")
        #expect(middle?.cursor == 6)

        let bare = MentionSuggestions.complete("@", cursor: 1, with: "lu")
        #expect(bare?.text == "@lu ")
        #expect(bare?.cursor == 4)

        #expect(MentionSuggestions.complete("hi", cursor: 2, with: "lu") == nil)
        #expect(MentionSuggestions.complete("a@b", cursor: 3, with: "lu") == nil)
    }

    @Test func pickedNamesStayPillsOnlyWhileWritten() {
        #expect(MentionSuggestions.stillMentioned(["beto", "lu"], in: "hey @Beto and lu") == ["beto"])
        #expect(MentionSuggestions.stillMentioned(["beto"], in: "hey @bet").isEmpty)
        #expect(MentionSuggestions.stillMentioned([], in: "@beto").isEmpty)
    }

    @Test func commentDraftCountsLikeTheServer() {
        #expect(CommentDraft.length("  hi \n") == 2)
        #expect(!CommentDraft.canSend("   \n"))
        #expect(CommentDraft.canSend(String(repeating: "a", count: 200)))
        #expect(!CommentDraft.canSend(String(repeating: "a", count: 201)))
        // JS Array.from counts Unicode scalars: a flag is two.
        #expect(CommentDraft.length("🇦🇷") == 2)
        #expect(CommentDraft.canSend(String(repeating: "🇦🇷", count: 100)))
        #expect(!CommentDraft.canSend(String(repeating: "🇦🇷", count: 101)))
    }

    @Test func myPendingCommentKeepsItsRowWhenConfirmed() {
        let other = ThreadComment(id: "c1", uid: "u2", username: "beto", text: "hi",
                                  mentions: [], at: Date())
        let pending = ThreadComment(id: "pending-1", uid: "me", username: "ana", text: "hi",
                                    mentions: [], at: Date(), isPending: true)
        var confirmed = pending
        confirmed.id = "srv-1"
        confirmed.isPending = false

        let before = CommentRowKeys.keys([other, pending], myUid: "me")
        let after = CommentRowKeys.keys([other, confirmed], myUid: "me")
        #expect(before == after)
        #expect(before[0] == "c1")

        // Two of mine with the same text stay distinct.
        let twice = CommentRowKeys.keys([confirmed, pending], myUid: "me")
        #expect(Set(twice).count == 2)
    }
}
