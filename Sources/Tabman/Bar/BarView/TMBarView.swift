//
//  TMBarView.swift
//  Tabman
//
//  Created by Merrick Sapsford on 01/08/2018.
//  Copyright © 2018 UI At Six. All rights reserved.
//

import UIKit
import Pageboy

private struct TMBarViewDefaults {
    static let animationDuration: TimeInterval = 0.25
}

/// `TMBarView` is the default Tabman implementation of `TMBar`. A `UIView` that contains a `TMBarLayout` which displays
/// a collection of `TMBarButton`, and also a `TMBarIndicator`. The types of these three components are defined by constraints
/// in the `TMBarView` type definition.
open class TMBarView<LayoutType: TMBarLayout, ButtonType: TMBarButton, IndicatorType: TMBarIndicator>: UIView {
    
    // MARK: Types
    
    public typealias BarButtonCustomization = (ButtonType) -> Void
    
    public enum AnimationStyle {
        case progressive
        case snap
    }
    
    // MARK: Properties
    
    private let rootContentStack = UIStackView()
    
    private let scrollViewContainer = EdgeFadedView()
    private let scrollView = UIScrollView()
    private var grid: TMBarViewGrid!

    private var rootContainerTop: NSLayoutConstraint!
    private var rootContainerBottom: NSLayoutConstraint!
    
    private var indicatorLayoutHandler: TMBarIndicatorLayoutHandler?
    private var indicatedPosition: CGFloat?
    private lazy var contentInsetGuides = TMBarViewContentInsetGuides(for: self)
    
    private var accessoryViews = [String: UIView]()
    
    // MARK: Components
    
    /// `TMBarLayout` that dictates display and behavior of bar buttons and other bar view components.
    public private(set) lazy var layout = LayoutType()
    /// Collection of `TMBarButton` objects that directly map to the `TMBarItem`s provided by the `dataSource`.
    public let buttons = TMBarButtonCollection<ButtonType>()
    /// `TMBarIndicator` that is used to indicate the current bar index state.
    public let indicator = IndicatorType()
    /// Background view that appears behind all content in the bar view.
    ///
    /// Note: Default style is `TMBarBackgroundView.Style.clear`.
    public var backgroundView = TMBarBackgroundView(style: .clear)
    
    /// Object that acts as a data source to the BarView.
    public weak var dataSource: TMBarDataSource?
    /// Object that acts as a delegate to the BarView.
    ///
    /// By default this is set to the `TabmanViewController` the bar is added to.
    public weak var delegate: TMBarDelegate?
    
    // MARK: Customization
    
    /// Style to use when animating bar position updates.
    ///
    /// Options:
    /// - `.progressive`: The bar will seemlessly transition between each button in progressive steps.
    /// - `.snap`: The bar will transition between each button by rounding and snapping to each positional bound.
    ///
    /// Defaults to `.progressive`.
    public var animationStyle: AnimationStyle = .progressive
    /// Whether the bar contents should be allowed to be scrolled by the user.
    public var isScrollEnabled: Bool {
        set {
            scrollView.isScrollEnabled = newValue
        } get {
            return scrollView.isScrollEnabled
        }
    }
    /// Whether to fade the leading and trailing edges of the bar content to an alpha of 0.
    public var fadesContentEdges: Bool {
        set {
            scrollViewContainer.showFade = newValue
        } get {
            return scrollViewContainer.showFade
        }
    }
    
    // MARK: Init
    
    public required init() {
        super.init(frame: .zero)
        buttons.interactionHandler = self
        layout(in: self)
    }
    
    public required init?(coder aDecoder: NSCoder) {
        fatalError("BarView does not support Interface Builder")
    }
    
    // MARK: Lifecycle
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        UIView.performWithoutAnimation {
            reloadIndicatorPosition()
        }
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
        
        // Set up grid - stack views that content views are added to.
        self.grid = TMBarViewGrid(with: layout.view)
        scrollView.addSubview(grid)
        grid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            grid.topAnchor.constraint(equalTo: scrollView.topAnchor),
            grid.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            grid.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            grid.heightAnchor.constraint(equalTo: rootContentStack.heightAnchor)
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
        constraints.append(contentsOf: [
            rootContentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootContentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        self.rootContainerTop = rootContentStack.topAnchor.constraint(equalTo: view.topAnchor)
        self.rootContainerBottom = view.bottomAnchor.constraint(equalTo: rootContentStack.bottomAnchor)
        constraints.append(contentsOf: [rootContainerTop, rootContainerBottom])
        
        NSLayoutConstraint.activate(constraints)
    }
}

// MARK: - Bar
extension TMBarView: TMBar {
    
    public func reloadData(at indexes: ClosedRange<Int>,
                           context: TMBarReloadContext) {
        guard let dataSource = self.dataSource else {
            return
        }
        
        switch context {
        case .full, .insertion:
            
            var newButtons = [ButtonType]()
            for index in indexes.lowerBound ... indexes.upperBound {
                var item = dataSource.barItem(for: self, at: index)
                item.assignedIndex = index
                
                let button = ButtonType()
                button.populate(for: item)
                button.update(for: .unselected)
                newButtons.append(button)
            }
            
            buttons.all.insert(contentsOf: newButtons, at: indexes.lowerBound)
            layout.insert(buttons: newButtons, at: indexes.lowerBound)
            
        case .deletion:
            var buttonsToRemove = [ButtonType]()
            for index in indexes.lowerBound ... indexes.upperBound {
                let button = buttons.all[index]
                buttonsToRemove.append(button)
            }
            layout.remove(buttons: buttonsToRemove)
        }
        
        reloadIndicatorPosition()
    }
    
    public func update(for pagePosition: CGFloat,
                       capacity: Int,
                       direction: TMBarUpdateDirection,
                       animation: TMBarAnimationConfig) {
        
        let (pagePosition, animated) = updateValues(for: animationStyle,
                                                    at: pagePosition,
                                                    shouldAnimate: animation.isEnabled)
        self.indicatedPosition = pagePosition
        layoutIfNeeded()
        
        // Get focus area for updating indicator layout
        let focusArea = grid.convert(layout.focusArea(for: pagePosition, capacity: capacity), from: layout.view) // raw focus area in grid coordinate space
        let focusRect = TMBarViewFocusRect(rect: focusArea, at: pagePosition, capacity: capacity)
        indicatorLayoutHandler?.update(for: focusRect.rect(isProgressive: indicator.isProgressive,
                                                           overscrollBehavior: indicator.overscrollBehavior)) // Update indicator layout
        
        // New content offset for scroll view for focus frame
        // Designed to center the frame in the view if possible.
        let centeredFocusFrame = (bounds.size.width / 2) - (focusRect.size.width / 2) // focus frame centered in view
        let pinnedAccessoryWidth = (accessoryView(at: .leading(pinned: true))?.bounds.size.width ?? 0.0) + (accessoryView(at: .trailing(pinned: true))?.bounds.size.width ?? 0.0)
        let maxOffsetX = (scrollView.contentSize.width - (bounds.size.width - pinnedAccessoryWidth)) + contentInset.right // maximum possible x offset
        let minOffsetX = -contentInset.left
        var contentOffset = CGPoint(x: (-centeredFocusFrame) + focusRect.origin.x, y: 0.0)
        
        contentOffset.x = max(minOffsetX, min(contentOffset.x, maxOffsetX)) // Constrain the offset to bounds
        
        let update = {
            self.layoutIfNeeded()
            
            self.buttons.stateController.update(for: pagePosition, direction: direction)
            self.scrollView.contentOffset = contentOffset
        }
        
        if animated {
            UIView.animate(withDuration: animation.duration, animations: {
                update()
            })
        } else {
            update()
        }
    }

    private func updateValues(for style: AnimationStyle,
                              at position: CGFloat,
                              shouldAnimate: Bool) -> (CGFloat, Bool) {
        var position = position
        var animated = shouldAnimate
        switch style {
        case .snap:
            position = round(position)
            animated = true
            
        default: break
        }
        
        return (position, animated)
    }
}

extension TMBarView: TMBarLayoutParent {
    
    var contentInset: UIEdgeInsets {
        set {
            let sanitizedContentInset = UIEdgeInsets(top: 0.0, left: newValue.left, bottom: 0.0, right: newValue.right)
            scrollView.contentInset = sanitizedContentInset
            scrollView.contentOffset.x -= sanitizedContentInset.left
            
            rootContainerTop.constant = newValue.top
            rootContainerBottom.constant = newValue.bottom
        } get {
            return UIEdgeInsets(top: rootContainerTop.constant,
                                left: scrollView.contentInset.left,
                                bottom: rootContainerBottom.constant,
                                right: scrollView.contentInset.right)
        }
    }
    
    var isPagingEnabled: Bool {
        set {
            scrollView.isPagingEnabled = newValue
        } get {
            return scrollView.isPagingEnabled
        }
    }
}

// MARK: - Indicator
extension TMBarView {
    
    /// Create a container for an indicator to be displayed in. Will also add the container to the view hierarchy.
    ///
    /// - Parameter indicator: Indicator to create container for.
    /// - Returns: Indicator container.
    private func container(for indicator: IndicatorType) -> TMBarIndicatorContainer<IndicatorType> {
        let container = TMBarIndicatorContainer(for: indicator)
        switch indicator.displayStyle {
        case .footer:
            grid.addBottomSubview(container)
            
        case .header:
            grid.addTopSubview(container)
            
        case .fill:
            scrollView.addSubview(container)
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
    
    private func reloadIndicatorPosition() {
        guard let indicatedPosition = self.indicatedPosition else {
            return
        }
        update(for: indicatedPosition,
               capacity: buttons.all.count,
               direction: .none,
               animation: TMBarAnimationConfig(isEnabled: true,
                                               duration: TMBarViewDefaults.animationDuration))
    }
}

// MARK: - Interaction
extension TMBarView: TMBarButtonInteractionHandler {
    
    func barButtonInteraction(controller: TMBarButtonInteractionController,
                              didHandlePressOf button: TMBarButton,
                              at index: Int) {
        delegate?.bar(self, didRequestScrollTo: index)
    }
}

// MARK: - Accessory Views
public extension TMBarView {
    
    /// Location of accessory views.
    ///
    /// - leading: At the leading edge of the view.
    ///            `pinned` set to true will make the view pin to the leading of the layout and always stay visible,
    ///            where as false will result in the view scrolling with the layout.
    /// - trailing: At the trailing edge of the view.
    ///            `pinned` set to true will make the view pin to the trailing of the layout and always stay visible,
    ///            where as false will result in the view scrolling with the layout.
    public enum AccessoryLocation {
        case leading(pinned: Bool)
        case trailing(pinned: Bool)
        
        internal var key: String {
            switch self {
            case .leading(let pinned):
                return "leading\(pinned ? "Pinned" : "")"
            case .trailing(let pinned):
                return "trailing\(pinned ? "Pinned" : "")"
            }
        }
    }
    
    /// Set an accessory view for a location in the bar view.
    ///
    /// - Parameters:
    ///   - view: Accessory view.
    ///   - location: Location of the accessory.
    public func setAccessoryView(_ view: UIView,
                                 at location: AccessoryLocation) {
        cleanUpOldAccessory(at: location)
        updateAccessory(view: view, at: location)
    }
    
    func accessoryView(at location: AccessoryLocation) -> UIView? {
        return accessoryViews[location.key]
    }
    
    private func cleanUpOldAccessory(at location: AccessoryLocation) {
        let view = accessoryView(at: location)
        view?.removeFromSuperview()
        accessoryViews[location.key] = nil
    }
    
    private func updateAccessory(view: UIView?, at location: AccessoryLocation) {
        guard let view = view else {
            return
        }
        
        accessoryViews[location.key] = view
        switch location {
        case .leading(let pinned):
            if pinned {
                rootContentStack.insertArrangedSubview(view, at: 0)
            } else {
                grid.addLeadingSubview(view)
            }
        case .trailing(let pinned):
            if pinned {
                rootContentStack.insertArrangedSubview(view, at: rootContentStack.arrangedSubviews.count)
            } else {
                grid.addTrailingSubview(view)
            }
        }
        reloadIndicatorPosition()
    }
}
