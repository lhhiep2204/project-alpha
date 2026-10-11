//
//  ProjectAlphaUITests.swift
//  ProjectAlpha
//
//  Created by Hoàng Hiệp Lê on 12/9/26.
//

import XCTest

private enum MapSearchUITestFixture {
    static let searchButton = "map.search"
    static let closeButton = "map.placeSearch.close"
    static let searchField = "map.placeSearch.field"
    static let clearButton = "map.placeSearch.clear"
    static let searchScreen = "map.placeSearch"
    static let title = "Search Places"
    static let placeholder = "Place name or address"
    static let idleHint = "Enter a place name or address to search Apple Maps."
    static let whitespaceQuery = " "
    static let returnKey = "\n"
    static let emptyValue = ""
    static let launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    static let existsPredicate = "exists == true"
    static let absentPredicate = "exists == false"
    static let valuePredicate = "value == %@"
    static let emptyFieldPredicate = "value == %@ OR value == %@"
    static let timeout: TimeInterval = 10
}

final class ProjectAlphaUITests: XCTestCase {

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
    /// AC-18/19/60, D-04/17: Return retains input, interior X clears; actual dismissal starts fresh next time.
    /// A compact iPhone journey; provider results and adaptive/device coverage have separate gates.
    func testMapSearchOpensOnlyAfterSearchActionAndCloses() throws {
        let app = XCUIApplication()
        app.launchArguments = MapSearchUITestFixture.launchArguments
        app.launch()
        defer { app.terminate() }

        // Three top-level destinations retain Home, Map, Settings order on the compact tab bar.
        let mapTab = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(mapTab.waitForExistence(timeout: MapSearchUITestFixture.timeout))
        mapTab.tap()

        let search = app.buttons[MapSearchUITestFixture.searchButton]
        let close = app.buttons[MapSearchUITestFixture.closeButton]
        let screen = app.descendants(matching: .any)
            .matching(identifier: MapSearchUITestFixture.searchScreen).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: MapSearchUITestFixture.timeout))
        XCTAssertFalse(close.exists)
        XCTAssertFalse(screen.exists)

        search.tap()
        XCTAssertTrue(screen.waitForExistence(timeout: MapSearchUITestFixture.timeout))
        let searchField = app.textFields[MapSearchUITestFixture.searchField]
        let title = app.navigationBars[MapSearchUITestFixture.title]
        XCTAssertTrue(searchField.waitForExistence(timeout: MapSearchUITestFixture.timeout))
        XCTAssertTrue(app.staticTexts[MapSearchUITestFixture.idleHint].waitForExistence(
            timeout: MapSearchUITestFixture.timeout))

        searchField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: MapSearchUITestFixture.timeout))
        XCTAssertTrue(title.exists)
        XCTAssertTrue(close.exists)
        XCTAssertTrue(close.isHittable)
        searchField.typeText(MapSearchUITestFixture.whitespaceQuery)
        let queryEntered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: MapSearchUITestFixture.valuePredicate,
                                   MapSearchUITestFixture.whitespaceQuery), object: searchField)
        XCTAssertEqual(XCTWaiter.wait(for: [queryEntered], timeout: MapSearchUITestFixture.timeout), .completed)
        searchField.typeText(MapSearchUITestFixture.returnKey)
        let keyboardHidden = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: MapSearchUITestFixture.absentPredicate),
            object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardHidden], timeout: MapSearchUITestFixture.timeout), .completed)
        XCTAssertEqual(searchField.value as? String, MapSearchUITestFixture.whitespaceQuery)
        XCTAssertTrue(screen.exists)
        XCTAssertTrue(title.exists)
        XCTAssertTrue(app.staticTexts[MapSearchUITestFixture.idleHint].exists)

        searchField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: MapSearchUITestFixture.timeout))
        XCTAssertTrue(title.exists)
        XCTAssertTrue(close.isHittable)
        let clear = app.buttons[MapSearchUITestFixture.clearButton]
        XCTAssertTrue(clear.waitForExistence(timeout: MapSearchUITestFixture.timeout))
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        let fieldCleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: MapSearchUITestFixture.emptyFieldPredicate,
                                   MapSearchUITestFixture.emptyValue, MapSearchUITestFixture.placeholder),
            object: searchField)
        XCTAssertEqual(XCTWaiter.wait(for: [fieldCleared], timeout: MapSearchUITestFixture.timeout), .completed)
        XCTAssertFalse(clear.exists)
        XCTAssertTrue(app.staticTexts[MapSearchUITestFixture.idleHint].exists)
        // Close with nonempty raw input so reopening cannot pass merely because X already cleared it.
        searchField.tap()
        searchField.typeText(MapSearchUITestFixture.whitespaceQuery)
        let queryBeforeClose = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: MapSearchUITestFixture.valuePredicate,
                                   MapSearchUITestFixture.whitespaceQuery), object: searchField)
        XCTAssertEqual(XCTWaiter.wait(for: [queryBeforeClose], timeout: MapSearchUITestFixture.timeout), .completed)
        XCTAssertTrue(close.isHittable)
        close.tap()
        let screenDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: MapSearchUITestFixture.absentPredicate), object: screen)
        let closeDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: MapSearchUITestFixture.absentPredicate), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [screenDismissed, closeDismissed],
                                    timeout: MapSearchUITestFixture.timeout), .completed)
        let searchReturned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: MapSearchUITestFixture.existsPredicate), object: search)
        XCTAssertEqual(XCTWaiter.wait(for: [searchReturned], timeout: MapSearchUITestFixture.timeout), .completed)

        search.tap()
        XCTAssertTrue(screen.waitForExistence(timeout: MapSearchUITestFixture.timeout))
        XCTAssertTrue(searchField.waitForExistence(timeout: MapSearchUITestFixture.timeout))
        let freshField = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: MapSearchUITestFixture.emptyFieldPredicate,
                                   MapSearchUITestFixture.emptyValue, MapSearchUITestFixture.placeholder),
            object: searchField)
        XCTAssertEqual(XCTWaiter.wait(for: [freshField], timeout: MapSearchUITestFixture.timeout), .completed)
        XCTAssertFalse(clear.exists)
        XCTAssertTrue(title.exists)
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(app.staticTexts[MapSearchUITestFixture.idleHint].exists)
        close.tap()
        let freshScreenDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: MapSearchUITestFixture.absentPredicate), object: screen)
        XCTAssertEqual(XCTWaiter.wait(for: [freshScreenDismissed], timeout: MapSearchUITestFixture.timeout), .completed)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
