//
//  LedFXApp.swift
//  LedFX
//
//  Created by Caleb Nordhagen on 5/9/26.
//

import SwiftUI

@main
struct LedFXApp: App {
    @State private var viewModel = ShowViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
