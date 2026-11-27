import AppKit
import CryptoKit

/// 下载并准备好新版安装包：下载 dmg → 按 Release 附带的 .sha256 校验 → 用访达打开 dmg，
/// 由用户把新版本拖进「应用程序」替换。
///
/// 为什么不让 App 自己替换 /Applications：本 App 开了沙箱，实测即使加
/// `temporary-exception.files.absolute-path.read-write` 也无法在 /Applications 新建文件（系统/App Management 保护），
/// 所以安装最后一步交给用户，换取「打开系统日历不额外弹授权」的现有体验。
/// 为什么不自己 `hdiutil attach`：沙箱内实测报「设备未配置」（2026-11-27，同一 dmg 沙箱外可挂载），
/// 改由访达打开 dmg，系统负责挂载并弹出窗口。BundleID、签名的核对交给系统打开时的 Gatekeeper。
/// 下载在串行队列里跑，isWorking 只在主线程读写。
nonisolated final class UpdateInstaller: @unchecked Sendable {
    static let shared = UpdateInstaller()

    /// 是否正在下载或准备（只在主线程读写）
    private(set) var isWorking = false

    private let queue = DispatchQueue(label: "io.github.andym129.calendartasks.update")

    /// 下载目录（主线程 prepare 时定好），留在磁盘上便于用户重复打开 dmg
    private var workRoot: URL?

    /// 开始准备安装（主线程调用）。成功后回调空串表示已打开 dmg；失败回调给用户看的原因
    @MainActor
    func prepare(_ update: UpdateInfo, completion: @MainActor @escaping (String) -> Void) {
        guard !isWorking else { return }

        guard let dmgURL = update.downloadURL else {
            Task { @MainActor in completion("该版本没有提供安装包。") }
            return
        }

        isWorking = true

        // 后台队列里不碰主线程隔离的类型，主目录由主线程带过去
        workRoot = ConfigFile.realHome
            .appending(path: ".config/CalendarTasks/update", directoryHint: .isDirectory)

        queue.async {
            do {
                let dmg = try self.downloadVerified(update, dmgURL: dmgURL)
                Task { @MainActor in
                    self.isWorking = false
                    if NSWorkspace.shared.open(dmg) {
                        completion("")
                    } else {
                        completion("无法打开安装包，可在访达中打开：\(dmg.path)")
                    }
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

    /// 下载并校验，返回本地 dmg；已下载过且校验通过就直接复用
    private func downloadVerified(_ update: UpdateInfo, dmgURL: URL) throws -> URL {
        let fm = FileManager.default
        guard let workRoot = workRoot else {
            throw InstallError.message("没有可用的下载目录。")
        }
        let work = workRoot.appending(path: update.version, directoryHint: .isDirectory)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let dmg = work.appending(path: dmgURL.lastPathComponent)
        if fm.fileExists(atPath: dmg.path) {
            // 已下载过：再校验一次，防止上次没下完或被改动
            do {
                try verify(dmg, checksumURL: update.checksumURL, work: work)
                return dmg
            } catch {
                try? fm.removeItem(at: dmg)
            }
        }

        let partial = work.appending(path: dmgURL.lastPathComponent + ".download")
        try? fm.removeItem(at: partial)
        try download(dmgURL, to: partial)
        try verify(partial, checksumURL: update.checksumURL, work: work)
        try fm.moveItem(at: partial, to: dmg)
        return dmg
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
                    try? FileManager.default.removeItem(at: destination)
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

    private func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
