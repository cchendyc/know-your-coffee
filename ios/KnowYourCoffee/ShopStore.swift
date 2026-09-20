import Foundation
import Observation

@MainActor
@Observable
final class ShopStore {
    enum ViewMode: String, CaseIterable {
        case list, map
    }

    var shops: [CoffeeShop] = []
    var total = 0
    var isLoading = false
    var errorMessage: String?

    // Search commits on submit, not per keystroke: the backend may spend an
    // LLM call understanding a free-form query.
    var draft = ""
    private(set) var search = ""

    var machine: MachineBrand? {
        didSet { reload() }
    }

    enum ListFilter: String, CaseIterable {
        case all, saved, been

        var label: String {
            switch self {
            case .all: "All"
            case .saved: "Saved"
            case .been: "Been"
            }
        }
    }

    // Saved/been come back empty until the app has sign-in; the feed shows
    // an explanatory empty state instead of hiding the tabs.
    var list: ListFilter = .all {
        didSet { if list != oldValue { reload() } }
    }

    var viewMode: ViewMode = .list {
        // The map needs every match; the list paginates.
        didSet { if viewMode != oldValue { reload() } }
    }

    private let pageSize = 24
    private let mapLimit = 1000
    private var loadTask: Task<Void, Never>?
    private var isLoadingMore = false

    var hasMore: Bool {
        viewMode == .list && shops.count < total
    }

    func commitSearch() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != search else { return }
        search = trimmed
        reload()
    }

    func clearSearchIfEmpty() {
        if draft.trimmingCharacters(in: .whitespaces).isEmpty, !search.isEmpty {
            search = ""
            reload()
        }
    }

    // Swap one shop in place after a save/been toggle so the feed stays honest.
    func patch(_ updated: CoffeeShop) {
        if let index = shops.firstIndex(where: { $0.id == updated.id }) {
            shops[index] = updated
        }
    }

    func remove(_ id: String) {
        shops.removeAll { $0.id == id }
        total = max(0, total - 1)
    }

    func reload() {
        loadTask?.cancel()
        isLoading = true
        loadTask = Task {
            do {
                let page = try await CoffeeAPI.fetchShops(
                    search: search,
                    machine: machine,
                    saved: list == .saved,
                    been: list == .been,
                    limit: viewMode == .map ? mapLimit : pageSize,
                    offset: 0
                )
                guard !Task.isCancelled else { return }
                shops = page.shops
                total = page.total
                errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // Next page, appended. The guard makes repeat sentinel hits no-ops.
    // Any of the last 4 triggers: the feed splits into two columns, so the
    // strict last item may sit in a column the user isn't scrolling past.
    func loadMoreIfNeeded(current shop: CoffeeShop) {
        guard hasMore, !isLoading, !isLoadingMore,
              shops.suffix(4).contains(where: { $0.id == shop.id }) else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            do {
                let page = try await CoffeeAPI.fetchShops(
                    search: search,
                    machine: machine,
                    saved: list == .saved,
                    been: list == .been,
                    limit: pageSize,
                    offset: shops.count
                )
                shops += page.shops
                total = page.total
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
