import SwiftUI

@main
struct KairosApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    var body: some View {
        GridRendererShowcase()
    }
}
