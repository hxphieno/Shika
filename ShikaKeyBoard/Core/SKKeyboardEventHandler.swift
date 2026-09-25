//
//  SKKeyboardEventHandler.swift
//  ShikaKeyBoard
//
//  Created by ShiKa on 2026/2/7.
//

import Foundation

enum SKKeyboardLayoutType {
    case alphabet
    case number
}

enum SKDeleteFeedback { case continueRepeating, restartDelay, stop }

protocol SKKeyboardEventHandler: AnyObject {
    func didTapSwitchScheme()
    func didTapKey(_ key: String)
    func didTapDelete()
    func didDeleteBackward(byWord: Bool) -> SKDeleteFeedback
    func didTapNextKeyboard()
    func didTapSwitchLayout(to layout: SKKeyboardLayoutType)
}

// Existing event consumers may keep character-only deletion.
extension SKKeyboardEventHandler {
    func didDeleteBackward(byWord: Bool) -> SKDeleteFeedback {
        didTapDelete(); return .continueRepeating
    }
}
