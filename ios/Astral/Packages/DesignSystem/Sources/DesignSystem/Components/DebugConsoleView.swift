import SwiftUI
import Core

/// In-app debug console. Shows recent log entries from AstralLogger.
/// Triggered by shaking the device (DEBUG builds only).
public struct DebugConsoleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [LogEntry] = []
    @State private var filterLevel: LogLevel? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(nil, label: "All")
                        filterChip(.network, label: "Network")
                        filterChip(.error, label: "Errors")
                        filterChip(.warning, label: "Warnings")
                        filterChip(.info, label: "Info")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background(Color.black)

                // Log entries
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredEntries) { entry in
                            logRow(entry)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 40)
                }
            }
            .background(Color.black)
            .navigationTitle("Debug Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        AstralLogger.shared.clear()
                        entries = []
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AstralColors.gold)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear { entries = AstralLogger.shared.entries }
    }

    private var filteredEntries: [LogEntry] {
        guard let level = filterLevel else { return entries }
        return entries.filter { $0.level == level }
    }

    @ViewBuilder
    private func filterChip(_ level: LogLevel?, label: String) -> some View {
        let isActive = filterLevel == level
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { filterLevel = level }
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? AstralColors.gold.opacity(0.25) : Color.white.opacity(0.08))
                .foregroundStyle(isActive ? AstralColors.gold : .white.opacity(0.7))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second().secondFraction(.fractional(2)))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 65, alignment: .leading)

            Text(entry.level.emoji)
                .font(.system(size: 10))
                .frame(width: 16)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(logColor(entry.level))
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }

    private func logColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: .white.opacity(0.7)
        case .warning: .yellow
        case .error: .red
        case .network: .cyan
        }
    }
}

// MARK: - Shake Gesture Detector

/// Wraps content and presents the debug console on device shake.
/// Only active in DEBUG builds.
public struct DebugShakeDetector<Content: View>: View {
    let content: Content
    @State private var showConsole = false

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .onShake {
                showConsole = true
            }
            .sheet(isPresented: $showConsole) {
                DebugConsoleView()
            }
    }
}

// MARK: - Shake Gesture (UIKit bridge)

private extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.overlay(ShakeDetectorView(action: action).frame(width: 0, height: 0))
    }
}

private struct ShakeDetectorView: UIViewControllerRepresentable {
    let action: () -> Void

    func makeUIViewController(context: Context) -> ShakeViewController {
        ShakeViewController(action: action)
    }

    func updateUIViewController(_ uiViewController: ShakeViewController, context: Context) {}
}

private class ShakeViewController: UIViewController {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            action()
        }
    }
}
