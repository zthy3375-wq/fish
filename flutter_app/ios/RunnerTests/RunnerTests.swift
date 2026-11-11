import Foundation
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
    func testAllowsExactSchoolHTTPSOrigin() {
        let urls = [
            "https://jwgl.hdc.edu.cn",
            "https://jwgl.hdc.edu.cn/xtgl/login_slogin.html",
            "https://jwgl.hdc.edu.cn/xtgl/index_initMenu.html",
            "https://jwgl.hdc.edu.cn:443/kbcx/xskbcx_cxXsgrkb.html?gnmkdm=N253508"
        ]
        for url in urls {
            XCTAssertTrue(AcademicSession.allowed(URL(string: url)), url)
        }
    }

    func testRejectsInsecureSchemesAndNonstandardPorts() {
        let urls = [
            "http://jwgl.hdc.edu.cn/",
            "http://jwgl.hdc.edu.cn:443/",
            "https://jwgl.hdc.edu.cn:80/",
            "https://jwgl.hdc.edu.cn:444/",
            "https://jwgl.hdc.edu.cn:8443/",
            "file:///xtgl/login_slogin.html",
            "javascript:alert(1)",
            "data:text/html,test"
        ]
        for url in urls {
            XCTAssertFalse(AcademicSession.allowed(URL(string: url)), url)
        }
    }

    func testRejectsUserInfoIncludingEmptyUserInfo() {
        let urls = [
            "https://student@jwgl.hdc.edu.cn/",
            "https://student:password@jwgl.hdc.edu.cn/",
            "https://:password@jwgl.hdc.edu.cn/",
            "https://@jwgl.hdc.edu.cn/",
            "https://jwgl.hdc.edu.cn@evil.example/"
        ]
        for url in urls {
            XCTAssertFalse(AcademicSession.allowed(URL(string: url)), url)
        }
    }

    func testRejectsLookalikeSubdomainAndParentHosts() {
        let urls = [
            "https://jwgl.hdc.edu.cn.evil.example/",
            "https://other.jwgl.hdc.edu.cn/",
            "https://jwgl-hdc.edu.cn/",
            "https://jwgl.hdc.edu.com/",
            "https://hdc.edu.cn/",
            "https://jwgl.hdc.edu.cn./",
            "https://evil.example/?next=https://jwgl.hdc.edu.cn/"
        ]
        for url in urls {
            XCTAssertFalse(AcademicSession.allowed(URL(string: url)), url)
        }
    }

    func testRejectsMissingAndRelativeURLs() {
        XCTAssertFalse(AcademicSession.allowed(nil))
        XCTAssertFalse(AcademicSession.allowed(URL(string: "/xtgl/login_slogin.html")))
        XCTAssertFalse(AcademicSession.allowed(URL(string: "//jwgl.hdc.edu.cn/")))
    }
}
