import XCTest
@testable import Notiee

final class NoteTodoDecodingTests: XCTestCase {
    func testDecode_missingNewFields_usesDefaults() throws {
        let json = """
        { "id": "00000000-0000-0000-0000-000000000001",
          "content": "buy milk",
          "isCompleted": false,
          "createdAt": 0 }
        """.data(using: .utf8)!

        let todo = try JSONDecoder().decode(NoteTodo.self, from: json)

        XCTAssertEqual(todo.content, "buy milk")
        XCTAssertFalse(todo.hasReminder)
        XCTAssertNil(todo.dueDate)
    }

    func testDecode_missingId_generatesId() throws {
        let json = #"{ "content": "x", "isCompleted": true, "createdAt": 0 }"#.data(using: .utf8)!
        let todo = try JSONDecoder().decode(NoteTodo.self, from: json)
        XCTAssertEqual(todo.content, "x")
        XCTAssertTrue(todo.isCompleted)
    }
}
