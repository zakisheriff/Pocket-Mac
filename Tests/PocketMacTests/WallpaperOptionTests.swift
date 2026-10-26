import XCTest
@testable import Pocket_Mac

final class WallpaperOptionTests: XCTestCase {

    func testEveryWallpaperHasThreeGradientStops() {
        for option in WallpaperOption.allCases {
            XCTAssertEqual(option.colors.count, 3, "\(option) should define a 3-stop gradient")
        }
    }

    func testWallpaperRawValuesRoundTripThroughInit() {
        for option in WallpaperOption.allCases {
            XCTAssertEqual(WallpaperOption(rawValue: option.rawValue), option)
        }
    }
}
