import SwiftUI
import RoomPlan
import simd

// MARK: - ScanNeedsReviewView (Tri-Mode Scanning build spec §5.4 step 2)
//
// Shown instead of ResultView/LockedResultView when ScanQualityGate finds a
// blocking issue on a LiDAR scan. Ported from AccuScan's ScanNeedsReviewView,
// adapted to AQ design tokens and this app's paywall gating.
//
// Now shows the partial 3D model via ScanViewer3D (Phase 3), matching
// AccuScan's ModelViewer3D-based version — the Phase 1 text-only placeholder
// this screen originally shipped with has been replaced now that the
// underlying viewer exists.
//
// "Fix these areas" calls ScanCoordinator.startPatchScan on the same
// lidarSession/bridge (not a fresh one) so the re-scan is intended to resume
// in the same coordinate space — see startPatchScan's doc comment in
// ScanCoordinator.swift for the resume-behaviour caveat and the
// shouldPreferNew safety net that protects against it going wrong.

struct ScanNeedsReviewView: View {
    @ObservedObject var coordinator: ScanCoordinator
    let room: CapturedRoom
    let result: RoomDimensions
    let confidence: ScanConfidence

    private var blockingCount: Int { confidence.issues.filter { $0.severity == .blocking }.count }
    private var hasBlockingIssues: Bool { blockingCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScanViewer3D(content: .room(room))
                .frame(maxHeight: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dimensionsSummary
                    issueList
                }
                .padding(20)
            }
            .frame(maxHeight: 260)

            footer
        }
        .background(Color.white)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(hasBlockingIssues ? Color(red: 0.98, green: 0.94, blue: 0.94) : Color(red: 1.0, green: 0.97, blue: 0.90))
                    .frame(width: 64, height: 64)
                Image(systemName: hasBlockingIssues ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(hasBlockingIssues ? Color(red: 0.85, green: 0.30, blue: 0.30) : AQ.amber)
            }
            Text("Scan needs review")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AQ.ink)
            Text(hasBlockingIssues
                 ? "\(blockingCount) issue\(blockingCount == 1 ? "" : "s") must be fixed before this scan can be used"
                 : "Warnings only — can be used as-is")
                .font(AQ.body(13))
                .foregroundColor(AQ.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    // MARK: - Dimensions summary (what was actually captured so far)

    private var dimensionsSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CAPTURED SO FAR")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AQ.secondary)
                .kerning(0.5)
            HStack(spacing: 20) {
                dimStat("Length", "\(result.lengthStr)m")
                dimStat("Width", "\(result.widthStr)m")
                dimStat("Height", "\(result.heightStr)m")
            }
            HStack(spacing: 20) {
                dimStat("Floor area", "\(result.floorAreaStr)m²")
                dimStat("Walls", "\(result.wallCount)")
            }
        }
        .padding(16)
        .background(AQ.fill)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AQ.rule, lineWidth: 1))
    }

    private func dimStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(AQ.ink)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AQ.secondary)
        }
    }

    // MARK: - Issue list (worst-first — ScanQualityGate already sorts this way)

    private var issueList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ISSUES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AQ.secondary)
                .kerning(0.5)
            ForEach(confidence.issues) { issue in
                IssueRow(issue: issue)
            }
        }
    }

    // MARK: - Footer CTAs

    private var footer: some View {
        VStack(spacing: 10) {
            Divider().background(AQ.rule)

            Button {
                coordinator.startPatchScan(priorRoom: room, priorConfidence: confidence)
            } label: {
                Text("Fix these areas")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(AQ.blue)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)

            if !hasBlockingIssues {
                // Only reachable when hasBlockingIssues is false — the
                // "perfect every time" guarantee (§5.4): export/quote
                // generation is hard-blocked while any blocking issue is
                // unresolved. Unlike AccuScan, there's no separate persisted
                // acceptedWithWarnings flag here yet — RoomDimensions/
                // SavedQuote don't carry a confidence field. Accepting simply
                // completes the scan; the quality-gate history isn't
                // retained past this point. Revisit once ScanResult (§5.1)
                // replaces RoomDimensions as the persisted record.
                Button {
                    coordinator.acceptWithWarnings(room: room, result: result)
                } label: {
                    Text("Use anyway")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AQ.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 28)
        .background(Color.white)
    }
}

// MARK: - IssueRow

private struct IssueRow: View {
    let issue: ScanIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity == .blocking ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(issue.severity == .blocking ? Color(red: 0.85, green: 0.30, blue: 0.30) : AQ.amber)
                .font(.system(size: 14))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(issue.hint)
                    .font(AQ.body(13))
                    .foregroundColor(AQ.ink)
                Text(issue.severity == .blocking ? "Must fix" : "Recommended")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(issue.severity == .blocking ? Color(red: 0.85, green: 0.30, blue: 0.30) : AQ.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(AQ.fill)
        .cornerRadius(10)
    }
}
