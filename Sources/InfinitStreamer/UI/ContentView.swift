import SwiftUI

struct ContentView: View {
    @ObservedObject var auth: GoogleAuth
    @ObservedObject var coordinator: SessionCoordinator
    @State private var errorMessage: String?
    @State private var now = Date()

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            StreamPreview(stream: coordinator.publisher.stream)
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .background(Color.black)
                .overlay(alignment: .topLeading) { statusBadge.padding(12) }

            List {
                Section("アカウント") {
                    if auth.isSignedIn {
                        Label("Google にサインイン済み", systemImage: "checkmark.seal")
                        Button("サインアウト", role: .destructive) { auth.signOut() }
                    } else {
                        Button {
                            Task { await signIn() }
                        } label: {
                            Label("Google でサインイン", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }

                Section("永久配信") {
                    LabeledContent("状態", value: coordinator.phase.label)
                    LabeledContent("配信本数", value: "\(coordinator.cycleCount)")
                    LabeledContent("切り替え間隔", value: "11時間55分")
                    LabeledContent("次の切り替えまで", value: countdown)
                    if let url = coordinator.currentBroadcastURL {
                        Link(destination: url) {
                            Label("現在のライブを開く", systemImage: "play.rectangle")
                        }
                    }
                    if coordinator.isRunning {
                        Button("停止", role: .destructive) { coordinator.stop() }
                    } else {
                        Button {
                            coordinator.start()
                        } label: {
                            Label("永久配信を開始", systemImage: "infinity")
                        }
                        .disabled(!auth.isSignedIn)
                    }
                }

                Section("ログ") {
                    if coordinator.logs.isEmpty {
                        Text("—").foregroundStyle(.secondary)
                    }
                    ForEach(coordinator.logs, id: \.self) { line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
        }
        .onReceive(ticker) { now = $0 }
        .alert("エラー", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var statusBadge: some View {
        Text(coordinator.phase.label)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(coordinator.publisher.isPublishing ? Color.red : Color.gray, in: Capsule())
            .foregroundStyle(.white)
    }

    private var countdown: String {
        guard let next = coordinator.nextRotationAt else { return "—" }
        let remaining = max(0, Int(next.timeIntervalSince(now)))
        return String(format: "%02d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60)
    }

    private func signIn() async {
        do {
            try await auth.signIn()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
