import SwiftUI
import UIKit
import Core

/// Observes the owning scroll view without replacing its delegate. A chapter pull
/// must BEGIN at a content edge, exceed 120pt while held, and be released there. Momentum,
/// layout, programmatic scrolling and a drag that began inside content cannot fire.
public struct ReaderScrollMonitor: UIViewRepresentable {
    public var controller: ReaderScrollController?
    public var axis: Axis
    public var reversed: Bool
    public var reportsProgrammaticChanges: Bool
    public var enabled: Bool
    public var onPosition: (Double) -> Void
    public var onPull: (Double) -> Void
    public var onRelease: (Bool) -> Void

    public init(controller: ReaderScrollController? = nil, axis: Axis = .vertical, reversed: Bool = false, reportsProgrammaticChanges: Bool = false, enabled: Bool = true, onPosition: @escaping (Double) -> Void,
                onPull: @escaping (Double) -> Void, onRelease: @escaping (Bool) -> Void) {
        self.axis = axis; self.reversed = reversed
        self.reportsProgrammaticChanges = reportsProgrammaticChanges
        self.controller = controller
        self.enabled = enabled; self.onPosition = onPosition
        self.onPull = onPull; self.onRelease = onRelease
    }
    public func makeUIView(context: Context) -> Probe {
        let view = Probe(); view.isUserInteractionEnabled = false; view.coordinator = context.coordinator; return view
    }
    public func updateUIView(_ uiView: Probe, context: Context) {
        context.coordinator.parent = self
        uiView.attach()
    }
    public func makeCoordinator() -> Coordinator { Coordinator(self) }
    public static func dismantleUIView(_ uiView: Probe, coordinator: Coordinator) { coordinator.detach() }

    public final class Probe: UIView {
        fileprivate weak var coordinator: Coordinator?
        public override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        public override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }
        fileprivate func attach() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var ancestor = self.superview
                while let view = ancestor {
                    if let scroll = view as? UIScrollView { self.coordinator?.attach(scroll); return }
                    ancestor = view.superview
                }
            }
        }
    }
    @MainActor public final class Coordinator: NSObject {
        fileprivate var parent: ReaderScrollMonitor
        private weak var scroll: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var sizeObservation: NSKeyValueObservation?
        private var pull = ChapterPullState()
        fileprivate init(_ parent: ReaderScrollMonitor) { self.parent = parent }
        fileprivate func attach(_ view: UIScrollView) {
            guard scroll !== view else { return }
            detach(); scroll = view; parent.controller?.scrollView = view
            view.panGestureRecognizer.addTarget(self, action: #selector(panChanged))
            sizeObservation = view.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.parent.controller?.applyRestore() }
            }
            observation = view.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.changed() }
            }
        }
        fileprivate func detach() {
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged))
            observation = nil; sizeObservation = nil; scroll = nil
        }
        // Normalize physical offsets into source order so RTL pulls keep their meaning.
        private func position(_ view: UIScrollView) -> (offset: CGFloat, extent: CGFloat) {
            if parent.axis == .horizontal {
                let start = -view.adjustedContentInset.left
                let end = max(start, view.contentSize.width - view.bounds.width + view.adjustedContentInset.right)
                return (parent.reversed ? end - view.contentOffset.x : view.contentOffset.x - start, end - start)
            }
            let start = -view.adjustedContentInset.top
            let end = max(start, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
            return (view.contentOffset.y - start, end - start)
        }
        @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
            guard let scroll else { return }
            switch pan.state {
            case .began:
                let (offset, extent) = position(scroll)
                let velocity = pan.velocity(in: scroll)
                let forwardVelocity = parent.axis == .vertical ? velocity.y : velocity.x * (parent.reversed ? -1 : 1)
                pull.begin(atTop: offset <= 24, atBottom: offset >= extent - 24, verticalVelocity: forwardVelocity)
            case .ended:
                let direction = pull.release(enabled: parent.enabled)
                parent.onPull(0)
                if let direction { parent.onRelease(direction == .next) }
            case .cancelled, .failed:
                pull.cancel(); parent.onPull(0)
            default: break
            }
        }
        private func changed() {
            guard let scroll else { return }
            let (offset, extent) = position(scroll)
            let fraction = extent > 0 ? min(1, max(0, offset / extent)) : 0
            if scroll.isDragging || scroll.isDecelerating || parent.reportsProgrammaticChanges || parent.controller?.isApplyingMovement == true {
                parent.onPosition(fraction)
            }
            guard parent.enabled, scroll.isDragging, let direction = pull.direction else { return }
            let distance = direction == .next ? offset - extent : -offset
            pull.update(distanceBeyondEdge: distance)
            parent.onPull(pull.progress)
        }
    }
}

public struct ReaderPullHint: View {
    public let progress: Double
    public init(progress: Double) { self.progress = progress }
    public var body: some View {
        if abs(progress) > 0.04 {
            HStack(spacing: 8) {
                Image(systemName: abs(progress) >= 1 ? "arrow.turn.down.right" : "arrow.up")
                Text(abs(progress) >= 1 ? "Release for \(progress > 0 ? "next" : "previous") chapter" : "Pull for \(progress > 0 ? "next" : "previous") chapter")
            }
            .font(.caption.weight(.semibold))
            .padding(12).background(.regularMaterial, in: Capsule())
            .allowsHitTesting(false)
            .accessibilityLabel(abs(progress) >= 1 ? "Release to change chapter" : "Pull further to change chapter")
        }
    }
}

@MainActor public final class ReaderScrollController {
    fileprivate weak var scrollView: UIScrollView? { didSet { applyRestore() } }
    fileprivate var isApplyingMovement = false
    private var pendingOffset: Double?
    public var offset: Double? { scrollView.map { Double($0.contentOffset.y) } }
    public func restore(offset: Double) { pendingOffset = offset; applyRestore() }
    fileprivate func applyRestore() {
        guard let view = scrollView, let offset = pendingOffset, view.contentSize.height > 0 else { return }
        let top = -view.adjustedContentInset.top
        let bottom = max(top, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        guard offset <= bottom else { return }
        pendingOffset = nil
        isApplyingMovement = true
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: max(top, offset)), animated: false)
        isApplyingMovement = false
    }
    public init() {}
    public func move(forward: Bool) {
        guard let view = scrollView else { return }
        let top = -view.adjustedContentInset.top
        let bottom = max(top, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        let y = min(bottom, max(top, view.contentOffset.y + view.bounds.height * (forward ? 0.8 : -0.8)))
        isApplyingMovement = true
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: y), animated: false)
        isApplyingMovement = false
    }
}
