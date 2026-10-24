//
//  Item.swift
//  RickAndMorty
//
//  Created by Ahmad on 24/10/2026.
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
