import XCTest
import UIKit

final class ProjectConfigurationTests: XCTestCase {
    func testAppDeclaresLaunchScreenForFullScreenRendering() {
        XCTAssertNotNil(
            Bundle.main.object(forInfoDictionaryKey: "UILaunchScreen"),
            "Notiee must declare UILaunchScreen so modern iPhone simulators do not letterbox the app."
        )
    }

    func testNotieeLogoIsAvailableAsNamedImage() {
        XCTAssertNotNil(
            UIImage(named: "Notiee-iOS"),
            "The about and onboarding screens need Notiee-iOS.png available as a named image."
        )
    }
}
