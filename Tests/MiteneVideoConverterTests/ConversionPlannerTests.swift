import XCTest
@testable import MiteneVideoConverter

final class ConversionPlannerTests: XCTestCase {
    private let planner = ConversionPlanner()

    func testLongVideoIsSplitEvenlyBelowTwoMinutes() {
        let analysis = makeAnalysis(duration: 300, size: VideoSize(width: 3840, height: 2160))
        let plan = planner.plan(for: analysis)

        XCTAssertEqual(plan.segments.count, 3)
        XCTAssertEqual(plan.segments.map(\.duration), [100, 100, 100])
        XCTAssertTrue(plan.segments.allSatisfy { $0.duration < 120 })
    }

    func test120SecondVideoDoesNotCreateOneSecondTail() {
        let plan = planner.plan(for: makeAnalysis(duration: 120, size: VideoSize(width: 1920, height: 1080)))

        XCTAssertEqual(plan.segments.count, 2)
        XCTAssertEqual(plan.segments.map(\.duration), [60, 60])
    }

    func testLandscapeResolutionIsDownscaledWithoutUpscaling() {
        let plan = planner.plan(for: makeAnalysis(duration: 10, size: VideoSize(width: 3840, height: 2160)))
        XCTAssertEqual(plan.outputSize, VideoSize(width: 1280, height: 720))

        let smallPlan = planner.plan(for: makeAnalysis(duration: 10, size: VideoSize(width: 640, height: 480)))
        XCTAssertEqual(smallPlan.outputSize, VideoSize(width: 640, height: 480))
    }

    func testPortraitResolutionUsesDisplayOrientation() {
        let plan = planner.plan(for: makeAnalysis(duration: 10, size: VideoSize(width: 2160, height: 3840)))
        XCTAssertEqual(plan.outputSize, VideoSize(width: 720, height: 1280))
    }

    func testSegmentDatesFollowSegmentStart() {
        let start = Date(timeIntervalSince1970: 1_000)
        let plan = planner.plan(for: makeAnalysis(duration: 300, size: VideoSize(width: 1920, height: 1080), date: start))

        XCTAssertEqual(plan.segments.map(\.creationDate), [start, start.addingTimeInterval(100), start.addingTimeInterval(200)])
    }

    private func makeAnalysis(duration: Double, size: VideoSize, date: Date = Date(timeIntervalSince1970: 0)) -> VideoAnalysis {
        VideoAnalysis(
            sourceURL: URL(fileURLWithPath: "/tmp/source.mov"),
            duration: duration,
            displaySize: size,
            orientation: size.width >= size.height ? .landscape : .portrait,
            frameRate: 60,
            codec: "HEVC",
            hasAudio: true,
            creationDate: date
        )
    }
}
