import SwiftUI

enum CodeBarPresentationMode: String, CaseIterable, Identifiable {
    case statusBar
    case island

    var id: String { rawValue }
    static let `default`: CodeBarPresentationMode = .statusBar

    var title: String {
        switch self {
        case .statusBar:
            return "状态栏"
        case .island:
            return "刘海"
        }
    }

    var description: String {
        switch self {
        case .statusBar:
            return "使用菜单栏状态项和弹出面板"
        case .island:
            return "使用屏幕顶部刘海面板"
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> CodeBarPresentationMode {
        guard let rawValue = defaults.string(forKey: Constants.presentationModeKey),
              let mode = CodeBarPresentationMode(rawValue: rawValue) else {
            return .default
        }
        return mode
    }

    static func save(_ mode: CodeBarPresentationMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: Constants.presentationModeKey)
    }
}

extension Notification.Name {
    static let codeBarPresentationModeChanged = Notification.Name("codeBarPresentationModeChanged")
}

enum CodeBarIslandState: Equatable {
    case closed
    case opened

    var isOpened: Bool {
        self == .opened
    }
}

enum CodeBarIslandTone: Equatable {
    case normal
    case warning
    case error
    case loading
}

struct CodeBarIslandCompactStatus: Equatable {
    let title: String
    let detail: String
    let tone: CodeBarIslandTone
    let platform: PlatformType?
}

enum CodeBarIslandCompactStatusBuilder {
    static func status(
        modules: [MonitorModule],
        usages: [String: PlatformUsageData],
        errors: [String: String]
    ) -> CodeBarIslandCompactStatus {
        let visibleModules = modules.filter { module in
            module.isMonitoringEnabled && module.showInMenuBar && module.isValid
        }

        guard !visibleModules.isEmpty else {
            return CodeBarIslandCompactStatus(
                title: "CodeBar",
                detail: "未配置",
                tone: .normal,
                platform: nil
            )
        }

        if let erroredModule = visibleModules.first(where: { errors[$0.id] != nil }) {
            return CodeBarIslandCompactStatus(
                title: erroredModule.platform.shortName,
                detail: "刷新异常",
                tone: .error,
                platform: erroredModule.platform
            )
        }

        let candidates = visibleModules.compactMap { module -> StatusCandidate? in
            guard let usage = usages[module.id] else { return nil }
            let visibleItems = visibleUsageItems(from: usage, module: module)
            guard let item = mostConstrainedItem(from: visibleItems, displayMode: module.percentDisplayMode) else {
                return StatusCandidate(
                    module: module,
                    detail: usage.planType,
                    tone: .normal,
                    score: 0
                )
            }

            return StatusCandidate(
                module: module,
                detail: UsageStatusFormatting.compactPercentText(for: item, displayMode: module.percentDisplayMode),
                tone: module.percentDisplayMode.isNearLimit(item) ? .warning : .normal,
                score: constraintScore(for: item, displayMode: module.percentDisplayMode)
            )
        }

        if let best = candidates.max(by: { $0.score < $1.score }) {
            return CodeBarIslandCompactStatus(
                title: best.module.platform.shortName,
                detail: best.detail,
                tone: best.tone,
                platform: best.module.platform
            )
        }

        let firstModule = visibleModules[0]
        return CodeBarIslandCompactStatus(
            title: firstModule.platform.shortName,
            detail: "刷新中",
            tone: .loading,
            platform: firstModule.platform
        )
    }

    private struct StatusCandidate {
        let module: MonitorModule
        let detail: String
        let tone: CodeBarIslandTone
        let score: Double
    }

    private static func visibleUsageItems(from usage: PlatformUsageData, module: MonitorModule) -> [UsageItem] {
        guard !module.displayKeys.isEmpty else { return usage.items }
        return usage.items.filter { module.displayKeys.contains($0.key) }
    }

    private static func mostConstrainedItem(from items: [UsageItem], displayMode: UsagePercentDisplayMode) -> UsageItem? {
        items.max { lhs, rhs in
            constraintScore(for: lhs, displayMode: displayMode) < constraintScore(for: rhs, displayMode: displayMode)
        }
    }

    private static func constraintScore(for item: UsageItem, displayMode: UsagePercentDisplayMode) -> Double {
        switch displayMode {
        case .used:
            return displayMode.percent(for: item)
        case .remaining:
            return 100 - displayMode.percent(for: item)
        }
    }
}

struct CodeBarIslandDisplayGeometry: Equatable {
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let hasNotch: Bool
    let notchGapWidth: CGFloat
    let notchMinX: CGFloat
    let notchMaxX: CGFloat
    let notchCenterX: CGFloat

    init(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame

        if let left = auxiliaryTopLeftArea,
           let right = auxiliaryTopRightArea,
           left.maxX < right.minX,
           left.width >= Constants.islandClosedLeftExtensionWidth,
           right.width > 0 {
            hasNotch = true
            notchGapWidth = right.minX - left.maxX
            notchMinX = left.maxX
            notchMaxX = right.minX
            notchCenterX = (left.maxX + right.minX) / 2
        } else {
            hasNotch = false
            notchGapWidth = 0
            notchMinX = screenFrame.midX
            notchMaxX = screenFrame.midX
            notchCenterX = screenFrame.midX
        }
    }

    var closedSize: CGSize {
        CGSize(
            width: hasNotch
                ? notchGapWidth + Constants.islandClosedLeftExtensionWidth
                : Constants.islandClosedWidth,
            height: Constants.islandClosedHeight
        )
    }

    var closedFrame: CGRect {
        guard hasNotch else {
            return CodeBarIslandLayout.frame(screenFrame: screenFrame, size: closedSize)
        }
        return CGRect(
            x: notchMinX - Constants.islandClosedLeftExtensionWidth,
            y: screenFrame.maxY - closedSize.height,
            width: closedSize.width,
            height: closedSize.height
        )
    }

    var closedLeftExtensionFrame: CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: hasNotch ? Constants.islandClosedLeftExtensionWidth : closedSize.width,
            height: closedSize.height
        )
    }

    var closedNotchGapFrame: CGRect {
        CGRect(
            x: closedLeftExtensionFrame.maxX,
            y: 0,
            width: notchGapWidth,
            height: closedSize.height
        )
    }

    func openedFrame(contentHeight: CGFloat) -> CGRect {
        CodeBarIslandLayout.openedFrame(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            contentHeight: contentHeight,
            centerX: notchCenterX
        )
    }
}

enum CodeBarIslandLayout {
    static func frame(screenFrame: CGRect, size: CGSize, centerX: CGFloat? = nil) -> CGRect {
        let desiredOriginX = (centerX ?? screenFrame.midX) - size.width / 2
        let maximumOriginX = screenFrame.maxX - size.width
        let originX = min(max(desiredOriginX, screenFrame.minX), maximumOriginX)
        let originY = screenFrame.maxY - size.height
        return CGRect(origin: CGPoint(x: originX, y: originY), size: size)
    }

    static func openedFrame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        contentHeight: CGFloat,
        centerX: CGFloat? = nil
    ) -> CGRect {
        let cappedHeight = openedHeight(contentHeight: contentHeight, visibleFrame: visibleFrame)
        let size = CGSize(width: Constants.islandOpenedWidth, height: cappedHeight)
        let frame = frame(screenFrame: screenFrame, size: size, centerX: centerX)
        if frame.minY < visibleFrame.minY {
            return frame.offsetBy(dx: 0, dy: visibleFrame.minY - frame.minY)
        }
        return frame
    }

    static func openedHeight(
        contentHeight: CGFloat,
        visibleFrame: CGRect
    ) -> CGFloat {
        let desiredHeight = max(Constants.islandClosedHeight, contentHeight)
        let maximumHeight = min(Constants.islandOpenedMaximumHeight, visibleFrame.height)
        return min(desiredHeight, maximumHeight)
    }

    static func openedContentHeight(panelHeight: CGFloat) -> CGFloat {
        max(0, panelHeight - Constants.islandClosedHeight - 16)
    }
}

struct CodeBarIslandShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topRadius = min(max(topCornerRadius, 0), rect.height / 2)
        let bottomRadius = min(max(bottomCornerRadius, 0), rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )

        return path
    }
}

struct CodeBarIslandView: View {
    @ObservedObject var tracker: UsageTracker
    @ObservedObject var updateChecker: UpdateChecker
    let state: CodeBarIslandState
    let onOpen: () -> Void
    let onClose: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void
    var maxContentHeight: CGFloat = Constants.islandOpenedMaximumHeight - Constants.islandClosedHeight - 16
    var notchGapWidth: CGFloat = 0

    private var isOpened: Bool {
        state.isOpened
    }

    private var compactStatus: CodeBarIslandCompactStatus {
        CodeBarIslandCompactStatusBuilder.status(
            modules: tracker.menuBarModules,
            usages: tracker.moduleUsages,
            errors: tracker.moduleErrors
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: Constants.islandClosedHeight)

            if isOpened {
                openedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(.horizontal, isOpened ? 18 : 14)
        .padding(.bottom, isOpened ? 16 : 0)
        .frame(
            width: isOpened ? Constants.islandOpenedWidth : compactWidth,
            alignment: .top
        )
        .background(Color.black)
        .clipShape(CodeBarIslandShape(
            topCornerRadius: isOpened ? 18 : 6,
            bottomCornerRadius: isOpened ? 26 : 16
        ))
        .shadow(color: isOpened ? Color.black.opacity(0.55) : .clear, radius: 10)
        .preferredColorScheme(.dark)
        .onTapGesture {
            if !isOpened { onOpen() }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: state)
    }

    private var compactWidth: CGFloat {
        notchGapWidth > 0
            ? notchGapWidth + Constants.islandClosedLeftExtensionWidth
            : Constants.islandClosedWidth
    }

    @ViewBuilder
    private var header: some View {
        if notchGapWidth > 0, isOpened {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    platformIdentity
                    compactDetail
                    closeButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: notchGapWidth)

                Color.clear
                    .frame(maxWidth: .infinity)
            }
        } else if notchGapWidth > 0 {
            HStack(spacing: 8) {
                platformIdentity
                compactDetail
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 8) {
                platformIdentity
                compactDetail
                Spacer(minLength: 0)
                if isOpened { closeButton }
            }
        }
    }

    private var platformIdentity: some View {
        HStack(spacing: 8) {
            if let platform = compactStatus.platform {
                PlatformLogoView(platform: platform, size: 14)
            } else {
                Image(systemName: "menubar.dock.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
            }

            Text(compactStatus.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(.white)
    }

    @ViewBuilder
    private var compactDetail: some View {
        if !compactStatus.detail.isEmpty {
            Text(compactStatus.detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(toneColor)
                .lineLimit(1)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .help("关闭")
    }

    private var toneColor: Color {
        switch compactStatus.tone {
        case .normal:
            return .white.opacity(0.76)
        case .warning:
            return .orange
        case .error:
            return .red
        case .loading:
            return .white.opacity(0.5)
        }
    }

    private var openedContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            MenuBarView(
                tracker: tracker,
                updateChecker: updateChecker,
                chrome: .island,
                onSettings: onSettings,
                onQuit: onQuit
            )
            .padding(.trailing, 4)
        }
        .frame(maxHeight: maxContentHeight, alignment: .top)
    }
}

#if !CODEBAR_BEHAVIOR_TESTS
#Preview {
    CodeBarIslandView(
        tracker: UsageTracker.shared,
        updateChecker: UpdateChecker.shared,
        state: .opened,
        onOpen: {},
        onClose: {},
        onSettings: {},
        onQuit: {}
    )
}
#endif
