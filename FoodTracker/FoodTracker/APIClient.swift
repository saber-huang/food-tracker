//
//  APIClient.swift
//  FoodTracker
//
//  负责和后端通信：把照片发给 /analyze 接口，拿回识别结果。
//

import Foundation

/// 调用后端时可能出现的错误。errorDescription 是显示给用户的说明。
enum APIError: LocalizedError {
    case offline  // 手机没联网
    case timeout  // 等太久没有回应
    case cannotConnect(code: Int)  // 连不上后端（比如后端没启动）
    case server(String)  // 后端返回了错误说明
    case badResponse  // 返回的数据看不懂

    var errorDescription: String? {
        switch self {
        case .offline:
            "手机没有联网，请检查网络设置。"
        case .timeout:
            "识别超时，请检查网络后重试。"
        case .cannotConnect(let code):
            "连不上后端服务（错误码 \(code)）。请确认电脑上的后端正在运行。"
        case .server(let message):
            message
        case .badResponse:
            "后端返回的数据格式不对，请稍后再试。"
        }
    }
}

enum APIClient {
    /// 把 JPEG 照片发给后端识别，返回识别结果。
    /// - Parameter lang: 结果用什么语言，"zh" 中文或 "en" 英文
    static func analyze(jpegData: Data, lang: String) async throws -> AnalyzeResult {
        // 1. 准备请求：POST 到 /analyze，内容用 multipart/form-data 格式（网页上传文件用的就是这种格式）
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: AppConfig.backendURL.appending(path: "analyze"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90  // AI 识别一般 5～15 秒，这里留足余量
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(jpegData: jpegData, lang: lang, boundary: boundary)

        // 2. 发送请求，等待回应；网络层面的错误转成中文说明
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw apiError(from: error)
        }

        // 3. 检查状态码：200 表示成功，其他情况后端会返回 {"detail": "错误说明"}
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        guard http.statusCode == 200 else {
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw APIError.server(body.detail)
            }
            throw APIError.server("服务器出错（错误码 \(http.statusCode)），请稍后再试。")
        }

        // 4. 把 JSON 转成 AnalyzeResult
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase  // is_food → isFood
        do {
            return try decoder.decode(AnalyzeResult.self, from: data)
        } catch {
            throw APIError.badResponse
        }
    }

    /// 拼出 multipart/form-data 格式的请求内容：一个 lang 字段 + 一个 photo 文件
    private static func multipartBody(jpegData: Data, lang: String, boundary: String) -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }

        // 普通字段：lang
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"lang\"\r\n\r\n")
        append("\(lang)\r\n")

        // 文件字段：photo（名字要和后端 main.py 里的参数名一致）
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"photo\"; filename=\"meal.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        append("\r\n")

        // 结束标记
        append("--\(boundary)--\r\n")
        return body
    }

    /// 把系统的网络错误翻译成用户看得懂的说明
    private static func apiError(from error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            .offline
        case .timedOut:
            .timeout
        default:
            // 包括后端没启动、找不到电脑等情况；带上错误码，方便排查
            .cannotConnect(code: error.code.rawValue)
        }
    }
}

/// 后端出错时返回的格式：{"detail": "错误说明"}
private struct ErrorBody: Decodable {
    let detail: String
}
