//
//  ContentData.swift
//  ImageScalingTest
//
//  Created by Den Jo on 2/17/24.
//
//

import SwiftUI
import Vision
import OSLog
import Accelerate
import UIKit

@Observable
final class ContentData {
    
    // MARK: - Value
    // MARK: Public
    private(set) var lowQualityImage: Image?
    private(set) var mediumQualityImage: Image?
    private(set) var highQualityImage: Image?
    private(set) var lanczosResamplingImage: Image?
    private(set) var lanczosResamplingImage2: Image?
    private(set) var superResolutionImage: Image?
    private(set) var edgeDirectedInterpolationImage: Image?
    
    // MARK: Private
    private let imageProcessor = ImageProcessor()
    private let size = CGSize(width: 360 * 3, height: 468 * 3)
    
    
    // MARK: - Function
    // MARK: Public
    func request() {
        resize()
        lanczosResampling()
        superResolution()
        edgeDirected()
    }
    
    private func resize() {
        Task {
            do {
                let lowQualityImage = try imageProcessor.resized(image:.medium, size: size, quality: .low)
                let mediumQualityImage = try imageProcessor.resized(image:.medium, size: size, quality: .medium)
                let highQualityImage = try imageProcessor.resized(image:.medium, size: size, quality: .high)
                
                await MainActor.run {
                    self.lowQualityImage = lowQualityImage
                    self.mediumQualityImage = mediumQualityImage
                    self.highQualityImage = highQualityImage
                }
            
            } catch {
                Logger().error("\(error.localizedDescription)")
            }
        }
    }
    
    private func lanczosResampling() {
        Task {
            let image = try imageProcessor.lanczosResampling(image: .medium, size: size)
            let image2 = try imageProcessor.lanczosResampling2(image: .medium, size: size)
            
            await MainActor.run {
                lanczosResamplingImage = image
                lanczosResamplingImage2 = image2
            }
        }
    }
    
    private func superResolution() {
        Task {
            Logger(subsystem: "CoreML", category: "Image").info("Start")
            
            do {
                let image = try imageProcessor.superResolution(image: .medium, size: size)
                await MainActor.run { self.superResolutionImage = image }
                
            } catch {
                Logger(subsystem: "CoreML", category: "Image").error("\(error.localizedDescription)")
            }
            
            Logger(subsystem: "CoreML", category: "Image").info("End")
        }
    }
    
    private func edgeDirected() {
        Task {
            do {
                let image = try imageProcessor.edgeDirected(image: .medium, size: size)
                await MainActor.run { edgeDirectedInterpolationImage = image }
                
            } catch {
                Logger().error("\(error.localizedDescription)")
            }
        }
    }
}
