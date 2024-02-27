//
//  UpscalingView.swift
//  ImageScalingTest
//
//  Created by 12282035 on 2/27/24.
//

import SwiftUI

struct UpscalingView: View {
    
    // MARK: - Value
    // MARK: Pubilc
    let title: String
    let image: Image?
    
    
    // MARK: - View
    // MARK: Public
    var body: some View {
        ZStack {
            imageView
            titleView
        }
        .overlay(progressView)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: Private
    private var titleView: some View {
        ZStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    @ViewBuilder
    private var imageView: some View {
        if let image {
            image
                .resizable()
                .scaledToFit()
    
        } else {
            ProgressView()
        }
    }
    
    @ViewBuilder
    private var progressView: some View {
        if image == nil {
            ZStack {
                ProgressView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    UpscalingView(title: "Origin", image: nil)
        .frame(width: 180, height: 200)
        .border(.gray)
}
