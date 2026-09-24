//
//  SKSeparatorLine.swift
//  ShikaKeyBoard
//
//  Created by ShiKa on 2026/2/8.
//

import UIKit

class SKSeparatorLine: UIView {
    
    init(color: UIColor = SKConfig.keyShadowColor, height: CGFloat = 2) {
        super.init(frame: .zero)
        self.backgroundColor = color.withAlphaComponent(0.2)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.heightAnchor.constraint(equalToConstant: height).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
