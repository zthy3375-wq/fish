import Foundation
import Combine

@MainActor
final class ParcelStore: ObservableObject {
    @Published private(set) var caches: [ParcelProvider: ParcelCache] = [:]
    @Published private(set) var notices: [ParcelProvider: String] = [:]
    @Published var activeSession: ParcelSession?
    @Published var message: String?
    private var envelopes: [ParcelProvider: ParcelEnvelope] = [:]
    private var blocked = Set<ParcelProvider>()
    private var vault: ParcelVault?
    private var runningSession: ParcelSession?
    init(storage: ProtectedStorage? = nil) {
        do {
            let vault = ParcelVault(storage: try storage ?? ProtectedStorage()); self.vault = vault
            for provider in ParcelProvider.allCases {
                do {
                    if let saved = try vault.read(provider) { envelopes[provider] = saved; caches[provider] = saved.cache }
                } catch let failure as ParcelFailure where failure == .account {
                    // Expired or ambiguous identity is never shown as a current account.
                    do { try vault.remove(provider) }
                    catch { blocked.insert(provider) }
                    notices[provider] = "旧登录已失效或无法确认，请重新在官方页连接。"
                } catch {
                    blocked.insert(provider); notices[provider] = ParcelFailure.storage.localizedDescription
                }
            }
        } catch { message = ParcelFailure.storage.localizedDescription }
    }
    func cookies(for provider: ParcelProvider) -> [HTTPCookie] { envelopes[provider]?.cookies.compactMap(\.cookie) ?? [] }
    func open(_ provider: ParcelProvider) {
        close()
        let session = ParcelSession(provider: provider, account: caches[provider]?.account,
            received: { [weak self] batch, account, cookies in
                guard let self else { throw ParcelFailure.cancelled }
                try self.accept(batch, account: account, cookies: cookies)
            }, invalidated: { [weak self] in self?.invalidate(provider) })
        runningSession = session; activeSession = session
    }
    func close() { runningSession?.close(); runningSession = nil; activeSession = nil }
    private func accept(_ batch: ParcelReadBatch, account: String, cookies: [HTTPCookie]) throws {
        guard let vault, !blocked.contains(batch.provider) else { throw ParcelFailure.storage }
        let provider = batch.provider
        if let previous = caches[provider], previous.account != account {
            caches.removeValue(forKey: provider); envelopes.removeValue(forKey: provider)
            do { try vault.remove(provider) }
            catch { blocked.insert(provider); throw ParcelFailure.storage }
        }
        var next = caches[provider] ?? ParcelCache(provider: provider, account: account)
        try next.merge(batch, account: account)
        let envelope = ParcelEnvelope(cache: next, cookies: cookies.map(ParcelCookie.init), savedAt: Date())
        do { try vault.write(envelope, provider: provider) }
        catch { throw ParcelFailure.storage }
        envelopes[provider] = envelope; caches[provider] = next
        notices[provider] = batch.phase == .empty
            ? "当前官方页显示暂无待取；历史码未删除，请核对时间。不是全量订单查询。"
            : "已读取当前页 \(batch.items.count) 个码；其他页面和订单尚未读取。"
    }
    private func invalidate(_ provider: ParcelProvider) {
        caches.removeValue(forKey: provider); envelopes.removeValue(forKey: provider)
        notices[provider] = "登录已变化或失效，旧账号记录已隐藏。请完成官方登录后重新读取。"
        do { guard let vault else { throw ParcelFailure.storage }; try vault.remove(provider) }
        catch { blocked.insert(provider); notices[provider] = "旧记录已隐藏，但本机加密数据尚未清理完成。请解锁后重试清除。" }
    }
    func logout(_ provider: ParcelProvider) {
        close(); caches.removeValue(forKey: provider); envelopes.removeValue(forKey: provider)
        do {
            guard let vault else { throw ParcelFailure.storage }
            try vault.remove(provider); blocked.remove(provider)
            notices[provider] = "已清除本机该平台登录和取件记录，不影响官方 App 或其他平台。"
        } catch {
            blocked.insert(provider); message = "本机记录已隐藏，但删除尚未完成。请解锁后重试清除，未宣称退出成功。"
        }
    }
    func mark(_ item: ParcelPickup, provider: ParcelProvider, taken: Bool) {
        guard let vault, !blocked.contains(provider), var saved = envelopes[provider],
              let index = saved.cache.items.firstIndex(where: { $0.id == item.id }) else { return }
        saved.cache.items[index].locallyTakenAt = taken ? Date() : nil
        do {
            try vault.write(saved, provider: provider)
            envelopes[provider] = saved; caches[provider] = saved.cache
        } catch { message = ParcelFailure.storage.localizedDescription }
    }
}
