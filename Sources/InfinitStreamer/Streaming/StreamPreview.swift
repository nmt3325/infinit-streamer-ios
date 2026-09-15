import HaishinKit
import SwiftUI

/// 送出中の映像プレビュー。
struct StreamPreview: UIViewRepresentable {
    let stream: RTMPStream

    func makeUIView(context: Context) -> MTHKView {
        let view = MTHKView(frame: .zero)
        view.videoGravity = .resizeAspectFill
        view.attachStream(stream)
        return view
    }

    func updateUIView(_ uiView: MTHKView, context: Context) {}
}
