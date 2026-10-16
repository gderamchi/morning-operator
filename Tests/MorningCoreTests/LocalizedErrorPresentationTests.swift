import Foundation
import Testing
@testable import MorningCore

@Suite("App-owned error presentation")
struct LocalizedErrorPresentationTests {
    @Test func typedErrorKeepsItsMeaningAndUnknownDiagnosticsStayPrivate() throws {
        struct KnownError: LocalizedError {
            var errorDescription: String? { "Exact app-controlled explanation." }
        }
        struct EmptyError: LocalizedError { var errorDescription: String? { " \n " } }
        let privateDiagnostic = "PRIVATE_PATH /private/customer/request?token=secret"
        let unknown = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: privateDiagnostic, "PrivateRequest": "PRIVATE_JSON_SOURCE"])
        #expect(KnownError().moreDescription == "Exact app-controlled explanation.")
        #expect(!unknown.moreDescription.contains("PRIVATE_PATH"))
        #expect(!unknown.moreDescription.contains("token=secret"))
        #expect(EmptyError().moreDescription == unknown.moreDescription)
        let encoded = try JSONEncoder().encode(["message": unknown.moreDescription])
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("PRIVATE_JSON_SOURCE") && !json.contains("PRIVATE_PATH") && !json.contains("token=secret"))
        #expect(try JSONDecoder().decode([String: String].self, from: encoded)["message"] == unknown.moreDescription)
    }
}
