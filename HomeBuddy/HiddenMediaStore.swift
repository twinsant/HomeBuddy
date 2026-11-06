import AppKit
import Combine
import Foundation
import Security

/// App-level visibility control; it does not encrypt or modify the original media.
@MainActor
final class HiddenMediaStore: ObservableObject {
    static let shared = HiddenMediaStore()

    @Published private(set) var isHiding = true
    @Published private(set) var revision = 0
    private var hiddenIDs: Set<String> = []
    private var storageError: String?
    private let fileURL: URL?
    private let service = (Bundle.main.bundleIdentifier ?? "HomeBuddy") + ".hidden-media"
    private let account = "visibility-password"
    private let passwordReader: (() throws -> Data?)?
    private let passwordWriter: ((Data) throws -> Void)?
    private let prompt: ((Bool) -> String?)?
    private let errorPresenter: ((String) -> Void)?

    init(fileURL: URL? = nil, passwordReader: (() throws -> Data?)? = nil,
         passwordWriter: ((Data) throws -> Void)? = nil, prompt: ((Bool) -> String?)? = nil,
         errorPresenter: ((String) -> Void)? = nil) {
        self.passwordReader = passwordReader
        self.passwordWriter = passwordWriter
        self.prompt = prompt
        self.errorPresenter = errorPresenter
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("HomeBuddy", isDirectory: true)
            .appendingPathComponent("hidden-media.json")
        do {
            guard let url = self.fileURL else { throw CocoaError(.fileNoSuchFile) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                hiddenIDs = Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: url)))
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                hiddenIDs = []
            }
        } catch {
            storageError = error.localizedDescription
        }
    }

    static func identity(for asset: LibraryAsset) -> String {
        switch asset.source {
        case .photos:
            return "photos:" + asset.localIdentifier
        case .disk(let directory, let image):
            let url = URL(fileURLWithPath: directory.path, isDirectory: true)
                .appendingPathComponent(image.relativePath).standardizedFileURL.resolvingSymlinksInPath()
            return "file:" + url.path
        }
    }

    func isHidden(_ asset: LibraryAsset) -> Bool { hiddenIDs.contains(Self.identity(for: asset)) }

    var canShowUnfilteredCounts: Bool { storageError == nil && (!isHiding || hiddenIDs.isEmpty) }

    func isVisible(_ asset: LibraryAsset) -> Bool {
        storageError == nil && (!isHiding || !isHidden(asset))
    }

    func visibleAssets(_ assets: [LibraryAsset]) -> [LibraryAsset] {
        guard storageError == nil else { return [] }
        guard isHiding && !hiddenIDs.isEmpty else { return assets }
        return assets.filter(isVisible)
    }

    func setHiding(_ hiding: Bool) {
        guard hiding != isHiding else { return }
        guard storageError == nil else { showError(storageError ?? "无法读取隐藏记录。") ; return }
        if !hiding && !authenticate() { return }
        isHiding = hiding
        revision += 1
    }

    func toggleHidden(_ asset: LibraryAsset) {
        guard storageError == nil else { showError(storageError ?? "无法读取隐藏记录。") ; return }
        let id = Self.identity(for: asset)
        let wasHidden = hiddenIDs.contains(id)
        guard !wasHidden || !isHiding else { return }
        if !wasHidden, !ensurePassword() { return }
        var updated = hiddenIDs
        if wasHidden { updated.remove(id) } else { updated.insert(id) }
        do {
            guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
            try JSONEncoder().encode(updated.sorted()).write(to: fileURL, options: .atomic)
            hiddenIDs = updated
            revision += 1
        } catch { showError(error.localizedDescription) }
    }

    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func readPassword() throws -> Data? {
        if let passwordReader { return try passwordReader() }
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DiskLibraryError.message("无法读取钥匙串中的密码（\(status)）。")
        }
        return data
    }

    private func ensurePassword() -> Bool {
        do {
            if try readPassword() != nil { return true }
            guard hiddenIDs.isEmpty else {
                throw DiskLibraryError.message("无法找到隐藏内容的密码，请恢复原来的钥匙串。")
            }
            guard let password = passwordPrompt(creating: true) else { return false }
            if let passwordWriter {
                try passwordWriter(Data(password.utf8))
                return true
            }
            var query = keychainQuery
            query[kSecValueData as String] = Data(password.utf8)
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw DiskLibraryError.message("无法保存密码到钥匙串（\(status)）。") }
            return true
        } catch { showError(error.localizedDescription); return false }
    }

    private func authenticate() -> Bool {
        do {
            guard let saved = try readPassword() else {
                guard hiddenIDs.isEmpty else {
                    throw DiskLibraryError.message("无法找到隐藏内容的密码，请恢复原来的钥匙串。")
                }
                return ensurePassword()
            }
            guard let entered = passwordPrompt(creating: false) else { return false }
            guard Data(entered.utf8) == saved else {
                showError("密码不正确。")
                return false
            }
            return true
        } catch { showError(error.localizedDescription); return false }
    }

    private func passwordPrompt(creating: Bool) -> String? {
        if let prompt { return prompt(creating) }
        let alert = NSAlert()
        alert.messageText = AppLocalization.string(creating ? "设置隐藏内容密码" : "输入密码以显示隐藏内容")
        alert.informativeText = AppLocalization.string(creating
            ? "请设置至少 8 个字符的密码。密码保存在钥匙串中；忘记密码后无法通过应用恢复。此功能不会加密原文件。"
            : "输入隐藏内容密码以显示已隐藏的照片和视频。")
        alert.addButton(withTitle: AppLocalization.string(creating ? "设置密码" : "解锁"))
        alert.addButton(withTitle: AppLocalization.string("取消"))
        let first = NSSecureTextField(frame: NSRect(x: 0, y: creating ? 34 : 0, width: 280, height: 24))
        first.placeholderString = AppLocalization.string(creating ? "密码（至少 8 个字符）" : "密码")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: creating ? 58 : 24))
        container.addSubview(first)
        let confirm = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        if creating {
            confirm.placeholderString = AppLocalization.string("再次输入密码")
            container.addSubview(confirm)
        }
        alert.accessoryView = container
        alert.window.initialFirstResponder = first
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let password = first.stringValue
        if creating && (password.count < 8 || password != confirm.stringValue) {
            showError("密码至少需要 8 个字符，且两次输入必须一致。")
            return nil
        }
        return password
    }

    private func showError(_ message: String) {
        if let errorPresenter { errorPresenter(message); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = AppLocalization.string("隐藏内容操作失败")
        alert.informativeText = AppLocalization.string(message)
        alert.addButton(withTitle: AppLocalization.string("确定"))
        alert.runModal()
    }
}
