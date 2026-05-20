//
//  AutomationInProgressViews.swift
//  Flick
//

import SwiftUI

struct AutomationProgressSummaryRow: View {
    var progress: AutomationPostProgress

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: progress.currentStep?.systemImage ?? "sparkles")
                .foregroundStyle(progress.currentStep?.state.tint ?? .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 6) {
                Text(progress.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let currentStep = progress.currentStep {
                    Text("\(currentStep.title) - \(currentStep.detail)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let creationModelName = progress.creationModelName, !creationModelName.isEmpty {
                    Text("Model: \(creationModelName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ProgressView(value: progress.progressFraction)
                    .progressViewStyle(.linear)

                Text("Step \(progress.currentStepIndex) of \(max(progress.totalCount, 1))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            DashboardStatusIcon(
                title: "In Progress",
                tint: .blue,
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct AutomationPostSkeletonShimmer: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.07))

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .aspectRatio(9.0 / 14.0, contentMode: .fit)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.18))
                    }

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white.opacity(0.12))
                        .frame(height: 7)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white.opacity(0.1))
                        .frame(width: 54, height: 7)
                }
            }
            .padding(10)
        }
        .overlay {
            GeometryReader { proxy in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.18),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * 0.7)
                    .offset(x: isAnimating ? proxy.size.width : -proxy.size.width)
            }
            .clipShape(.rect(cornerRadius: 14))
            .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

struct AutomationProgressStepStrip: View {
    var steps: [AutomationPostProgressStep]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(steps) { step in
                Image(systemName: step.state.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(step.state.tint)
                    .frame(width: 16, height: 18)

                if step.id != steps.last?.id {
                    Capsule()
                        .fill(step.state == .completed ? Color.green.opacity(0.45) : Color.secondary.opacity(0.18))
                        .frame(width: 8, height: 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}
