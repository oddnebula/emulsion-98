import Foundation

/// The shared Platinum theme calls into the app's retro layer for WindowShade; the extension has none.
final class Retro {
    static let shared = Retro()
    func toggleShade() {}
}
