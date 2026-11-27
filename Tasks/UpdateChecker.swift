import AppKit

/// 更新相关的用户设置（存在 UserDefaults，随配置文件一起落盘）
enum UpdateSettings {
    static let autoUpdateKey = "autoUpdate"
    static let checkAtKey = "updateCheckAt"
    static let pendingVersionKey = "pendingUpdateVersion"

    /// 是否自动检查更新，默认开启。
    /// 只写 UserDefaults：CalendarStore 监听 UserDefaults 变化，会顺带写回配置文件
    static var autoUpdate: Bool {
        get { UserDefaults.standard.object(forKey: autoUpdateKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoUpdateKey) }
    }
}

/// 新版本信息
struct UpdateInfo {
    /// 版本号，如 0.3.2
    let version: String
    /// 更新说明（Markdown）
    let notes: String
    /// dmg 下载地址
    let downloadURL: URL?
    /// dmg 对应的 .sha256 校验文件地址
    let checksumURL: URL?
    /// Release 页地址
    let pageURL: URL
}

/// 检查更新结果
enum UpdateCheckResult {
    case upToDate
    case updateAvailable(UpdateInfo)
    case failed(String)
}

/// 检查更新：查 GitHub 最新正式版 Release，与当前版本比较。
/// 沙箱内不能自己替换 /Applications，所以只负责「查 + 下载校验 + 打开 dmg」，安装由用户拖进「应用程序」。
/// 网络回调在后台，解析与回调统一切回主线程。
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// 启动后首次自动检查的延迟（秒），避开开机时网络还没就绪
    private let initialDelay: TimeInterval = 20

    /// 自动检查间隔（秒）：常驻 App，6 小时查一次
    private let interval: TimeInterval = 6 * 60 * 60

    private var timer: Timer?

    /// 开始自动检查：开关关掉或本地开发构建都不查。
    /// 发现新版本不弹窗打扰，只记到设置里，用户打开「关于」页才看到。
    func startAutomaticChecks() {
        guard UpdateSettings.autoUpdate, AppInfo.channel != "dev" else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
            guard let self = self else { return }

            self.checkSilently()
            self.timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in
                self?.checkSilently()
            }
        }
    }

    private func checkSilently() {
        guard UpdateSettings.autoUpdate else { return }

        check { result in
            UserDefaults.standard.set(Date(), forKey: UpdateSettings.checkAtKey)
            guard case let .updateAvailable(update) = result else { return }

            UserDefaults.standard.set(update.version, forKey: UpdateSettings.pendingVersionKey)
        }
    }

    /// 检查更新，回调在主线程
    func check(completion: @MainActor @escaping (UpdateCheckResult) -> Void) {
        var request = URLRequest(url: AppInfo.latestReleaseAPI)
        request.setValue("CalendarTasks", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            Task { @MainActor in
                completion(Self.makeResult(data: data, response: response, error: error))
            }
        }.resume()
    }

    private static func makeResult(data: Data?, response: URLResponse?, error: Error?) -> UpdateCheckResult {
        if let error = error {
            return .failed(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }

        if status == 404 {
            return .failed("没找到正式版发布。若仓库是私有的，请先设为公开。")
        }

        guard (200 ... 299).contains(status) else {
            let message = (json?["message"] as? String) ?? "HTTP \(status)"
            return .failed("检查更新失败：\(message)")
        }

        guard let json = json, let tag = json["tag_name"] as? String else {
            return .failed("无法解析更新信息")
        }

        let latest = normalizeVersion(tag)
        guard isVersion(latest, newerThan: AppInfo.version) else { return .upToDate }

        let notes = (json["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pageURL = (json["html_url"] as? String).flatMap { URL(string: $0) } ?? AppInfo.repositoryURL
        let assets = assetURLs(from: json)
        let dmg = assets.keys.first { $0.hasSuffix(".dmg") }

        return .updateAvailable(UpdateInfo(version: latest,
                                           notes: notes,
                                           downloadURL: dmg.flatMap { assets[$0] },
                                           checksumURL: dmg.flatMap { assets[$0 + ".sha256"] },
                                           pageURL: pageURL))
    }

    /// assets 的「文件名 → 下载地址」
    private static func assetURLs(from json: [String: Any]) -> [String: URL] {
        let assets = json["assets"] as? [[String: Any]] ?? []
        var result: [String: URL] = [:]
        for asset in assets {
            if let name = asset["name"] as? String,
               let urlString = asset["browser_download_url"] as? String,
               let url = URL(string: urlString) {
                result[name] = url
            }
        }

        return result
    }

    /// 归一化版本号：去掉前导 v 与 -beta 之类后缀，只留 x.y.z
    static func normalizeVersion(_ tag: String) -> String {
        var value = tag
        if value.hasPrefix("v") { value.removeFirst() }
        if let dash = value.firstIndex(of: "-") { value = String(value[..<dash]) }

        return value
    }

    /// 语义化比较：a 是否比 b 新
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }

        for index in 0 ..< max(pa.count, pb.count) {
            let x = index < pa.count ? pa[index] : 0
            let y = index < pb.count ? pb[index] : 0
            if x != y { return x > y }
        }

        return false
    }
}