import XCTest
@testable import BloomCore

final class ZoomTransitionTests: XCTestCase {
    let full = 2 * Double.pi

    func testZoomInMapsWheelIntoOldWindow() {
        // New focus occupied [π/2, π] at ring 1 in the old layout.
        let window = AngularWindow(start: .pi / 2, end: .pi, ring: 1)

        // A segment spanning the full new wheel starts spanning the window.
        let whole = ZoomTransition.initialState(finalStart: 0, finalEnd: full, direction: .zoomIn, window: window)
        XCTAssertEqual(whole.start, .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(whole.end, .pi, accuracy: 1e-9)
        XCTAssertEqual(whole.ringOffset, 2)

        // A segment at the second half of the new wheel starts at the second
        // half of the window.
        let half = ZoomTransition.initialState(finalStart: .pi, finalEnd: full, direction: .zoomIn, window: window)
        XCTAssertEqual(half.start, .pi * 0.75, accuracy: 1e-9)
        XCTAssertEqual(half.end, .pi, accuracy: 1e-9)
    }

    func testZoomOutIsInverseOfZoomIn() {
        let window = AngularWindow(start: 0.4, end: 1.9, ring: 2)
        let finalStart = 0.7, finalEnd = 1.2

        let compressed = ZoomTransition.initialState(
            finalStart: finalStart, finalEnd: finalEnd, direction: .zoomIn, window: window
        )
        // Applying the zoom-out mapping to the compressed angles recovers the originals.
        let recovered = ZoomTransition.initialState(
            finalStart: compressed.start, finalEnd: compressed.end, direction: .zoomOut, window: window
        )
        XCTAssertEqual(recovered.start, finalStart, accuracy: 1e-9)
        XCTAssertEqual(recovered.end, finalEnd, accuracy: 1e-9)
        XCTAssertEqual(recovered.ringOffset, -3)
    }

    func testDirectionClassification() {
        let child = FileNode(name: "child", isDirectory: true, size: 0, children: [FileNode(name: "f", isDirectory: false, size: 1)])
        let mid = FileNode(name: "mid", isDirectory: true, size: 0, children: [child])
        let root = FileNode(name: "root", isDirectory: true, size: 0, children: [mid], rootPath: "/r")
        let stranger = FileNode(name: "stranger", isDirectory: true, size: 0)

        XCTAssertEqual(ZoomTransition.direction(from: root, to: child), .zoomIn)
        XCTAssertEqual(ZoomTransition.direction(from: child, to: root), .zoomOut)
        XCTAssertNil(ZoomTransition.direction(from: root, to: stranger))
        XCTAssertNil(ZoomTransition.direction(from: root, to: root))
    }
}
