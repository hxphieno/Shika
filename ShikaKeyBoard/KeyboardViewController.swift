//
//  KeyboardViewController.swift
//  ShikaKeyBoard
//
//  Created by 分诺 on 2026/1/30.
//

import UIKit

class KeyboardViewController: UIInputViewController, SKKeyboardEventHandler {

    private var candidateBarView: CandidateBarView!
    private var skInputView: SKInputView!
    private var skNumberInputView: SKNumberInputView!
    private var inputSwitchButton: SKInputSwitchButton!
    private var topBarStackView: UIStackView!
    private var separatorLine: SKSeparatorLine!
    
    override func updateViewConstraints() {
        super.updateViewConstraints()
        // Add custom view sizing constraints here
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Use the centralized utility to fix popup clipping
        SKUtils.disableClipping(for: self.view)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup SKInputSwitchButton
        inputSwitchButton = SKInputSwitchButton()
        inputSwitchButton.translatesAutoresizingMaskIntoConstraints = false
        inputSwitchButton.widthAnchor.constraint(equalToConstant: SKConfig.defaultKeyHeight).isActive = true
        inputSwitchButton.heightAnchor.constraint(equalToConstant: SKConfig.defaultKeyHeight).isActive = true
        
        inputSwitchButton.stateChangeHandler = { [weak self] state in
            self?.skInputView.currentLanguageState = state
        }
        
        // Setup CandidateBarView
        candidateBarView = CandidateBarView()
        candidateBarView.translatesAutoresizingMaskIntoConstraints = false
        candidateBarView.heightAnchor.constraint(equalToConstant: SKConfig.defaultKeyHeight).isActive = true
        
        // Setup StackView
        topBarStackView = UIStackView(arrangedSubviews: [inputSwitchButton, candidateBarView])
        topBarStackView.axis = .horizontal
        topBarStackView.alignment = .center
        topBarStackView.distribution = .fill
        topBarStackView.spacing = 0
        topBarStackView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(topBarStackView)
        
        // Setup Separator Line
        separatorLine = SKSeparatorLine()
        self.view.addSubview(separatorLine)
        
        // Setup SKInputView
        skInputView = SKInputView()
        skInputView.eventHandler = self
        skInputView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(skInputView)
        
        // Setup SKNumberInputView
        skNumberInputView = SKNumberInputView()
        skNumberInputView.eventHandler = self
        skNumberInputView.translatesAutoresizingMaskIntoConstraints = false
        skNumberInputView.isHidden = true // Hidden by default
        self.view.addSubview(skNumberInputView)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Top Bar StackView: Top, Left, Right, Height 40
            topBarStackView.topAnchor.constraint(equalTo: self.view.topAnchor),
            topBarStackView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            topBarStackView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            topBarStackView.heightAnchor.constraint(equalToConstant: SKConfig.topBarHeight),
            
            // Separator Line: Below Top Bar, Left, Right
            separatorLine.topAnchor.constraint(equalTo: topBarStackView.bottomAnchor),
            separatorLine.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: SKConfig.keyboardHorizontalSpacing),
            separatorLine.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -SKConfig.keyboardHorizontalSpacing),
            
            // Input View: Below Separator, Left, Right, Bottom
            skInputView.topAnchor.constraint(equalTo: separatorLine.bottomAnchor),
            skInputView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            skInputView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            skInputView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            
            // Number Input View: Same constraints as Input View
            skNumberInputView.topAnchor.constraint(equalTo: separatorLine.bottomAnchor),
            skNumberInputView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            skNumberInputView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            skNumberInputView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
        ])
    }
    
    override func textWillChange(_ textInput: UITextInput?) {
        // The app is about to change the document's contents. Perform any preparation here.
    }
    
    override func textDidChange(_ textInput: UITextInput?) {
        // The app has just changed the document's contents, the document context has been updated.
    }
    
    // MARK: - SKKeyboardEventHandler
    
    func didTapKey(_ key: String) {
        self.textDocumentProxy.insertText(key)
    }
    
    func didTapDelete() {
        self.textDocumentProxy.deleteBackward()
    }
    
    func didTapNextKeyboard() {
        self.advanceToNextInputMode()
    }
    
    func didTapSwitchLayout(to layout: SKKeyboardLayoutType) {
        switch layout {
        case .alphabet:
            skInputView.isHidden = false
            skNumberInputView.isHidden = true
        case .number:
            skInputView.isHidden = true
            skNumberInputView.isHidden = false
        }
    }

}
