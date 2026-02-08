//
//  SKNumberInputView.swift
//  ShikaKeyBoard
//
//  Created by ShiKa on 2026/1/30.
//

import UIKit

// SKNumberInputViewDelegate removed in favor of SKKeyboardEventHandler

class SKNumberInputView: UIView {
    
    weak var eventHandler: SKKeyboardEventHandler?
    private var mainStackView: UIStackView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        updateNumberAndPunctuationStackView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        updateNumberAndPunctuationStackView()
    }
    
    private func setupView() {
        // No background color
        
        mainStackView = UIStackView()
        mainStackView.axis = .horizontal
        mainStackView.distribution = .fill
        mainStackView.alignment = .fill
        mainStackView.spacing = 0 // Spacing handled internally
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        
        self.addSubview(mainStackView)
        
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: self.topAnchor, constant: 5),
            mainStackView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 5),
            mainStackView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -5),
            mainStackView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -5)
        ])
    }
    
    private func updateNumberAndPunctuationStackView() {
        mainStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Left Side: Numbers 3x3 + Bottom Row
        let leftView = UIStackView()
        leftView.axis = .vertical
        leftView.spacing = SKConfig.keyboardVerticalSpacing
        leftView.alignment = .fill
        leftView.distribution = .fill
        
        // 1-9 Grid
        for i in 0..<3 {
            let numberLineRow = UIStackView()
            numberLineRow.axis = .horizontal
            numberLineRow.spacing = SKConfig.keyboardHorizontalSpacing
            numberLineRow.alignment = .fill
            numberLineRow.distribution = .fill
            
            for j in 1..<4 {
                let number = i * 3 + j
                let numberButton = SKIMKeyButton(title: "\(number)", width: 55, font: UIFont.systemFont(ofSize: 20, weight: .regular))
                numberButton.addTarget(self, action: #selector(numberKeyPressed(_:)), for: .touchUpInside)
                numberLineRow.addArrangedSubview(numberButton)
            }
            leftView.addArrangedSubview(numberLineRow)
        }
        
        // Bottom Row: Return, 0, Delete
        let numberLine3Row = UIStackView()
        numberLine3Row.axis = .horizontal
        numberLine3Row.spacing = 6
        numberLine3Row.alignment = .fill
        numberLine3Row.distribution = .fill
        
        let returnButton = SKIMKeyButton(title: "返回", width: 55, font: UIFont.systemFont(ofSize: 16, weight: .regular), backgroundColor: UIColor(white: 0.9, alpha: 1))
        returnButton.addTarget(self, action: #selector(returnToAlphaPressed), for: .touchUpInside)
        
        let zeroButton = SKIMKeyButton(title: "0", width: 55, font: UIFont.systemFont(ofSize: 20, weight: .regular))
        zeroButton.addTarget(self, action: #selector(numberKeyPressed(_:)), for: .touchUpInside)
        
        let deleteButton = SKIMKeyButton(title: "⌫", width: 55, font: UIFont.systemFont(ofSize: 20, weight: .regular))
        deleteButton.addTarget(self, action: #selector(deleteKeyPressed), for: .touchUpInside)
        // TODO: Long press delete
        
        numberLine3Row.addArrangedSubview(returnButton)
        numberLine3Row.addArrangedSubview(zeroButton)
        numberLine3Row.addArrangedSubview(deleteButton)
        leftView.addArrangedSubview(numberLine3Row)
        
        // Right Side: ScrollView with Punctuation
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // Make sure scroll view clips bounds so content doesn't overflow
        scrollView.clipsToBounds = true
        
        let contentStackView = waterfallView(items: KeyboardLayout.punctuation)
        scrollView.addSubview(contentStackView)
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
        
        mainStackView.addArrangedSubview(leftView)
        mainStackView.addArrangedSubview(scrollView)
        
        // Constraint for scroll view width or priority?
        // In ref: `scrollView.trailingAnchor.constraint(equalTo: mainKeyboardStackView.trailingAnchor).isActive = true`
        // In UIStackView, we just need to make sure leftView doesn't hug everything.
        // SKIMKeyButton has fixed width now. Left view has fixed width (roughly 55*3 + spacing).
        // ScrollView should take the rest.
    }
    
    private func waterfallView(items: [String]) -> UIStackView {
        let wtfView = UIStackView()
        wtfView.axis = .vertical
        wtfView.spacing = SKConfig.keyboardVerticalSpacing
        wtfView.distribution = .fillEqually // rows have equal height
        
        var rowViews = [UIStackView]()
        
        for _ in 0..<4 {
            let rowView = UIStackView()
            rowView.axis = .horizontal
            rowView.spacing = SKConfig.keyboardHorizontalSpacing
            rowView.distribution = .fill // Buttons have fixed width
            rowView.alignment = .fill
            wtfView.addArrangedSubview(rowView)
            rowViews.append(rowView)
        }
        
        for (index, item) in items.enumerated() {
            let width: CGFloat = (item.count >= 2) ? 42 : 33 // Simple heuristic from ref
            let button = SKIMKeyButton(title: item, width: width, backgroundColor: UIColor(white: 0.95, alpha: 1))
            button.addTarget(self, action: #selector(punctuationKeyPressed(_:)), for: .touchUpInside)
            
            let rowIndex = index % 4
            rowViews[rowIndex].addArrangedSubview(button)
        }
        
        return wtfView
    }
    
    @objc private func numberKeyPressed(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
        eventHandler?.didTapKey(title)
    }
    
    @objc private func punctuationKeyPressed(_ sender: UIButton) {
        guard let title = sender.title(for: .normal) else { return }
         eventHandler?.didTapKey(title) 
    }
    
    @objc private func returnToAlphaPressed() {
        eventHandler?.didTapSwitchLayout(to: .alphabet)
    }
    
    @objc private func deleteKeyPressed() {
         eventHandler?.didTapDelete()
    }
}
