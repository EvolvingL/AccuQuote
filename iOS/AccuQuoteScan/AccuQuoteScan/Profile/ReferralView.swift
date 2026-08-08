import SwiftUI

// MARK: - Referral View
//
// "Refer a friend" screen, opened from ProfileMenuSheet's Account tab.
// Shows the user's own permanent referral code plus how many friends have
// converted so far. All copy is plain-English — no mention of Stripe, Apple,
// webhooks, or any other implementation detail (matches QuoteErrorMessaging's
// house convention of never surfacing technical detail to the user).

struct ReferralView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var info: ReferralInfo?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showCopiedConfirmation = false
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let info {
                    content(for: info)
                } else {
                    // loadFailed — calm, non-technical copy; the real cause
                    // (network/server failure) is logged by ReferralService,
                    // never shown here.
                    VStack(spacing: 16) {
                        Image(systemName: "person.2")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(AQ.secondary)
                        Text("Couldn't load your referral details right now.")
                            .font(.system(size: 15))
                            .foregroundColor(AQ.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("Try Again") { Task { await load() } }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AQ.blue)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Refer a Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(for info: ReferralInfo) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Share your code")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AQ.ink)
                    Text("When a friend signs up with your code and subscribes, you get a free month.")
                        .font(.system(size: 14))
                        .foregroundColor(AQ.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 12)

                // ── Code card (tap to copy) ───────────────────────────────
                Button {
                    UIPasteboard.general.string = info.code
                    showCopiedConfirmation = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        showCopiedConfirmation = false
                    }
                } label: {
                    VStack(spacing: 10) {
                        Text(info.code)
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                            .foregroundColor(AQ.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(showCopiedConfirmation ? "Copied ✓" : "Tap to copy")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(showCopiedConfirmation ? AQ.green : AQ.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(AQ.fill)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(AQ.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                Button {
                    showShareSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Share your code")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AQ.blue)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 20)

                // ── Reward summary ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 15))
                            .foregroundColor(AQ.green)
                            .frame(width: 24)
                        Text(rewardSummary(count: info.referralCount))
                            .font(.system(size: 15))
                            .foregroundColor(AQ.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(Color.white)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))
                .padding(.horizontal, 20)

                Spacer(minLength: 20)
            }
            .padding(.bottom, 24)
        }
        .background(AQ.fill.opacity(0.4).ignoresSafeArea())
        .sheet(isPresented: $showShareSheet) {
            TextShareSheet(text: shareText(code: info.code))
        }
    }

    private func rewardSummary(count: Int) -> String {
        guard count > 0 else {
            return "No friends have subscribed with your code yet."
        }
        let month = count == 1 ? "month" : "months"
        return "You've earned \(count) free \(month) — thanks for spreading the word!"
    }

    private func shareText(code: String) -> String {
        "Use my AccuQuote referral code \(code) when you sign up and we'll both be sorted — I get a free month once you subscribe. Get the app at https://accuquote.uk"
    }

    private func load() async {
        isLoading = true
        loadFailed = false
        do {
            info = try await ReferralService.fetchInfo()
        } catch {
            info = nil
            loadFailed = true
        }
        isLoading = false
    }
}

// MARK: - Text Share Sheet
//
// ShareSheet (Quote/ShareSheet.swift) wraps a URL for sharing exported PDFs/
// USDZ files — this is the same UIActivityViewController pattern, retyped
// for a plain String (the referral code + message), since a URL and a
// String need different activityItems and a shared conformance would be
// awkward to express for both.

struct TextShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
