import SwiftUI

@main
struct KnowYourCoffeeApp: App {
    init() {
        // Shop cards render remote photos; a generous URLCache keeps scrolling smooth.
        URLCache.shared = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(.espresso700)
        }
    }
}
