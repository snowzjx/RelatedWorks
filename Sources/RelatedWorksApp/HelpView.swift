import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Group {
                    Text(appLocalized("Getting Started")).font(.title2).bold()

                    VStack(alignment: .leading, spacing: 8) {
                        HelpStep(number: "1", title: appLocalized("Create a Project"),
                            detail: appLocalized("Each project represents a paper you're writing. Click the + button in the sidebar or press ⌘N to create one."))
                        HelpStep(number: "2", title: appLocalized("Add Papers"),
                            detail: appLocalized("Import a PDF. RelatedWorks automatically extracts metadata and searches DBLP or arXiv."))
                        HelpStep(number: "3", title: appLocalized("Assign a Semantic ID"),
                            detail: appLocalized("Every paper gets a short memorable ID (e.g. Transformer, BERT, GPT4) used to cross-reference papers in notes."))
                        HelpStep(number: "4", title: appLocalized("Take Notes & Cross-Reference"),
                            detail: appLocalized("Write annotation notes in the editor. Use @SemanticID syntax to link to other papers — they render as clickable links."))
                        HelpStep(number: "5", title: appLocalized("Generated Related Works"),
                            detail: appLocalized("Click Generated Related Works in the project view. RelatedWorks synthesizes your notes and paper metadata into a LaTeX-ready draft."))
                        HelpStep(number: "6", title: appLocalized("Export BibTeX"),
                            detail: appLocalized("BibTeX entries are fetched from DBLP automatically, or generated from metadata when unavailable."))
                        HelpStep(number: "7", title: appLocalized("Export / Import Project"),
                            detail: appLocalized("Right-click a project → Export… to save a .relatedworks file. Use File → Import Project… (⌘⇧I) to import on any machine."))
                    }
                }

                Divider()

                Group {
                    Text(appLocalized("AI Backends")).font(.title2).bold()
                    Text(appLocalized("Set up the AI backend first, then choose models in Settings."))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Label(appLocalized("Ollama runs locally and needs no API key."), systemImage: "desktopcomputer")
                        Label(appLocalized("Gemini uses a key from Google AI Studio. Recommended: gemini-2.5-flash."), systemImage: "cloud")
                    }
                    .font(.callout)
                }

                Divider()

                Group {
                    Text(appLocalized("Keyboard Shortcuts")).font(.title2).bold()

                    VStack(alignment: .leading, spacing: 6) {
                        HelpShortcut(key: "⌘N", action: appLocalized("New Project"))
                        HelpShortcut(key: "⌘⇧A", action: appLocalized("Add Paper"))
                        HelpShortcut(key: "⌘,", action: appLocalized("Open Settings"))
                        HelpShortcut(key: "⌘⇧I", action: appLocalized("Import Project"))
                        HelpShortcut(key: "⌘E", action: appLocalized("Export Selected Project"))
                    }
                    .font(.callout)
                }

                Divider()

                Group {
                    Text(appLocalized("Deep Links")).font(.title2).bold()
                    Text(appLocalized("Every paper and project has a relatedworks:// URI for tools like Hookmark."))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("relatedworks://open?project=<UUID>").monospaced().font(.callout)
                        Text("relatedworks://open?project=<UUID>&paper=<SemanticID>").monospaced().font(.callout)
                        Text("relatedworks://settings").monospaced().font(.callout)
                    }
                }

                Divider()

                Group {
                    Text(appLocalized("Data Storage")).font(.title2).bold()
                    VStack(alignment: .leading, spacing: 8) {
                    Text(appLocalized("Local storage keeps projects and PDFs under:"))
                        Text("~/Library/Application Support/RelatedWorks/projects/")
                            .font(.callout).monospaced()
                        Text(appLocalized("With iCloud sync on, projects and PDFs live in the app's iCloud Drive container and sync across devices."))
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 560, height: 520)
        .safeAreaInset(edge: .bottom) {
            Button(appLocalized("Close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .padding()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

enum FirstLaunchTarget: Hashable {
    case projectCreateEmpty
    case projectCreateToolbar
    case projectSelection
    case aiBackend
    case addPaper
    case annotation
    case generateButton
    case iCloudToggle
}

enum FirstLaunchStep: Int, CaseIterable {
    case aiSetup, projectCreate, projectSelect, ingest, semantic, generate, sync

    var title: String {
        switch self {
        case .aiSetup: return appLocalized("AI Setup")
        case .projectCreate: return appLocalized("Project")
        case .projectSelect: return appLocalized("Select Project")
        case .ingest: return appLocalized("Add Paper")
        case .semantic: return appLocalized("Semantic IDs")
        case .generate: return appLocalized("Related Works")
        case .sync: return appLocalized("iCloud Sync")
        }
    }

    var subtitle: String {
        switch self {
        case .aiSetup: return appLocalized("Configure your AI backend and models.")
        case .projectCreate: return appLocalized("Create one project for one paper.")
        case .projectSelect: return appLocalized("Select the project you want to work on.")
        case .ingest: return appLocalized("Import a PDF.")
        case .semantic: return appLocalized("Select a paper and write notes with semantic IDs.")
        case .generate: return appLocalized("Generate the Related Works section.")
        case .sync: return appLocalized("Open Settings and sync the library.")
        }
    }

    var progressLabel: String {
        return appLocalizedFormat("%lld of %lld", rawValue + 1, FirstLaunchStep.allCases.count)
    }

    var target: FirstLaunchTarget {
        switch self {
        case .aiSetup: return .aiBackend
        case .projectCreate: return .projectCreateToolbar
        case .projectSelect: return .projectSelection
        case .ingest: return .addPaper
        case .semantic: return .annotation
        case .generate: return .generateButton
        case .sync: return .iCloudToggle
        }
    }

    var placement: BubblePlacement {
        switch self {
        case .aiSetup: return .trailing
        case .projectCreate: return .trailing
        case .projectSelect: return .trailing
        case .ingest: return .aboveLeading
        case .semantic: return .leading
        case .generate: return .belowTrailing
        case .sync: return .trailing
        }
    }
}

enum BubblePlacement {
    case leading
    case trailing
    case aboveLeading
    case belowLeading
    case belowTrailing
}

struct FirstLaunchAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [FirstLaunchTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [FirstLaunchTarget: Anchor<CGRect>], nextValue: () -> [FirstLaunchTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct FirstLaunchTutorialHost<Content: View>: View {
    @Binding var isPresented: Bool
    @Binding var step: FirstLaunchStep
    @Binding var selectedProjectID: UUID?
    @Binding var selectedPaperID: String?
    let onFinish: () -> Void
    let content: Content

    init(
        isPresented: Binding<Bool>,
        step: Binding<FirstLaunchStep>,
        selectedProjectID: Binding<UUID?>,
        selectedPaperID: Binding<String?>,
        onFinish: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._isPresented = isPresented
        self._step = step
        self._selectedProjectID = selectedProjectID
        self._selectedPaperID = selectedPaperID
        self.onFinish = onFinish
        self.content = content()
    }

    @State private var navigatingBack = false

    var body: some View {
        content
            .overlayPreferenceValue(FirstLaunchAnchorPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    if isPresented {
                        let targetFrame = targetFrame(from: anchors, proxy: proxy)
                        FirstLaunchCoachmarkBubble(
                            step: step,
                            progressLabel: step.progressLabel,
                            targetFrame: targetFrame,
                            selectedProjectID: selectedProjectID,
                            canGoBack: step.rawValue > FirstLaunchStep.aiSetup.rawValue,
                            canGoForward: canAdvance,
                            onBack: goBack,
                            onNext: goForward,
                            onFinish: finish
                        )
                        .position(bubbleCenter(for: targetFrame, in: proxy.size, placement: step.placement))
                        .animation(.easeInOut(duration: 0.2), value: step)

                        if let targetFrame {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.8), lineWidth: 3)
                                .frame(width: targetFrame.width + 8, height: targetFrame.height + 8)
                                .position(x: targetFrame.midX, y: targetFrame.midY)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .onChange(of: selectedProjectID) { selectedPaperID = nil }
    }

    private var canAdvance: Bool {
        switch step {
        case .aiSetup: return true
        case .projectCreate, .projectSelect: return selectedProjectID != nil
        case .ingest: return selectedPaperID != nil
        case .semantic: return true
        case .generate: return selectedProjectID != nil
        case .sync: return true
        }
    }

    private func targetFrame(from anchors: [FirstLaunchTarget: Anchor<CGRect>], proxy: GeometryProxy) -> CGRect? {
        let candidates: [FirstLaunchTarget]
        switch step {
        case .aiSetup:
            candidates = [.aiBackend]
        case .projectCreate:
            candidates = [.projectCreateToolbar]
        case .projectSelect:
            candidates = [.projectSelection]
        case .ingest:
            candidates = [.addPaper]
        case .semantic:
            candidates = [.annotation]
        case .generate:
            candidates = [.generateButton]
        case .sync:
            candidates = []
        }
        for candidate in candidates {
            if let anchor = anchors[candidate] {
                return proxy[anchor]
            }
        }
        return nil
    }

    private func bubbleCenter(for targetFrame: CGRect?, in size: CGSize, placement: BubblePlacement) -> CGPoint {
        let bubbleWidth: CGFloat = 380
        let bubbleHeight: CGFloat = 220
        let margin: CGFloat = 20

        guard let targetFrame else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }

        func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            min(max(value, lower), upper)
        }

        switch placement {
        case .leading:
            return CGPoint(
                x: clamp(targetFrame.minX - bubbleWidth / 2 - margin, bubbleWidth / 2 + margin, size.width - bubbleWidth / 2 - margin),
                y: clamp(targetFrame.midY, bubbleHeight / 2 + margin, size.height - bubbleHeight / 2 - margin)
            )
        case .trailing:
            return CGPoint(
                x: clamp(targetFrame.maxX + bubbleWidth / 2 + margin, bubbleWidth / 2 + margin, size.width - bubbleWidth / 2 - margin),
                y: clamp(targetFrame.midY, bubbleHeight / 2 + margin, size.height - bubbleHeight / 2 - margin)
            )
        case .aboveLeading:
            return CGPoint(
                x: clamp(targetFrame.minX + bubbleWidth / 2, bubbleWidth / 2 + margin, size.width - bubbleWidth / 2 - margin),
                y: clamp(targetFrame.minY - bubbleHeight / 2 - margin, bubbleHeight / 2 + margin, size.height - bubbleHeight / 2 - margin)
            )
        case .belowLeading:
            return CGPoint(
                x: clamp(targetFrame.minX + bubbleWidth / 2, bubbleWidth / 2 + margin, size.width - bubbleWidth / 2 - margin),
                y: clamp(targetFrame.maxY + bubbleHeight / 2 + margin, bubbleHeight / 2 + margin, size.height - bubbleHeight / 2 - margin)
            )
        case .belowTrailing:
            return CGPoint(
                x: clamp(targetFrame.maxX - bubbleWidth / 2, bubbleWidth / 2 + margin, size.width - bubbleWidth / 2 - margin),
                y: clamp(targetFrame.maxY + bubbleHeight / 2 + margin + 28, bubbleHeight / 2 + margin, size.height - bubbleHeight / 2 - margin)
            )
        }
    }

    private func goBack() {
        navigatingBack = true
        step = FirstLaunchStep(rawValue: max(step.rawValue - 1, FirstLaunchStep.aiSetup.rawValue)) ?? .aiSetup
        // Clear the flag after the onChange(of: step) fires
        DispatchQueue.main.async { navigatingBack = false }
    }

    private func goForward() {
        navigatingBack = false
        guard canAdvance else { return }
        if step == .semantic {
            // Brief delay so the annotation editor can resign focus before the
            // overlay repositions to the generate button anchor.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.step = .generate
            }
            return
        }
        guard let next = FirstLaunchStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        step = next
    }

    private func finish() {
        onFinish()
    }
}

private struct FirstLaunchCoachmarkBubble: View {
    let step: FirstLaunchStep
    let progressLabel: String
    let targetFrame: CGRect?
    let selectedProjectID: UUID?
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onNext: () -> Void
    let onFinish: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: arrowSymbol)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(step.title)
                            .font(.headline)
                        Spacer()
                        Text(progressLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(step.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            stepBody

            HStack(spacing: 10) {
                Button(appLocalized("Back")) { onBack() }
                    .disabled(!canGoBack)

                Spacer()

                Button(appLocalized("Skip")) { onFinish() }

                Button(step == .sync ? appLocalized("Done") : appLocalized("Next")) {
                    if step == .sync {
                        onFinish()
                    } else {
                        onNext()
                    }
                }
                .buttonStyle(.borderedProminent)
                .inactiveAwareProminentButtonForeground()
                .disabled(!canGoForward)
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }

    private var stepBody: some View {
        switch step {
        case .aiSetup:
            return AnyView(aiSetupBody)
        case .projectCreate:
            return AnyView(projectCreateBody)
        case .projectSelect:
            return AnyView(projectSelectBody)
        case .ingest:
            return AnyView(ingestBody)
        case .semantic:
            return AnyView(semanticBody)
        case .generate:
            return AnyView(generateBody)
        case .sync:
            return AnyView(syncBody)
        }
    }

    private var projectCreateBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("Click the + button in the sidebar to create your project. One project is one paper, and it contains the related papers, annotations, and the generation prompt for that paper."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var aiSetupBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("Configure the AI backend first, then choose models in Settings."))
                .font(.callout)
                .foregroundStyle(.secondary)
            settingsLaunchControl(appLocalized("Open Settings"))
        }
    }

    @ViewBuilder
    private func settingsLaunchControl(_ title: String) -> some View {
        SettingsLink {
            Label(title, systemImage: "gearshape")
        }
        .buttonStyle(.borderedProminent)
        .inactiveAwareProminentButtonForeground()
    }

    private var projectSelectBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("Select or create a project to start organizing your literature."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var ingestBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("Import a PDF. RelatedWorks automatically extracts metadata and searches DBLP or arXiv."))
                .font(.callout)
                .foregroundStyle(.secondary)
            InteractiveCallout(
                title: appLocalized("What Happens"),
                detail: appLocalized("Import PDF -> extract metadata -> search DBLP/arXiv.")
            )
        }
    }

    private var semanticBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("Write annotation notes in the editor. Use @SemanticID syntax to link to other papers — they render as clickable links."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var generateBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("Click Generated Related Works in the project view. RelatedWorks synthesizes your notes and paper metadata into a LaTeX-ready draft."))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                if let selectedProjectID {
                    openWindow(id: AppWindowID.generate, value: selectedProjectID)
                }
            } label: {
                Label(appLocalized("Generated Related Works"), systemImage: "text.badge.star")
            }
            .buttonStyle(.borderedProminent)
            .inactiveAwareProminentButtonForeground()
            .disabled(selectedProjectID == nil)
        }
    }

    private var syncBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("With iCloud sync enabled in Settings, projects and PDFs are stored in the app's iCloud Drive container and sync across your devices."))
                .font(.callout)
                .foregroundStyle(.secondary)
            settingsLaunchControl(appLocalized("Open Settings"))
            InteractiveCallout(
                title: appLocalized("Inbox Flow"),
                detail: appLocalized("On iPhone or iPad, share a PDF from Safari or Files to RelatedWorks. Mac processes it, sends a notification, and you can add it to your project.")
            )
        }
    }

    private var arrowSymbol: String {
        switch step {
        case .aiSetup: return "brain.head.profile"
        case .projectCreate, .projectSelect: return "arrow.left"
        case .ingest: return "arrow.down"
        case .semantic: return "arrow.right"
        case .generate: return "arrow.right"
        case .sync: return "cloud"
        }
    }
}

private struct HelpShortcut: View {
    let key: String
    let action: String
    var body: some View {
        HStack(spacing: 16) {
            Text(key).monospaced().frame(width: 48, alignment: .leading)
            Text(action).foregroundStyle(.secondary)
        }
    }
}

private struct HelpStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.callout).bold()
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).bold()
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct InteractiveCallout: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .fontWeight(.semibold)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct InactiveAwareProminentButtonForeground: ViewModifier {
    @Environment(\.controlActiveState) private var controlActiveState

    func body(content: Content) -> some View {
        content.foregroundStyle(controlActiveState == .inactive ? Color.primary : Color.white)
    }
}

extension View {
    func inactiveAwareProminentButtonForeground() -> some View {
        modifier(InactiveAwareProminentButtonForeground())
    }
}
