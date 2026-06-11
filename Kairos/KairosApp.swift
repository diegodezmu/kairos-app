import SwiftUI

@main
struct KairosApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

private struct RootView: View {
    var body: some View {
        if RenderPerfSpike.isEnabled {
            RenderPerfSpikeView()
        } else {
            ContentView()
        }
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Kairos")
                .font(.largeTitle)
            Text("Project scaffold ready for follow-up tasks.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
    }
}
