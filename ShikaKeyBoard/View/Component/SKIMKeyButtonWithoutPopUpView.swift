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
