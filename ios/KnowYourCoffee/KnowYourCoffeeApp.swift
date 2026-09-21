import SwiftUI

@main
struct KnowYourCoffeeApp: App {
    // nil = follow the system appearance; set from the Profile appearance picker.
    @AppStorage("appearance") private var appearanceRaw = AppAppearance.system.rawValue

    init() {
        // Shop cards render remote photos; a generous URLCache keeps scrolling smooth.
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            LaunchAnimation {
                HomeView()
            }
            .tint(.espresso700)
            .preferredColorScheme(AppAppearance(rawValue: appearanceRaw)?.colorScheme ?? nil)
        }
    }
}
