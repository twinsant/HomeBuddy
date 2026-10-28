//
//  HomeBuddyUITests.swift
//  HomeBuddyUITests
//
//  Created by Atman An on 2026/8/26.
//

import XCTest

final class HomeBuddyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testReturnToAlbumAtEveryZoomLevel() throws {
        let app = XCUIApplication()
        app.launch()

        let thumbnail = app.buttons["photoThumbnail-0"]
        guard thumbnail.waitForExistence(timeout: 15) else {
            throw XCTSkip("需要已授权且当前相册至少有一张照片的测试环境")
        }

        for steps in [0, 4, 16] {
            thumbnail.click()
            let back = app.buttons["backToPhotoLibrary"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            let resetZoom = app.buttons["zoomPercentage"]
            XCTAssertTrue(resetZoom.waitForExistence(timeout: 5))
            let imageLoaded = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == true"), object: resetZoom
            )
            XCTAssertEqual(XCTWaiter.wait(for: [imageLoaded], timeout: 30), .completed)

            for _ in 0..<steps {
                app.buttons["zoomIn"].click()
            }
            XCTAssertTrue(app.buttons["\(100 + steps * 25)%"].waitForExistence(timeout: 5))

            // 使用坐标点击，不能用 accessibility press 绕过图片的命中区域。
            back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            XCTAssertTrue(back.waitForNonExistence(timeout: 5))
            XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testReturnToAlbumScrollsToCurrentPhoto() throws {
        let app = XCUIApplication()
        app.launch()

        let firstThumbnail = app.buttons["photoThumbnail-0"]
        guard firstThumbnail.waitForExistence(timeout: 15) else {
            throw XCTSkip("需要已授权且当前相册有照片的测试环境")
        }
        firstThumbnail.click()

        let next = app.buttons["nextPhoto"]
        for _ in 0..<15 {
            guard next.isEnabled else {
                throw XCTSkip("需要当前相册至少有 16 张照片")
            }
            next.click()
        }

        app.buttons["backToPhotoLibrary"].click()
        let currentThumbnail = app.buttons["photoThumbnail-15"]
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: currentThumbnail
        )
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 10), .completed)
    }

    @MainActor
    func testDiskPhotosUseFullViewerAndRecognitionTools() throws {
        let app = XCUIApplication()
        app.launch()
        let directory = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "diskDirectory-")).firstMatch
        guard directory.waitForExistence(timeout: 15) else {
            throw XCTSkip("需要至少一个已添加且包含图片的磁盘目录")
        }
        directory.click()
        let thumbnail = app.buttons["photoThumbnail-0"]
        guard thumbnail.waitForExistence(timeout: 15) else {
            throw XCTSkip("当前磁盘目录需要至少一张已索引图片")
        }
        XCTAssertTrue(app.buttons["batchOllamaRecognition"].isEnabled)
        XCTAssertTrue(app.buttons["batchFaceRecognition"].isEnabled)
        thumbnail.click()
        let back = app.buttons["backToPhotoLibrary"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        let zoom = app.buttons["zoomPercentage"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: zoom)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 30), .completed)
        for tool in ["copyImage", "recognizeText", "recognizeBarcodes", "detectFaces", "ollamaImageRecognition", "photoInfo"] {
            XCTAssertTrue(app.buttons[tool].exists, "照片查看器缺少工具：\(tool)")
        }
        app.buttons["recognizeText"].click()
        XCTAssertTrue(app.descendants(matching: .any)["analysisResultTitle"].waitForExistence(timeout: 30))
        app.buttons["completeAnalysis"].click()
        for _ in 0..<16 { app.buttons["zoomIn"].click() }
        XCTAssertTrue(app.buttons["500%"].exists)
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5))
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
