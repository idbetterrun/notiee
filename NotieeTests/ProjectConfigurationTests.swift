import XCTest

final class ProjectConfigurationTests: XCTestCase {
    func testAppDeclaresLaunchScreenForFullScreenRendering() {
        XCTAssertNotNil(
            Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen"),
            "Notiee must declare UILaunchScreen so modern iPhone simulators do not letterbox the app."
        )
    }
}
