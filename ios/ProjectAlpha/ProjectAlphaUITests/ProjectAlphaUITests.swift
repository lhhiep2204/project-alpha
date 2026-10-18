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
    // NSArgumentDomain overrides only this process; localized copy assertions
    // remain independent of the user's persisted in-app language preference.
    static let englishAppPreferenceArguments = ["-CURRENT_LANGUAGE", "English"]
    static let englishMapLaunchArguments = launchArguments + englishAppPreferenceArguments
    static let existsPredicate = "exists == true"
    static let absentPredicate = "exists == false"
    static let valuePredicate = "value == %@"
    static let emptyFieldPredicate = "value == %@ OR value == %@"
    static let timeout: TimeInterval = 10
}

private enum SettingsUITestFixture {
    static let languagePicker = "settings.language"
    static let french = "français"
    static let frenchSettingsTitle = "Paramètres"
    static let frenchHomeTitle = "Mes collections"
    static let arabicSettingsTitle = "الإعدادات"
    static let staleNavigationTitle = "The navigation title did not follow the selected app language."
    static let arabic = "العربية"
    static let englishSystem = "System"
    static let frenchSystem = "Système"
    static let arabicSystem = "حسب النظام"
    static let backButton = "BackButton"
    static let hittablePredicate = "exists == true AND hittable == true"
    static let missingControl = "Required Settings control did not become usable."
    static let restoreFailed = "The language regression could not restore the original preference; inspect the attached accessibility tree."
    static let initialStateAttachment = "Settings language original preference and accessibility tree"
    static let restoreStateAttachment = "Settings language restoration accessibility tree"
    static let attachmentSeparator = "\n\n"
}

private enum SettingsUITestFailure: Error { case missingControl }


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
        app.launchArguments = MapSearchUITestFixture.englishMapLaunchArguments
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

    /// J-08, AC-36/60: native language selection closes its picker and applies
    /// the selected locale without resetting other destinations or preferences.
    @MainActor
    func testNativeLanguageSelectionDismissesPickerAndUpdatesApp() throws {
        // XCTest's stop-on-failure exception can bypass Swift defer. Keep failures
        // nonfatal here and explicitly throw before interacting with missing controls.
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = MapSearchUITestFixture.launchArguments
        app.launch()
        defer { app.terminate() }
        let settingsTab = app.tabBars.buttons.element(boundBy: 2)
        try tapSettingsControl(settingsTab)
        let picker = app.buttons[SettingsUITestFixture.languagePicker]
        try requireSettingsControl(picker)
        let initialValue = try XCTUnwrap(picker.value as? String)
        let initial = XCTAttachment(string: initialValue + SettingsUITestFixture.attachmentSeparator + app.debugDescription)
        initial.name = SettingsUITestFixture.initialStateAttachment
        initial.lifetime = .keepAlways
        add(initial)
        // Restoration avoids assertions until navigation and selection attempts finish.
        // This runs on successful completion and on every guarded failure below.
        defer {
            let restored = restoreSettingsLanguage(initialValue, in: app)
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = SettingsUITestFixture.restoreStateAttachment
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(restored, SettingsUITestFixture.restoreFailed)
        }
        try tapSettingsControl(picker)
        let french = app.buttons[SettingsUITestFixture.french]
        let arabic = app.buttons[SettingsUITestFixture.arabic]
        try tapSettingsControl(french)
        try requireSettingsNavigationTitle(SettingsUITestFixture.frenchSettingsTitle, in: app)
        try requireSettingsControl(picker)
        XCTAssertEqual(picker.value as? String, SettingsUITestFixture.french)
        try tapSettingsControl(app.tabBars.buttons.element(boundBy: 0))
        try requireSettingsNavigationTitle(SettingsUITestFixture.frenchHomeTitle, in: app)
        try tapSettingsControl(settingsTab)
        try tapSettingsControl(picker)
        try tapSettingsControl(arabic)
        try requireSettingsNavigationTitle(SettingsUITestFixture.arabicSettingsTitle, in: app)
        try requireSettingsControl(picker)
        XCTAssertEqual(picker.value as? String, SettingsUITestFixture.arabic)
    }

    @MainActor
    private func requireSettingsNavigationTitle(_ title: String, in app: XCUIApplication) throws {
        guard app.navigationBars[title].waitForExistence(timeout: MapSearchUITestFixture.timeout) else {
            XCTFail(SettingsUITestFixture.staleNavigationTitle)
            throw SettingsUITestFailure.missingControl
        }
    }

    @MainActor
    private func requireSettingsControl(_ control: XCUIElement) throws {
        guard settingsControlIsUsable(control) else {
            XCTFail(SettingsUITestFixture.missingControl)
            throw SettingsUITestFailure.missingControl
        }
    }

    @MainActor
    private func tapSettingsControl(_ control: XCUIElement) throws {
        try requireSettingsControl(control)
        control.tap()
    }

    @MainActor
    private func settingsControlIsUsable(_ control: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: SettingsUITestFixture.hittablePredicate), object: control)
        return XCTWaiter.wait(for: [expectation], timeout: MapSearchUITestFixture.timeout) == .completed
    }

    /// No failing assertions during cleanup: reach root, select the original choice,
    /// return to root, and verify the effective value before reporting a result.
    @MainActor
    private func restoreSettingsLanguage(_ initialValue: String, in app: XCUIApplication) -> Bool {
        let settingsTab = app.tabBars.buttons.element(boundBy: 2)
        guard settingsControlIsUsable(settingsTab) else { return false }
        settingsTab.tap()
        let picker = app.buttons[SettingsUITestFixture.languagePicker]
        let back = app.buttons[SettingsUITestFixture.backButton]
        if back.exists && back.isHittable { back.tap() }
        guard settingsControlIsUsable(picker) else { return false }
        if picker.value as? String == initialValue { return true }
        picker.tap()
        let systemLabels = [SettingsUITestFixture.englishSystem, SettingsUITestFixture.frenchSystem,
                            SettingsUITestFixture.arabicSystem]
        let isSystem = systemLabels.contains(initialValue)
        var original: XCUIElement {
            if isSystem {
                return systemLabels.map { app.buttons[$0] }.first { $0.exists && $0.isHittable }
                    ?? app.buttons[initialValue]
            }
            return app.buttons[initialValue]
        }
        // The original language may be below the current viewport. Start from the
        // first row (System) then scan the finite supported-language list.
        for _ in 0..<5 {
            if original.exists && original.isHittable { break }
            app.swipeDown()
        }
        for _ in 0..<8 {
            if original.exists && original.isHittable { break }
            app.swipeUp()
        }
        guard settingsControlIsUsable(original) else { return false }
        original.tap()
        if back.exists && back.isHittable { back.tap() }
        guard settingsControlIsUsable(picker) else { return false }
        return picker.value as? String == initialValue
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
