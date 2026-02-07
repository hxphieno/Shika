//
//  CandidateBarView.swift
//  ShikaKeyBoard
//
//  Created by ShiKa on 2026/2/7.
//

import UIKit

class CandidateBarView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        self.heightAnchor.constraint(equalToConstant: 43).isActive = true
        // Placeholder for future implementation
    }
}
