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

protocol SKKeyboardEventHandler: AnyObject {
    func didTapSwitchScheme()
    func didTapKey(_ key: String)
    func didTapDelete()
    func didTapNextKeyboard()
    func didTapSwitchLayout(to layout: SKKeyboardLayoutType)
}
