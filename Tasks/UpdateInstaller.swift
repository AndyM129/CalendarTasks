import AppKit
import CryptoKit

/// 下载并准备好新版安装包：下载 dmg → 按 Release 附带的 .sha256 校验 → 挂载 → 核对 BundleID / 版本 / 签名
/// → 在访达里打开挂载卷，由用户把新版本拖进「应用程序」替换。
///
/// 为什么不让 App 自己替换 /Applications：本 App 开了沙箱，实测即使加
/// `temporary-exception.files.absolute-path.read-write` 也无法在 /Applications 新建文件（系统/App Management 保护），
/// 所以安装最后一步交给用户，换取「打开系统日历不额外弹授权」的现有体验。
/// 下载与挂载在串行队列里跑，isWorking / mounted 只在主线程或该队列里读写。
nonisolated final class UpdateInstaller: @unchecked Sendable {
    static let shared = UpdateInstaller()

    /// 是否正在下载或准备（只在主线程读写）
    private(set) var isWorking = false

    private let queue = DispatchQueue(label: "io.github.andym129.calendartasks.update")

    /// 下载与挂载的工作目录（主线程 prepare 时定好），留在磁盘上便于用户重复打开 dmg
    private var workRoot: URL?

    /// 本次运行里已经挂载好的 dmg 与挂载点，避免每次点都新挂一份
    private var mounted: (dmg: URL, mount: URL)?

    /// 开始准备安装（主线程调用）。成功后回调空串表示已打开 dmg；失败回调给用户看的原因
    @MainActor
    func prepare(_ update: UpdateInfo, completion: @MainActor @escaping (String) -> Void) {
        guard !isWorking else { return }

        guard let dmgURL = update.downloadURL else {
            Task { @MainActor in completion("该版本没有提供安装包。") }
            return
        }

        isWorking = true

        // 后台队列里不碰主线程隔离的类型：主目录、App 名、BundleID 都由主线程带过去
        workRoot = ConfigFile.realHome
            .appending(path: ".config/CalendarTasks/update", directoryHint: .isDirectory)
        let name = AppInfo.name
        let bundleID = Bundle.main.bundleIdentifier ?? ""

        queue.async {
            do {
                let mount = try self.prepareFiles(update, dmgURL: dmgURL, appName: name, bundleID: bundleID)
                Task { @MainActor in
                    self.isWorking = false
                    NSWorkspace.shared.open(mount)
                    completion("")
                }
            } catch {
                Task { @MainActor in
                    self.isWorking = false
                    completion(error.localizedDescription)
                }
            }
        }
    }

    private enum InstallError: LocalizedError {
        case message(String)

        var errorDescription: String? {
            if case let .message(text) = self { return text }
            return nil
        }
    }

    /// 下载、校验、挂载，返回 dmg 的挂载点
    private func prepareFiles(_ update: UpdateInfo, dmgURL: URL, appName: String, bundleID: String) throws -> URL {
        let fm = FileManager.default
        guard let workRoot = workRoot else {
            throw InstallError.message("没有可用的下载目录。")
        }
        let work = workRoot.appending(path: update.version, directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let dmg = work.appending(path: dmgURL.lastPathComponent)
        if !fm.fileExists(atPath: dmg.path) {
            try download(dmgURL, to: dmg)
            try verify(dmg, checksumURL: update.checksumURL, work: work)
        }

        // 本次运行已挂载过同一个 dmg 就直接复用
        if let mounted = mounted, mounted.dmg == dmg { return mounted.mount }

        let output = try runTool("/usr/bin/hdiutil",
                                ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen"],
                                failure: "挂载安装包失败")
        guard let mount = output.split(whereSeparator: \.isNewline)
            .map(String.init)
            .first(where: { $0.hasPrefix("/Volumes/") })
            .flatMap({ URL(filePath: $0, directoryHint: .isDirectory) })
        else {
            throw InstallError.message("挂载后没找到安装包位置。")
        }

        _ = try findApp(in: mount, version: update.version, appName: appName, bundleID: bundleID)
        mounted = (dmg, mount)
        return mount
    }

    /// 同步下载到指定位置
    private func download(_ url: URL, to destination: URL) throws {
        var request = URLRequest(url: url)
        request.setValue("CalendarTasks", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120

        let done = DispatchSemaphore(value: 0)
        var failure: String?
        URLSession.shared.downloadTask(with: request) { location, response, error in
            defer { done.signal() }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error {
                failure = "下载失败：\(error.localizedDescription)"
            } else if !(200 ... 299).contains(status) {
                failure = "下载失败：HTTP \(status)"
            } else if let location {
                do {
                    try FileManager.default.moveItem(at: location, to: destination)
                } catch {
                    failure = "保存安装包失败：\(error.localizedDescription)"
                }
            }
        }.resume()
        done.wait()

        if let failure { throw InstallError.message(failure) }
    }

    /// Release 附带 .sha256 时必须一致；没有附带时跳过（旧版本发布可能没有）
    private func verify(_ dmg: URL, checksumURL: URL?, work: URL) throws {
        guard let checksumURL = checksumURL else { return }

        let file = work.appending(path: "checksum.sha256")
        try download(checksumURL, to: file)
        let expected = (try? String(contentsOf: file, encoding: .utf8))?
            .split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased()
        let actual = try sha256(of: dmg)
        guard let expected, expected == actual else {
            throw InstallError.message("安装包校验失败（SHA-256 不一致），已取消。")
        }
    }

    /// 在挂载目录里找 BundleID 一致、版本号相符、签名完整的 .app
    private func findApp(in mount: URL, version: String, appName: String, bundleID: String) throws -> URL {
        let items = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
        guard let app = items.first(where: {
            $0.pathExtension == "app" && Bundle(url: $0)?.bundleIdentifier == bundleID
        }) else {
            throw InstallError.message("安装包里没找到 \(appName).app。")
        }

        let newVersion = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard newVersion == version else {
            throw InstallError.message("安装包版本（\(newVersion ?? "未知")）与 v\(version) 不一致。")
        }

        try runTool("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], failure: "新版本签名校验失败")
        return app
    }

    private func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 运行系统工具，非 0 退出码时抛出带输出的错误
    @discardableResult
    private func runTool(_ path: String, _ args: [String], failure: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallError.message(detail.isEmpty ? "\(failure)。" : "\(failure)：\(detail)")
        }
        return output
    }
}