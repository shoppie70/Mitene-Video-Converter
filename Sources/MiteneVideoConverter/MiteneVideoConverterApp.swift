import SwiftUI

@main
struct MiteneVideoConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 520)
        }
        .windowResizability(.contentSize)
    }
}
