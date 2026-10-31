//
//  DecoderTests.swift
//  CourseMateTests
//
//  The two decoders are the only place where the app trusts the server's JSON
//  shape, and their failure mode is silent — a renamed field would render blank
//  rows rather than crash. These tests pin the shapes CI can check without a
//  server.
//
import XCTest
@testable import CourseMate

final class DecisionDecoderTests: XCTestCase {
    func testMultipleChoiceRowDecodes() throws {
        let row: [String: Any] = [
            "id": "dec_1",
            "kind": "quiz_answer",
            "screen_type": "quiz",
            "ts": 1_700_000_000.0,
            "confidence": 0.82,
            "needs_human": 0,
            "payload": [
                "question": ["stem": "Which organelle makes ATP?", "options": ["Nucleus", "Mitochondrion", "Ribosome"]],
                "chosen_index": 1,
                "chosen_text": "Mitochondrion",
                "answer_text": "Mitochondrion",
                "work": "The inner membrane holds the ATP synthase.",
                "evidence": "lecture",
            ],
        ]

        let decision = try XCTUnwrap(DecisionDecoder.from(row))
        XCTAssertEqual(decision.kindLabel, "Quiz")
        XCTAssertEqual(decision.headline, "Which organelle makes ATP?")
        XCTAssertEqual(decision.answer, "Mitochondrion")
        XCTAssertEqual(decision.options.count, 3)
        XCTAssertEqual(decision.chosenIndex, 1)
        XCTAssertEqual(decision.confidence, 0.82, accuracy: 0.0001)
        XCTAssertFalse(decision.needsHuman)
        XCTAssertEqual(decision.evidence, "lecture")
    }

    /// Free response sends `question` as a plain string, not an object.
    func testStringQuestionDecodes() throws {
        let row: [String: Any] = [
            "id": "dec_2",
            "kind": "essay",
            "ts": 1_700_000_100.0,
            "confidence": 0.7,
            "needs_human": 1,
            "payload": [
                "question": "Explain osmosis.",
                "prose": "Osmosis is the movement of water …",
            ],
        ]

        let decision = try XCTUnwrap(DecisionDecoder.from(row))
        XCTAssertEqual(decision.headline, "Explain osmosis.")
        XCTAssertEqual(decision.answer, "Osmosis is the movement of water …")
        XCTAssertTrue(decision.needsHuman)
        XCTAssertTrue(decision.options.isEmpty)
        XCTAssertNil(decision.chosenIndex)
    }

    /// `needs_human` arrives as a SQLite integer, and a Bool elsewhere.
    func testNeedsHumanAcceptsBothShapes() throws {
        let asInt = try XCTUnwrap(DecisionDecoder.from([
            "id": "dec_3", "kind": "quiz_answer", "needs_human": 1, "payload": [:],
        ]))
        XCTAssertTrue(asInt.needsHuman)

        let asBool = try XCTUnwrap(DecisionDecoder.from([
            "id": "dec_4", "kind": "quiz_answer", "needs_human": false, "payload": [:],
        ]))
        XCTAssertFalse(asBool.needsHuman)
    }

    /// A row missing everything but its id must still render, not vanish.
    func testSparseRowSurvives() throws {
        let decision = try XCTUnwrap(DecisionDecoder.from(["id": "dec_5"]))
        XCTAssertEqual(decision.id, "dec_5")
        XCTAssertEqual(decision.confidence, 0)
        XCTAssertFalse(decision.needsHuman)
        XCTAssertTrue(decision.answer.isEmpty)
    }

    func testRowWithoutIDIsRejected() {
        XCTAssertNil(DecisionDecoder.from(["kind": "quiz_answer"]))
    }
}

final class ReviewDecoderTests: XCTestCase {
    func testSessionsLessonsAndStats() throws {
        let object: [String: Any] = [
            "sessions": [
                ["id": "ses_1", "course": "BIOL 201", "started_at": "2026-10-31T09:15:00.000Z"],
                ["id": "ses_2", "course": "BIOL 201"],
            ],
            "lessons": [
                ["id": 7, "scope": "quiz", "text": "the right answer was 42", "weight": 1.4],
            ],
            "stats": [
                ["screen_type": "quiz", "graded": 4, "agreed": 3, "accuracy": 0.75],
                ["screen_type": "essay", "graded": 0, "accuracy": 0],
            ],
        ]

        let review = ReviewDecoder.review(from: object)

        XCTAssertEqual(review.sessions.count, 2)
        XCTAssertEqual(review.sessions[0].id, "ses_1")
        XCTAssertNotNil(review.sessions[0].startedAt, "ISO timestamp should parse")
        XCTAssertNil(review.sessions[1].startedAt, "absent timestamp stays nil")

        XCTAssertEqual(review.lessons.count, 1)
        XCTAssertEqual(review.lessons[0].id, "7", "numeric ids become strings")
        XCTAssertEqual(review.lessons[0].scope, "quiz")

        // A screen type with nothing graded is noise, not a 0% record.
        XCTAssertEqual(review.stats.count, 1)
        XCTAssertEqual(review.stats[0].screenType, "quiz")
        XCTAssertEqual(review.stats[0].accuracy, 0.75, accuracy: 0.0001)
    }

    func testEmptyObjectYieldsEmptyReview() {
        let review = ReviewDecoder.review(from: [:])
        XCTAssertTrue(review.sessions.isEmpty)
        XCTAssertTrue(review.lessons.isEmpty)
        XCTAssertTrue(review.stats.isEmpty)
    }

    func testDateAcceptsEpochNumbers() throws {
        let fromDouble = try XCTUnwrap(ReviewDecoder.date(1_700_000_000.0))
        XCTAssertEqual(fromDouble.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)

        let fromNumber = try XCTUnwrap(ReviewDecoder.date(NSNumber(value: 1_700_000_000)))
        XCTAssertEqual(fromNumber.timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)

        XCTAssertNil(ReviewDecoder.date(nil))
        XCTAssertNil(ReviewDecoder.date("not a date"))
    }
}
