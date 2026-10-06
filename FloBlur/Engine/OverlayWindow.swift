import AppKit
import QuartzCore

/// Display link via the same factory the original uses
/// (`displayLinkWithTarget:selector:`, resolved dynamically since the
/// public header marks it unavailable on macOS).
private extension CADisplayLink {
    static func make(target: AnyObject, selector: Selector) -> CADisplayLink? {
        let sel = NSSelectorFromString("displayLinkWithTarget:selector:")
        guard CADisplayLink.responds(to: sel),
              let method = class_getClassMethod(CADisplayLink.self, sel)
        else { return nil }
        typealias Fn = @convention(c) (AnyClass, Selector, AnyObject, Selector) -> Unmanaged<CADisplayLink>
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        // Factory methods return autoreleased (+0): takeUnretainedValue.
        // takeRetainedValue would over-release into EXC_BAD_ACCESS.
        return fn(CADisplayLink.self, sel, target, selector).takeUnretainedValue()
    }
}

/// Click-through content view for the overlay (diagnostic name parity).
final class ClickThroughContentView: NSView {}

/// Full-screen effect window for one display. Structure mirrors the
/// original's `OverlayWindow`:
/// - transparent, non-opaque, no shadow, ignores mouse, never key/main
/// - `collectionBehavior` 0x251: all Spaces, stationary, no cycle, aux-fullscreen
/// - black dim layer (opacity animated) + `NSVisualEffectView` blur fallback
/// - sharp regions cut as plain rects into an even-odd mask (flipped coords)
/// - SkyLight blur radius eased out-cubic over 0.28s via `CADisplayLink`
/// - show/hide fade the window alpha; hide parks an `orderOut` on delay
final class OverlayWindow: NSWindow {
    private(set) var dimView = NSView()
    private var fallbackBlurView: NSVisualEffectView!

    private var appliedHoles: [CGRect] = []
    private var appliedBlurRadius: Int?
    private var appliedDimOpacity: Float?
    private var appliedDimColor: CGColor?

    private var blurRamp: CADisplayLink?
    private var blurRampFrom = 0
    private var blurRampTo = 0
    private var blurRampStart = 0.0
    private var presentedBlurRadius = 0
    private var pendingOrderOut: DispatchWorkItem?

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isMovable = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        // canJoinAllSpaces | stationary | ignoresCycle | fullScreenAuxiliary
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        sharingType = .none
        isExcludedFromWindowsMenu = true

        let content = ClickThroughContentView(frame: NSRect(origin: .zero, size: frame.size))
        content.autoresizingMask = [.width, .height]

        let fallback = NSVisualEffectView(frame: content.bounds)
        fallback.autoresizingMask = [.width, .height]
        fallback.material = NSVisualEffectView.Material(rawValue: 15) ?? .hudWindow
        fallback.blendingMode = .behindWindow
        fallback.state = .active
        fallback.alphaValue = 0
        fallback.wantsLayer = true
        content.addSubview(fallback)
        fallbackBlurView = fallback

        content.wantsLayer = true // hosts the hole mask
        let dim = NSView(frame: content.bounds)
        dim.autoresizingMask = [.width, .height]
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.cgColor
        dim.layer?.opacity = 0
        content.addSubview(dim)
        dimView = dim

        self.contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func close() {
        blurRamp?.invalidate()
        blurRamp = nil
        pendingOrderOut?.cancel()
        pendingOrderOut = nil
        super.close()
    }

    // MARK: - Holes (snap; already in flipped window-local coords)

    func setHoles(_ holes: [CGRect]) {
        guard holes != appliedHoles else { return }
        appliedHoles = holes
        applyMask(holes, to: contentView?.layer)
    }

    private func applyMask(_ holes: [CGRect], to layer: CALayer?) {
        guard let layer else { return }
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: layer.bounds.size))
        for hole in holes where !hole.isEmpty {
            path.addRect(hole)
        }
        let mask = CAShapeLayer()
        // Pin the mask geometry to the masked layer: with an explicit frame
        // the path coordinates map 1:1 under every mask-mapping rule, so
        // holes can never drift onto a neighboring window.
        mask.frame = layer.bounds
        mask.bounds = layer.bounds
        // This overlay's own screen scale — never main's. Mixed
        // Retina/non-Retina setups would otherwise get soft holes
        // drifting a pixel off on the secondary display.
        if let screenScale = screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor {
            mask.contentsScale = screenScale
        }
        mask.path = path
        mask.fillRule = .evenOdd
        layer.mask = mask
    }

    // MARK: - Blur (ease-out-cubic ramp over 0.28s)

    func setBlur(radius: Int, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { _ in
                fallbackBlurView.animator().alphaValue = radius > 0 ? 1 : 0
            }
        } else {
            fallbackBlurView.alphaValue = radius > 0 ? 1 : 0
        }
        startBlurRamp(to: radius)
    }

    private func startBlurRamp(to radius: Int) {
        blurRamp?.invalidate()
        blurRamp = nil
        blurRampFrom = presentedBlurRadius
        blurRampTo = radius
        blurRampStart = CACurrentMediaTime()
        if blurRampFrom == blurRampTo {
            SkyLight.setBackgroundBlurRadius(windowNumber: windowNumber, radius: radius)
            presentedBlurRadius = radius
            appliedBlurRadius = radius
            return
        }
        guard let link = CADisplayLink.make(target: self, selector: #selector(stepBlurRamp)) else { return }
        link.add(to: .main, forMode: .common)
        blurRamp = link
    }

    @objc private func stepBlurRamp() {
        let duration = 0.28
        let t = min((CACurrentMediaTime() - blurRampStart) / duration, 1)
        let eased = 1 - pow(1 - t, 3)
        let radius = Int((Double(blurRampFrom) + eased * Double(blurRampTo - blurRampFrom)).rounded())
        if radius != presentedBlurRadius {
            presentedBlurRadius = radius
            appliedBlurRadius = radius
            if windowNumber > 0 {
                SkyLight.setBackgroundBlurRadius(windowNumber: windowNumber, radius: radius)
            }
        }
        if t >= 1 {
            blurRamp?.invalidate()
            blurRamp = nil
        }
    }

    // MARK: - Dim (layer opacity + color, animated)

    func setDim(color: NSColor, animated: Bool) {
        let cg = color.cgColor
        guard appliedDimColor != cg else { return }
        appliedDimColor = cg
        if animated {
            NSAnimationContext.runAnimationGroup { _ in
                dimView.animator().layer?.backgroundColor = cg
            }
        } else {
            dimView.layer?.backgroundColor = cg
        }
    }

    func setDim(opacity: Float, animated: Bool) {
        let clamped = min(max(opacity, 0), 1)
        guard appliedDimOpacity != clamped else { return }
        appliedDimOpacity = clamped
        if animated {
            NSAnimationContext.runAnimationGroup { _ in
                dimView.animator().layer?.opacity = clamped
            }
        } else {
            dimView.layer?.opacity = clamped
        }
    }

    // MARK: - Show / hide (window-alpha fade; hide parks a delayed orderOut)

    func fadeIn(animated: Bool, duration: TimeInterval = 0.15) {
        pendingOrderOut?.cancel()
        pendingOrderOut = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                // Ease-out: covers most ground in the first third, so the
                // return reads as instant while staying smooth.
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            })
        } else {
            alphaValue = 1
        }
    }

    func fadeOut(animated: Bool, duration: TimeInterval = 0.18) {
        let work = DispatchWorkItem { [weak self] in
            self?.orderOut(nil)
        }
        pendingOrderOut?.cancel()
        pendingOrderOut = work
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                self.animator().alphaValue = 0
            }, completionHandler: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            })
        } else {
            alphaValue = 0
            work.perform()
        }
    }

    /// Raw alpha fade with no ordering side effects: used to dip the overlay
    /// out for Mission Control while keeping its seating and blur converged,
    /// so the return is only a fade-in.
    func fadeAlpha(to value: Double, duration: TimeInterval) {
        guard abs(alphaValue - value) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            animator().alphaValue = value
        })
    }
}
