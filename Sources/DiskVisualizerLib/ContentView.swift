import SwiftUI
import AppKit

public struct ContentView: View {
    @State private var scanner = DiskScanner()
    @State private var currentRoot: FileNode?
    @State private var hoveredNode: FileNode?
    @State private var nodeToTrash: FileNode?
    @State private var selectedVolume: Volume?
    @State private var volumes: [Volume] = listVolumes()
    @State private var hasFullDiskAccess = DiskScanner.hasFullDiskAccess
    @State private var selectedNode: FileNode?
    @State private var inspectorExpanded: Bool = true
    /// Bumps when the underlying file tree is mutated outside of SwiftUI
    /// observation (after removing `@Observable` from `FileNode`), forcing
    /// the sunburst/detail views to redraw while keeping the rest of the
    /// app reactive through standard `@State` changes.
    @State private var treeVersion: UInt = 0
    /// Changes only when the user double-clicks a folder wedge to drill down.
    /// Used to key the sunburst transition so the opening animation does not
    /// run on breadcrumb navigation, scan completion, or trash updates.
    @State private var drillDownID: UUID?

    private var displayedRoot: FileNode? {
        currentRoot ?? scanner.rootNode
    }

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedVolume) {
                Section("Drives") {
                    ForEach(volumes) { volume in
                        VolumeRow(volume: volume)
                            .tag(volume)
                    }
                }

                Section("Actions") {
                    Button("Scan Folder…") {
                        pickFolder()
                    }
                    .disabled(scanner.isScanning)
                    .buttonStyle(.borderedProminent)

                    Button("Rescan") {
                        if let url = scanner.rootNode?.url ?? selectedVolume?.url {
                            scanner.scan(url: url, ignoreCache: true)
                        }
                    }
                    .disabled(scanner.isScanning || scanner.rootNode == nil && selectedVolume == nil)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedVolume) { _, newVolume in
                // Drives the scan off the List's selection binding instead of .onTapGesture,
                // which `List(selection:)` can swallow on macOS — causing "the button doesn't
                // respond" symptoms. The dedupe guard avoids re-scanning the active drive
                // when SwiftUI re-emits the same selection value.
                guard let volume = newVolume, scanner.rootNode?.url != volume.url else { return }
                scanner.scan(url: volume.url)
            }

            // "Selected Details" inspector card lives below the drives list,
            // outside the List entirely so the multi-row layout isn't constrained
            // to sidebar row heights. Only appears once something has been selected.
            if let node = selectedNode {
                Divider()
                SelectedDetailsCard(
                    node: node,
                    totalCapacity: selectedVolume?.totalCapacity,
                    isExpanded: $inspectorExpanded,
                    onRevealInFinder: openInFinder,
                    onTrash: { nodeToTrash = $0 },
                    onOpenInTerminal: openInTerminal
                )
                .id(treeVersion)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(minWidth: 200, idealWidth: 240)
    }

    // MARK: - Detail

    private var detailView: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            VStack(spacing: 0) {
                if !hasFullDiskAccess {
                    fdaBanner
                }
                header
                mainContent
            }
        }
        .frame(minWidth: 700, minHeight: 650)
        .alert(item: $nodeToTrash) { node in
            Alert(
                title: Text("Move to Trash?"),
                message: Text("Are you sure you want to move “\(node.name)” to trash?"),
                primaryButton: .destructive(Text("Move to Trash")) {
                    trash(node: node)
                },
                secondaryButton: .cancel()
            )
        }
        .onKeyPress(.delete) {
            guard let node = hoveredNode else { return .ignored }
            nodeToTrash = node
            return .handled
        }
        .onChange(of: scanner.isScanning) { _, scanning in
            if scanning {
                currentRoot = nil
                // A scan replaces the entire FileNode tree. selectedNode from the
                // old tree would dangle — drop it so the inspector doesn't render
                // a tombstone pointing at a node no longer reachable.
                selectedNode = nil
                drillDownID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = DiskScanner.hasFullDiskAccess
        }
    }

    private var fdaBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access required")
                    .fontWeight(.semibold)
                Text("Protected folders are skipped until access is granted in System Settings.")
                    .font(.caption)
            }
            Spacer()
            Button("Open Privacy Settings") {
                openPrivacySettings()
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.yellow.opacity(0.2))
        .cornerRadius(6)
        .padding([.top, .horizontal])
    }

    private var header: some View {
        HStack(spacing: 16) {
            if displayedRoot != nil {
                BreadcrumbView(
                    currentRoot: currentRoot,
                    appRoot: scanner.rootNode
                ) { selected in
                    // Only double-click drill-down should animate the sunburst.
                    currentRoot = selected
                }
            }

            Spacer()

            if scanner.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text(scanner.isCancelling ? "Cancelling…" : "Scanning…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(scanner.isCancelling ? "Cancelling…" : "Cancel") {
                    scanner.cancel()
                }
                .disabled(scanner.isCancelling)
            }

            if let error = scanner.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .padding()
    }

    private var mainContent: some View {
        HStack(spacing: 0) {
            if scanner.isScanning {
                loadingView
            } else if let root = displayedRoot {
                SunburstView(
                    root: root,
                    hoveredNode: $hoveredNode,
                    onDoubleTap: { node in
                        if node.isDirectory && !node.children.isEmpty {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                // New drill-down identity: drives the Canvas-internal
                                // entrance animation and resets the canvas camera state.
                                // The canvas itself is reused, so only one instance is
                                // rendered and animated.
                                drillDownID = UUID()
                                currentRoot = node
                                // Selection follows the drill: keeps inspector in sync.
                                selectedNode = node
                            }
                        }
                    },
                    onSelect: { node in
                        selectedNode = node
                        inspectorExpanded = true
                    },
                    onOpenInFinder: openInFinder,
                    treeVersion: treeVersion,
                    drillDownID: drillDownID
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                DetailPanel(
                    root: root,
                    selected: hoveredNode,
                    onDelete: { node in
                        nodeToTrash = node
                    },
                    onSelect: { node in
                        selectedNode = node
                        inspectorExpanded = true
                    }
                )
                .frame(width: 280)
            } else {
                placeholder
            }
        }
    }

    private var loadingView: some View {
        HStack(spacing: 0) {
            Spacer()
            VStack(spacing: 32) {
                Spacer()
                VStack(spacing: 24) {
                    PulsatingFlower()
                        .frame(width: 240, height: 240)

                    VStack(spacing: 8) {
                        Text(scanner.isCancelling ? "Stopping scan…" : "Estimating disk usage…")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)

                        if scanner.scannedBytes > 0 || scanner.scannedItemCount > 0 {
                            Text("\(formattedBytes(scanner.scannedBytes)) scanned across \(scanner.scannedItemCount) items")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            Text("Preparing scan…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.15), radius: 24, x: 0, y: 12)
                )
                Spacer()
            }
            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("Select a drive or click “Scan Folder…”")
                .font(.title2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { result in
            if result == .OK, let url = panel.url {
                Task { @MainActor in
                    scanner.scan(url: url)
                }
            }
        }
    }

    private func trash(node: FileNode) {
        let url = node.url
        var resultingURL: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)

            // If we just deleted the current drill-down root, pop up.
            if currentRoot == node {
                currentRoot = node.parent
            }
            // Clear the inspector selection when trashing it OR any ancestor of it:
            // the right DetailPanel's Trash button / Delete key fires against
            // hoveredNode (not selectedNode), so a sibling/ancestor trash can
            // leave the inspector showing a now-unreachable leaf.
            if let sel = selectedNode, sel == node || isAncestor(node, of: sel) {
                selectedNode = nil
            }
            node.removeFromTree()
            // Defer the segment-rebuild trigger so SwiftUI can batch multiple
            // trash updates (e.g. trashing a folder with tracked children).
            DispatchQueue.main.async {
                self.treeVersion += 1
            }
        } catch {
            scanner.errorMessage = "Could not move to trash: \(error.localizedDescription)"
        }
    }

    /// Walk `child.parent` chain; return true if `ancestor` is reached.
    private func isAncestor(_ ancestor: FileNode, of child: FileNode) -> Bool {
        var current = child.parent
        while let p = current {
            if p == ancestor { return true }
            current = p.parent
        }
        return false
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openInFinder(_ node: FileNode) {
        // `activateFileViewerSelecting` opens Finder with this URL selected,
        // whether it's a file or a folder. Works for any node hit on the sunburst,
        // including the scanned root in the center hole.
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    private func openInTerminal(_ node: FileNode) {
        // Open Terminal.app pointed at this path. `/usr/bin/open` with `-a` is
        // argv-based (no shell), so embedded spaces/quotes in the path are safe.
        // NSWorkspace.shared.open works too but doesn't `cd` inside the new
        // Terminal window; Process + `/usr/bin/open` does.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal.app", node.url.path]
        try? process.run()
    }
}

struct VolumeRow: View {
    let volume: Volume

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(volume.name)
                .font(.system(size: 13, weight: .medium))
            HStack {
                Text(volume.formattedUsed)
                Text("/")
                Text(volume.formattedTotal)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: Double(volume.usedCapacity), total: Double(max(volume.totalCapacity, 1)))
                .progressViewStyle(.linear)
                .scaleEffect(x: 1, y: 0.6, anchor: .leading)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Selected Details inspector card

struct SelectedDetailsCard: View {
    let node: FileNode
    let totalCapacity: Int64?
    @Binding var isExpanded: Bool
    let onRevealInFinder: (FileNode) -> Void
    let onTrash: (FileNode) -> Void
    let onOpenInTerminal: (FileNode) -> Void

    private var percentOfCapacity: Double {
        guard let cap = totalCapacity, cap > 0 else { return 0 }
        return min(1.0, Double(node.size) / Double(cap))
    }

    private var percentLabel: String {
        guard totalCapacity != nil else { return "—" }
        return String(format: "%.1f%%", min(100, percentOfCapacity * 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — clickable chevron toggles the body. Always visible when
            // selectedNode is non-nil so the user can collapse to a header band.
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Selected Details")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: node.iconName)
                        .imageScale(.small)
                        .foregroundStyle(.tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    nameRow
                    sizeRow
                    if node.isDirectory {
                        HStack(spacing: 5) {
                            Image(systemName: "tray.full")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(node.childSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(node.formattedModificationDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    pathRow
                    actionButtons
                }
                .padding(.top, 6)
            }
        }
    }

    private var nameRow: some View {
        HStack(spacing: 6) {
            Image(systemName: node.iconName)
                .foregroundStyle(.tint)
            Text(node.name)
                .font(.system(.subheadline, design: .default).weight(.medium))
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private var sizeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(node.formattedSize)
                    .font(.title3.weight(.semibold))
                Spacer()
                if totalCapacity != nil {
                    Text(percentLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if totalCapacity != nil {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * percentOfCapacity)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private var pathRow: some View {
        HStack(spacing: 4) {
            Text(node.url.path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.setString(node.url.path, forType: .string)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Copy path")
            .accessibilityLabel("Copy path")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button {
                onRevealInFinder(node)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 14, weight: .medium))
            }
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal in Finder")

            Button {
                onTrash(node)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
            }
            .help("Move to Trash")
            .accessibilityLabel("Move to Trash")

            Button {
                onOpenInTerminal(node)
            } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 14, weight: .medium))
            }
            .help("Open in Terminal")
            .accessibilityLabel("Open in Terminal")
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }
}

// MARK: - Pulsating flower loading indicator

struct PulsatingFlower: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `0` collapses every petal to the center of the view; `1` reaches the
    /// resting radius and we hand off to the steady pulse loop. The
    /// `easeOut(duration: 0.6)` "spin out" applies this on appear so the
    /// petals feel like they are flying outward instead of just popping in.
    @State private var spinProgress: CGFloat = 0
    /// Continuously-running sine phase for the steady pulse after the
    /// entrance has finished. Independent from `spinProgress` so the two
    /// animations compose without stomping each other.
    @State private var pulsePhase: Double = 0

    private let petalCount = 12
    private let petalRadius: CGFloat = 56

    var body: some View {
        ZStack {
            ForEach(0..<petalCount, id: \.self) { index in
                petal(at: index)
            }

            // Center core with a soft glow. Scales with `spinProgress` so
            // the whole flower blooms outward consistently.
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 60, height: 60)
                    .blur(radius: 8)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.3)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 28
                        )
                    )
                    .frame(width: 36, height: 36)
            }
            .scaleEffect(reduceMotion ? 1.0 : Double(spinProgress))
            .opacity(reduceMotion ? 1.0 : Double(spinProgress))
        }
        .onAppear {
            guard !reduceMotion else { return }
            // Petals fly out from center to their rest radius over 600ms.
            // The steady pulse takes over via the second concurrent
            // animation; both start on the same frame so there is no visible
            // handoff gap. `pulsePhase` ends at 1.0 exactly; `sin(0)=0` simply
            // means `pulseScale = 1 + 0.18·0 = 1.0`, so the spin-out scale is
            // `spin·1.0` — already smooth, no special seeding needed.
            withAnimation(.easeOut(duration: 0.6)) {
                spinProgress = 1.0
            }
            // Fast traveling pop wave: each petal scales from 0 to 1.5×
            // and fades in/out as the wave peak orbits the ring.
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                pulsePhase = 1.0
            }
        }
    }

    private func petal(at index: Int) -> some View {
        let angle = Double(index) * (2.0 * .pi / Double(petalCount))
        let finalX = petalRadius * cos(angle)
        let finalY = petalRadius * sin(angle)
        // Spin-out: offset is interpolated between center and final position.
        let progress = Double(spinProgress)
        let x = finalX * progress
        let y = finalY * progress
        let hue = (0.55 + Double(index) / Double(petalCount)).truncatingRemainder(dividingBy: 1.0)
        let color = Color(hue: hue, saturation: 0.75, brightness: 0.95)

        return Circle()
            .fill(
                LinearGradient(
                    colors: [color, color.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 20, height: 20)
            .offset(x: x, y: y)
            .scaleEffect(reduceMotion ? 1.0 : scaleMultiplier(index: index))
            .opacity(reduceMotion ? 0.85 : opacityMultiplier(index: index))
            .shadow(color: color.opacity(0.35), radius: 4, x: 0, y: 0)
    }

    /// Combines the entrance growth with the steady-state pulse sine.
    /// `guard spin > 0` keeps the petals invisible before `.onAppear` runs,
    /// which prevents a single-frame flash at their final radius.
    private func scaleMultiplier(index: Int) -> CGFloat {
        let spin = Double(spinProgress)
        guard spin > 0 else { return 0 }
        // Pop from 0 to 1.5× and back to 0, following the traveling wave.
        return CGFloat(spin * popWave(index: index) * 1.5)
    }

    /// Normalized [0, 1] traveling wave. When `pulsePhase` animates 0 → 1,
    /// the wave peak travels around the ring, causing each petal to scale and
    /// fade in and out like a bubble popping.
    private func popWave(index: Int) -> Double {
        let offset = Double(index) / Double(petalCount)
        return 0.5 + 0.5 * sin((pulsePhase + offset) * 2.0 * .pi)
    }

    private func opacityMultiplier(index: Int) -> Double {
        let spin = Double(spinProgress)
        guard spin > 0 else { return 0 }
        return spin * popWave(index: index)
    }
}
