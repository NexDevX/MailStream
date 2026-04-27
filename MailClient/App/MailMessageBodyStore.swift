import Foundation

/// In-memory LRU cache + façade in front of the repository's body plane.
///
/// Why this lives here (App layer, not Persistence):
/// - The cache **policy** (how many bodies to keep, when to evict) is a
///   product decision, not a storage concern.
/// - AppState hands a `MailMessageBodyStore` to the detail view; the view
///   asks for a body by id and the store handles cache + I/O.
///
/// LRU semantics: keep at most `capacity` bodies. On hit, move the entry
/// to the front. On miss, hit the repository, insert at front, evict the
/// tail if we exceed capacity.
///
/// Thread safety: actor — all mutations are serialized. Read calls are
/// `async` so callers must `await`, which is fine because they're already
/// inside Task contexts (button taps, selection changes).
actor MailMessageBodyStore {
    private let repository: any MailRepository
    private let capacity: Int

    /// Doubly-linked LRU implemented as a dictionary + ordered keys array.
    /// At ~50 entries, array shifting is faster than maintaining real
    /// linked-list nodes. If we ever cache 1 000+ bodies, swap to a real
    /// list — the API stays the same.
    private var cache: [UUID: MailMessageBody] = [:]
    private var order: [UUID] = []

    init(repository: any MailRepository, capacity: Int = 64) {
        self.repository = repository
        self.capacity = max(1, capacity)
    }

    // MARK: - Public API

    /// Fetch a body. Returns immediately on cache hit; otherwise hits the
    /// repository and caches the result. Returns `nil` if the body simply
    /// hasn't been fetched from the server yet — the caller should display
    /// an empty / skeleton state and wait for the next sync.
    func body(for id: UUID) async -> MailMessageBody? {
        if let cached = cache[id] {
            promote(id)
            return cached
        }
        guard let loaded = await repository.loadBody(messageID: id) else {
            return nil
        }
        insert(id: id, body: loaded)
        return loaded
    }

    /// Persist a freshly-parsed body and cache it.
    func store(id: UUID, body: MailMessageBody) async {
        await repository.storeBody(messageID: id, body: body)
        insert(id: id, body: body)
    }

    /// Drop a single entry — call when the message itself is deleted.
    func invalidate(_ id: UUID) {
        cache.removeValue(forKey: id)
        order.removeAll { $0 == id }
    }

    /// Drop everything — used on account removal or sign-out.
    func invalidateAll() {
        cache.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
    }

    /// Diagnostic: how full the cache currently is.
    var stats: (count: Int, capacity: Int) {
        (cache.count, capacity)
    }

    // MARK: - LRU bookkeeping

    private func promote(_ id: UUID) {
        guard let i = order.firstIndex(of: id), i != 0 else { return }
        order.remove(at: i)
        order.insert(id, at: 0)
    }

    private func insert(id: UUID, body: MailMessageBody) {
        if cache[id] == nil {
            order.insert(id, at: 0)
        } else {
            promote(id)
        }
        cache[id] = body
        if order.count > capacity, let tail = order.popLast() {
            cache.removeValue(forKey: tail)
        }
    }
}
