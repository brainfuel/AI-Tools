//
//  Item.swift
//  AI Tools
//
//  Created by Ben Milford on 27/02/2026.
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
