//
//  Item.swift
//  HomeBuddy
//
//  Created by Atman An on 2026/8/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
