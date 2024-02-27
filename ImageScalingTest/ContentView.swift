//
//  ContentView.swift
//  ImageScalingTest
//
//  Created by Den Jo on 2/16/24.
//

import SwiftUI

struct ContentView: View {
    
    // MARK: - Value
    // MARK: Private
    @State private var data = ContentData()
    
    
    // MARK: - View
    // MARK: Public
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    UpscalingView(title: "Origin", image: Image(.original))
                    UpscalingView(title: "Low Quality", image: data.lowQualityImage)
                }
                
                HStack {
                    UpscalingView(title: "Medium Quality", image: data.mediumQualityImage)
                    UpscalingView(title: "High Quality", image: data.highQualityImage)
                }
                
                HStack {
                    UpscalingView(title: "Lanczos Resampling", image: data.lanczosResamplingImage)
                    UpscalingView(title: "Lanczos Resampling2", image: data.lanczosResamplingImage2)
                }
                
                HStack {
                    UpscalingView(title: "Edge Directed", image: data.edgeDirectedInterpolationImage)
                    UpscalingView(title: "Super Resolution", image: data.superResolutionImage)
                }
            }
            .padding(.horizontal)
        }
        .task {
            data.request()
        }
    }
}

#Preview {
    ContentView()
}
