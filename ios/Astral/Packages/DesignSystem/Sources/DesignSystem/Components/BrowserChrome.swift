import SwiftUI

// Shared chrome for the comic and fan fiction source browsers.

/// Horizontal source chips. The selected source is filled gold.
public struct BrowserSourceChips<Source: Hashable>: View {
    let sources: [Source]
    @Binding var selection: Source
    let label: (Source) -> String
    let isDisabled: Bool

    public init(sources: [Source], selection: Binding<Source>, isDisabled: Bool = false, label: @escaping (Source) -> String) {
        self.sources = sources; self._selection = selection; self.isDisabled = isDisabled; self.label = label
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sources, id: \.self) { source in
                    let selected = source == selection
                    Button { selection = source } label: {
                        Text(label(source))
                            .font(.subheadline.weight(selected ? .semibold : .medium))
                            .foregroundStyle(selected ? AstralColors.background : AstralColors.body)
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(selected ? AstralColors.gold : AstralColors.elevated, in: Capsule())
                    }
                    .buttonStyle(PressButtonStyle(scale: 0.94))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

/// Address field that shows the site's host until it is edited, like Safari.
/// Text that isn't an address is passed to `onSubmit` for a source search.
public struct BrowserAddressBar: View {
    @Binding var text: String
    let url: URL?
    let progress: Double
    let isLoading: Bool
    let prompt: String
    let onSubmit: () -> Void
    let onReload: () -> Void
    let onStop: () -> Void
    @FocusState private var focused: Bool

    public init(text: Binding<String>, url: URL?, progress: Double, isLoading: Bool, prompt: String = "Search or enter address",
                onSubmit: @escaping () -> Void, onReload: @escaping () -> Void, onStop: @escaping () -> Void) {
        self._text = text; self.url = url; self.progress = progress; self.isLoading = isLoading; self.prompt = prompt
        self.onSubmit = onSubmit; self.onReload = onReload; self.onStop = onStop
    }

    private var host: String {
        guard let host = url?.host() else { return prompt }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: url?.scheme == "https" ? "lock.fill" : "magnifyingglass")
                .font(.caption).foregroundStyle(AstralColors.muted)
            TextField(prompt, text: $text)
                .focused($focused)
                .font(.subheadline)
                .foregroundStyle(focused ? AstralColors.white : .clear)
                .tint(focused ? AstralColors.gold : .clear)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .onSubmit { focused = false; onSubmit() }
                .overlay {
                    if !focused {
                        Text(host)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(url == nil ? AstralColors.muted : AstralColors.white)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(AstralColors.elevated)
                            .contentShape(Rectangle())
                            .onTapGesture { text = url?.absoluteString ?? ""; focused = true }
                            .accessibilityLabel("Address, \(host)")
                            .accessibilityAddTraits(.isButton)
                    }
                }
            if focused {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(AstralColors.muted) }
                    .accessibilityLabel("Clear address")
            } else {
                Button { isLoading ? onStop() : onReload() } label: {
                    Image(systemName: isLoading ? "xmark" : "arrow.clockwise").font(.subheadline.weight(.semibold))
                        .foregroundStyle(AstralColors.body).frame(width: 28, height: 28)
                }
                .accessibilityLabel(isLoading ? "Stop loading" : "Reload")
            }
        }
        .padding(.leading, 14).padding(.trailing, 8)
        .frame(height: 42)
        .background(AstralColors.elevated, in: Capsule())
        .overlay(alignment: .bottom) {
            if isLoading {
                GeometryReader { proxy in
                    Capsule().fill(AstralColors.gold)
                        .frame(width: max(12, proxy.size.width * min(1, max(0.05, progress))), height: 2.5)
                        .animation(.easeOut(duration: 0.2), value: progress)
                }
                .frame(height: 2.5)
                .padding(.horizontal, 18)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isLoading)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// What the browser's primary action can do for the page that is open.
public enum BrowserImportState: Equatable {
    case unavailable(String)
    case ready(String)
    case inLibrary(String)
    case importing(String)
}

/// Floating bottom bar: navigation on the sides, the import action in the middle.
public struct BrowserBottomBar: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let state: BrowserImportState
    let onBack: () -> Void
    let onForward: () -> Void
    let onImport: () -> Void
    let onOpen: () -> Void
    let onCancel: () -> Void
    let menu: AnyView

    public init<Menu: View>(canGoBack: Bool, canGoForward: Bool, state: BrowserImportState,
                            onBack: @escaping () -> Void, onForward: @escaping () -> Void,
                            onImport: @escaping () -> Void, onOpen: @escaping () -> Void, onCancel: @escaping () -> Void,
                            @ViewBuilder menu: () -> Menu) {
        self.canGoBack = canGoBack; self.canGoForward = canGoForward; self.state = state
        self.onBack = onBack; self.onForward = onForward; self.onImport = onImport; self.onOpen = onOpen; self.onCancel = onCancel
        self.menu = AnyView(menu())
    }

    public var body: some View {
        HStack(spacing: 4) {
            navButton("chevron.backward", label: "Back", enabled: canGoBack, action: onBack)
            navButton("chevron.forward", label: "Forward", enabled: canGoForward, action: onForward)
            primary.frame(maxWidth: .infinity)
            Menu { menu } label: {
                Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: 40, height: 40)
            }
            .foregroundStyle(AstralColors.body)
            .accessibilityLabel("More browser actions")
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(AstralColors.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(.horizontal, 12).padding(.bottom, 8)
        .animation(AstralAnimation.smooth, value: state)
    }

    private func navButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 40, height: 40)
        }
        .foregroundStyle(enabled ? AstralColors.white : AstralColors.muted.opacity(0.5))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var primary: some View {
        switch state {
        case .unavailable(let hint):
            Text(hint).font(.footnote).foregroundStyle(AstralColors.muted)
                .lineLimit(1).minimumScaleFactor(0.85)
        case .ready(let title):
            Button(action: onImport) {
                Label(title, systemImage: "plus").font(.subheadline.weight(.semibold))
                    .foregroundStyle(AstralColors.background)
                    .padding(.horizontal, 16).frame(height: 38)
                    .background(AstralColors.gold, in: Capsule())
            }
            .buttonStyle(PressButtonStyle(scale: 0.95))
            .accessibilityIdentifier("browser.import")
        case .inLibrary(let title):
            Button(action: onOpen) {
                Label(title, systemImage: "checkmark").font(.subheadline.weight(.semibold))
                    .foregroundStyle(AstralColors.gold)
                    .padding(.horizontal, 16).frame(height: 38)
                    .background(AstralColors.gold.opacity(0.15), in: Capsule())
            }
            .buttonStyle(PressButtonStyle(scale: 0.95))
        case .importing(let step):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(AstralColors.gold)
                Text(step).font(.footnote.weight(.medium)).foregroundStyle(AstralColors.body).lineLimit(1)
                Button("Cancel", action: onCancel).font(.footnote.weight(.semibold)).foregroundStyle(AstralColors.gold)
            }
        }
    }
}

/// Short confirmation after an import, with a direct way to start reading.
public struct BrowserImportBanner: View {
    let title: String
    let primaryTitle: String
    let onPrimary: () -> Void
    let onDismiss: () -> Void

    public init(title: String, primaryTitle: String, onPrimary: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.title = title; self.primaryTitle = primaryTitle; self.onPrimary = onPrimary; self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(AstralColors.success)
            VStack(alignment: .leading, spacing: 1) {
                Text("Added to library").font(.caption).foregroundStyle(AstralColors.muted)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AstralColors.white).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(primaryTitle, action: onPrimary)
                .font(.subheadline.weight(.semibold)).foregroundStyle(AstralColors.background)
                .padding(.horizontal, 14).frame(height: 32)
                .background(AstralColors.gold, in: Capsule())
            Button(action: onDismiss) { Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: 28, height: 28) }
                .foregroundStyle(AstralColors.muted).accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(AstralColors.border, lineWidth: 0.5))
        .padding(.horizontal, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Turns address-bar text into a URL: an address when it looks like one,
/// otherwise the source's own search page.
public enum BrowserAddress {
    public static func url(for input: String, search: (String) -> URL?) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://"), let url = URL(string: text), url.host() != nil { return url }
        if !text.contains(" "), text.contains("."), let url = URL(string: "https://" + text), url.host() != nil { return url }
        return search(text)
    }

    public static func query(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? text
    }
}
