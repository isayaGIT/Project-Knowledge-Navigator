import XCTest
@testable import ProjectKnowledgeNavigator

final class NativeOutlineLayoutTests: XCTestCase {
    func testNativeOutlineRowsCenterTextAndFilmstripGroupsVertically() {
        XCTAssertEqual(ProjectTreeRowMetrics.titleLineCenter(hasFilmstrip: false), ProjectTreeRowMetrics.textRowHeight / 2)
        XCTAssertEqual(ProjectTreeRowMetrics.textRowHeight, 32)

        let groupHeight = ProjectTreeRowMetrics.iconSize
            + ProjectTreeRowMetrics.filmstripSpacing
            + ProjectTreeRowMetrics.filmstripHeight
        let groupTop = (ProjectTreeRowMetrics.filmstripRowHeight - groupHeight) / 2
        let titleCenter = ProjectTreeRowMetrics.titleLineCenter(hasFilmstrip: true)
        let groupBottom = groupTop + groupHeight

        XCTAssertEqual(titleCenter, groupTop + ProjectTreeRowMetrics.iconSize / 2, accuracy: 0.001)
        XCTAssertEqual(groupTop, ProjectTreeRowMetrics.filmstripRowHeight - groupBottom, accuracy: 0.001)
        XCTAssertEqual(ProjectTreeRowMetrics.filmstripRowHeight, 78)
    }

}
