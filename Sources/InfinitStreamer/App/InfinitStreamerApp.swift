import SwiftUI

@main
struct InfinitStreamerApp: App {
    @StateObject private var auth = GoogleAuth()

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth)
        }
    }
}

struct RootView: View {
    @StateObject private var coordinator: SessionCoordinator
    @ObservedObject private var auth: GoogleAuth

    init(auth: GoogleAuth) {
        self.auth = auth
        _coordinator = StateObject(wrappedValue: SessionCoordinator(auth: auth))
    }

    var body: some View {
        ContentView(auth: auth, coordinator: coordinator)
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    }
}
