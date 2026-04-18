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

struct FirstLaunchTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var step: TutorialStepID = .project
    @State private var projectType: ProjectPreset = .research
    @State private var intakeStage: IntakeStage = .drop
    @State private var semanticID = "Transformer"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label(appLocalized("Welcome to RelatedWorks"), systemImage: "books.vertical.fill")
                    .font(.title2)
                    .fontWeight(.semibold)
            Text(appLocalized("This walkthrough is interactive. Try each control as you go."))
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    stepHeader

                    switch step {
                    case .project:
                        projectStep
                    case .ingest:
                        ingestStep
                    case .semantic:
                        semanticStep
                    case .sync:
                        syncStep
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(appLocalized("You can reopen this tutorial from the Help menu anytime."))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(appLocalized("Back")) { goBack() }
                    .disabled(step == .project)

                Spacer()

                Button(appLocalized("Skip")) { dismiss() }

                Button(step == .sync ? appLocalized("Start Exploring") : appLocalized("Next")) {
                    goForward()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .inactiveAwareProminentButtonForeground()
            }
        }
        .padding(24)
        .frame(width: 720)
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(step.title)
                    .font(.headline)
                Spacer()
                Text(step.progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(step.rawValue + 1), total: Double(TutorialStepID.allCases.count))
        }
    }

    private var projectStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appLocalized("Each project represents a paper you're writing. Click the + button in the sidebar or press ⌘N to create one."))
                .foregroundStyle(.secondary)

            Picker(appLocalized("Project Type"), selection: $projectType) {
                ForEach(ProjectPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            InteractiveCallout(
                title: projectType.title,
                detail: projectType.detail
            )

            HStack {
                Button(appLocalized("Open New Project")) {
                    NotificationCenter.default.post(name: .newProject, object: nil)
                }
                .buttonStyle(.borderedProminent)
                .inactiveAwareProminentButtonForeground()

                Spacer()

                Text(appLocalized("You can change presets or write a custom prompt later."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ingestStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appLocalized("Import a PDF. RelatedWorks automatically extracts metadata and searches DBLP or arXiv."))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(IntakeStage.allCases) { stage in
                    if stage == intakeStage {
                        Button(stage.title) {
                            intakeStage = stage
                        }
                        .buttonStyle(.borderedProminent)
                        .inactiveAwareProminentButtonForeground()
                    } else {
                        Button(stage.title) {
                            intakeStage = stage
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            InteractivePipeline(stage: intakeStage)

            HStack {
                Button(appLocalized("Open Add Paper")) {
                    NotificationCenter.default.post(name: .addPaper, object: nil)
                }
                .buttonStyle(.borderedProminent)
                .inactiveAwareProminentButtonForeground()

                Spacer()

                Text(appLocalized("You can also drag a PDF into the sheet or paper list."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var semanticStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appLocalized("Every paper gets a short memorable ID (e.g. Transformer, BERT, GPT4) used to cross-reference papers in notes."))
                .foregroundStyle(.secondary)

            TextField(appLocalized("Semantic ID"), text: $semanticID)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            InteractiveCallout(
                title: appLocalized("Annotation preview"),
                detail: appLocalizedFormat("Use @SemanticID syntax to link to other papers — they render as clickable links.")
            )

            Text(appLocalized("These links feed the final Related Works section."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var syncStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(appLocalized("When enabled, projects are read from iCloud Drive and synced across your devices. Existing local data is not moved."))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Label(appLocalized("Mac"), systemImage: "desktopcomputer")
                Label(appLocalized("iPhone"), systemImage: "iphone")
                Label(appLocalized("iPad"), systemImage: "ipad")
            }
            .font(.callout)

            InteractiveCallout(
                title: appLocalized("Inbox Flow"),
                detail: appLocalized("On iPhone or iPad, share a PDF from Safari or Files to RelatedWorks. Mac processes it, sends a notification, and you can add it to your project.")
            )

            HStack {
                Button(appLocalized("Open Inbox")) {
                    openWindow(id: AppWindowID.inbox)
                }
                .buttonStyle(.borderedProminent)
                .inactiveAwareProminentButtonForeground()

                Button(appLocalized("Open User Guide")) {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }

                Spacer()
            }
        }
    }

    private func goBack() {
        step = TutorialStepID(rawValue: max(step.rawValue - 1, 0)) ?? .project
    }

    private func goForward() {
        guard let next = TutorialStepID(rawValue: step.rawValue + 1) else {
            dismiss()
            return
        }
        step = next
    }
}

struct FirstLaunchCoachmarkView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow
    let onFinish: () -> Void
    @State private var step: CoachmarkStep = .project
    @State private var projectType: ProjectPreset = .research
    @State private var semanticID = "Transformer"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appLocalized("Welcome to RelatedWorks"))
                        .font(.headline)
                    Text(step.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(appLocalized("Skip")) { onFinish() }
                    .buttonStyle(.borderless)
            }

            Divider().padding(.vertical, 12)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: step.arrowSymbol)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(step.title)
                            .font(.headline)
                        Spacer()
                        Text(step.progressLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: Double(step.rawValue + 1), total: Double(CoachmarkStep.allCases.count))

                    switch step {
                    case .project:
                        projectStep
                    case .ingest:
                        ingestStep
                    case .semantic:
                        semanticStep
                    case .sync:
                        syncStep
                    }
                }
            }

            Divider().padding(.vertical, 12)

            HStack(spacing: 10) {
                Button(appLocalized("Back")) { goBack() }
                    .disabled(step == .project)

                Spacer()

                Button(appLocalized("Close Tutorial")) { onFinish() }
                Button(step == .sync ? appLocalized("Done") : appLocalized("Next")) {
                    goForward()
                }
                .buttonStyle(.borderedProminent)
                .inactiveAwareProminentButtonForeground()
            }
        }
        .padding(18)
        .frame(width: 430)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: step.alignment)
        .padding(step.padding)
    }

    private var projectStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("One project belongs to one paper. The project stores the related papers, annotations, the generation prompt, and the BibTeX output for that paper."))
                .foregroundStyle(.secondary)

            Picker(appLocalized("Project Type"), selection: $projectType) {
                ForEach(ProjectPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            InteractiveCallout(
                title: projectType.title,
                detail: projectType.detail
            )

            HStack {
                Button(appLocalized("Open New Project")) {
                    NotificationCenter.default.post(name: .newProject, object: nil)
                }
                .buttonStyle(.borderedProminent)
                .inactiveAwareProminentButtonForeground()

                Spacer()
            }
        }
    }

    private var ingestStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("Add Paper is a sheet inside a project. Drop a PDF there and RelatedWorks extracts the metadata, then looks it up on DBLP or arXiv."))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(IntakeStage.allCases) { stage in
                    Button(stage.title) { }
                        .buttonStyle(.bordered)
                        .disabled(true)
                }
            }

            InteractivePipeline(stage: .drop)

            if store.projects.isEmpty {
                Text(appLocalized("Create a project first, then use Add Paper from that project."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button(appLocalized("Open Add Paper")) {
                    NotificationCenter.default.post(name: .addPaper, object: nil)
                }
                .buttonStyle(.borderedProminent)
                .inactiveAwareProminentButtonForeground()
            }
        }
    }

    private var semanticStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("Each paper gets a semantic ID, often suggested from the algorithm or system name in the paper. You can change it later and reference it in annotations like @Transformer."))
                .foregroundStyle(.secondary)

            TextField(appLocalized("Semantic ID"), text: $semanticID)
                .textFieldStyle(.roundedBorder)

            InteractiveCallout(
                title: appLocalized("Live preview"),
                detail: appLocalizedFormat("Try writing relationships like %@", "@\(semanticID)")
            )

            Text(appLocalized("Those relationships are considered when generating the Related Works section."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var syncStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized("Your library syncs across Mac, iPhone, and iPad with iCloud. On iPhone and iPad, share a PDF from Safari or Files to RelatedWorks. Mac processes it automatically, sends a notification, and you can add it to your project."))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Label(appLocalized("Mac"), systemImage: "desktopcomputer")
                Label(appLocalized("iPhone"), systemImage: "iphone")
                Label(appLocalized("iPad"), systemImage: "ipad")
            }
            .font(.callout)

            InteractiveCallout(
                title: appLocalized("Inbox Flow"),
                detail: appLocalized("Share from Safari or Files -> RelatedWorks Inbox -> Mac processes it -> notification.")
            )

            HStack {
                Button(appLocalized("Open Inbox")) {
                    openWindow(id: AppWindowID.inbox)
                }
                .buttonStyle(.borderedProminent)
                .inactiveAwareProminentButtonForeground()

                Button(appLocalized("Open User Guide")) {
                    NotificationCenter.default.post(name: .showHelp, object: nil)
                }

                Spacer()
            }
        }
    }

    private func goBack() {
        step = CoachmarkStep(rawValue: max(step.rawValue - 1, 0)) ?? .project
    }

    private func goForward() {
        guard let next = CoachmarkStep(rawValue: step.rawValue + 1) else {
            onFinish()
            return
        }
        step = next
    }
}

enum FirstLaunchScene {
    case main
    case settings
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

    func progressLabel(includingAISetup: Bool) -> String {
        let total = includingAISetup ? 7 : 6
        let index: Int
        switch self {
        case .aiSetup: index = 1
        case .projectCreate: index = includingAISetup ? 2 : 1
        case .projectSelect: index = includingAISetup ? 3 : 2
        case .ingest: index = includingAISetup ? 4 : 3
        case .semantic: index = includingAISetup ? 5 : 4
        case .generate: index = includingAISetup ? 6 : 5
        case .sync: index = includingAISetup ? 7 : 6
        }
        return appLocalizedFormat("%lld of %lld", index, total)
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

    var scene: FirstLaunchScene {
        switch self {
        case .aiSetup: return .main
        case .sync: return .main
        default: return .main
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
    let scene: FirstLaunchScene
    let includesAISetup: Bool
    @Binding var isPresented: Bool
    @Binding var step: FirstLaunchStep
    let onFinish: () -> Void
    let content: Content

    init(
        scene: FirstLaunchScene,
        includesAISetup: Bool,
        isPresented: Binding<Bool>,
        step: Binding<FirstLaunchStep>,
        onFinish: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.scene = scene
        self.includesAISetup = includesAISetup
        self._isPresented = isPresented
        self._step = step
        self.onFinish = onFinish
        self.content = content()
    }

    @FocusedValue(\.selectedProjectID) private var selectedProjectID
    @FocusedValue(\.selectedPaperID) private var selectedPaperID
    @EnvironmentObject private var store: Store

    var body: some View {
        content
            .overlayPreferenceValue(FirstLaunchAnchorPreferenceKey.self) { anchors in
                GeometryReader { proxy in
                    if isPresented, step.scene == scene {
                        let targetFrame = targetFrame(from: anchors, proxy: proxy)
                        FirstLaunchCoachmarkBubble(
                            step: step,
                            progressLabel: step.progressLabel(includingAISetup: includesAISetup),
                            targetFrame: targetFrame,
                            selectedProjectID: selectedProjectID,
                            canGoBack: step != .aiSetup,
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
            .onChange(of: selectedProjectID) { _ in
                autoAdvanceIfNeeded()
            }
            .onChange(of: selectedPaperID) { _ in
                autoAdvanceIfNeeded()
            }
            .onReceive(store.$projects) { _ in
                autoAdvanceIfNeeded()
            }
    }

    private func autoAdvanceIfNeeded() {
        guard isPresented, step.scene == scene else { return }
        switch step {
        case .projectCreate:
            if selectedProjectID != nil {
                step = .projectSelect
            }
        case .projectSelect:
            if selectedProjectID != nil {
                step = .ingest
            }
        case .ingest:
            guard let selectedProjectID,
                  let project = store.projects.first(where: { $0.id == selectedProjectID }),
                  !project.papers.isEmpty,
                  selectedPaperID != nil else { return }
            step = .semantic
        default:
            break
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .aiSetup:
            return true
        case .projectCreate, .projectSelect:
            return selectedProjectID != nil
        case .ingest:
            guard let selectedProjectID,
                  let project = store.projects.first(where: { $0.id == selectedProjectID }) else { return false }
            return !project.papers.isEmpty && selectedPaperID != nil
        case .semantic:
            return true
        case .generate:
            return selectedProjectID != nil
        case .sync:
            return true
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
        step = FirstLaunchStep(rawValue: max(step.rawValue - 1, 0)) ?? .projectCreate
    }

    private func goForward() {
        guard canAdvance else { return }
        if step == .semantic {
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
        if #available(macOS 14.0, *) {
            SettingsLink {
                Label(title, systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            .inactiveAwareProminentButtonForeground()
        } else {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            } label: {
                Label(title, systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            .inactiveAwareProminentButtonForeground()
        }
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
        content.foregroundStyle(controlActiveState == .inactive ? .black : .white)
    }
}

extension View {
    func inactiveAwareProminentButtonForeground() -> some View {
        modifier(InactiveAwareProminentButtonForeground())
    }
}

private struct InteractivePipeline: View {
    let stage: IntakeStage

    var body: some View {
        HStack(spacing: 8) {
            ForEach(IntakeStage.allCases) { step in
                VStack(spacing: 4) {
                    Image(systemName: step.icon)
                        .font(.callout)
                    Text(step.title)
                        .font(.caption2)
                }
                .foregroundStyle(step == stage ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(step == stage ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private enum TutorialStepID: Int, CaseIterable {
    case project, ingest, semantic, sync

    var title: String {
        switch self {
        case .project: return appLocalized("1 of 4 · Project")
        case .ingest: return appLocalized("2 of 4 · Add Paper")
        case .semantic: return appLocalized("3 of 4 · Semantic IDs")
        case .sync: return appLocalized("4 of 4 · iCloud Sync")
        }
    }

    var progressLabel: String {
        switch self {
        case .project: return appLocalized("Project workflow")
        case .ingest: return appLocalized("PDF workflow")
        case .semantic: return appLocalized("Annotation workflow")
        case .sync: return appLocalized("Sync workflow")
        }
    }
}

private enum ProjectPreset: String, CaseIterable, Identifiable {
    case research, survey, techReport, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .research: return appLocalized("Research")
        case .survey: return appLocalized("Survey")
        case .techReport: return appLocalized("Tech Report")
        case .custom: return appLocalized("Custom")
        }
    }

    var detail: String {
        switch self {
        case .research:
            return appLocalized("Best for a focused paper and a tight Related Works draft.")
        case .survey:
            return appLocalized("Best for broader coverage and comparison-heavy writing.")
        case .techReport:
            return appLocalized("Best for system papers and engineering context.")
        case .custom:
            return appLocalized("Write your own prompt for full control.")
        }
    }
}

private enum CoachmarkStep: Int, CaseIterable {
    case project, ingest, semantic, sync

    var title: String {
        switch self {
        case .project: return appLocalized("Project")
        case .ingest: return appLocalized("Add Paper")
        case .semantic: return appLocalized("Semantic IDs")
        case .sync: return appLocalized("iCloud Sync")
        }
    }

    var subtitle: String {
        switch self {
        case .project: return appLocalized("Create one project for one paper.")
        case .ingest: return appLocalized("Show how a PDF becomes a paper entry.")
        case .semantic: return appLocalized("Turn paper names into links.")
        case .sync: return appLocalized("Keep the library in sync.")
        }
    }

    var progressLabel: String {
        switch self {
        case .project: return appLocalized("1 / 4")
        case .ingest: return appLocalized("2 / 4")
        case .semantic: return appLocalized("3 / 4")
        case .sync: return appLocalized("4 / 4")
        }
    }

    var arrowSymbol: String {
        switch self {
        case .project: return "arrow.up.left"
        case .ingest: return "arrow.up.left"
        case .semantic: return "arrow.left"
        case .sync: return "arrow.down.right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .project, .ingest: return .topLeading
        case .semantic: return .trailing
        case .sync: return .bottomTrailing
        }
    }

    var padding: EdgeInsets {
        switch self {
        case .project, .ingest:
            return EdgeInsets(top: 18, leading: 18, bottom: 0, trailing: 0)
        case .semantic:
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 18)
        case .sync:
            return EdgeInsets(top: 0, leading: 0, bottom: 18, trailing: 18)
        }
    }
}

private enum IntakeStage: Int, CaseIterable, Identifiable {
    case drop, extract, lookup, ready

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .drop: return appLocalized("Drop PDF")
        case .extract: return appLocalized("Extract")
        case .lookup: return appLocalized("DBLP/arXiv")
        case .ready: return appLocalized("Ready")
        }
    }

    var icon: String {
        switch self {
        case .drop: return "doc.badge.plus"
        case .extract: return "doc.text.magnifyingglass"
        case .lookup: return "network"
        case .ready: return "checkmark.seal"
        }
    }
}
