import AppKit
import DiskInventoryCore
import QuartzCore
import SwiftUI

/// Everything that changes the treemap's picture. A change triggers a new layout and render.
struct TreemapInputs: Equatable {
    var treeVersion: Int
    var colorsVersion: Int
    var displayRoot: ObjectIdentifier?
    var sizeMode: SizeMode
    var showPackageContents: Bool
    var showFreeSpace: Bool
    var showOtherSpace: Bool
}

struct TreemapView: NSViewRepresentable {
    let document: DocumentModel
    let inputs: TreemapInputs
    let selection: FileNode?
    let transition: DocumentModel.ZoomTransition?

    func makeNSView(context: Context) -> TreemapNSView {
        TreemapNSView(document: document)
    }

    func updateNSView(_ view: TreemapNSView, context: Context) {
        view.update(inputs: inputs, selection: selection, transition: transition)
    }
}

final class TreemapNSView: NSView {
    private let document: DocumentModel
    private var inputs: TreemapInputs?
    private var selection: FileNode?
    private var lastTransition: DocumentModel.ZoomTransition?

    private var layoutResult = TreemapLayoutResult.empty
    private var image: CGImage?
    private var renderedSize: CGSize = .zero
    private var renderTask: Task<Void, Never>?
    private let zoomLayer = CALayer()

    init(document: DocumentModel) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        zoomLayer.contentsGravity = .resize
        zoomLayer.isHidden = true
        zoomLayer.actions = ["contents": NSNull(), "hidden": NSNull()]
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if zoomLayer.superlayer == nil { layer?.addSublayer(zoomLayer) }
    }

    func update(inputs: TreemapInputs, selection: FileNode?, transition: DocumentModel.ZoomTransition?) {
        if selection !== self.selection {
            self.selection = selection
            needsDisplay = true
        }
        guard inputs != self.inputs else { return }
        self.inputs = inputs
        let isNewZoom = transition != nil && transition != lastTransition
        lastTransition = transition
        render(transition: isNewZoom && Pref.bool(Pref.animatedZooming) ? transition : nil)
    }

    // MARK: Layout and rendering

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // During a live resize the last image is stretched; it is re-rendered once resizing ends.
        if !inLiveResize { render(transition: nil) }
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        render(transition: nil)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        render(transition: nil)
    }

    private func render(transition: DocumentModel.ZoomTransition?) {
        renderTask?.cancel()
        let size = bounds.size
        guard size.width >= 1, size.height >= 1, inputs != nil else { return }
        let items = document.treemapItems
        let options = {
            var options = TreemapOptions(sizeMode: document.sizeMode, showPackageContents: document.showPackageContents)
            options.minArea = 0.5
            return options
        }()
        let colors = document.colors
        let scale = window?.backingScaleFactor ?? 2
        let previous = (layout: layoutResult, image: image)

        renderTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> (TreemapLayoutResult, CGImage?)? in
                let layout = TreemapLayout.layout(items, in: CGRect(origin: .zero, size: size), options: options)
                guard !Task.isCancelled else { return nil }
                let image = CushionRenderer.render(layout.tiles, size: size, scale: scale) { colors.color(for: $0) }
                return (layout, image)
            }.value
            guard let self, let (layout, image) = result, !Task.isCancelled else { return }
            self.layoutResult = layout
            self.image = image
            self.renderedSize = size
            self.needsDisplay = true
            if let transition { self.animate(transition, previous: previous) }
        }
    }

    /// Zoom in: the new picture grows out of the folder's old rectangle.
    /// Zoom out: the old picture shrinks into the folder's new rectangle.
    private func animate(_ transition: DocumentModel.ZoomTransition,
                         previous: (layout: TreemapLayoutResult, image: CGImage?)) {
        let full = bounds
        let (contents, from, to): (CGImage?, CGRect?, CGRect)
        if transition.zoomingIn {
            (contents, from, to) = (image, previous.layout.rects[transition.to], full)
        } else {
            (contents, from, to) = (previous.image, full, layoutResult.rects[transition.from] ?? full)
        }
        guard let contents, let from else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        zoomLayer.contents = contents
        zoomLayer.frame = from
        zoomLayer.isHidden = false
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.setCompletionBlock { [weak self] in self?.zoomLayer.isHidden = true }
        zoomLayer.frame = to
        CATransaction.commit()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        if let image {
            NSImage(cgImage: image, size: renderedSize)
                .draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        }
        if let rect = selectionRect() {
            let scale = CGSize(width: bounds.width / max(renderedSize.width, 1),
                               height: bounds.height / max(renderedSize.height, 1))
            let scaled = CGRect(x: rect.minX * scale.width, y: rect.minY * scale.height,
                                width: rect.width * scale.width, height: rect.height * scale.height)
            NSColor.yellow.setStroke()
            let path = NSBezierPath(rect: scaled.insetBy(dx: 1, dy: 1))
            path.lineWidth = 2
            path.stroke()
        }
    }

    /// Rect of the selection, or of its nearest drawn ancestor (e.g. a hidden package or a tiny file).
    private func selectionRect() -> CGRect? {
        var node = selection
        while let current = node {
            if let rect = layoutResult.rects[current.id] { return rect }
            node = current.parent
        }
        return nil
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    private func node(at event: NSEvent) -> FileNode? {
        let point = convert(event.locationInWindow, from: nil)
        let scaled = CGPoint(x: point.x * renderedSize.width / max(bounds.width, 1),
                             y: point.y * renderedSize.height / max(bounds.height, 1))
        return layoutResult.tile(at: scaled)?.node
    }

    override func mouseMoved(with event: NSEvent) {
        let node = node(at: event)
        if document.hovered !== node { document.hovered = node }
    }

    override func mouseExited(with event: NSEvent) {
        document.hovered = nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let node = node(at: event), node.special == nil else { return }
        document.selection = node
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let node = node(at: event), node.special == nil else { return nil }
        document.selection = node
        return MenuBuilder.nsMenu(document.actions(for: node))
    }
}
