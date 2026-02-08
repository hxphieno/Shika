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
    static let popUpScale: CGFloat = 1.6
    static let popUpBubbleHeightScale: CGFloat = 1.1
    static let popUpNeckHeightScale: CGFloat = 0.5
    static let popUpCornerRadius: CGFloat = 10
    
    // MARK: - UI Colors
    static let keyBackgroundColor: UIColor = UIColor(white: 1, alpha: 1.0)
    static let keyShadowColor: UIColor = .black
    static let keyTitleColor: UIColor = .black
    
    static let popUpShadowColor: UIColor = .black
    
    // MARK: - Layout
    static let topBarHeight: CGFloat = 60
    static let keyboardVerticalSpacing: CGFloat = 12
    static let keyboardHorizontalSpacing: CGFloat = 6
}

struct SKUtils {
    
    /// Recursively disables clipsToBounds and masksToBounds up the view hierarchy.
    /// This is a common workaround for iOS Keyboard Extensions to allow popups to overflow the main view.
    static func disableClipping(for view: UIView?) {
        var current: UIView? = view
        while let v = current {
            v.clipsToBounds = false
            v.layer.masksToBounds = false
            current = v.superview
        }
        
        // Also check window
        if let window = view?.window {
            window.clipsToBounds = false
            window.layer.masksToBounds = false
        }
    }
}
