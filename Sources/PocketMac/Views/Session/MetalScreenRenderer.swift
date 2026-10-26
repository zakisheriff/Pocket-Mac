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
    private let worker = MetalFrameWorker()

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
        // This timeout is up to one second, not a nonblocking poll. Drawable
        // acquisition must run on the render worker, never the input thread.
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
        return true
    }

    /// Submit at most one frame. A busy GPU never queues old frames or
    /// blocks touches; the display link retries with the latest pixels.
    @discardableResult
    func draw(retry: @escaping @MainActor () -> Void) -> Bool {
        guard let texture else { return true }
        return worker.submit(texture: texture, layer: layer, queue: queue, retry: retry)
    }
}

/// Only immutable frame references cross onto the render queue. The lock
/// covers the single in-flight slot, shared with the GPU completion callback.
private final class MetalFrameWorker: @unchecked Sendable {
    private let renderQueue = DispatchQueue(label: "com.zakisheriff.pocketmac.render", qos: .userInteractive)
    private let lock = NSLock()
    private var busy = false

    func submit(texture: MTLTexture, layer: CAMetalLayer, queue: MTLCommandQueue,
                retry: @escaping @MainActor () -> Void) -> Bool {
        let accepted = lock.withLock {
            guard !busy else { return false }
            busy = true
            return true
        }
        guard accepted else { return false }
        renderQueue.async { [self] in
            autoreleasepool {
                guard let drawable = layer.nextDrawable(),
                      drawable.texture.width == texture.width,
                      drawable.texture.height == texture.height,
                      let commands = queue.makeCommandBuffer(),
                      let blit = commands.makeBlitCommandEncoder() else {
                    finish()
                    DispatchQueue.main.async { retry() }
                    return
                }
                blit.copy(
                    from: texture, sourceSlice: 0, sourceLevel: 0,
                    sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                    sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                    to: drawable.texture, destinationSlice: 0, destinationLevel: 0,
                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                )
                blit.endEncoding()
                commands.present(drawable)
                commands.addCompletedHandler { [self] _ in finish() }
                commands.commit()
            }
        }
        return true
    }

    private func finish() {
        lock.withLock { busy = false }
    }
}
