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
        cell.lifetime = 12
        cell.birthRate = style == .snow ? 35 : 100
        cell.velocity = style == .snow ? 50 : 220
        cell.velocityRange = style == .snow ? 25 : 80
        cell.yAcceleration = style == .snow ? 30 : 350
        cell.scale = style == .snow ? 0.06 : 0.08
        cell.scaleRange = style == .snow ? 0.03 : 0.04
        cell.emissionRange = .pi
        cell.color = UIColor(white: 0.95, alpha: 1).cgColor


        let image = UIImage(named: "snowflake")
        print("❄️ Snowflake image on iOS:", image as Any)

        cell.contents = image?.cgImage

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
