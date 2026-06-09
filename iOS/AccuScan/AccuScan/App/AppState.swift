import SwiftUI
import CoreData

// MARK: - AppState
// Root @StateObject — owns navigation and global state.

@MainActor
final class AppState: ObservableObject {

    // MARK: - Navigation
    enum Screen {
        case home
        case setup
        case scanning
        case review(ScanSession)
        case export(ScanSession)
    }

    @Published var screen: Screen = .home

    // #20: room name + type captured in ScanSetupView, carried through the scan
    // so the saved ScanMetadata preserves what the user typed (was discarded before).
    @Published var pendingRoomName: String = ""
    @Published var pendingRoomType: RoomType = .other

    // MARK: - Core Data
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "AccuScan")
        container.loadPersistentStores { _, error in
            if let error { fatalError("CoreData load failed: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    var context: NSManagedObjectContext { persistentContainer.viewContext }

    // MARK: - Navigation helpers

    func goHome()                         { withAnimation(.easeInOut(duration: 0.35)) { screen = .home } }
    func goSetup()                        { withAnimation(.easeInOut(duration: 0.3))  { screen = .setup } }
    func startScan()                      { withAnimation(.easeInOut(duration: 0.2))  { screen = .scanning } }
    func showReview(_ s: ScanSession)     { withAnimation(.easeInOut(duration: 0.35)) { screen = .review(s) } }
    func showExport(_ s: ScanSession)     { withAnimation(.easeInOut(duration: 0.25)) { screen = .export(s) } }
}
