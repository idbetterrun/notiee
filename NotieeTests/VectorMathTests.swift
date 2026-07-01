import XCTest
@testable import Notiee

final class VectorMathTests: XCTestCase {
    func testIdenticalVectors_similarityIsOne() {
        let v: [Float] = [1, 2, 3]
        XCTAssertEqual(VectorMath.cosineSimilarity(v, v), 1.0, accuracy: 1e-5)
    }

    func testOrthogonalVectors_similarityIsZero() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 0], [0, 1]), 0.0, accuracy: 1e-5)
    }

    func testOppositeVectors_similarityIsMinusOne() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 0], [-1, 0]), -1.0, accuracy: 1e-5)
    }

    func testMismatchedOrEmpty_returnsZero() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 2], [1, 2, 3]), 0.0)
        XCTAssertEqual(VectorMath.cosineSimilarity([], []), 0.0)
    }
}
