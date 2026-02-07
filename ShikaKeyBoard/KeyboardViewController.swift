//
//  KeyboardViewController.swift
//  ShikaKeyBoard
//
//  Created by 分诺 on 2026/1/30.
//

import UIKit

class KeyboardViewController: UIInputViewController, SKInputViewDelegate, SKNumberInputViewDelegate {

    private var candidateBarView: UIView!
    private var skInputView: SKInputView!
    private var skNumberInputView: SKNumberInputView!
    
    override func updateViewConstraints() {
        super.updateViewConstraints()
        // Add custom view sizing constraints here
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setup CandidateBarView
        candidateBarView = UIView()
        self.view.addSubview(candidateBarView)
        
        // Setup SKInputView
        skInputView = SKInputView()
        skInputView.delegate = self
        skInputView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(skInputView)
        
        // Setup SKNumberInputView
        skNumberInputView = SKNumberInputView()
        skNumberInputView.delegate = self
        skNumberInputView.translatesAutoresizingMaskIntoConstraints = false
        skNumberInputView.isHidden = true // Hidden by default
        self.view.addSubview(skNumberInputView)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Candidate Bar: Top, Left, Right, Height 40
            candidateBarView.topAnchor.constraint(equalTo: self.view.topAnchor),
            candidateBarView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            candidateBarView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            candidateBarView.heightAnchor.constraint(equalToConstant: 40),
            
            // Input View: Below Candidate Bar, Left, Right, Bottom
            skInputView.topAnchor.constraint(equalTo: candidateBarView.bottomAnchor),
            skInputView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            skInputView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            skInputView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            
            // Number Input View: Same constraints as Input View
            skNumberInputView.topAnchor.constraint(equalTo: candidateBarView.bottomAnchor),
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
    
    // MARK: - SKInputViewDelegate
    
    func didTapKey(_ title: String) {
        self.textDocumentProxy.insertText(title)
    }
    
    func didTapNumberButton() {
        skInputView.isHidden = true
        skNumberInputView.isHidden = false
    }
    
    func didTapNextKeyboard() {
        self.advanceToNextInputMode()
    }
    
    // MARK: - SKNumberInputViewDelegate
    
    func didTapNumberKey(_ title: String) {
        self.textDocumentProxy.insertText(title)
    }
    
    func didTapSwitchToAlpha() {
        skNumberInputView.isHidden = true
        skInputView.isHidden = false
    }

}
