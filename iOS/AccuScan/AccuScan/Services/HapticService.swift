import UIKit

// MARK: - HapticService
// Central haptic coordinator. Generators are pre-created and pre-prepared so
// the taptic engine fires immediately without allocation latency on each call.
// Each method re-prepares the generator after firing so the next call is
// equally responsive. Must be called from the main thread only.

@MainActor
final class HapticService {
    static let shared = HapticService()

    private let light  = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy  = UIImpactFeedbackGenerator(style: .heavy)
    private let select = UISelectionFeedbackGenerator()
    private let notify = UINotificationFeedbackGenerator()

    private init() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        select.prepare()
        notify.prepare()
    }

    func lightImpact()  { light.impactOccurred();                    light.prepare()  }
    func mediumImpact() { medium.impactOccurred();                   medium.prepare() }
    func heavyImpact()  { heavy.impactOccurred();                    heavy.prepare()  }
    func selection()    { select.selectionChanged();                  select.prepare() }
    func success()      { notify.notificationOccurred(.success);      notify.prepare() }
    func warning()      { notify.notificationOccurred(.warning);      notify.prepare() }
    func error()        { notify.notificationOccurred(.error);        notify.prepare() }
}
