//
//  APIClient.swift
//  FoodTracker
//
//  负责和后端通信：上传照片识别（/analyze）、生成食谱（/recipes）、查询剩余次数（/quota）。
//

import Foundation

/// 调用后端时可能出现的错误。errorDescription 是显示给用户的说明。
enum APIError: LocalizedError {
    case offline  // 手机没联网
    case timeout  // 等太久没有回应
    case cannotConnect(code: Int)  // 连不上后端（比如后端没启动，或云端服务器还在唤醒）
    case server(String)  // 后端返回了错误说明
    case badResponse  // 返回的数据看不懂

    var errorDescription: String? {
        switch self {
        case .offline:
            "手机没有联网，请检查网络设置。"
        case .timeout:
            AppConfig.isCloud
                ? "服务器没有及时响应。免费服务器闲置后会休眠，唤醒大约需要 1 分钟，请稍等一下再试。"
                : "等待超时，请检查网络后重试。"
        case .cannotConnect(let code):
            AppConfig.isCloud
                ? "连不上服务器（错误码 \(code)）。请检查手机网络，或稍等 1 分钟再试。"
                : "连不上后端服务（错误码 \(code)）。请确认电脑上的后端正在运行。"
        case .server(let message):
            message
        case .badResponse:
            "后端返回的数据格式不对，请稍后再试。"
        }
    }
}

enum APIClient {
    // MARK: - 接口

    /// 把 JPEG 照片发给后端识别，返回识别结果。
    /// - Parameter lang: 结果用什么语言，"zh" 中文或 "en" 英文
    static func analyze(jpegData: Data, lang: String) async throws -> AnalyzeResult {
        // 照片用 multipart/form-data 格式上传（网页上传文件用的就是这种格式）
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = makeRequest(path: "analyze", method: "POST", timeout: 120)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(jpegData: jpegData, lang: lang, boundary: boundary)
        return try await send(request)
    }

    /// 根据目标和偏好生成食谱
    static func recipes(_ body: RecipeRequest) async throws -> RecipesResult {
        // 服务器最坏情况约 145 秒（排队 25 秒 + 两次 AI 调用各 60 秒），App 要比它多等一会儿
        var request = makeRequest(path: "recipes", method: "POST", timeout: 180)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase  // dailyCalories → daily_calories
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    /// 今天还能识别几次、生成几次食谱
    static func quota() async throws -> Quota {
        try await send(makeRequest(path: "quota", method: "GET", timeout: 90))
    }

    /// 叫醒服务器：App 启动时悄悄访问一次 /health。
    /// 免费的云端服务器闲置 15 分钟就会休眠，提前叫醒，用户点识别时就不用等了。失败也没关系。
    static func warmUp() async {
        _ = try? await URLSession.shared.data(for: makeRequest(path: "health", method: "GET", timeout: 90))
    }

    // MARK: - 公共部分

    /// 准备一个请求：拼上后端地址，带上设备 ID 和 App 密钥
    private static func makeRequest(path: String, method: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: AppConfig.backendURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(DeviceID.current, forHTTPHeaderField: "X-Device-ID")
        if !AppConfig.appKey.isEmpty {
            request.setValue(AppConfig.appKey, forHTTPHeaderField: "X-App-Key")
        }
        return request
    }

    /// 发送请求，检查状态码，把返回的 JSON 转成需要的类型
    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        // 1. 发送请求，等待回应；网络层面的错误转成中文说明
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw apiError(from: error)
        }

        // 2. 检查状态码：200 表示成功，其他情况后端会返回 {"detail": "错误说明"}
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        guard http.statusCode == 200 else {
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw APIError.server(body.detail)
            }
            // 云端服务器唤醒过程中，Render 可能先返回一个不含 JSON 的页面
            if AppConfig.isCloud && (500...599).contains(http.statusCode) {
                throw APIError.server("服务器正在启动，请稍等 1 分钟再试。")
            }
            throw APIError.server("服务器出错（错误码 \(http.statusCode)），请稍后再试。")
        }

        // 3. 把 JSON 转成需要的类型
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase  // is_food → isFood
        do {
            return try decoder.decode(T.self, from: data)
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
