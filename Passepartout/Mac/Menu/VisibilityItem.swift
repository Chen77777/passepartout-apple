//
//  VisibilityItem.swift
//  Passepartout
//
//  Created by Davide De Rosa on 7/3/22.
//  Copyright (c) 2022 Davide De Rosa. All rights reserved.
//
//  https://github.com/passepartoutvpn
//
//  This file is part of Passepartout.
//
//  Passepartout is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Passepartout is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Passepartout.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import AppKit

struct VisibilityItem: Item {
    private let title: String
    
    private let viewModel: ViewModel

    init(_ title: String, utils: LightUtils) {
        self.title = title
        viewModel = ViewModel(utils: utils)
    }
    
    func asMenuItem(withParent parent: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(viewModel.bringToForeground),
            keyEquivalent: ""
        )
        item.target = viewModel
        item.representedObject = viewModel
        return item
    }
}
