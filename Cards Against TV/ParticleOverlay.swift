import SwiftUI
import UIKit

final class ParticleView: UIView {

    enum Style { case snow, confetti }
    private let style: Style
    private let emitter = CAEmitterLayer()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        isOpaque = false
        backgroundColor = .clear

        setupEmitter()
        layer.addSublayer(emitter)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupEmitter() {
        emitter.emitterShape = .line
        emitter.renderMode = .additive

        let cell = CAEmitterCell()
        cell.lifetime = 10
        cell.birthRate = style == .snow ? 25 : 80
        cell.velocity = style == .snow ? 40 : 200
        cell.velocityRange = 30
        cell.yAcceleration = style == .snow ? 20 : 300
        cell.scale = style == .snow ? 0.04 : 0.06
        cell.scaleRange = 0.02
        cell.emissionRange = .pi

        // ✅ IMPORTANT: real bitmap, NOT SF Symbol
        cell.contents = UIImage(named: "snowflake")?.cgImage

        emitter.emitterCells = [cell]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -10)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
    }
}

struct ParticleOverlay: UIViewRepresentable {

    let style: ParticleView.Style

    func makeUIView(context: Context) -> UIView {
        ParticleView(style: style)
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
