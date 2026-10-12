import Observation
import SwiftUI
import UIKit

/// A photo taken or picked in the launcher, uploaded with the sheet that used it.
struct CapturedPhoto: Identifiable {
    let id = UUID()
    let kind: String // PhotoKind: MACHINE, MENU, VIBE
    let dataURL: String
}

/// One launcher session: the shop as last fetched, the server's option lists,
/// which tiles saved, and the sign-in gate. Sign-in happens at Save (or before
/// a vision call), so the launcher stays readable signed out.
@MainActor
@Observable
final class ReportSession {
    var shop: CoffeeShop
    var options: ReportOptions?
    var optionsError: String?
    var saved: Set<ReportFact> = []
    var showSignIn = false
    /// A sheet text field has focus; the launcher grows to `.large` so suggestions clear the keyboard.
    var fieldFocused = false
    var analyzing = false
    /// Vision results waiting for the Machine or Menu sheet to open and consume them.
    var pendingMachine: (guess: MachineGuess, photo: CapturedPhoto)?
    var pendingMenu: (items: [DrinkItem], photo: CapturedPhoto)?

    private var signInWaiter: CheckedContinuation<Bool, Never>?

    init(shop: CoffeeShop) {
        self.shop = shop
    }

    func loadOptions() async {
        optionsError = nil
        do {
            options = try await CoffeeAPI.fetchReportOptions()
        } catch {
            optionsError = error.localizedDescription
        }
    }

    /// False when the person dismissed sign-in.
    func ensureSignedIn() async -> Bool {
        if AuthStore.shared.isSignedIn { return true }
        showSignIn = true
        return await withCheckedContinuation { signInWaiter = $0 }
    }

    func signInDismissed() {
        signInWaiter?.resume(returning: AuthStore.shared.isSignedIn)
        signInWaiter = nil
    }

    /// One report per sheet. Fields are ReportInput keys; the server folds
    /// scalars per field and replaces arrays whole. False if sign-in was dismissed.
    func submit(_ fact: ReportFact, fields: [String: Any?], photos: [CapturedPhoto] = []) async throws -> Bool {
        guard await ensureSignedIn() else { return false }
        var input = fields
        input["shopId"] = shop.id
        input["source"] = photos.isEmpty ? "TEXT" : "PHOTO"
        try await CoffeeAPI.submitReport(input)
        if !photos.isEmpty {
            try await CoffeeAPI.addShopPhotos(
                shopID: shop.id,
                photos: photos.map { ["kind": $0.kind, "data": $0.dataURL] }
            )
        }
        saved.insert(fact)
        await refresh()
        return true
    }

    /// reportShop flags the shop; it is not a community update.
    func flag(reason: String) async throws -> Bool {
        guard await ensureSignedIn() else { return false }
        try await CoffeeAPI.reportShop(shopID: shop.id, reason: reason)
        saved.insert(.other)
        return true
    }

    /// Routes photos: machine → Machine sheet, menu → Menu sheet, else a VIBE upload.
    /// Returns the sheet to push, if any. Vision calls need sign-in.
    func route(images: [UIImage]) async -> ReportFact? {
        guard await ensureSignedIn() else { return nil }
        analyzing = true
        defer { analyzing = false }
        var destination: ReportFact?
        for image in images {
            guard let data = image.reportDataURL() else { continue }
            if let guess = try? await CoffeeAPI.identifyMachine(imageBase64: data), guess.machine != .unknown {
                pendingMachine = (guess, CapturedPhoto(kind: "MACHINE", dataURL: data))
                destination = destination ?? .machine
                continue
            }
            if let items = try? await CoffeeAPI.parseMenu(imageBase64: data), !items.isEmpty {
                pendingMenu = (items, CapturedPhoto(kind: "MENU", dataURL: data))
                destination = destination ?? .menu
                continue
            }
            if (try? await CoffeeAPI.addShopPhotos(shopID: shop.id, photos: [["kind": "VIBE", "data": data]])) != nil {
                await refresh()
            }
        }
        return destination
    }

    func refresh() async {
        if let fresh = try? await CoffeeAPI.fetchShop(id: shop.id) {
            shop = fresh
        }
    }
}

extension UIImage {
    /// Downscale to ~1000px and encode as a JPEG data URL, matching the web
    /// client's downscaleImage() so backend vision costs stay flat.
    func reportDataURL(maxDimension: CGFloat = 1000) -> String? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }
}
