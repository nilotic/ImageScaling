//
//  ImageProcessor.swift
//  ImageScalingTest
//
//  Created by 12282035 on 2/27/24.
//

import SwiftUI
import UIKit
import Accelerate
import Vision
import Metal
import MetalKit
import MetalPerformanceShaders

final class ImageProcessor {
    
    // MARK: - Value
    // MARK: Private
    private let device = MTLCreateSystemDefaultDevice()
    
    private lazy var commandQueue: MTLCommandQueue? = {
        device?.makeCommandQueue()
    }()
    
    private var computePipelineState: MTLComputePipelineState?
   
    
    // MARK: - Function
    // MARK: Public
    func resized(image: UIImage, size: CGSize, quality: CGInterpolationQuality) throws -> Image {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        
        // Context
        guard let context = UIGraphicsGetCurrentContext() else {
            throw ImageError(description: "Could not get current context")
        }
        
        context.interpolationQuality = quality
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        // UIImage → CGImage
        guard let cgImage = image.cgImage else {
            throw ImageError(description: "Could not create a cgImage")
        }
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        // Scaling
        guard let scaledImage = UIGraphicsGetImageFromCurrentImageContext() else {
            throw ImageError(description: "Could not convert a scaledImage")
        }
        
        UIGraphicsEndImageContext()
        return Image(uiImage: scaledImage)
    }
    
    func lanczosResampling(image: UIImage, size: CGSize) throws -> Image {
        // UIImage → CGImage
        guard let cgImage = image.cgImage else {
            throw ImageError(description: "Could not create a cgImage")
        }
        
        // Input, Output Format
        var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: nil,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
                                          version: 0, decode: nil, renderingIntent: .defaultIntent)
        
        var sourceBuffer = vImage_Buffer()
        var error = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, cgImage, vImage_Flags(kvImageNoFlags))
        
        guard error == kvImageNoError else {
            throw ImageError(description: "Could not initalize a sourceBuffer")
        }
        
        // Input Buffer
        var destinationBuffer = vImage_Buffer()
        error = vImageBuffer_Init(&destinationBuffer, vImagePixelCount(size.height), vImagePixelCount(size.width), format.bitsPerPixel, vImage_Flags(kvImageNoFlags))
        
        guard error == kvImageNoError else {
            throw ImageError(description: "Could not initalize a destinationBuffer")
        }
        
        // Resampling
        error = vImageScale_ARGB8888(&sourceBuffer, &destinationBuffer, nil, vImage_Flags(kvImageHighQualityResampling))

        guard error == kvImageNoError else {
            throw ImageError(description: "Could not create a image")
        }
        
        // Buffer → CIImage
        guard let ciImage = vImageCreateCGImageFromBuffer(&destinationBuffer, &format, nil, nil, vImage_Flags(kvImageNoFlags), &error)?.takeRetainedValue() else {
            throw ImageError(description: "Could not create a ciImage")
        }
        
        // CIImage → Image
        return Image(uiImage: UIImage(cgImage: ciImage))
    }
    
    func lanczosResampling2(image: UIImage, size: CGSize) throws -> Image {
        // UIImage → CGImage
        guard let cgImage = image.cgImage else {
            throw ImageError(description: "Could not create a cgImage")
        }
        
        // Device
        guard let device else {
            throw ImageError(description: "Metal is not supported on this device")
        }
        
        // MTLTexture
        let textureLoader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [.origin: MTKTextureLoader.Origin.bottomLeft,
                                                       .SRGB: false]
        let sourceTexture = try textureLoader.newTexture(cgImage: cgImage, options: options)
        
        
        // LanczosScale
        let lanczosScale = MPSImageLanczosScale(device: device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sourceTexture.pixelFormat, width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        // Output Texture
        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            throw ImageError(description: "Failed to create output texture")
        }
        
        // Command Buffer
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else {
            throw ImageError(description: "Failed to create command buffer")
        }
        
        lanczosScale.encode(commandBuffer: commandBuffer, sourceTexture: sourceTexture, destinationTexture: outputTexture)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // MTLTexture → Image
        return try convert(texture: outputTexture)
    }
    
    func superResolution(image: UIImage, size: CGSize) throws -> Image {
        // UIImage → CGImage
        guard let cgImage = image.cgImage else {
            throw ImageError(description: "Could not create a cgImage")
        }
        
        // ML Model
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let realESRGAN = try RealESRGAN(configuration: configuration)
        
        // Model
        let coreMLModel = try VNCoreMLModel(for: realESRGAN.model)
        
        // Request
        let coreMLRequest = VNCoreMLRequest(model: coreMLModel)
        coreMLRequest.imageCropAndScaleOption = .scaleFit
        
        // Perform
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([coreMLRequest])
        
        guard let result = coreMLRequest.results?.first as? VNPixelBufferObservation else {
            throw ImageError(description: "Failed to create pixel buffer")
        }
        
        // Pixel Buffer → CIImage
        let ciImage = CIImage(cvPixelBuffer: result.pixelBuffer)
        let scale = max(size.width / ciImage.extent.width, size.height / ciImage.extent.height)

        // scale down, retaining the original's aspect ratio
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let xInset = (scaledImage.extent.width - size.width) / 2
        let yInset = (scaledImage.extent.height - size.height) / 2

        // crop the center to match the target size
        let croppedImage = scaledImage.cropped(to: scaledImage.extent.insetBy(dx: xInset, dy: yInset))
        
        
        // CIImage → CGImage
        guard let cgImage = CIContext(options: nil).createCGImage(croppedImage, from: croppedImage.extent) else {
            throw ImageError(description: "Could not convert a cgImage")
        }
        
        // CGImage → Image
        return Image(uiImage: UIImage(cgImage: cgImage))
    }

    func edgeDirected(image: UIImage, size: CGSize) throws -> Image {
        // Process
        let processedTexture = try processEdgeDirectedInterpolation(texture: try convert(image: image), size: size)
        
        // MTLTexture → Image
        return Image(uiImage: try convert(texture: processedTexture))
    }
    
    // MARK: Private
    private func processEdgeDirectedInterpolation(texture: MTLTexture, size: CGSize) throws -> MTLTexture {
        // Device, CommandQueue
        guard let device, let commandQueue else {
            throw ImageError(description: "Could not create a command queue")
        }
        
        // Kernel
        guard let kernelFunction = device.makeDefaultLibrary()?.makeFunction(name: "edgeDirectedInterpolation") else {
            throw ImageError(description: "Could not create the kernel function for EDI")
        }
        
        // Command Buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer(), let computeCommandEncoder = commandBuffer.makeComputeCommandEncoder() else {
            throw ImageError(description: "Failed to create command encoder")
        }
        
        // Pipeline
        let computePipelineState = try device.makeComputePipelineState(function: kernelFunction)
        computeCommandEncoder.setComputePipelineState(computePipelineState)
        
        // Input Texture
        computeCommandEncoder.setTexture(texture, index: 0)
        
        // Output Texture
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: texture.width, height: texture.height, mipmapped: false)
        textureDescriptor.usage = [.shaderWrite, .shaderRead]
        
        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw ImageError(description: "Failed to create output texture")
        }
        
        computeCommandEncoder.setTexture(outputTexture, index: 1)
        
        // Scaling
        let threadGroupSize = MTLSize(width: 8, height: 8, depth: 1)
        let threadGroups = MTLSize(width: (Int(size.width) + threadGroupSize.width - 1) / threadGroupSize.width, height: (Int(size.height) + threadGroupSize.height - 1) / threadGroupSize.height, depth: 1)
        computeCommandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        
        // Commit CommandBuffer
        computeCommandEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        return outputTexture
    }
    
    private func convert(image: UIImage) throws -> MTLTexture {
        // Device
        guard let device else {
            throw ImageError(description: "Metal is not supported on this device")
        }
        
        // UIImage → CGImage
        guard let cgImage = image.cgImage else {
            throw ImageError(description: "Could not create a cgImage")
        }
        
        let options: [MTKTextureLoader.Option: Any] = [.textureUsage: MTLTextureUsage.shaderWrite.rawValue | MTLTextureUsage.shaderRead.rawValue,
                                                       .textureStorageMode: MTLStorageMode.private.rawValue,
                                                       .SRGB: false]
        // CGImage → MTLTexture
        return try MTKTextureLoader(device: device).newTexture(cgImage: cgImage, options: options)
    }
    
    private func convert(texture: MTLTexture) throws -> UIImage {
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * texture.width
        var imageBytes = [UInt8](repeating: 0, count: Int(texture.width * texture.height * 4))
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        
        texture.getBytes(&imageBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        guard let provider = CGDataProvider(data: Data(bytes: &imageBytes, count: imageBytes.count) as CFData),
              let cgImage = CGImage(width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            
            throw ImageError(description: "Could not create a cgImage")
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func convert(texture: MTLTexture) throws -> Image {
        let bytesPerRow = texture.width * 4
        var imageData = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        
        texture.getBytes(&imageData, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            
        
        guard let context = CGContext(data: &imageData, width: texture.width, height: texture.height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: CGColorSpaceCreateDeviceRGB(), 
                                      bitmapInfo: bitmapInfo) else {
            
            throw ImageError(description: "Could not create a context")
        }
        
        guard let cgImage = context.makeImage() else {
            throw ImageError(description: "Could not create a cgImage")
        }
        
        return Image(uiImage: UIImage(cgImage: cgImage, scale: 1, orientation: .downMirrored))
    }

    
    private func convert(image: UIImage) throws -> MPSImage {
        // Device
        guard let device else {
            throw ImageError(description: "Metal is not supported on this device")
        }
        
        // UIImage → CGImage
        guard let cgImage = image.cgImage else {
            throw ImageError(description: "Could not create a cgImage")
        }
        
        // CGImage → MTLTexture
        let texture = try MTKTextureLoader(device: device).newTexture(cgImage: cgImage, options: [:])
        return MPSImage(texture: texture, featureChannels: 4)
    }

    private func convert(mpsImage: MPSImage) throws -> Image {
        let bytesPerPixel = 4 * 4
        var data = [UInt8](repeating: 0, count: mpsImage.width * mpsImage.height * bytesPerPixel)
        mpsImage.texture.getBytes(&data, bytesPerRow: bytesPerPixel * mpsImage.width, from: MTLRegionMake2D(0, 0, mpsImage.width, mpsImage.height), mipmapLevel: 0)
        
        guard let provider = CGDataProvider(data: NSData(bytes: &data, length: data.count)) else {
            throw ImageError(description: "Could not create a CGDataProvider")
        }
        
        guard let cgImage = CGImage(width: mpsImage.width, height: mpsImage.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4 * mpsImage.width,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent) else {
            
            throw ImageError(description: "Could not create a cgImage")
        }
        
        return Image(uiImage: UIImage(cgImage: cgImage))
    }
}
