//
//  SKInputSwitchButton.swift
//  ShikaKeyBoard
//
//  Created by ShiKa on 2026/2/7.
//

import UIKit

enum SKInputSwitchState {
    case chinese
    case japanese
    case mixed
    
    var next: SKInputSwitchState {
        switch self {
        case .chinese: return .japanese
        case .japanese: return .mixed
        case .mixed: return .chinese
        }
    }
}

class SKInputSwitchButton: UIButton {
    
    var stateChangeHandler: ((SKInputSwitchState) -> Void)?
    
    private(set) var currentState: SKInputSwitchState = .mixed
    
    // UI Components
    private let singleLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let topLeftLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bottomRightLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .right
        label.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let bracketsLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.black.cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 1.5
        return layer
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateBrackets()
    }
    
    private func setupView() {
        self.layer.cornerRadius = 5
        self.clipsToBounds = true
        // No default border as per recent user edits
        
        self.layer.addSublayer(bracketsLayer)
        
        addSubview(singleLabel)
        addSubview(topLeftLabel)
        addSubview(bottomRightLabel)
        
        setupConstraints()
        updateDisplay()
        
        self.addTarget(self, action: #selector(didTapButton), for: .touchUpInside)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Single Label Centered
            singleLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            singleLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            
            // Top Left Label - Positioned for the new layout
            // "中" needs to be in the empty space at top-left
            topLeftLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 8),
            topLeftLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
            
            // Bottom Right Label - Positioned for the new layout
            // "あ" needs to be in the empty space at bottom-right
            bottomRightLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            bottomRightLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8)
        ])
    }
    
    @objc private func didTapButton() {
        currentState = currentState.next
        stateChangeHandler?(currentState)
        updateDisplay()
        setNeedsLayout()
    }
    
    private func updateDisplay() {
        switch currentState {
        case .chinese:
            singleLabel.text = "中"
            singleLabel.isHidden = false
            topLeftLabel.isHidden = true
            bottomRightLabel.isHidden = true
            bracketsLayer.isHidden = true
            
        case .japanese:
            singleLabel.text = "あ"
            singleLabel.isHidden = false
            topLeftLabel.isHidden = true
            bottomRightLabel.isHidden = true
            bracketsLayer.isHidden = true
            
        case .mixed:
            singleLabel.isHidden = true
            topLeftLabel.text = "中"
            topLeftLabel.isHidden = false
            bottomRightLabel.text = "あ"
            bottomRightLabel.isHidden = false
            bracketsLayer.isHidden = false
        }
    }
    
    private func updateBrackets() {
        guard currentState == .mixed else { return }
        
        // Ensure layout is current so we have correct bounds
        // layoutIfNeeded() // Avoid calling layoutIfNeeded inside layoutSubviews to prevent loops
        
        let path = UIBezierPath()
        let w = bounds.width
        let h = bounds.height
        let cornerRadius: CGFloat = 5.0
        
        // 修改这里：增加一个 margin 值，让括号往中间收缩
        // Modify here: Add a margin value to make the brackets shrink towards the center
        let margin: CGFloat = 12.0
        
        // Define gap for text
        // "中" is top-left, "あ" is bottom-right.
        // We need lines at: Top-Right, Bottom-Left.
        
        // Top-Right Bracket
        // Start from top edge (around center or slightly right), go right, round corner, go down
        // 调整坐标，应用 margin
        let topStart = CGPoint(x: w * 0.5, y: margin) // Start after "中"
        let rightEnd = CGPoint(x: w - margin, y: h * 0.48) // End before "あ"
        
        path.move(to: topStart)
        path.addLine(to: CGPoint(x: w - margin - cornerRadius, y: margin))
        path.addArc(withCenter: CGPoint(x: w - margin - cornerRadius, y: margin + cornerRadius), 
                    radius: cornerRadius, 
                    startAngle: -CGFloat.pi / 2, 
                    endAngle: 0, 
                    clockwise: true)
        path.addLine(to: rightEnd)
        
        // Bottom-Left Bracket
        // Start from bottom edge (around center or slightly left), go left, round corner, go up
        // 调整坐标，应用 margin
        let bottomStart = CGPoint(x: w * 0.5, y: h - margin) // Start before "あ"
        let leftEnd = CGPoint(x: margin, y: h * 0.48) // End after "中"
        
        path.move(to: bottomStart)
        path.addLine(to: CGPoint(x: margin + cornerRadius, y: h - margin))
        path.addArc(withCenter: CGPoint(x: margin + cornerRadius, y: h - margin - cornerRadius), 
                    radius: cornerRadius, 
                    startAngle: CGFloat.pi / 2, 
                    endAngle: CGFloat.pi, 
                    clockwise: true)
        path.addLine(to: leftEnd)
        
        bracketsLayer.path = path.cgPath
    }
}
