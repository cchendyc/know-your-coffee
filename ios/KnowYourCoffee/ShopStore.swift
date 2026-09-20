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

    func reload() {
        loadTask?.cancel()
        isLoading = true
        loadTask = Task {
            do {
                let page = try await CoffeeAPI.fetchShops(
                    search: search,
                    machine: machine,
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
    func loadMoreIfNeeded(current shop: CoffeeShop) {
        guard hasMore, !isLoading, !isLoadingMore, shop.id == shops.last?.id else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            do {
                let page = try await CoffeeAPI.fetchShops(
                    search: search,
                    machine: machine,
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
