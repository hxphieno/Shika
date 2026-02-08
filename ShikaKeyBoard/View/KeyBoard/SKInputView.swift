//
//  SKInputView.swift
//  ShikaKeyBoard
//
//  Created by ShiKa on 2026/1/30.
//

import UIKit

// SKInputViewDelegate removed in favor of SKKeyboardDelegate

class SKInputView: UIView {
    
    weak var eventHandler: SKKeyboardEventHandler?
    
    // Internal state for Shift key
    private enum CapsLockState {
        case lower
        case upper
        case capsLock
    }
    
    private var capsLockState: CapsLockState = .lower
    private var mainStackView: UIStackView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        updateMainKeyboardStackView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        updateMainKeyboardStackView()
    }
    
    private func setupView() {
        // Background color removed
        
        mainStackView = UIStackView()
        mainStackView.distribution = .fillEqually
        mainStackView.spacing = SKConfig.keyboardVerticalSpacing
        mainStackView.axis = .vertical
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.layoutMargins = UIEdgeInsets(top: 3, left: 3, bottom: 0, right: 3)
        mainStackView.isLayoutMarginsRelativeArrangement = true
        
        self.addSubview(mainStackView)
        
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: self.topAnchor, constant: 5),
            mainStackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -5)
        ])
    }
    
    var currentLanguageState: SKInputSwitchState = .mixed {
        didSet {
            updateMainKeyboardStackView()
        }
    }
    
    private func updateMainKeyboardStackView() {
        mainStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let layout = (capsLockState == .lower) ? KeyboardLayout.lowercase : KeyboardLayout.uppercase
        
        for (index, row) in layout.enumerated() {
            let rowStackView = UIStackView()
            rowStackView.axis = .horizontal
            rowStackView.spacing = SKConfig.keyboardHorizontalSpacing
            rowStackView.distribution = .fillEqually
            rowStackView.alignment = .fill
            rowStackView.translatesAutoresizingMaskIntoConstraints = false
            
            // Handle Japanese/Chinese layout difference for the second row
            var keys = row
            // Only hide "—" (dash) when in Chinese mode. Show in Mixed and Japanese.
            if index == 1 && currentLanguageState == .chinese {
                keys = row.filter { $0 != "—" }
                rowStackView.layoutMargins = UIEdgeInsets(top: 0, left: 19.5, bottom: 0, right: 19.5)
                rowStackView.isLayoutMarginsRelativeArrangement = true
            }
            
            for key in keys {
                let keyButton = SKIMKeyButton(title: key)
                if KeyboardLayout.lowCaseLetter.contains(key) {
                   keyButton.titleEdgeInsets = UIEdgeInsets(top: -2, left: 0, bottom: 2, right: 0)
                }
                keyButton.addTarget(self, action: #selector(keyPressed(_:)), for: .touchUpInside)
                rowStackView.addArrangedSubview(keyButton)
            }
            
            if index != 2 {
                mainStackView.addArrangedSubview(rowStackView)
            } else {
                // Third Row (Z line) with Shift and Backspace
                let rowStackViewLine2 = UIStackView()
                rowStackViewLine2.axis = .horizontal
                rowStackViewLine2.distribution = .equalSpacing
                rowStackViewLine2.spacing = 6
                
                // Shift Key
                let shiftIcon = (capsLockState == .lower) ? "⇧" : "⇪"
                let shiftButton = SKIMKeyButtonWithoutPopUpView(title: shiftIcon, width: 42)
                shiftButton.addTarget(self, action: #selector(shiftKeyPressed(_:)), for: .touchUpInside)
                
                // Double tap / Long press for Caps Lock
                let doubleTap = UITapGestureRecognizer(target: self, action: #selector(shiftKeyDoubleOrLongPressed(_:)))
                doubleTap.numberOfTapsRequired = 2
                shiftButton.addGestureRecognizer(doubleTap)
                
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(shiftKeyDoubleOrLongPressed(_:)))
                longPress.minimumPressDuration = 0.5
                shiftButton.addGestureRecognizer(longPress)
                
                rowStackViewLine2.addArrangedSubview(shiftButton)
                rowStackViewLine2.addArrangedSubview(rowStackView)
                
                // Backspace Key
                let deleteButton = SKIMKeyButton(title: "⌫", width: 42)
                deleteButton.addTarget(self, action: #selector(deleteKeyPressed(_:)), for: .touchUpInside)
                
                rowStackViewLine2.addArrangedSubview(deleteButton)
                
                mainStackView.addArrangedSubview(rowStackViewLine2)
            }
        }
        
        // Fourth Row (Numbers, Emoji, Space, Return)
        let rowStackViewLine3 = UIStackView()
        rowStackViewLine3.axis = .horizontal
        rowStackViewLine3.distribution = .equalSpacing
        rowStackViewLine3.alignment = .fill
        rowStackViewLine3.spacing = 6
        
        // 123 Key
        let numberButton = SKIMKeyButtonWithoutPopUpView(title: "123", width: 42, font: UIFont.systemFont(ofSize: 16, weight: .regular))
        numberButton.addTarget(self, action: #selector(numberKeyPressed), for: .touchUpInside)
        rowStackViewLine3.addArrangedSubview(numberButton)
        
        // Emoji Key
        let emojiButton = SKIMKeyButtonWithoutPopUpView(title: "🦌", width: 42, font: UIFont.systemFont(ofSize: 24, weight: .regular))
        rowStackViewLine3.addArrangedSubview(emojiButton)
        
        // Space Key
        let spaceButton = SKIMKeyButtonWithoutPopUpView(title: "空格", width: 185, font: UIFont.systemFont(ofSize: 16, weight: .regular))
        spaceButton.addTarget(self, action: #selector(spaceKeyPressed), for: .touchUpInside)
        rowStackViewLine3.addArrangedSubview(spaceButton)
        
        // Return Key
        let enterButton = SKIMKeyButtonWithoutPopUpView(title: "换行", width: 90, font: UIFont.systemFont(ofSize: 16, weight: .regular))
        enterButton.addTarget(self, action: #selector(enterKeyPressed), for: .touchUpInside)
        rowStackViewLine3.addArrangedSubview(enterButton)
        
        mainStackView.addArrangedSubview(rowStackViewLine3)
    }

    // MARK: - Actions
    
    @objc private func keyPressed(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        eventHandler?.didTapKey(title)
        
        if capsLockState == .upper {
            capsLockState = .lower
            updateMainKeyboardStackView()
        }
    }
    
    @objc private func shiftKeyPressed(_ sender: UIButton) {
        capsLockState = (capsLockState == .lower) ? .upper : .lower
        updateMainKeyboardStackView()
    }
    
    @objc private func shiftKeyDoubleOrLongPressed(_ sender: Any) {
        capsLockState = .capsLock
        updateMainKeyboardStackView()
    }
    
    @objc private func deleteKeyPressed(_ sender: UIButton) {
        eventHandler?.didTapDelete()
    }
    
    @objc private func numberKeyPressed() {
        eventHandler?.didTapSwitchLayout(to: .number)
    }
    
    @objc private func spaceKeyPressed() {
        eventHandler?.didTapKey(" ")
    }
    
    @objc private func enterKeyPressed() {
        eventHandler?.didTapKey("\n")
    }
}
