//
//  CreateKeyboardDismissal.swift
//  Flick
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension View {
    @ViewBuilder
    func dismissKeyboardOnTap() -> some View {
        #if canImport(UIKit)
        simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
        #else
        self
        #endif
    }
}
