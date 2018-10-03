//
//  TorStatusIndicator.swift
//  VergeiOS
//
//  Created by Swen van Zanten on 11-09-18.
//  Copyright © 2018 Verge Currency. All rights reserved.
//

import UIKit
import SystemConfiguration

class TorStatusIndicator: UIWindow {

    enum status {
        case connected
        case disconnected
        case turnedOff
    }
    
    static var shared = TorStatusIndicator()
    var torStatusIndicatorViewController: TorStatusIndicatorViewController?
    let defaultStatus: TorStatusIndicator.status = .turnedOff

    func initialize() {
        let hasNotch = self.hasNotch()
        let frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.size.width, height:  hasNotch ? 54 : 20)
        self.torStatusIndicatorViewController = TorStatusIndicatorViewController(nibName: "TorStatusIndicatorViewController", bundle: .main)
        self.torStatusIndicatorViewController?.view.frame = frame
        self.backgroundColor = .clear

        self.windowLevel = UIWindow.Level.statusBar + 1
        self.rootViewController = self.torStatusIndicatorViewController

        self.frame = frame
        
        self.layoutIfNeeded()
        
        self.torStatusIndicatorViewController?.setHasNotch(hasNotch)
        self.makeKeyAndVisible()
        
        self.setStatus(defaultStatus)
    }

    func hasNotch() -> Bool {
        var hasNotch = false
        if #available(iOS 12.0, *) {
            if self.safeAreaInsets != UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0) {
                hasNotch = true
            }
        }
        else if #available(iOS 11.0, *) {
            if self.safeAreaInsets != UIEdgeInsets.zero {
                hasNotch = true
            }
        }
        return hasNotch
    }
    
    func setStatus(_ status: TorStatusIndicator.status) {
        torStatusIndicatorViewController?.setStatus(status)
    }
}
