import Foundation

enum OAuthHelper {
    struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int?
        let refresh_token: String?
    }

    static func refreshToken(
        url: String,
        clientId: String,
        refreshToken: String,
        grantType: String = "refresh_token",
        extraParams: [String: String] = [:]
    ) async throws -> TokenResponse {
        guard let requestURL = URL(string: url) else {
            throw PlatformError.unknown("Invalid OAuth URL")
        }

        var params = [
            "grant_type": grantType,
            "client_id": clientId,
            "refresh_token": refreshToken,
        ]
        for (k, v) in extraParams {
            params[k] = v
        }

        let body = params.map { "\($0.key)=\($0.value.urlEncoded())" }.joined(separator: "&")

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = Constants.networkTimeout
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PlatformError.invalidAPIKey
        }

        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}
