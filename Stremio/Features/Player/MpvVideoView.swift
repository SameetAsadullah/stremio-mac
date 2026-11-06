import AppKit
import Libmpv
import OpenGL.GL3

/// Shows mpv's video under the web view.
final class MpvVideoView: NSView {
    let videoLayer: MpvVideoLayer

    init(player: MpvPlayerBackend) {
        videoLayer = MpvVideoLayer(player: player)
        super.init(frame: .zero)
        // A layer-hosting view, so AppKit does not draw into the layer or redraw it on its own.
        layer = videoLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    // AppKit does not set the scale of a hosted layer. Without it, video renders at 1x on Retina.
    private func updateScale() {
        guard let scale = window?.backingScaleFactor, scale != videoLayer.contentsScale else { return }
        videoLayer.contentsScale = scale
        videoLayer.setNeedsDisplay()
    }
}

/// Draws only when mpv has a new frame, the size changes or the video stops. An asynchronous
/// CAOpenGLLayer draws on every display refresh, which at 120 Hz costs about 10 W more.
final class MpvVideoLayer: CAOpenGLLayer {
    private unowned let player: MpvPlayerBackend
    private var context: CGLContextObj?
    private var render: OpaquePointer?
    private var shownLoadId: Int?

    /// Without a configured video output the layer clears to black, so no old frame stays.
    var videoConfigured = false {
        didSet { if videoConfigured != oldValue { setNeedsDisplay() } }
    }

    init(player: MpvPlayerBackend) {
        self.player = player
        super.init()
        isAsynchronous = false
        isOpaque = true
        needsDisplayOnBoundsChange = true
        backgroundColor = NSColor.black.cgColor
        player.videoLayer = self
        setNeedsDisplay()
    }

    override init(layer: Any) {
        guard let other = layer as? MpvVideoLayer else { fatalError("unexpected layer type") }
        player = other.player
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Draws the current frame, then reports load `loadId` as shown.
    func showVideo(loadId: Int) {
        shownLoadId = loadId
        setNeedsDisplay()
    }

    func freeRenderContext() {
        guard let render, let context else { return }
        CGLSetCurrentContext(context)
        mpv_render_context_set_update_callback(render, nil, nil)
        mpv_render_context_free(render)
        self.render = nil
    }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated, kCGLPFADoubleBuffer, kCGLPFAAllowOfflineRenderers, CGLPixelFormatAttribute(0),
        ]
        var pixelFormat: CGLPixelFormatObj?
        var count: GLint = 0
        CGLChoosePixelFormat(attributes, &pixelFormat, &count)
        guard let pixelFormat else { return super.copyCGLPixelFormat(forDisplayMask: mask) }
        return pixelFormat
    }

    override func copyCGLContext(forPixelFormat pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        let context = super.copyCGLContext(forPixelFormat: pixelFormat)
        self.context = context
        CGLSetCurrentContext(context)
        createRenderContext()
        return context
    }

    private func createRenderContext() {
        var glInit = mpv_opengl_init_params(
            get_proc_address: { _, name in
                guard let name, let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString) else {
                    return nil
                }
                return CFBundleGetFunctionPointerForName(bundle, String(cString: name) as CFString)
            }, get_proc_address_ctx: nil)
        let status = MPV_RENDER_API_TYPE_OPENGL.withCString { api in
            withUnsafeMutablePointer(to: &glInit) { glInit in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: api)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: glInit),
                    mpv_render_param(),
                ]
                return mpv_render_context_create(&render, player.handle, &params)
            }
        }
        if status < 0 {
            Log.player.error("render context failed: \(String(cString: mpv_error_string(status)), privacy: .public)")
        }
        mpv_render_context_set_update_callback(
            render,
            { context in
                guard let context else { return }
                let layer = Unmanaged<MpvVideoLayer>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { layer.update() }
            }, Unmanaged.passUnretained(self).toOpaque())
        player.renderContextCreated()
    }

    private func update() {
        guard let render, let context else { return }
        CGLSetCurrentContext(context)
        if mpv_render_context_update(render) & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0 {
            setNeedsDisplay()
        }
    }

    override func canDraw(
        inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj, forLayerTime time: CFTimeInterval,
        displayTime: UnsafePointer<CVTimeStamp>?
    ) -> Bool {
        render != nil
    }

    override func draw(
        inCGLContext context: CGLContextObj, pixelFormat: CGLPixelFormatObj, forLayerTime time: CFTimeInterval,
        displayTime: UnsafePointer<CVTimeStamp>?
    ) {
        if let render, videoConfigured {
            renderFrame(render)
            if let id = shownLoadId {
                shownLoadId = nil
                player.videoShown(loadId: id)
            }
        } else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
        glFlush()
    }

    private func renderFrame(_ render: OpaquePointer) {
        var framebuffer: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &framebuffer)
        var viewport = [GLint](repeating: 0, count: 4)
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        var target = mpv_opengl_fbo(fbo: framebuffer, w: viewport[2], h: viewport[3], internal_format: 0)
        var flipY: Int32 = 1
        // With video-timing-offset=0 mpv does not wait here anyway. This keeps the main thread
        // from waiting if that option changes.
        var blockForTargetTime: Int32 = 0
        withUnsafeMutablePointer(to: &target) { target in
            withUnsafeMutablePointer(to: &flipY) { flipY in
                withUnsafeMutablePointer(to: &blockForTargetTime) { block in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: target),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipY),
                        mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: block),
                        mpv_render_param(),
                    ]
                    _ = mpv_render_context_render(render, &params)
                }
            }
        }
    }
}
