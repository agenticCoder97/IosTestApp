import SwiftUI
import Core
import DesignSystem
import ComicFeature
import FanficFeature

struct RootView: View {
    @State private var appState = AppState()
    @State private var showLanding = !CommandLine.arguments.contains("--uitesting")

    var body: some View {
        DebugShakeDetector {
            ZStack {
                if showLanding {
                    MorphLandingView { tab in
                        appState.activeTab = tab
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                            showLanding = false
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    Group {
                        switch appState.activeTab {
                        case .comic:
                            ComicTabView(onSwitchTab: { appState.activeTab = .fanfic })
                        case .fanfic:
                            FanficTabView(onSwitchTab: { appState.activeTab = .comic })
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
        }
        .environment(appState)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Morph Landing View

private struct MorphLandingView: View {
    let onSelect: (AppTab) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Phase tracking
    @State private var phase = 0 // 0=blank, 1=blobAppear, 2=expand, 3=morph, 4=ready

    // Gold orb (comics) — starts as a tiny dot in absolute top-left corner
    @State private var goldSize: CGFloat = 10
    @State private var goldOffset: CGSize = .zero // set dynamically onAppear
    @State private var goldRotation: Double = -30
    @State private var goldOpacity: Double = 0
    @State private var goldBlobSkew: CGFloat = 1.35
    @State private var goldCornerRadius: CGFloat = 100
    @State private var goldGlow: Double = 0

    // Blue orb (fanfic) — starts as a tiny dot in absolute bottom-right corner
    @State private var blueSize: CGFloat = 8
    @State private var blueOffset: CGSize = .zero // set dynamically onAppear
    @State private var blueRotation: Double = 22
    @State private var blueOpacity: Double = 0
    @State private var blueBlobSkew: CGFloat = 0.75
    @State private var blueCornerRadius: CGFloat = 100
    @State private var blueGlow: Double = 0

    // Screen-relative offsets calculated from geometry
    @State private var screenSize: CGSize = .zero

    // Content inside orbs
    @State private var contentRevealGold: Double = 0
    @State private var contentRevealBlue: Double = 0
    @State private var contentSlide: CGFloat = 20 // internal content slides up

    // Title + labels
    @State private var titleScale: CGFloat = 0.5
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var labelOpacity: Double = 0
    @State private var titleBlur: CGFloat = 8

    // Cancellation guard for phase completion chain
    @State private var animationToken = UUID()

    // Ambient
    @State private var ambientShift: Bool = false

    private let goldColor = AstralColors.gold
    private let blueColor = Color(hex: 0x5C9DFF)

    var body: some View {
        GeometryReader { geo in
        ZStack {
            AstralColors.background.ignoresSafeArea()

            // Ambient background glow
            Circle()
                .fill(goldColor.opacity(0.05))
                .frame(width: 350, height: 350)
                .blur(radius: 100)
                .offset(x: ambientShift ? 60 : -60, y: ambientShift ? -40 : 40)

            Circle()
                .fill(blueColor.opacity(0.04))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: ambientShift ? -50 : 50, y: ambientShift ? 50 : -50)

            // Title — centered, appears in phase 3
            VStack(spacing: 10) {
                Text("Astral")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(AstralColors.white)
                    .blur(radius: titleBlur)
                    .scaleEffect(titleScale)
                    .opacity(titleOpacity)

                Text("What are you reading?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AstralColors.muted)
                    .opacity(subtitleOpacity)
            }
            .offset(y: -80)

            // Gold orb — full screen coordinate space
            goldOrb
                .scaleEffect(goldSize / 130)
                .offset(goldOffset)
                .rotationEffect(.degrees(goldRotation))
                .opacity(goldOpacity)

            // Blue orb — full screen coordinate space
            blueOrb
                .scaleEffect(blueSize / 130)
                .offset(blueOffset)
                .rotationEffect(.degrees(blueRotation))
                .opacity(blueOpacity)

            // Labels — positioned below the orbs at final resting Y
            HStack(spacing: 80) {
                Text("Comics")
                    .font(AstralTypography.bodyMedium)
                    .foregroundStyle(AstralColors.white)
                Text("Fan Fiction")
                    .font(AstralTypography.bodyMedium)
                    .foregroundStyle(AstralColors.white)
            }
            .offset(y: 110)
            .opacity(labelOpacity)

            // Tap zones — only active in phase 4
            if phase >= 4 {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(.comic) }
                        .accessibilityIdentifier(AccessibilityID.landingComicOrb)
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(.fanfic) }
                        .accessibilityIdentifier(AccessibilityID.landingFanficOrb)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            screenSize = geo.size
            // Start orbs at absolute screen corners
            goldOffset = CGSize(width: -(geo.size.width / 2 - 20), height: -(geo.size.height / 3))
            blueOffset = CGSize(width: geo.size.width / 2 - 20, height: geo.size.height / 3)
            runAnimation()
        }
        .onDisappear {
            animationToken = UUID()
        }
        } // GeometryReader
    }

    // MARK: - Gold Orb (Comics)

    private var goldOrb: some View {
        ZStack {
            // Glow halo
            RoundedRectangle(cornerRadius: goldCornerRadius)
                .fill(goldColor.opacity(0.15))
                .frame(width: 130 * goldBlobSkew, height: 130)
                .blur(radius: 20)
                .opacity(goldGlow)

            // Main shape
            RoundedRectangle(cornerRadius: goldCornerRadius)
                .fill(goldColor.opacity(0.15))
                .frame(width: 130 * goldBlobSkew, height: 130)

            RoundedRectangle(cornerRadius: goldCornerRadius)
                .stroke(goldColor.opacity(0.35), lineWidth: 2)
                .frame(width: 130 * goldBlobSkew, height: 130)

            // Content inside — manga panel grid + book icon
            VStack(spacing: 5) {
                Image(systemName: "book.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(goldColor.opacity(0.8))

                // Decorative manga panel grid
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(goldColor.opacity(0.2))
                            .frame(width: 24, height: 12)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(goldColor.opacity(0.15))
                            .frame(width: 18, height: 12)
                    }
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(goldColor.opacity(0.15))
                            .frame(width: 14, height: 10)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(goldColor.opacity(0.2))
                            .frame(width: 28, height: 10)
                    }
                }
            }
            .offset(y: contentSlide)
            .opacity(contentRevealGold)
            .clipShape(RoundedRectangle(cornerRadius: goldCornerRadius))
        }
    }

    // MARK: - Blue Orb (Fanfic)

    private var blueOrb: some View {
        ZStack {
            // Glow halo
            RoundedRectangle(cornerRadius: blueCornerRadius)
                .fill(blueColor.opacity(0.15))
                .frame(width: 130 * blueBlobSkew, height: 130)
                .blur(radius: 20)
                .opacity(blueGlow)

            // Main shape
            RoundedRectangle(cornerRadius: blueCornerRadius)
                .fill(blueColor.opacity(0.15))
                .frame(width: 130 * blueBlobSkew, height: 130)

            RoundedRectangle(cornerRadius: blueCornerRadius)
                .stroke(blueColor.opacity(0.35), lineWidth: 2)
                .frame(width: 130 * blueBlobSkew, height: 130)

            // Content inside — text lines + scroll icon
            VStack(spacing: 5) {
                Image(systemName: "scroll.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(blueColor.opacity(0.8))

                // Decorative text lines
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(blueColor.opacity(0.25))
                        .frame(width: 40, height: 3)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(blueColor.opacity(0.18))
                        .frame(width: 32, height: 3)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(blueColor.opacity(0.12))
                        .frame(width: 36, height: 3)
                }
            }
            .offset(y: contentSlide)
            .opacity(contentRevealBlue)
            .clipShape(RoundedRectangle(cornerRadius: blueCornerRadius))
        }
    }

    // MARK: - Animation Sequence

    private func runAnimation() {
        // Ambient background — continuous slow drift
        withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
            ambientShift = true
        }

        // ═══════════════════════════════════════════════════════
        // PHASE 1: Blob Appear (0.3s - 1.0s)
        // Tiny organic shapes pop in far from center
        // ═══════════════════════════════════════════════════════

        let halfW = screenSize.width / 2
        let halfH = screenSize.height / 3

        // Gold appears first — tiny dot at top-left corner
        withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
            goldOpacity = 1
            goldSize = 30
            goldBlobSkew = 1.3
            goldGlow = 0.5
        }

        // Blue appears 0.2s after — tiny dot at bottom-right corner
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            blueOpacity = 1
            blueSize = 24
            blueBlobSkew = 0.8
            blueGlow = 0.5
        }

        // Both drift inward from corners while still small
        withAnimation(.easeInOut(duration: 1.2).delay(0.5)) {
            goldOffset = CGSize(width: -(halfW * 0.45), height: -(halfH * 0.5))
            blueOffset = CGSize(width: halfW * 0.4, height: halfH * 0.45)
            goldRotation = -18
            blueRotation = 12
        }

        // ═══════════════════════════════════════════════════════
        // PHASE 2: Expand + Drift (1.0s - 2.8s)
        // Orbs grow dramatically, content fades in, gentle float
        // ═══════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            phase = 2

            // Dramatic expansion to full size
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) {
                goldSize = 140
                blueSize = 135
                goldBlobSkew = 1.0 // become circular
                blueBlobSkew = 1.0
                goldGlow = 0.7
                blueGlow = 0.7
            }

            // Drift closer together but still spread wide
            withAnimation(.easeInOut(duration: 1.5)) {
                goldOffset = CGSize(width: -(halfW * 0.3), height: -(halfH * 0.2))
                blueOffset = CGSize(width: halfW * 0.25, height: halfH * 0.2)
                goldRotation = -8
                blueRotation = 6
            }

            // Content fades in and slides up
            withAnimation(.easeOut(duration: 1.0).delay(0.3)) {
                contentRevealGold = 0.85
                contentRevealBlue = 0.85
                contentSlide = 0
            }
        }

        // Mid-drift — floating motion, pulling gradually closer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 1.0)) {
                goldOffset = CGSize(width: -(halfW * 0.2), height: -(halfH * 0.1))
                blueOffset = CGSize(width: halfW * 0.15, height: halfH * 0.12)
                goldRotation = -4
                blueRotation = 3
            }
        }

        // ═══════════════════════════════════════════════════════
        // PHASE 3: Contract + Morph (2.8s - 3.8s)
        // Pull inward, shape morphs circle→roundedRect, content fades
        // ═══════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            phase = 3

            // Content dissolves
            withAnimation(.easeIn(duration: 0.4)) {
                contentRevealGold = 1.0 // icon stays, decorative lines will be clipped
                contentRevealBlue = 1.0
                contentSlide = -5
            }

            // Shape morph + pull to final position with OVERSHOOT
            withAnimation(.spring(response: 0.55, dampingFraction: 0.55, blendDuration: 0.3)) {
                goldSize = 120
                blueSize = 120
                goldCornerRadius = 28
                blueCornerRadius = 28
                // Final resting: spaced apart so 120pt orbs don't overlap
                // Each needs to be at least 70pt from center (120/2 + gap)
                goldOffset = CGSize(width: -80, height: 30)
                blueOffset = CGSize(width: 80, height: 30)
                goldRotation = 0
                blueRotation = 0
                goldGlow = 0.3
                blueGlow = 0.3
            }

            // Title appears with scale spring
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.2)) {
                titleScale = 1.0
                titleOpacity = 1
            }
        }

        // ═══════════════════════════════════════════════════════
        // PHASE 4: Ready (3.8s - 4.5s)
        // Labels appear, buttons become tappable
        // ═══════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
            withAnimation(.easeOut(duration: 0.5)) {
                subtitleOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                labelOpacity = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
            phase = 4
        }
    }
}

#Preview {
    RootView()
}
