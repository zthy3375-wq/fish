import XCTest
@testable import Hanyuantong

final class MedalParityTests:XCTestCase {
    @MainActor func testScopeIsolationAndPermanentDeviceAwards() throws {
        let key=UUID().uuidString; let defaults=try XCTUnwrap(UserDefaults(suiteName:key))
        defer { defaults.removePersistentDomain(forName:key) }
        let journal=MedalJournal(defaults:defaults)
        XCTAssertEqual(Set(CampusMedal.catalog.map(\.code)).count,32)
        XCTAssertEqual(CampusMedal.catalog.filter{$0.hidden == true}.count,8)
        journal.unlock("schedule",scope:"A"); journal.unlock("schedule",scope:"B")
        let m=try XCTUnwrap(CampusMedal.byCode["schedule"])
        let date=try XCTUnwrap(journal.stamp(m,scope:"A"))
        journal.unlock("schedule",scope:"A"); XCTAssertEqual(date,journal.stamp(m,scope:"A"))
        XCTAssertNil(journal.stamp(m,scope:nil)); XCTAssertNil(journal.stamp(m,scope:"C"))
        journal.unlock("firstpost",scope:"A")
        XCTAssertNil(journal.stamp(try XCTUnwrap(CampusMedal.byCode["firstpost"]),scope:"A"))
        for code in ["bath","map","laundry"] { journal.unlock(code) }
        let reopened=MedalJournal(defaults:defaults)
        XCTAssertNotNil(reopened.stamp(try XCTUnwrap(CampusMedal.byCode["life"]),scope:nil))
    }
    @MainActor func testPinSetIsScopedAndRejectsLockedOrPublicMedals() throws {
        let key=UUID().uuidString
        let defaults=try XCTUnwrap(UserDefaults(suiteName:key))
        defer { defaults.removePersistentDomain(forName:key) }
        let j=MedalJournal(defaults:defaults)
        for code in ["schedule","firstpost","grade"] {
            let m=try XCTUnwrap(CampusMedal.byCode[code])
            if code != "grade" { j.unlock(code,scope:"alpha") }
            j.togglePin(m,school:"alpha",learning:nil)
        }
        XCTAssertEqual(j.pinned(school:"alpha",learning:nil),["schedule"])
        XCTAssertTrue(j.pinned(school:"beta",learning:nil).isEmpty)
    }
    func testTapSequenceRequiresConsecutiveGestures() {
        var counter=TapSequence(); let start=Date()
        for i in 0..<4 { XCTAssertFalse(counter.tap(target:5,at:start.addingTimeInterval(Double(i)/10))) }
        XCTAssertFalse(counter.tap(target:5,at:start.addingTimeInterval(8)))
        for i in 1...3 { XCTAssertFalse(counter.tap(target:5,at:start.addingTimeInterval(8+Double(i)/10))) }
        XCTAssertTrue(counter.tap(target:5,at:start.addingTimeInterval(8.4)))
    }
    func testIdentityProjectionAndLegacyPayload() throws {
        let old=try JSONDecoder().decode(TreeholeAuthor.self,from:Data(#"{"name":"校友","mine":false,"anonymous":false}"#.utf8))
        XCTAssertNil(old.badges)
        let badges=MemberBadges(official:HonorStamp(code:"contributor",at:nil),worn:HonorStamp(code:"developer",at:nil))
        XCTAssertTrue(badges.visible.isEmpty)
    }
}
