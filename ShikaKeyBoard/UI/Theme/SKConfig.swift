//
//  SKConfig.swift
//  ShikaKeyBoard
//
//  Created by ShiKa on 2026/2/8.
//

import UIKit

struct SKConfig {
    
    // MARK: - Key Button Dimensions
    static let defaultKeyWidth: CGFloat = 33
    static let defaultKeyHeight: CGFloat = 43
    static let defaultCornerRadius: CGFloat = 5
    
    // MARK: - PopUp Dimensions
    static let popUpScale: CGFloat = 1.5
    static let popUpBubbleHeightScale: CGFloat = 1.05
    static let popUpNeckHeightScale: CGFloat = 0.5
    static let popUpCornerRadius: CGFloat = 10
    
    // MARK: - UI Colors
    static let keyBackgroundColor: UIColor = UIColor(white: 1, alpha: 1.0)
    static let keyShadowColor: UIColor = .black
    static let keyTitleColor: UIColor = .black
    static let keyHintColor: UIColor = UIColor(white: 0.35, alpha: 1)
    static let keyInitialColor: UIColor = .systemBlue
    
    static let popUpShadowColor: UIColor = .black
    
    // MARK: - Layout
    static let topBarHeight: CGFloat = 44
    static let keyboardVerticalSpacing: CGFloat = 12
    static let keyboardHorizontalSpacing: CGFloat = 6
    static let numberInputViewSpacing: CGFloat = 10
}
