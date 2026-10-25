import Foundation

/// A lightweight logger for API responses.
enum NetworkLogger {
    /// Formats network response details into a readable string.
    static func formatMessage(
        url: URL?,
        parameters: [String: Any]? = nil,
        statusCode: Int,
        data: Data
    ) -> String {
        let urlString = url?.absoluteString ?? "N/A"
        let paramsDescription: String
        if let parameters, !parameters.isEmpty {
            if JSONSerialization.isValidJSONObject(parameters),
               let paramData = try? JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]),
               let paramString = String(data: paramData, encoding: .utf8) {
                paramsDescription = paramString
            } else {
                let sortedPairs = parameters
                    .sorted { $0.key < $1.key }
                    .map { "\"\($0.key)\": \($0.value)" }
                    .joined(separator: ", ")
                paramsDescription = "[\(sortedPairs)]"
            }
        } else {
            paramsDescription = "None"
        }

        let jsonString = prettyPrintedJSON(from: data)

        return """
        ========================================
        [API Response]
        URL: \(urlString)
        Parameters: \(paramsDescription)
        Response Code: \(statusCode)
        Response Data:
        \(jsonString)
        ========================================
        """
    }

    /// Logs network response details to the console in DEBUG mode only.
    static func logResponse(
        url: URL?,
        parameters: [String: Any]? = nil,
        statusCode: Int,
        data: Data
    ) {
        #if DEBUG
        let message = formatMessage(
            url: url,
            parameters: parameters,
            statusCode: statusCode,
            data: data
        )
        print(message)
        #endif
    }

    /// Logs an endpoint response to the console in DEBUG mode only.
    static func logResponse(
        endpoint: Endpoint,
        url: URL?,
        response: HTTPURLResponse,
        data: Data
    ) {
        #if DEBUG
        var params: [String: Any] = [:]
        for item in endpoint.queryItems {
            params[item.name] = item.value ?? ""
        }
        if params.isEmpty,
           let url,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            for item in items {
                params[item.name] = item.value ?? ""
            }
        }
        logResponse(
            url: url,
            parameters: params.isEmpty ? nil : params,
            statusCode: response.statusCode,
            data: data
        )
        #endif
    }

    /// Converts raw JSON data into a formatted, pretty-printed JSON string.
    static func prettyPrintedJSON(from data: Data) -> String {
        guard !data.isEmpty else { return "(Empty)" }
        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return String(data: data, encoding: .utf8) ?? "(Non-UTF8 Data)"
    }
}
