//
//  APPsLinkApp.swift
//  APPsLink
//
//  Created by 李秉璋 on 2025/5/1.
//

import SwiftUI

@main
struct APPsLinkApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 500)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowToolbarStyle(UnifiedWindowToolbarStyle())
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
