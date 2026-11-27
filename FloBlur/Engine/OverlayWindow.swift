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
/// - disjoint sharp regions in window-local Cocoa coordinates
/// - SkyLight blur radius eased out-cubic over 0.28s via `CADisplayLink`
/// - show/hide fade the window alpha; hide parks an `orderOut` on delay
final class OverlayWindow: NSWindow {
    private(set) var dimView = NSView()
    private var fallbackBlurView: NSVisualEffectView!

    private var appliedHoles: [CGRect] = []
    private var maskSize = CGSize.zero
    private var maskScale: CGFloat = 0
    private var materialAlpha: CGFloat = 0
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

    // MARK: - Sharp regions

    func setHoles(_ globalRects: [CGRect], in frame: CGRect) {
        guard let layer = dimView.layer else { return }
        let holes = globalRects.compactMap { rect -> CGRect? in
            let clipped = rect.intersection(frame)
            guard !clipped.isEmpty else { return nil }
            return clipped.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
        let size = frame.size
        let scale = backingScaleFactor
        guard holes != appliedHoles || size != maskSize || scale != maskScale else { return }
        appliedHoles = holes
        maskSize = size
        maskScale = scale

        guard !holes.isEmpty else {
            layer.mask = nil
            fallbackBlurView.maskImage = nil
            return
        }
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: size))
        path.addRects(holes)
        let mask = CAShapeLayer()
        mask.frame = CGRect(origin: .zero, size: size)
        mask.contentsScale = scale
        mask.path = path
        mask.fillRule = .evenOdd
        layer.mask = mask

        // Behind-window materials are composited separately from the dim layer.
        fallbackBlurView.maskImage = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
            return true
        }
    }

    // MARK: - Blur (ease-out-cubic ramp over 0.28s)

    func setBlur(radius: Int, animated: Bool) {
        // A WindowServer blur affects the whole window. With holes, use the
        // explicitly masked material so no native blur remains inside a hole.
        let masked = !appliedHoles.isEmpty
        let alpha = masked ? CGFloat(radius) / 80 : (radius > 0 ? 1 : 0)
        if materialAlpha != alpha {
            materialAlpha = alpha
            if animated {
                NSAnimationContext.runAnimationGroup { _ in
                    fallbackBlurView.animator().alphaValue = alpha
                }
            } else {
                fallbackBlurView.alphaValue = alpha
            }
        }
        if masked || !animated {
            let immediateRadius = masked ? 0 : radius
            blurRamp?.invalidate()
            blurRamp = nil
            blurRampTo = immediateRadius
            if presentedBlurRadius != immediateRadius {
                SkyLight.setBackgroundBlurRadius(windowNumber: windowNumber, radius: immediateRadius)
                presentedBlurRadius = immediateRadius
            }
        } else if blurRampTo != radius {
            startBlurRamp(to: radius)
        }
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
            return
        }
        guard let link = CADisplayLink.make(target: self, selector: #selector(stepBlurRamp)) else {
            SkyLight.setBackgroundBlurRadius(windowNumber: windowNumber, radius: radius)
            presentedBlurRadius = radius
            return
        }
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
