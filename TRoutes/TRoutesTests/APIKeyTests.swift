//
//  TRoutesTests.swift
//  TRoutesTests
//
//  Created by Adam Post on 8/25/26.
//

import Foundation
import Testing
@testable import TRoutes

struct APIKeyResponseValidationTests {

    @Test func acceptsSuccessfulResponseWithAuthenticatedRateLimit() throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://api-v3.mbta.com/routes")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-ratelimit-limit": "1000"]
            )
        )

        #expect(isValidAPIKeyResponse(response))
    }

    @Test func rejectsErrorResponseWithAuthenticatedRateLimit() throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://api-v3.mbta.com/routes")!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["x-ratelimit-limit": "1000"]
            )
        )

        #expect(!isValidAPIKeyResponse(response))
    }

    @Test func rejectsSuccessfulResponseWithAnonymousRateLimit() throws {
        let response = try #require(
            HTTPURLResponse(
                url: URL(string: "https://api-v3.mbta.com/routes")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["x-ratelimit-limit": "20"]
            )
        )

        #expect(!isValidAPIKeyResponse(response))
    }

    @Test func rejectsNonHTTPResponse() {
        let response = URLResponse(
            url: URL(string: "https://api-v3.mbta.com/routes")!,
            mimeType: nil,
            expectedContentLength: 0,
            textEncodingName: nil
        )

        #expect(!isValidAPIKeyResponse(response))
    }

}
