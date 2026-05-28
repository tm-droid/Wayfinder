//
//  Item.swift
//  Wayfinder
//
//  Created by Tanush Malhotra (School) on 5/28/26.
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
