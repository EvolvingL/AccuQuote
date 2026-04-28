import SwiftUI
import RoomPlan
import ARKit
import SceneKit

// MARK: - Preparing View (flywheel onboarding while AI model downloads)

struct PreparingView: View {
    @EnvironmentObject var assetManager: PhotogrammetryAssetManager
    @StateObject private var engine = QuestionEngine.shared
    @State private var inputText = ""
    @State private var showAllDone = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            HStack(alignment: .center) {
                Text("ACCUQUOTE")
                    .font(.custom("AvenirNext-Heavy", size: 20))
                    .kerning(4)
                    .foregroundColor(.primary)
                Spacer()
                // Download pill
                DownloadProgressPill(progress: assetManager.downloadProgress)
            }
            .padding(.horizontal, 24)
            .padding(.top, 56)
            .padding(.bottom, 20)

            // ── Progress dots ────────────────────────────────────────────
            OnboardingProgressDots(engine: engine)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            Spacer()

            // ── Question card ────────────────────────────────────────────
            if let question = engine.currentQuestion, !showAllDone {
                QuestionCard(
                    question: question,
                    inputText: $inputText,
                    inputFocused: $inputFocused,
                    onSubmit: {
                        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            engine.submitAnswer(inputText)
                            inputText = ""
                        }
                    },
                    onSkip: {
                        withAnimation { engine.skipCurrent() }
                        inputText = ""
                    }
                )
                .padding(.horizontal, 20)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(question.id)   // forces SwiftUI to animate between cards

            } else if engine.isGeneratingMore {
                // Generating next questions
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(Color(hex: "#3B82F6"))
                    Text("Generating personalised questions…")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Color(.systemGray6).opacity(0.6))
                .cornerRadius(20)
                .padding(.horizontal, 20)

            } else {
                // All current questions answered
                AllAnsweredCard(answeredCount: engine.answeredCount)
                    .padding(.horizontal, 20)
            }

            Spacer()

            // ── Bottom context ───────────────────────────────────────────
            VStack(spacing: 6) {
                if assetManager.downloadProgress < 0.05 {
                    Button { assetManager.retry() } label: {
                        Label("Retry Download", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(hex: "#3B82F6"))
                    }
                    .padding(.bottom, 4)
                }
                Text("Your answers train your personal AI quoting assistant.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(.tertiaryLabel))
                    .multilineTextAlignment(.center)
                Text("Scanning unlocks once the AI model finishes downloading.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(.quaternaryLabel))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
        .onTapGesture { inputFocused = false }
    }
}

// MARK: - Download progress pill (compact, lives in header)

struct DownloadProgressPill: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 8) {
            // Mini arc progress
            ZStack {
                Circle()
                    .stroke(Color(hex: "#3B82F6").opacity(0.15), lineWidth: 2.5)
                    .frame(width: 22, height: 22)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color(hex: "#3B82F6"), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 22, height: 22)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: progress)
            }
            Text("\(Int(progress * 100))%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#3B82F6"))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: progress)
            Text("AI model")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(hex: "#3B82F6").opacity(0.08))
        .cornerRadius(20)
    }
}

// MARK: - Progress dots

struct OnboardingProgressDots: View {
    @ObservedObject var engine: QuestionEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<min(engine.questions.count, 20), id: \.self) { i in
                    Capsule()
                        .fill(dotColor(for: i))
                        .frame(width: i == engine.currentIndex ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.3), value: engine.currentIndex)
                }
                if engine.isGeneratingMore {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Color(hex: "#3B82F6"))
                        .padding(.leading, 2)
                }
            }
            HStack {
                Text("\(engine.answeredCount) of \(engine.questions.count) answered")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if engine.answeredCount > 0 {
                    Text("Your AI is \(personalisation)% personalised")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#22C55E"))
                }
            }
        }
    }

    func dotColor(for index: Int) -> Color {
        if index < engine.questions.count && engine.questions[index].isAnswered {
            return Color(hex: "#22C55E")
        } else if index == engine.currentIndex {
            return Color(hex: "#3B82F6")
        } else {
            return Color(.systemGray4)
        }
    }

    var personalisation: Int {
        // Each answer adds to personalisation, capped at 95% until enough answered
        min(Int(Double(engine.answeredCount) / 14.0 * 95), 95)
    }
}

// MARK: - Question card

struct QuestionCard: View {
    let question: OnboardingQuestion
    @Binding var inputText: String
    var inputFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onSkip: () -> Void

    var categoryColor: Color {
        switch question.category {
        case "pricing":   return Color(hex: "#22C55E")
        case "workflow":  return Color(hex: "#8B5CF6")
        case "customers": return Color(hex: "#F59E0B")
        case "materials": return Color(hex: "#EF4444")
        default:          return Color(hex: "#3B82F6")
        }
    }

    var categoryLabel: String {
        switch question.category {
        case "foundation": return "About You"
        case "pricing":    return "Pricing"
        case "workflow":   return "How You Work"
        case "customers":  return "Your Customers"
        case "materials":  return "Materials"
        default:           return question.category.capitalized
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category badge
            HStack {
                Text(categoryLabel.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.2)
                    .foregroundColor(categoryColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(categoryColor.opacity(0.1))
                    .cornerRadius(6)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Question
            Text(question.text)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.primary)
                .lineSpacing(3)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            // Text input
            VStack(spacing: 0) {
                TextField(question.hint, text: $inputText, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(3)
                    .focused(inputFocused)
                    .submitLabel(.done)
                    .onSubmit(onSubmit)
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            // Buttons
            HStack(spacing: 12) {
                Button(action: onSkip) {
                    Text("Skip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }

                Button(action: onSubmit) {
                    HStack(spacing: 6) {
                        Text("Save")
                            .font(.system(size: 15, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color(hex: "#FFD600").opacity(0.4)
                            : Color(hex: "#FFD600")
                    )
                    .cornerRadius(12)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.07), radius: 20, x: 0, y: 4)
        )
    }
}

// MARK: - All answered card

struct AllAnsweredCard: View {
    let answeredCount: Int

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: "#22C55E"))
            Text("Your AI is taking shape")
                .font(.system(size: 22, weight: .bold))
            Text("You've answered \(answeredCount) questions. More personalised questions will appear as your AI learns your trade.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 16)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6).opacity(0.6))
        .cornerRadius(20)
    }
}

// MARK: - Ready View

struct ReadyView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var methodIcon: String {
        switch coordinator.scanMethod {
        case .lidar:          return "cube.transparent"
        case .photogrammetry: return "camera.viewfinder"
        case nil:             return "camera.viewfinder"
        }
    }

    var methodBadgeColor: Color {
        switch coordinator.scanMethod {
        case .lidar:          return Color(hex: "#22C55E")
        case .photogrammetry: return Color(hex: "#3B82F6")
        case nil:             return Color(hex: "#3B82F6")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ACCUQUOTE")
                    .font(.custom("AvenirNext-Heavy", size: 22))
                    .kerning(4)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 24)

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1.5)
                    .frame(width: 120, height: 120)
                Image(systemName: methodIcon)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 24)

            Text("Scan Space")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.primary)
                .padding(.bottom, 12)

            HStack(spacing: 6) {
                Circle()
                    .fill(methodBadgeColor)
                    .frame(width: 8, height: 8)
                Text(coordinator.scanMethod?.displayName ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(methodBadgeColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(methodBadgeColor.opacity(0.1))
            .cornerRadius(20)
            .padding(.bottom, 16)

            Text(coordinator.scanMethod?.description ?? "")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .padding(.bottom, 8)

            methodInstructions
                .padding(.horizontal, 40)

            Spacer()

            Button { coordinator.startScan() } label: {
                Text("Start Scan")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color(hex: "#FFD600"))
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Text(deviceRequirementText)
                .font(.system(size: 12))
                .foregroundColor(Color(.tertiaryLabel))
                .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    var methodInstructions: some View {
        switch coordinator.scanMethod {
        case .lidar, nil:
            EmptyView()
        case .photogrammetry:
            VStack(alignment: .leading, spacing: 8) {
                InstructionRow(icon: "1.circle.fill", text: "Walk slowly around the entire room")
                InstructionRow(icon: "2.circle.fill", text: "Keep all walls visible as you move")
                InstructionRow(icon: "3.circle.fill", text: "Good lighting gives better results")
            }
            .padding(.top, 12)
        }
    }

    var deviceRequirementText: String {
        switch coordinator.scanMethod {
        case .lidar:          return "Using LiDAR — iPhone 12 Pro or later"
        case .photogrammetry: return "Using AI depth — iPhone XS or later, iOS 17+"
        case nil:             return ""
        }
    }
}

struct InstructionRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Scanning View

struct ScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        switch coordinator.scanMethod {
        case .lidar:
            LiDARScanningView(coordinator: coordinator)
        case .photogrammetry:
            PhotoScanningView(coordinator: coordinator)
        case nil:
            EmptyView()
        }
    }
}

// MARK: - LiDAR Scanning View

struct LiDARScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        ZStack(alignment: .bottom) {
            if let captureView = coordinator.captureView {
                RoomCaptureViewRepresentable(captureView: captureView)
                    .ignoresSafeArea()
            }
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { coordinator.stopScan() } label: {
                        Text("Done")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                Spacer()
                ScanProgressCard(coordinator: coordinator)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Photo/AI Scanning View

struct PhotoScanningView: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        ZStack(alignment: .bottom) {
            if let arSession = coordinator.arSession {
                ARViewRepresentable(session: arSession)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Text("\(coordinator.photoCount) frames")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(20)

                    Spacer()

                    Button { coordinator.stopScan() } label: {
                        Text("Done")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color(hex: "#FFD600").opacity(0.9))
                            .cornerRadius(20)
                    }
                    .disabled(coordinator.photoCount < 20)
                    .opacity(coordinator.photoCount < 20 ? 0.5 : 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: 200, height: 200)
                    Circle()
                        .trim(from: 0, to: CGFloat(coordinator.scanProgress))
                        .stroke(Color(hex: "#FFD600"),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: coordinator.scanProgress)
                    VStack(spacing: 4) {
                        Text("\(Int(coordinator.scanProgress * 100))%")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("captured")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.bottom, 24)

                ScanProgressCard(coordinator: coordinator)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Shared progress card

struct ScanProgressCard: View {
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(Color(hex: "#FFD600"))
                        .frame(width: geo.size.width * CGFloat(coordinator.scanProgress))
                        .animation(.easeInOut(duration: 0.4), value: coordinator.scanProgress)
                }
            }
            .frame(height: 4)

            Text(coordinator.instructionText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.7)))
    }
}

// MARK: - Processing View

struct ProcessingView: View {
    @State private var rotation = 0.0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 4).frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            }
            VStack(spacing: 8) {
                Text("Processing Scan")
                    .font(.system(size: 22, weight: .bold)).foregroundColor(.primary)
                Text("Calculating room dimensions…")
                    .font(.system(size: 15)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Result View

struct ResultView: View {
    let result: RoomDimensions
    @ObservedObject var coordinator: ScanCoordinator
    @State private var sent = false

    var accuracyNote: String {
        switch result.scanMethod {
        case .lidar:          return "High precision · LiDAR"
        case .photogrammetry: return "AI depth · ±5% accuracy"
        }
    }

    var accuracyColor: Color {
        switch result.scanMethod {
        case .lidar:          return Color(hex: "#22C55E")
        case .photogrammetry: return Color(hex: "#3B82F6")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ACCUQUOTE")
                    .font(.custom("AvenirNext-Heavy", size: 20)).kerning(4)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24)).foregroundColor(.green)
            }
            .padding(.horizontal, 24).padding(.top, 60).padding(.bottom, 8)

            Text("Scan Complete")
                .font(.system(size: 13)).foregroundColor(.secondary)
                .padding(.horizontal, 24).frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            VStack(spacing: 0) {
                HStack {
                    Text("Room Dimensions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary).kerning(0.5).textCase(.uppercase)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(result.roomType.capitalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color(.systemGray6)).cornerRadius(8)
                        Text(accuracyNote)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(accuracyColor)
                    }
                }
                .padding(.bottom, 20)

                HStack(spacing: 16) {
                    DimensionBadge(label: "Length", value: result.lengthStr, unit: "m")
                    DimensionBadge(label: "Width",  value: result.widthStr,  unit: "m")
                    DimensionBadge(label: "Height", value: result.heightStr, unit: "m")
                }
                .padding(.bottom, 20)

                Divider().padding(.bottom, 16)

                HStack(spacing: 24) {
                    StatPill(icon: "square.fill",
                             label: "Floor area",
                             value: String(format: "%.1fm²", result.floorArea))
                    StatPill(icon: "door.left.hand.open",
                             label: "Doors",
                             value: "\(result.doorCount)")
                    StatPill(icon: "window.casement",
                             label: "Windows",
                             value: "\(result.windowCount)")
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 4)
            )
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    coordinator.sendResultToAccuQuote(result: result)
                    sent = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: sent ? "checkmark" : "arrow.right.circle.fill")
                            .font(.system(size: sent ? 16 : 20, weight: .bold))
                        Text(sent ? "Sent to AccuQuote" : "Send to AccuQuote")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(sent ? Color.green : Color(hex: "#FFD600"))
                    .cornerRadius(16)
                    .animation(.easeInOut(duration: 0.2), value: sent)
                }

                Button { coordinator.reset() } label: {
                    Text("Scan Again")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    @ObservedObject var coordinator: ScanCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light)).foregroundColor(.orange)
            VStack(spacing: 8) {
                Text("Scan Failed").font(.system(size: 22, weight: .bold))
                Text(message).font(.system(size: 15)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            Spacer()
            Button { coordinator.reset() } label: {
                Text("Try Again")
                    .font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Color(hex: "#FFD600")).cornerRadius(16)
            }
            .padding(.horizontal, 24).padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Sub-components

struct DimensionBadge: View {
    let label: String; let value: String; let unit: String
    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                .kerning(0.5).textCase(.uppercase)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.primary)
                Text(unit).font(.system(size: 14, weight: .medium)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(Color(.systemGray6)).cornerRadius(14)
    }
}

struct StatPill: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 16, weight: .bold)).foregroundColor(.primary)
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UIViewRepresentable for RoomCaptureView (LiDAR)

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    let captureView: RoomCaptureView
    func makeUIView(context: Context) -> RoomCaptureView { captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

// MARK: - UIViewRepresentable for ARSession (photogrammetry)

struct ARViewRepresentable: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        view.automaticallyUpdatesLighting = true
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

// MARK: - Color extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
