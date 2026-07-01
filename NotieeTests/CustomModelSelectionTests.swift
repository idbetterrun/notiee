import XCTest
@testable import Notiee

@MainActor
final class CustomModelSelectionTests: XCTestCase {
    private func makeVM() -> SettingsViewModel {
        // Uses the default live store; we only touch in-memory arrays here.
        let vm = SettingsViewModel()
        vm.customModels = []
        return vm
    }

    func testCustomModelsFilteredByKind() {
        let vm = makeVM()
        let textModel = CustomAIModel(name: "T", kind: .text, endpoint: "https://e/v1", protocolType: .openai, modelIdentifier: "m-t", apiKey: "k")
        let visionModel = CustomAIModel(name: "V", kind: .vision, endpoint: "https://e/v1", protocolType: .openai, modelIdentifier: "m-v", apiKey: "k")
        vm.customModels = [textModel, visionModel]

        XCTAssertEqual(vm.customModels(for: .text).map(\.id), [textModel.id])
        XCTAssertEqual(vm.customModels(for: .vision).map(\.id), [visionModel.id])
    }

    func testApplyCustomModelSetsCustomProvider() {
        let vm = makeVM()
        let model = CustomAIModel(name: "T", kind: .text, endpoint: "https://e/v1", protocolType: .openai, modelIdentifier: "m-t", apiKey: "k")
        vm.customModels = [model]

        vm.applyCustomModel(model, for: .text)

        XCTAssertEqual(vm.textConfiguration.providerType, .custom)
        XCTAssertEqual(vm.textConfiguration.customEndpoint, "https://e/v1")
        XCTAssertEqual(vm.textConfiguration.modelName, "m-t")
    }
}
