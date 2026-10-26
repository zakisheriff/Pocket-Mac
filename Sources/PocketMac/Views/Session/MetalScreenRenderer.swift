import IOSurface
import Metal
import QuartzCore

/// Shows the Mac's framebuffer through Metal with no CPU copies: the decoded
/// IOSurface is wrapped as a texture and copied GPU-to-GPU into the layer's
/// drawable each frame.
@MainActor
final class MetalScreenRenderer {
    let layer = CAMetalLayer()
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var texture: MTLTexture?

    /// nil when this device can't do it; the caller falls back to images.
    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.isOpaque = true
        layer.contentsGravity = .resize
        layer.magnificationFilter = .linear
        layer.minificationFilter = .linear
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.maximumDrawableCount = 3
        // Never stall the main thread (and with it, touch input) waiting
        // for a drawable: skip the frame and draw the next tick instead.
        layer.allowsNextDrawableTimeout = true
        layer.presentsWithTransaction = false
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    /// Wraps a new framebuffer. Returns false if it can't be shown via Metal.
    func setSurface(_ surface: IOSurface?, width: Int, height: Int) -> Bool {
        guard let surface, width > 0, height > 0 else {
            texture = nil
            return true
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
            self.texture = nil
            return false
        }
        self.texture = texture
        layer.drawableSize = CGSize(width: width, height: height)
        draw()
        return true
    }

    /// Frames on the GPU not yet shown; one is enough, more only adds delay.
    private var inFlight = 0

    /// Returns false if the frame was skipped (the GPU is still busy with
    /// the last one), so the caller can try again next screen refresh.
    @discardableResult
    func draw() -> Bool {
        guard let texture else { return true }
        guard inFlight == 0 else { return false }
        guard let drawable = layer.nextDrawable(),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder() else { return false }
        blit.copy(
            from: texture, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
            to: drawable.texture, destinationSlice: 0, destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blit.endEncoding()
        commands.present(drawable)
        inFlight += 1
        commands.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async { self?.inFlight -= 1 }
        }
        commands.commit()
        return true
    }
}
