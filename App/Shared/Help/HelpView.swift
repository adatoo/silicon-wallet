import SwiftUI

/// Short, offline help: the Help window on the Mac, a sheet on iOS. It mirrors the support
/// page (`site/support.html`), so change both together.
struct HelpView: View {
    /// The Mac's Help window (`SiliconWalletApp`).
    static let windowID = "help"

    #if os(macOS)
        @State private var selection: HelpTopic.ID? = HelpTopic.all.first?.id
    #endif

    var body: some View {
        #if os(macOS)
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(HelpTopic.all) { topic in
                        Label(topic.title, systemImage: topic.symbol).tag(topic.id)
                    }
                    Section("More Help") { links }
                }
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            } detail: {
                if let topic = HelpTopic.all.first(where: { $0.id == selection }) {
                    HelpTopicView(topic: topic)
                }
            }
        #else
            List {
                Section {
                    ForEach(HelpTopic.all) { topic in
                        NavigationLink {
                            HelpTopicView(topic: topic)
                        } label: {
                            Label(topic.title, systemImage: topic.symbol)
                        }
                    }
                }
                Section("More Help") { links }
            }
            .navigationTitle("Help")
        #endif
    }

    @ViewBuilder
    private var links: some View {
        Link(destination: AppLinks.support) { Label("Support Website", systemImage: "safari") }
        Link(destination: AppLinks.issues) { Label("Report a Problem", systemImage: "exclamationmark.bubble") }
    }
}

/// Opens Help: the Help window on the Mac, a sheet on iOS. Give it a `systemImage` to use it
/// in a toolbar.
struct HelpButton: View {
    var title: LocalizedStringKey = "Help"
    var systemImage: String?
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #else
        @State private var showingHelp = false
    #endif

    var body: some View {
        #if os(macOS)
            button { openWindow(id: HelpView.windowID) }
        #else
            button { showingHelp = true }
                .sheet(isPresented: $showingHelp) {
                    NavigationStack {
                        HelpView().toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { showingHelp = false } }
                        }
                    }
                }
        #endif
    }

    @ViewBuilder
    private func button(action: @escaping () -> Void) -> some View {
        if let systemImage {
            Button(title, systemImage: systemImage, action: action)
        } else {
            Button(title, action: action)
        }
    }
}

/// One topic's paragraphs, readable at any text size.
struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(topic.paragraphs, id: \.self) { paragraph in
                    Text(LocalizedStringKey(paragraph))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let link = topic.link {
                    Link(link.title, destination: link.url)
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: 620, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(topic.title)
    }
}

/// A help topic: a title, a symbol and a few short paragraphs, with Markdown for emphasis.
struct HelpTopic: Identifiable, Hashable {
    struct TopicLink: Hashable {
        let title: String
        let url: URL
    }

    let id: String
    let title: String
    let symbol: String
    let paragraphs: [String]
    var link: TopicLink?

    #if os(macOS)
        private static let biometrics = "Touch ID"
        private static let autoLock =
            "The vault locks itself after 5 minutes without use, and when the Mac sleeps, starts its screen saver or locks its screen. Change this in **Settings ▸ Locking**. To lock straight away, choose **Vault ▸ Lock** (⌃⌘L)."
        private static let importSteps =
            "Choose **File ▸ Import from Acrylic Wallet…** (or **Settings ▸ Import from Acrylic Wallet…**). Wallet keeps its vault at `~/Library/Containers/com.acrylic.WalletMac/Data/Library/Application Support/Wallet/Database.wallet`: in the file picker, press ⇧⌘G and paste that path. A Dropbox copy or a \"Wallet Database\" export works too."
        private static let attachmentsAdd =
            "Add files in an entry's **Attachments** section, or drop them there. Each one is encrypted with its own key, up to 100 MB."
    #else
        private static let biometrics = "Face ID or Touch ID"
        private static let autoLock =
            "The vault locks itself after 5 minutes without use, and when Silicon Wallet goes into the background. Change both in **Settings ▸ Locking**. To lock straight away, choose **Settings ▸ Lock Now**."
        private static let importSteps =
            "First put your `Database.wallet` file, or a \"Wallet Database\" export, in the Files app. Then choose **Settings ▸ Import from Acrylic Wallet…** and pick the file."
        private static let attachmentsAdd =
            "Add photos and files in an entry's **Attachments** section. Each one is encrypted with its own key, up to 100 MB."
    #endif

    static let all: [HelpTopic] = [
        HelpTopic(
            id: "start",
            title: "Getting Started",
            symbol: "sparkles",
            paragraphs: [
                "Silicon Wallet keeps your passwords, cards, notes and files in an encrypted vault. There's no account to create: your master password is the only key.",
                "Your vault is organised into **groups**, such as Logins or Credit Cards. Each group has its own fields, and every **entry** in it fills them in. Edit a group to add fields, rename them, mark them as concealed so their values stay hidden until you reveal them, or show their values in a monospaced font, which makes card numbers and keys easier to check. Drag fields, extra fields and attachments to change their order while editing.",
                "Add an entry with the + button. When you need a new password, use the generator in the entry editor. Mark entries you use often as favourites.",
                "Deleted entries and groups go to **Recently Deleted**, at the bottom of the sidebar. Recover them from there, or delete them for good; anything left is deleted for good after 30 days.",
                "Search finds entries by their title and visible fields. It never searches concealed values.",
            ]
        ),
        HelpTopic(
            id: "password",
            title: "Your Master Password",
            symbol: "key",
            paragraphs: [
                "Your master password encrypts everything in your vault. **It can't be recovered or reset.** Nobody else has a copy, including the people who make Silicon Wallet. Write it down and keep it somewhere safe, away from your devices.",
                "Choose something long that you don't use anywhere else. A few random words make a strong password that's easy to remember.",
                "To change it, choose **Settings ▸ Change Master Password…**. Your entries don't need re-encrypting, so this is quick.",
                "**Settings ▸ Delete Vault…** removes the vault from this device, or from every device and iCloud. It asks for your master password first, and it can't be undone.",
            ]
        ),
        HelpTopic(
            id: "lock",
            title: "Locking and Unlocking",
            symbol: "lock",
            paragraphs: [
                autoLock,
                "Turn on **Unlock with \(biometrics)** in Settings to skip typing your password. You still need the master password after a restart, and at least once every 7 days (you can change how often).",
                "Copied values are cleared from the clipboard after 60 seconds, and when the vault locks, unless you've copied something else since.",
                "**Settings ▸ Access Log…** lists unlocks and failed attempts on this device.",
            ]
        ),
        HelpTopic(
            id: "sync",
            title: "iCloud Sync",
            symbol: "icloud",
            paragraphs: [
                "When your device is signed in to iCloud, your vault syncs automatically with your other devices on the same Apple Account. Only encrypted data leaves the device, so Apple can't read it.",
                "The sync icon in the toolbar shows the status. Tap or click it to sync now.",
                "On a new device, install Silicon Wallet, sign in to the same Apple Account, and wait for it to find your vault. Then unlock it with your master password.",
                "Without iCloud, everything still works and stays on this device. If the same entry is changed on two devices at once, the later change wins and the other is kept as a **conflict copy**, so nothing is lost.",
            ]
        ),
        HelpTopic(
            id: "attachments",
            title: "Attachments",
            symbol: "paperclip",
            paragraphs: [
                attachmentsAdd,
                "Images, PDFs and text files are shown straight from memory. Other files open in Quick Look from a temporary decrypted copy, which is deleted when you close it and when the vault locks.",
                "**Save a Copy** writes an unencrypted copy wherever you choose. Delete it when you've finished with it.",
                "To remove an attachment, use its menu in the entry, or the red remove button next to it while editing; that one takes effect when you save.",
            ]
        ),
        HelpTopic(
            id: "acrylic",
            title: "Moving from Acrylic Wallet",
            symbol: "square.and.arrow.down",
            paragraphs: [
                "Silicon Wallet reads Acrylic Wallet's vault file directly. You don't need Wallet installed, and nothing is uploaded or saved unencrypted.",
                importSteps,
                "Enter your **old Wallet password** (not your Silicon Wallet master password), check the preview, and import. Groups, field labels, entries, notes, favourites and attachments all come across.",
                "Silicon Wallet doesn't change the old file. Once you've checked your entries, delete it, along with any Dropbox copy and Wallet exports. Wallet's encryption is weak by today's standards, so anyone with an old copy could try passwords against it very quickly.",
            ]
        ),
        HelpTopic(
            id: "security",
            title: "How Your Data Is Protected",
            symbol: "lock.shield",
            paragraphs: [
                "Your master password is stretched with Argon2id, a deliberately slow function that makes guessing it very expensive. The result unlocks a random vault key, and every entry, group and file is encrypted with AES-256-GCM.",
                "Only encrypted data is ever written to disk or sent to iCloud. Names, field labels, values, notes and file names are all encrypted.",
                "Silicon Wallet collects no data: no account, no analytics, no tracking. It's free and open source, so anyone can check how it works.",
            ],
            link: TopicLink(title: "Read the full security design", url: AppLinks.securityDesign)
        ),
    ]
}
