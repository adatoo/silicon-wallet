import SwiftUI

/// Placeholder for the three-column layout in DESIGN.md §3: Groups | Entries | Detail.
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("No groups yet")
            }
            .navigationTitle("Groups")
        } content: {
            ContentUnavailableView("No Entries", systemImage: "tray")
        } detail: {
            ContentUnavailableView("No Selection", systemImage: "lock.rectangle")
        }
    }
}

#Preview {
    ContentView()
}
