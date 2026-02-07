//
//  SKIMKeyButton.swift
//  ShiKaKeyBoard
//
//  Created by ShiKa on 2026/1/30.
//

import UIKit

class SKIMKeyButton: UIButton {
    
    private var popUpView: SKIMKeyPopUpView?
    private var keyColor: UIColor
    private var keyFont: UIFont
    private var keyTitle: String
    private var originalTitleColor: UIColor?

    init(title: String,
         width: CGFloat = 33,
         height: CGFloat = 43,
         font: UIFont = UIFont.systemFont(ofSize: 26, weight: .regular),
         color: UIColor = .black,
         backgroundColor: UIColor = UIColor(white: 1, alpha: 1.0)) {
        
        self.keyTitle = title
        self.keyColor = color
        self.keyFont = font
        
        super.init(frame: .zero)
        
        self.setTitle(title, for: .normal)
        self.titleLabel?.font = font
        self.setTitleColor(color, for: .normal)
        self.backgroundColor = backgroundColor
        
        // Layout Constraints
        self.translatesAutoresizingMaskIntoConstraints = false
        self.widthAnchor.constraint(equalToConstant: width).isActive = true
        self.heightAnchor.constraint(equalToConstant: height).isActive = true
        
        // Appearance
        self.layer.cornerRadius = 5
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowOpacity = 0.2
        self.layer.shadowOffset = CGSize(width: 0, height: 1)
        self.layer.shadowRadius = 0
        self.layer.masksToBounds = false
        
        // Touch Events
        self.addTarget(self, action: #selector(touchDown), for: .touchDown)
        self.addTarget(self, action: #selector(touchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func touchDown() {
        showPopUp()
    }
    
    @objc private func touchEnded() {
        hidePopUp()
    }
    
    private func showPopUp() {
        if popUpView == nil {
            let scale: CGFloat = 1.6
            let keyWidth = self.bounds.width
            let keyHeight = self.bounds.height
            
            let popUpWidth = keyWidth * scale
            let bubbleHeight = keyHeight * 1.1
            let neckHeight = keyHeight * 0.5
            let totalHeight = bubbleHeight + neckHeight + keyHeight
            
            let frame = CGRect(x: 0, y: 0, width: popUpWidth, height: totalHeight)
            
            let view = SKIMKeyPopUpView(frame: frame)
            view.backgroundColor = .clear
            view.keyWidth = keyWidth
            view.bubbleColor = self.backgroundColor ?? .white
            view.bubbleHeight = bubbleHeight
            view.neckHeight = neckHeight
            view.keyBodyHeight = keyHeight
            view.cornerRadius = 10
            
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOpacity = 0.2
            view.layer.shadowOffset = CGSize(width: 0, height: 2)
            view.layer.shadowRadius = 3
            
            let labelHeight = bubbleHeight
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: popUpWidth, height: labelHeight))
            label.text = keyTitle
            label.font = keyFont.withSize(keyFont.pointSize * 1.5)
            label.textColor = keyColor
            label.textAlignment = .center
            view.addSubview(label)
            
            self.popUpView = view
        }
        
        if let window = self.window, let view = popUpView {
            let rect = self.convert(self.bounds, to: window)
            let popUpX = rect.midX - (view.frame.width / 2)
            let popUpY = rect.maxY - view.frame.height
            view.frame.origin = CGPoint(x: popUpX, y: popUpY)
            
            window.addSubview(view)
        }
    }
    
    private func hidePopUp() {
        popUpView?.removeFromSuperview()
        popUpView = nil
    }
}

class SKIMKeyPopUpView: UIView {
    
    var keyWidth: CGFloat = 0
    var bubbleHeight: CGFloat = 0
    var bubbleColor: UIColor = .white
    var cornerRadius: CGFloat = 10
    var neckHeight: CGFloat = 0
    var keyBodyHeight: CGFloat = 0
    
    override func draw(_ rect: CGRect) {
        guard UIGraphicsGetCurrentContext() != nil else { return }
        
        let width = rect.width
        let height = rect.height
        if bubbleHeight == 0 || keyBodyHeight == 0 { return }
        
        let neckEndY = bubbleHeight + neckHeight
        let keyBodyTopY = neckEndY
        
        let path = UIBezierPath()
        
        // Key Body Constraints
        let keyLeftX = (width - keyWidth) / 2
        let keyRightX = (width + keyWidth) / 2
        let keyCornerRadius: CGFloat = 5.0 
        
        // --- Start Drawing from Bottom-Left of the entire shape ---
        
        // 1. Bottom-Left Corner of Key Body
        path.move(to: CGPoint(x: keyLeftX + keyCornerRadius, y: height))
        path.addLine(to: CGPoint(x: keyRightX - keyCornerRadius, y: height))
        
        // 2. Bottom-Right Corner of Key Body
        path.addArc(withCenter: CGPoint(x: keyRightX - keyCornerRadius, y: height - keyCornerRadius),
                    radius: keyCornerRadius,
                    startAngle: 0.5 * .pi,
                    endAngle: 0,
                    clockwise: false)
        
        // 3. Right side of Key Body (Upwards)
        path.addLine(to: CGPoint(x: keyRightX, y: keyBodyTopY))
        
        // 4. Right Neck Curve (Connecting Key Body Top-Right to Bubble Bottom-Right)
        path.addCurve(to: CGPoint(x: width, y: bubbleHeight - cornerRadius),
                      controlPoint1: CGPoint(x: keyRightX, y: keyBodyTopY - neckHeight * 0.5),
                      controlPoint2: CGPoint(x: width, y: bubbleHeight + neckHeight * 0.5))
        
        // 5. Bubble Right Side (Upwards)
        path.addLine(to: CGPoint(x: width, y: cornerRadius))
        
        // 6. Top-Right Corner of Bubble
        path.addArc(withCenter: CGPoint(x: width - cornerRadius, y: cornerRadius),
                    radius: cornerRadius,
                    startAngle: 0,
                    endAngle: 1.5 * .pi, // 270 degrees, up
                    clockwise: false)
        
        // 7. Top Edge of Bubble
        path.addLine(to: CGPoint(x: cornerRadius, y: 0))
        
        // 8. Top-Left Corner of Bubble
        path.addArc(withCenter: CGPoint(x: cornerRadius, y: cornerRadius),
                    radius: cornerRadius,
                    startAngle: 1.5 * .pi, // -90 deg
                    endAngle: .pi, // 180 deg
                    clockwise: false)
        
        // 9. Bubble Left Side (Downwards)
        path.addLine(to: CGPoint(x: 0, y: bubbleHeight - cornerRadius))
        
        // 10. Left Neck Curve (Connecting Bubble Bottom-Left to Key Body Top-Left)
        path.addCurve(to: CGPoint(x: keyLeftX, y: keyBodyTopY),
                      controlPoint1: CGPoint(x: 0, y: bubbleHeight + neckHeight * 0.5),
                      controlPoint2: CGPoint(x: keyLeftX, y: keyBodyTopY - neckHeight * 0.5))
        
        // 11. Left Side of Key Body (Downwards)
        path.addLine(to: CGPoint(x: keyLeftX, y: height - keyCornerRadius))
        
        // 12. Bottom-Left Corner of Key Body
        path.addArc(withCenter: CGPoint(x: keyLeftX + keyCornerRadius, y: height - keyCornerRadius),
                    radius: keyCornerRadius,
                    startAngle: .pi,
                    endAngle: 0.5 * .pi,
                    clockwise: false)
        
        path.close()
        
        bubbleColor.setFill()
        path.fill()
    }
}
