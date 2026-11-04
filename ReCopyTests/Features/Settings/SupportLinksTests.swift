import Foundation
import Testing
@testable import ReCopy

struct SupportLinksTests {
    @Test func bugReportGoesToAdminWithVersions() throws {
        let url = try #require(SupportLinks.bugReport(appVersion: "1.2.3 (4)", systemVersion: "Version 26.0"))
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "help.me@lazycatlabs.com")
        let body = components.queryItems?.first { $0.name == "body" }?.value ?? ""
        #expect(body.contains("1.2.3 (4)") && body.contains("Version 26.0"))
    }

    @Test func feedbackHasNoEmptyBody() throws {
        let url = try #require(SupportLinks.feedback())
        #expect(!url.absoluteString.contains("body="))
    }
}
