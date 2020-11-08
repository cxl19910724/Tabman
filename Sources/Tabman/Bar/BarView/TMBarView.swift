//
//  TMBarView.swift
//  Tabman
//
//  Created by Merrick Sapsford on 01/08/2018.
//  Copyright © 2020 UI At Six. All rights reserved.
//

import UIKit
import Pageboy

// swiftlint:disable file_length

private struct TMBarViewDefaults {
    static let animationDuration: TimeInterval = 0.25
}

/// `TMBarView` is the default Tabman implementation of `TMBar`. A `UIView` that contains a `TMBarLayout` which displays
/// a collection of `TMBarButton`, and also a `TMBarIndicator`. The types of these three components are defined by constraints
/// in the `TMBarView` type definition.
open class TMBarView<Layout: TMBarLayout, Button: TMBarButton, Indicator: TMBarIndicator>: UIView, TMTransitionStyleable, TMBarLayoutParent {
    
    // MARK: Types
    
    public typealias BarButtonCustomization = (Button) -> Void
    
    public enum ScrollMode: Int {
        case interactive
        case swipe
        case none
    }
    
    // MARK: Properties
    
    internal let rootContentStack = UIStackView()
    
    internal let scrollViewContainer = EdgeFadedView()
    internal let scrollView = GestureScrollView()
    internal private(set) var layoutStackView: TMBarLayoutStackView!
    
    private let scrollHandler: TMBarViewScrollHandler
    
    private var rootContainerTop: NSLayoutConstraint!
    private var rootContainerBottom: NSLayoutConstraint!
    
    private var indicatorLayoutHandler: TMBarIndicatorLayoutHandler?
    private var indicatedPosition: CGFloat?
    private lazy var contentInsetGuides = TMBarViewContentInsetGuides(for: self)
    
    private var accessoryViews = [TMBarAccessoryView.Location: UIView]()
    
    // MARK: Components
    
    /// `TMBarLayout` that dictates display and behavior of bar buttons and other bar view components.
    public private(set) lazy var layout = Layout()
    /// Collection of `TMBarButton` objects that directly map to the `TMBarItem`s provided by the `dataSource`.
    public let buttons = TMBarButtonCollection<Button>()
    /// `TMBarIndicator` that is used to indicate the current bar index state.
    public let indicator = Indicator()
    /// Background view that appears behind all content in the bar view.
    ///
    /// Note: Default style is `.blur(style: .extraLight)`.
    public let backgroundView = TMBarBackgroundView(style: .blur(style: .extraLight))
    
    /// Items that are displayed in the bar.
    open private(set) var items: [TMBarItemable]?
    
    /// Object that acts as a data source to the BarView.
    open weak var dataSource: TMBarDataSource?
    /// Object that acts as a delegate to the BarView.
    ///
    /// By default this is set to the `TabmanViewController` the bar is added to.
    open weak var delegate: TMBarDelegate?
    
    // MARK: Accessory Views
    
    /// View to display on the leading edge of the bar.
    ///
    /// This view is within the scroll view and is subject to scroll off-screen
    /// with bar contents.
    open var leadingAccessoryView: TMBarAccessoryView? {
        didSet {
            updateAccessoryView(to: leadingAccessoryView, at: .leading)
        }
    }
    /// View to display on the leading edge of the bar.
    ///
    /// This view is not part of the scrollable bar contents and will be visible at all times.
    open var leadingPinnedAccessoryView: TMBarAccessoryView? {
        didSet {
            updateAccessoryView(to: leadingPinnedAccessoryView, at: .leadingPinned)
        }
    }
    /// View to display on the trailing edge of the bar.
    ///
    /// This view is within the scroll view and is subject to scroll off-screen
    /// with bar contents.
    open var trailingAccessoryView: TMBarAccessoryView? {
        didSet {
            updateAccessoryView(to: trailingAccessoryView, at: .trailing)
        }
    }
    /// View to display on the trailing edge of the bar.
    ///
    /// This view is not part of the scrollable bar contents and will be visible at all times.
    open var trailingPinnedAccessoryView: TMBarAccessoryView? {
        didSet {
            updateAccessoryView(to: trailingPinnedAccessoryView, at: .trailingPinned)
        }
    }
    
    // MARK: Customization
    
    /// Transition style for updating bar view components such as scroll view.
    internal var transitionStyle: TMTransitionStyle = .progressive
    /// The type of scrolling interaction to allow.
    ///
    /// Options:
    /// - `.interactive`: The bar contents can be scrolled interactively.
    /// - `.swipe`: The bar contents can be scrolled through with swipe gestures.
    /// - `.none`: The bar contents can't be scrolled at all.
    open var scrollMode: ScrollMode {
        get {
            return ScrollMode(rawValue: scrollView.scrollMode.rawValue)!
        }
        set {
            scrollView.scrollMode = GestureScrollView.ScrollMode(rawValue: newValue.rawValue)!
        }
    }
    /// Whether to fade the leading and trailing edges of the bar content to an alpha of 0.
    open var fadesContentEdges: Bool {
        get {
            return scrollViewContainer.showFade
        }
        set {
            scrollViewContainer.showFade = newValue
        }
    }
    /// Spacing between components in the bar, such as between the layout and accessory views.
    ///
    /// Defaults to `8.0`.
    open var spacing: CGFloat {
        get {
            layout.view.spacing
        }
        set {
            layout.view.spacing = newValue
        }
    }
    
    open var isInfinite: Bool = false
    
    // MARK: TMBarLayoutParent
    
    var contentInset: UIEdgeInsets = .zero {
        didSet {
            updateScrollViewContentInset()
        }
    }
    
    var alignment: TMBarLayout.Alignment = .leading {
        didSet {
            updateScrollViewContentInset()
        }
    }
    
    func layout(needsReload layout: TMBarLayout) {
        guard let items = self.items else {
            return
        }
        reloadData(at: 0 ... items.count, context: .full)
    }
    
    // MARK: Init
    
    public required init() {
        self.scrollHandler = TMBarViewScrollHandler(for: scrollView)
        super.init(frame: .zero)
        
        buttons.interactionHandler = self
        scrollHandler.delegate = self
        scrollView.gestureDelegate = self
        accessibilityTraits = [.tabBar]
        layout(in: self)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(itemNeedsUpdate(_:)),
                                               name: TMBarItemableNeedsUpdateNotification,
                                               object: nil)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("BarView does not support Interface Builder")
    }
    
    // MARK: Layout
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        updateIndicatorPositionForLayoutUpdates()
    }
    
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        
        updateIndicatorPositionForLayoutUpdates()
    }
    
    private func layout(in view: UIView) {
        layoutRootViews(in: view)
        
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollViewContainer.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: scrollViewContainer.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: scrollViewContainer.topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: scrollViewContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: scrollViewContainer.bottomAnchor)
            ])
        rootContentStack.addArrangedSubview(scrollViewContainer)
        
        self.layoutStackView = TMBarLayoutStackView(with: layout.view)
        scrollView.addSubview(layoutStackView)
        layoutStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            layoutStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            layoutStackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            layoutStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            layoutStackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            layoutStackView.heightAnchor.constraint(equalTo: rootContentStack.heightAnchor)
            ])
        
        layout.layout(parent: self, insetGuides: contentInsetGuides)
        self.indicatorLayoutHandler = container(for: indicator).layoutHandler
    }
    
    private func layoutRootViews(in view: UIView) {
        var constraints = [NSLayoutConstraint]()
        
        view.addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        constraints.append(contentsOf: [
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        
        rootContentStack.axis = .horizontal
        view.addSubview(rootContentStack)
        rootContentStack.translatesAutoresizingMaskIntoConstraints = false
        self.rootContainerTop = rootContentStack.topAnchor.constraint(equalTo: view.topAnchor)
        self.rootContainerBottom = view.bottomAnchor.constraint(equalTo: rootContentStack.bottomAnchor)
        NSLayoutConstraint.activate([
            rootContentStack.leadingAnchor.constraint(equalTo: view.safeAreaLeadingAnchor),
            rootContainerTop,
            rootContentStack.trailingAnchor.constraint(equalTo: view.safeAreaTrailingAnchor),
            rootContainerBottom
        ])
    }

    private func updateScrollViewContentInset() {
        let leftAlignmentInset: CGFloat
        let rightAlignmentInset: CGFloat
        
        switch alignment {
        case .leading:
            leftAlignmentInset = 0.0
            rightAlignmentInset = 0.0
        case .center:
            // Left Side Inset
            let leftButtonWidth = (buttons.all.first?.bounds.size.width ?? 0.0) / 2.0
            var width = bounds.size.width / 2
            width -= contentInset.left - safeAreaInsets.left
            leftAlignmentInset = width - leftButtonWidth
            
            // Right Side Inset
            let rightButtonWidth = (buttons.all.last?.bounds.size.width ?? 0.0) / 2.0
            width = bounds.size.width / 2
            width -= contentInset.right - safeAreaInsets.right
            rightAlignmentInset = width - rightButtonWidth
        case .trailing:
            let buttonWidth = (buttons.all.first?.bounds.size.width ?? 0.0)
            let width = bounds.size.width - safeAreaInsets.left
            leftAlignmentInset = width - buttonWidth
            rightAlignmentInset = 0.0
        case .centerDistributed:
            let width = (bounds.size.width / 2) - safeAreaInsets.left
            leftAlignmentInset = max(0.0, width - layoutStackView.frame.width / 2)
            rightAlignmentInset = 0.0
        }
        
        let sanitizedContentInset = UIEdgeInsets(top: 0.0,
                                                 left: leftAlignmentInset + contentInset.left,
                                                 bottom: 0.0,
                                                 right: rightAlignmentInset + contentInset.right)
        scrollView.contentInset = sanitizedContentInset
        scrollView.contentOffset.x -= sanitizedContentInset.left
        
        rootContainerTop.constant = contentInset.top
        rootContainerBottom.constant = contentInset.bottom
    }
    
    // MARK: Notifications
    
    @objc private func itemNeedsUpdate(_ notification: Notification) {
        guard let item = notification.object as? TMBarItemable else {
            return
        }
        guard let button = buttons.all.filter({ $0.item === item }).first else {
            return
        }
        
        UIView.animate(withDuration: 0.2, delay: 0.0, options: .curveEaseIn, animations: {
            button.populate(for: item)
            self.updateIndicatorPosition()
        }, completion: nil)
    }

    // MARK: UIAccessibilityContainer

    override open func accessibilityElementCount() -> Int {
        return buttons.all.count
    }

    override open func accessibilityElement(at index: Int) -> Any? {
        return buttons.all[index]
    }

    open override func index(ofAccessibilityElement element: Any) -> Int {
        guard let item = element as? Button else {
            return 0
        }
        return buttons.all.firstIndex(of: item) ?? 0
    }
}

// MARK: - Bar
extension TMBarView: TMBar {
    
    public func reloadData(at indexes: ClosedRange<Int>,
                           context: TMBarReloadContext) {
        guard let dataSource = self.dataSource else {
            return
        }
        
        var items = self.items ?? [TMBarItemable]()
        
        switch context {
        case .full, .insertion:
            
            if context == .full && buttons.all.count > 0 { // remove existing buttons
                layout.remove(buttons: buttons.all)
                buttons.all.removeAll()
            }
            
            var newButtons = [Button]()
            for index in indexes.lowerBound ... indexes.upperBound {
                let item = dataSource.barItem(for: self, at: index)
                items.insert(item, at: index)
                
                let button = Button(for: item, intrinsicSuperview: self)
                button.populate(for: item)
                button.update(for: .unselected)
                newButtons.append(button)
            }
            
            buttons.all.insert(contentsOf: newButtons, at: indexes.lowerBound)
            layout.insert(buttons: newButtons, at: indexes.lowerBound)
            
        case .deletion:
            var buttonsToRemove = [Button]()
            for index in indexes.lowerBound ... indexes.upperBound {
                let button = buttons.all[index]
                buttonsToRemove.append(button)
                items.remove(at: index)
            }
            buttons.all.removeAll(where: { buttonsToRemove.contains($0) })
            layout.remove(buttons: buttonsToRemove)
        }
        
        self.items = items
        updateIndicatorPositionForLayoutUpdates()
    }
    
    private func updateIndicatorPositionForLayoutUpdates() {
        UIView.performWithoutAnimation {
            layoutIfNeeded()
            updateScrollViewContentInset()
            updateIndicatorPosition()
        }
    }
    
    public func update(for position: CGFloat,
                       capacity: Int,
                       direction: TMBarUpdateDirection,
                       animation: TMAnimation) {
        self.indicatedPosition = position
        layoutIfNeeded()
        
        let handler = TMBarViewUpdateHandler(for: self,
                                             at: position,
                                             capacity: capacity,
                                             direction: direction,
                                             expectedAnimation: animation)
        
        // Update indicator
        handler.update(component: indicator) { (context) in
            self.indicatorLayoutHandler?.update(for: context.focusRect.rect(isProgressive: self.indicator.isProgressive,
                                                                            overscrollBehavior: self.indicator.overscrollBehavior)) // Update indicator layout
            self.indicator.superview?.layoutIfNeeded()
        }
        
        // Update buttons
        handler.update(component: buttons) { (context) in
            self.buttons.stateController.update(for: context.position,
                                                direction: context.direction)
        }
        
        // Update bar view
        handler.update(component: self) { (context) in
            
            let pinnedAccessoryWidth = (self.accessoryView(at: .leadingPinned)?.bounds.size.width ?? 0.0) + (self.accessoryView(at: .trailingPinned)?.bounds.size.width ?? 0.0)
            let maxOffsetX = (self.scrollView.contentSize.width - (self.bounds.size.width - pinnedAccessoryWidth)) + self.scrollView.contentInset.right + self.safeAreaInsets.right // maximum possible x offset
            let minOffsetX = -self.scrollView.contentInset.left
            
            // Aim to use a focus origin that centers the button in the bar.
            // If the minimum viable x offset is greater than the center of the bar however, use that.
            let focusRectCenterX = context.focusRect.origin.x + (context.focusRect.size.width / 2)
            let barCenterX = (self.bounds.size.width / 2) - focusRectCenterX
            let centeredFocusOrigin = CGPoint(x: -barCenterX, y: 0.0)
            
            // Create offset and sanitize for bounds.
            var contentOffset = centeredFocusOrigin
            contentOffset.x = max(minOffsetX, min(contentOffset.x, maxOffsetX))
            
            // Calculate how far the scroll view leading content inset is actually off 'center' as a delta.
            // As the target for this update is to center the focusRect in the bar, we have to append
            // this delta to the offset otherwise the inset could be ignored.
            let actualCenterX = ((self.bounds.size.width - (self.buttons.all.first?.bounds.size.width ?? 0.0 )) / 2)
            let offCenterDelta = self.scrollView.contentInset.left - actualCenterX
            if offCenterDelta > 0.0 {
                contentOffset.x -= offCenterDelta
            }
            
            self.scrollView.contentOffset = contentOffset
        }
    }

    // MARK: Updating
    
    func updateEdgeFades(for scrollView: UIScrollView) {
        guard scrollView.contentSize.width > scrollView.bounds.size.width else {
            scrollViewContainer.leadingFade = 0.0
            scrollViewContainer.trailingFade = 0.0
            return
        }
        
        let contentSizeRatio = ((scrollView.contentSize.width - scrollView.bounds.size.width) / 2)
        
        let leadingOffsetRatio = max(0.0, min(1.0, (scrollView.contentOffset.x / contentSizeRatio)))
        let trailingOffsetRatio = max(0.0, min(1.0, ((scrollView.contentSize.width - scrollView.bounds.size.width) - scrollView.contentOffset.x) / contentSizeRatio))
        
        scrollViewContainer.leadingFade = leadingOffsetRatio
        scrollViewContainer.trailingFade = trailingOffsetRatio
    }
}

// MARK: - Indicator
extension TMBarView {
    
    /// Create a container for an indicator to be displayed in. Will also add the container to the view hierarchy.
    ///
    /// - Parameter indicator: Indicator to create container for.
    /// - Returns: Indicator container.
    private func container(for indicator: Indicator) -> TMBarIndicatorContainer<Indicator> {
        let container = TMBarIndicatorContainer(for: indicator)
        switch indicator.displayMode {
        case .top:
            layoutStackView.addTopSubview(container)
            
        case .bottom:
            layoutStackView.addBottomSubview(container)
            
        case .fill:
            scrollView.insertSubview(container, at: 0)
            container.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                container.topAnchor.constraint(equalTo: scrollView.topAnchor),
                container.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                container.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
                ])
        }
        return container
    }
    
    private func updateIndicatorPosition() {
        guard let indicatedPosition = self.indicatedPosition else {
            return
        }
        update(for: indicatedPosition,
               capacity: buttons.all.count,
               direction: .none,
               animation: TMAnimation(isEnabled: true,
                                               duration: TMBarViewDefaults.animationDuration))
    }
}

// MARK: - Interaction
extension TMBarView: TMBarButtonInteractionHandler, GestureScrollViewGestureDelegate {
    
    func barButtonInteraction(controller: TMBarButtonInteractionController,
                              didHandlePressOf button: TMBarButton,
                              at index: Int) {
        delegate?.bar(self, didRequestScrollTo: index)
    }
    
    func scrollView(_ scrollView: GestureScrollView,
                    didReceiveSwipeTo direction: UISwipeGestureRecognizer.Direction) {
        let index = Int(indicatedPosition ?? 0)
        switch direction {
        case .right, .down:
            delegate?.bar(self, didRequestScrollTo: max(0, index - 1))
        case .left, .up:
            delegate?.bar(self, didRequestScrollTo: min(buttons.all.count - 1, index + 1))
        default:
            fatalError()
        }
    }
}

// MARK: - Accessory View Management
private extension TMBarView {

    func updateAccessoryView(to view: UIView?,
                             at location: TMBarAccessoryView.Location) {
        removeAccessoryView(at: location)
        addAccessoryView(view, at: location)
    }
    
    private func accessoryView(at location: TMBarAccessoryView.Location) -> UIView? {
        return accessoryViews[location]
    }
    
    private func removeAccessoryView(at location: TMBarAccessoryView.Location) {
        let view = accessoryView(at: location)
        view?.removeFromSuperview()
        accessoryViews[location] = nil
    }
    
    private func addAccessoryView(_ view: UIView?, at location: TMBarAccessoryView.Location) {
        guard let view = view else {
            return
        }
        
        accessoryViews[location] = view
        switch location {
        case .leading:
            layout.leadingAccessoryView = view
        case .leadingPinned:
            rootContentStack.insertArrangedSubview(view, at: 0)
        case .trailing:
            layout.trailingAccessoryView = view
        case .trailingPinned:
            rootContentStack.insertArrangedSubview(view, at: rootContentStack.arrangedSubviews.count)
        }
        
        updateIndicatorPosition()
    }
}

extension TMBarView: TMBarViewScrollHandlerDelegate {
    
    func barViewScrollHandler(_ handler: TMBarViewScrollHandler,
                              didReceiveUpdated contentOffset: CGPoint,
                              from scrollView: UIScrollView) {
        
        updateEdgeFades(for: scrollView)
    }
}
