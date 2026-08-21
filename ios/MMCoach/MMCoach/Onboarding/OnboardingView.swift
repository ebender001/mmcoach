//
//  OnboardingView.swift
//  MMCoach
//
//  First-launch-only onboarding, shown before WelcomeView (see RootView,
//  which persists completion via @AppStorage and decides when to show
//  this at all). This view itself has no opinion about persistence or
//  accounts -- it only reports when Skip or Get Started is tapped.
//

import SwiftUI

struct OnboardingView: View {
    /// Called exactly once, when Skip is tapped or the final page's Get
    /// Started is tapped. The caller owns marking onboarding complete and
    /// moving on to WelcomeView.
    let onFinished: () -> Void

    @State private var currentPage: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages = OnboardingPageModel.all

    /// `initialPage` exists only so previews can open directly to a
    /// specific page (e.g. the final "Get Started" state) -- real usage
    /// from RootView always starts at the default, page 0.
    init(onFinished: @escaping () -> Void, initialPage: Int = 0) {
        self.onFinished = onFinished
        _currentPage = State(initialValue: initialPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            skipBar

            TabView(selection: $currentPage) {
                ForEach(pages) { page in
                    OnboardingPage(model: page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            OnboardingPageIndicator(pageCount: pages.count, currentPage: currentPage)
                .padding(.top, 4)
                .padding(.bottom, 24)

            actionButton
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .background(Color.warmBackground.ignoresSafeArea())
    }

    private var isLastPage: Bool { currentPage == pages.count - 1 }

    private var skipBar: some View {
        HStack {
            Spacer()
            Button("Skip") { onFinished() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.slateText)
                // Reserve the space rather than removing the button, so
                // the layout doesn't shift vertically on the last page.
                .opacity(isLastPage ? 0 : 1)
                .disabled(isLastPage)
                .accessibilityHidden(isLastPage)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isLastPage {
            Button("Get Started") { onFinished() }
                .buttonStyle(.michiganProminent)
        } else {
            Button("Next", action: advance)
                .buttonStyle(.michiganProminent)
        }
    }

    private func advance() {
        let next = min(currentPage + 1, pages.count - 1)
        guard !reduceMotion else {
            currentPage = next
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPage = next
        }
    }
}

/// A restrained, brand-colored page-dot row -- built by hand rather than
/// relying on `.tabViewStyle(.page(indexDisplayMode: .always))`'s system
/// `UIPageControl`, so the dots use the app's own navy palette instead of
/// the system default blue, and stay visible against the warm background.
private struct OnboardingPageIndicator: View {
    let pageCount: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.michiganBlue : Color.michiganBlue.opacity(0.2))
                    .frame(width: index == currentPage ? 18 : 8, height: 8)
            }
        }
        // One combined VoiceOver stop ("Page 2 of 4") rather than four
        // separate dot elements, which would read as unlabeled clutter.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentPage + 1) of \(pageCount)")
    }
}

#Preview("Page 1 of 4") {
    OnboardingView(onFinished: {})
}

#Preview("Final page (Get Started)") {
    OnboardingView(onFinished: {}, initialPage: 3)
}

#Preview("Dynamic Type - XXL") {
    OnboardingView(onFinished: {})
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
}
