import XCTest

final class RotationPlanTests: XCTestCase {
    func testIntervalIs11Hours55Minutes() {
        XCTAssertEqual(RotationPlan().intervalSeconds, 42_900, accuracy: 0.001)
    }

    func testRotationDateIsIntervalAfterStart() {
        let plan = RotationPlan()
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(plan.rotationDate(startedAt: start).timeIntervalSince1970, 42_900, accuracy: 0.001)
    }

    func testPrepareHappensBeforeRotation() {
        let plan = RotationPlan()
        let rotation = Date(timeIntervalSince1970: 42_900)
        let prepare = plan.prepareDate(rotatingAt: rotation)
        XCTAssertLessThan(prepare, rotation)
        XCTAssertEqual(rotation.timeIntervalSince(prepare), plan.prerollSeconds, accuracy: 0.001)
    }

    func testBackoffIsClamped() {
        let plan = RotationPlan()
        XCTAssertEqual(plan.backoffSeconds(failureCount: 0), 0)
        XCTAssertEqual(plan.backoffSeconds(failureCount: 1), 2, accuracy: 0.001)
        XCTAssertEqual(plan.backoffSeconds(failureCount: 3), 8, accuracy: 0.001)
        XCTAssertEqual(plan.backoffSeconds(failureCount: 99), plan.maxBackoffSeconds, accuracy: 0.001)
    }

    func testTitleIncludesCycleNumber() {
        let title = RotationPlan().title(cycle: 7, date: Date(timeIntervalSince1970: 0), prefix: "Test")
        XCTAssertTrue(title.contains("Test #7"))
    }
}
