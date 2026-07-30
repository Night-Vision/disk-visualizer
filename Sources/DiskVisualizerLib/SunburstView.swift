import SwiftUI
import AppKit

struct SunburstView: View {
    let root: FileNode
    @Binding var hoveredNode: FileNode?
    let onDoubleTap: (FileNode) -> Void
    let onSelect: (FileNode) -> Void
    let onOpenInFinder: (FileNode) -> Void
    /// Bumps when the backing tree is mutated outside of observation so the
    /// sunburst can rebuild its cached `segments` without relying on the
    /// now-removed `@Observable` machinery on `FileNode`.
    let treeVersion: UInt
    /// Changes only when the user double-clicks a folder wedge to drill down.
    /// Used to key the sunburst transition so the opening animation does not
    /// run on breadcrumb navigation, scan completion, or trash updates.
    let drillDownID: UUID?

    var body: some View {
        GeometryReader { geometry in
            SunburstCanvas(
                root: root,
                hoveredNode: $hoveredNode,
                onDoubleTap: onDoubleTap,
                onSelect: onSelect,
                onOpenInFinder: onOpenInFinder,
                treeVersion: treeVersion,
                drillDownID: drillDownID,
                geometry: geometry
            )
        }
    }
}

// MARK: - SunburstCanvas

/// The actual interactive sunburst canvas. Kept separate from `SunburstView`
/// so the parent can inject geometry and drive drill-down animation without
/// re-creating the Canvas on every root change.
private struct SunburstCanvas: View {
    let root: FileNode
    @Binding var hoveredNode: FileNode?
    let onDoubleTap: (FileNode) -> Void
    let onSelect: (FileNode) -> Void
    let onOpenInFinder: (FileNode) -> Void
    let treeVersion: UInt
    let drillDownID: UUID?
    let geometry: GeometryProxy

    @State private var segments: [SunburstSegment] = []
    @State private var lastTappedNode: FileNode?

    // Camera state for zoom/pan.
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var scrollMonitor = ScrollMonitor()
    @State private var rightClickMonitor = RightClickMonitor()
    @State private var canvasFrame: CGRect = .zero
    @State private var isHovering = false
    /// 0 → 1 during a double-click drill-down. Used to scale the sunburst
    /// from 90 % to 100 % inside the Canvas, replacing the previous heavy
    /// SwiftUI view transition.
    @State private var drillDownProgress: CGFloat = 1.0

    /// Precomputed ring width derived from canvas size. Recalculated in
    /// `onChange(of: geometry.size)` to avoid per-frame division in `draw()`
    /// and per-tap division in `hitTest()`.
    @State private var cachedRingWidth: CGFloat = 12

    @Environment(\.displayScale) private var screenScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Bounds.
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 8.0

    init(
        root: FileNode,
        hoveredNode: Binding<FileNode?>,
        onDoubleTap: @escaping (FileNode) -> Void,
        onSelect: @escaping (FileNode) -> Void,
        onOpenInFinder: @escaping (FileNode) -> Void,
        treeVersion: UInt,
        drillDownID: UUID?,
        geometry: GeometryProxy
    ) {
        self.root = root
        self._hoveredNode = hoveredNode
        self.onDoubleTap = onDoubleTap
        self.onSelect = onSelect
        self.onOpenInFinder = onOpenInFinder
        self.treeVersion = treeVersion
        self.drillDownID = drillDownID
        self.geometry = geometry
        // Pre-compute segments eagerly so the Canvas's first render has data.
        // When the view is reused this initial value is ignored (state is
        // preserved), but it avoids the one-frame "center hole only" flash on
        // the very first appearance.
        self._segments = State(initialValue: SunburstLayout.segments(root: root))
    }

    var body: some View {
        // Keep wedges crisp while zoomed in, but avoid the 4× memory cliff.
        // 2.5× is enough to look sharp on Retina at normal zoom while preventing
        // a huge backing-store allocation at max zoom.
        let hiDPIScale = min(max(scale, 1.0), 2.5) * screenScale

        return Canvas { context, size in
            draw(root: root, segments: segments, in: &context, size: size)
        }
        .environment(\.displayScale, hiDPIScale)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onAppear {
            rebuildSegments()
            // Capture the initial frame synchronously; `.onChange` only fires on
            // a value change, so any right-click that races the very first frame
            // relayout would otherwise hit-test against a zero-sized canvas.
            canvasFrame = geometry.frame(in: .global)
            installEventMonitors()
            lastTappedNode = nil
        }
        .onDisappear {
            scrollMonitor.stop()
            rightClickMonitor.stop()
        }
        .onChange(of: geometry.frame(in: .global)) { _, newFrame in
            canvasFrame = newFrame
        }
        .onChange(of: geometry.size) { _, newSize in
            let maxRadius = min(newSize.width, newSize.height) / 2 - 20
            cachedRingWidth = max(12, (maxRadius - SunburstLayout.centerHoleRadius) / CGFloat(SunburstLayout.maxDepth))
            rebuildSegments()
        }
        .onChange(of: root) { _, _ in
            // Reset camera on any root change (drill-down, breadcrumb, or
            // trash). The drill-down entrance animation is handled separately
            // by `drillDownProgress`; this just keeps the camera centered.
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
            lastTappedNode = nil
            rebuildSegments()
        }
        .onChange(of: treeVersion) { _, _ in rebuildSegments() }
        .onChange(of: drillDownID) { _, _ in
            // `nil` is the default/reset state (new scan, back-to-root). Only a
            // real drill-down (non-nil UUID) should trigger the entrance pop.
            guard drillDownID != nil else { return }
            // If another drill-down races the current entrance, just snap to
            // the finished state instead of restarting and jumping backward.
            guard drillDownProgress >= 1.0 else {
                drillDownProgress = 1.0
                return
            }
            if reduceMotion {
                drillDownProgress = 1.0
            } else {
                drillDownProgress = 0.0
                withAnimation(.easeOut(duration: 0.25)) {
                    drillDownProgress = 1.0
                }
            }
        }
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    if let node = hitTest(point: value.location, size: geometry.size) {
                        hoveredNode = node
                        lastTappedNode = node
                        onSelect(node)
                    }
                }
        )
        .onTapGesture(count: 2) {
            if let node = lastTappedNode ?? hoveredNode {
                lastTappedNode = nil
                onDoubleTap(node)
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let newScale = lastScale * value
                    scale = clamp(newScale, min: minScale, max: maxScale)
                }
                .onEnded { _ in
                    lastScale = scale
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    lastOffset = offset
                }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                isHovering = true
                let hit = hitTest(point: location, size: geometry.size)
                if let previous = hoveredNode, let new = hit, previous != new {
                    lastTappedNode = nil
                }
                hoveredNode = hit
            case .ended:
                isHovering = false
                hoveredNode = nil
            }
        }
        .overlay(alignment: .topTrailing) {
            if scale != 1.0 || offset != .zero {
                resetZoomButton
                    .padding(8)
            }
        }
    }

    private var resetZoomButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
            }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 12, weight: .semibold))
                .padding(8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .help("Reset zoom")
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }

    private func rebuildSegments() {
        segments = SunburstLayout.segments(root: root)
    }

    // MARK: - Scroll wheel support

    private func installEventMonitors() {
        scrollMonitor.onScroll = { [self] delta in
            let newScale = scale + (delta > 0 ? 0.15 : -0.15)
            withAnimation(.easeOut(duration: 0.15)) {
                scale = clamp(newScale, min: minScale, max: maxScale)
                lastScale = scale
            }
        }
        scrollMonitor.start()

        rightClickMonitor.onRightClick = { [self] screenPoint in
            handleRightClick(screenPoint: screenPoint)
        }
        rightClickMonitor.start()
    }

    private func handleRightClick(screenPoint: NSPoint) {
        // Hit-test in Canvas-local coordinates: subtract the Canvas's screen-origin
        // from the event's screen point.
        let localPoint = CGPoint(
            x: screenPoint.x - canvasFrame.origin.x,
            y: screenPoint.y - canvasFrame.origin.y
        )
        guard let node = hitTest(point: localPoint, size: canvasFrame.size) else { return }
        presentContextMenu(for: node, at: screenPoint)
    }

    private func presentContextMenu(for node: FileNode, at screenPoint: NSPoint) {
        let menu = NSMenu(title: node.name)

        // Each menu item needs an NSObject target; an instance closure captures
        // the FileNode and the callback without subclassing the view.
        let target = ContextActionTarget()
        target.onOpenInFinder = { [onOpenInFinder] in
            onOpenInFinder(node)
        }

        let openItem = NSMenuItem(
            title: "Open in Finder",
            action: #selector(ContextActionTarget.openInFinder(_:)),
            keyEquivalent: ""
        )
        openItem.target = target
        menu.addItem(openItem)

        // in: nil pops the menu at an absolute screen point.
        menu.popUp(positioning: nil, at: screenPoint, in: nil)
    }

    // MARK: - Drawing

    private func draw(root: FileNode, segments: [SunburstSegment], in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ringWidth = cachedRingWidth

        // Apply camera transform: scale around the view center, then pan.
        // Also mix in a subtle drill-down entrance scale so the Canvas pops in
        // without the heavy cost of a SwiftUI view transition.
        let entranceScale = 0.9 + 0.1 * drillDownProgress
        let animatedScale = scale * entranceScale
        context.translateBy(x: center.x + offset.width, y: center.y + offset.height)
        context.scaleBy(x: animatedScale, y: animatedScale)
        context.translateBy(x: -center.x, y: -center.y)

        // Center root circle.
        let centerPath = Path(ellipseIn: CGRect(
            x: center.x - SunburstLayout.centerHoleRadius,
            y: center.y - SunburstLayout.centerHoleRadius,
            width: SunburstLayout.centerHoleRadius * 2,
            height: SunburstLayout.centerHoleRadius * 2
        ))
        context.fill(centerPath, with: .color(.white.opacity(0.12)))
        context.stroke(centerPath, with: .color(.white.opacity(0.3)), lineWidth: 1)

        // Wedges.
        for segment in segments {
            drawSegment(segment, root: root, center: center, ringWidth: ringWidth, in: &context)
        }

        // Root label.
        let rootText = Text(root.formattedSize).font(.caption).bold()
        context.draw(rootText, at: center, anchor: .center)
    }

    private func drawSegment(_ segment: SunburstSegment, root: FileNode, center: CGPoint, ringWidth: CGFloat, in context: inout GraphicsContext) {
        let path = wedgePath(segment: segment, center: center, ringWidth: ringWidth)
        let isHovered = hoveredNode.map { $0 == segment.node } ?? false

        let color = Color.paletteColor(for: segment.node, root: root)
        context.fill(path, with: .color(color))

        // Petal-like stroke gap.
        context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 1.2)

        if isHovered {
            context.fill(path, with: .color(.white.opacity(0.18)))
            context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 1.5)
        }
    }

    private func wedgePath(segment: SunburstSegment, center: CGPoint, ringWidth: CGFloat) -> Path {
        let innerRadius = SunburstLayout.centerHoleRadius + CGFloat(segment.depth - 1) * ringWidth
        let outerRadius = SunburstLayout.centerHoleRadius + CGFloat(segment.depth) * ringWidth - SunburstLayout.ringGap

        let start = segment.startAngle
        let end = segment.endAngle

        // Clamp to avoid tiny negative arcs from rounding.
        guard end - start > 0.0001 else { return Path() }

        let innerStart = CGPoint(
            x: center.x + innerRadius * cos(start),
            y: center.y + innerRadius * sin(start)
        )
        let outerEnd = CGPoint(
            x: center.x + outerRadius * cos(end),
            y: center.y + outerRadius * sin(end)
        )

        var path = Path()
        path.move(to: innerStart)
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: Angle(radians: start),
            endAngle: Angle(radians: end),
            clockwise: false,
            transform: .identity
        )
        path.addLine(to: outerEnd)
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: Angle(radians: end),
            endAngle: Angle(radians: start),
            clockwise: true,
            transform: .identity
        )
        path.closeSubpath()
        return path
    }

    // MARK: - Hit testing

    private func hitTest(point: CGPoint, size: CGSize) -> FileNode? {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // Inverse camera transform: undo pan and scale around the view center.
        let localX = (point.x - center.x - offset.width) / scale + center.x
        let localY = (point.y - center.y - offset.height) / scale + center.y

        let dx = localX - center.x
        let dy = localY - center.y
        let distance = hypot(dx, dy)

        let ringWidth = cachedRingWidth

        // Root hit.
        if distance <= SunburstLayout.centerHoleRadius {
            return root
        }

        var angle = atan2(dy, dx)
        if angle < 0 { angle += .pi * 2 }

        let depth = Int((distance - SunburstLayout.centerHoleRadius) / ringWidth) + 1
        if depth < 1 || depth > SunburstLayout.maxDepth { return nil }

        let segs = segments
        return segs.first { segment in
            segment.depth == depth && angle >= segment.startAngle && angle <= segment.endAngle
        }?.node
    }
}

// MARK: - Scroll wheel monitor

/// Small helper that wraps `NSEvent.addLocalMonitorForEvents` so a SwiftUI struct
/// can receive scroll-wheel events without leaking self into a closure.
private final class ScrollMonitor {
    var onScroll: ((CGFloat) -> Void)?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self, let onScroll = self.onScroll else { return event }
            onScroll(event.scrollingDeltaY)
            return event
        }
    }

    func stop() {
        guard let monitor = monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    deinit {
        stop()
    }
}

// MARK: - Right-click monitor

/// Mirror of `ScrollMonitor` for `.rightMouseDown`. Callback is given a global
/// screen point (top-left origin, points — matches SwiftUI `.global` frames) so
/// callers can hit-test against a Canvas by direct subtraction.
private final class RightClickMonitor {
    var onRightClick: ((NSPoint) -> Void)?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self,
                  let onRightClick = self.onRightClick,
                  let window = event.window else { return event }
            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            onRightClick(NSPoint(x: screenPoint.x, y: screenPoint.y))
            // Don't consume — let SwiftUI's normal handling run too.
            return event
        }
    }

    func stop() {
        guard let monitor = monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    deinit {
        stop()
    }
}

/// Tiny NSObject target that lets a captured closure back an `NSMenuItem.action`
/// so a SwiftUI struct can present a real AppKit context menu without
/// subclassing the view.
private final class ContextActionTarget: NSObject {
    var onOpenInFinder: (() -> Void)?

    @objc func openInFinder(_ sender: Any?) {
        onOpenInFinder?()
    }
}
