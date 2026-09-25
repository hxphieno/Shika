//
//  SKIMKeyButtonWithoutPopUpView.swift
//  ShiKaKeyBoard
//
//  Created by ShiKa on 2026/1/30.
//

import UIKit

class SKIMKeyButtonWithoutPopUpView: UIButton {
    
    var keyColor: UIColor
    var keyFont: UIFont
    var keyTitle: String
    var touchInsets = UIEdgeInsets.zero
    private var deletion: SKDeleteKeyInteraction?
    private var deletionBackground: UIColor?
    var onDelete: ((Bool) -> SKDeleteFeedback)? {
        didSet {
            deletion?.cancel()
            if onDelete != nil { deletionBackground = backgroundColor }
            deletion = onDelete.map { SKDeleteKeyInteraction(control: self, action: $0) }
        }
    }
    override var isHighlighted: Bool {
        didSet {
            guard onDelete != nil else { return }
            backgroundColor = isHighlighted ? UIColor(white: 0.8, alpha: 1) : deletionBackground
        }
    }
    override func accessibilityActivate() -> Bool {
        deletion?.activateOnce() ?? super.accessibilityActivate()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { deletion?.cancel() }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let area = bounds.inset(by: touchInsets)
        return (onDelete != nil && isTracking ? area.insetBy(dx: -6, dy: -6) : area).contains(point)
    }

    init(title: String,
         width: CGFloat = SKConfig.defaultKeyWidth,
         height: CGFloat = SKConfig.defaultKeyHeight,
         font: UIFont = UIFont.systemFont(ofSize: 26, weight: .regular),
         color: UIColor = SKConfig.keyTitleColor,
         backgroundColor: UIColor = SKConfig.keyBackgroundColor) {
        
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
        self.layer.cornerRadius = SKConfig.defaultCornerRadius
        self.layer.shadowColor = SKConfig.keyShadowColor.cgColor
        self.layer.shadowOpacity = 0.2
        self.layer.shadowOffset = CGSize(width: 0, height: 1)
        self.layer.shadowRadius = 0
        self.layer.masksToBounds = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
