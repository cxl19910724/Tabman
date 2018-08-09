//
//  BarButtonHandler.swift
//  Tabman
//
//  Created by Merrick Sapsford on 03/08/2018.
//  Copyright © 2018 UI At Six. All rights reserved.
//

import UIKit

/// Container for BarButton objects and related controllers.
public final class BarButtonCollection<BarButtonType: BarButton> {
    
    // MARK: Types
    
    public typealias Customization = (BarButtonType) -> Void
    
    // MARK: Properties
    
    /// Raw collection of currently active bar buttons.
    public internal(set) var all = [BarButtonType]() {
        didSet {
            self.stateController = BarButtonStateController(for: all)
            self.interactionController = BarButtonInteractionController(for: all, handler: self)
            
            for button in all {
                customization?(button)
            }
        }
    }
    
    private var customization: Customization?
    
    /// Controller which handles button state updates.
    internal private(set) var stateController: BarButtonStateController!
    /// Controller which handles button interaction.
    internal private(set) var interactionController: BarButtonInteractionController!
    
    /// External handler that responds to interaction controller events.
    internal weak var interactionHandler: BarButtonInteractionHandler?
    
    // MARK: Init
    
    init() {
        self.stateController = BarButtonStateController(for: all)
        self.interactionController = BarButtonInteractionController(for: all, handler: self)
    }
    
    // MARK: Customization

    /**
     Customize the bar buttons that are added to the bar.
     
     Note: The customization closure is retained and will be called every time a bar button is added/removed.
     
     Parameter customize: The closure in which customization takes place.
     **/
    public func customize(_ customize: @escaping Customization) {
        self.customization = customize
        all.forEach { (button) in
            customize(button)
        }
    }
}

extension BarButtonCollection: BarButtonInteractionHandler {
    
    func barButtonInteraction(controller: BarButtonInteractionController,
                              didHandlePressOf button: BarButton,
                              at index: Int) {
        interactionHandler?.barButtonInteraction(controller: controller,
                                                 didHandlePressOf: button,
                                                 at: index)
    }
}