import SwiftUI

struct SummaryView: View {
    let summary: Summary?
    let streamingText: String
    let isLoading: Bool
    var statusMessage: String? = nil
    let onRegenerate: () -> Void
    var onCancel: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    if isLoading, let onCancel {
                        Button {
                            onCancel()
                        } label: {
                            Label("Stop", systemImage: "stop.circle")
                        }
                        .controlSize(.small)
                    }
                    Button {
                        onRegenerate()
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(isLoading)
                }

                if isLoading {
                    loadingView
                } else if let summary {
                    summaryContent(summary)
                } else if !streamingText.isEmpty {
                    Text(streamingText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    emptyState
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 12) {
            if !streamingText.isEmpty {
                Text(streamingText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let statusMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Summarizing transcript...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Structured Summary

    @ViewBuilder
    private func summaryContent(_ summary: Summary) -> some View {
        // 1. Overview
        if let overview = summary.overview, !overview.isEmpty {
            sectionCard(
                title: "Overview",
                icon: "doc.text",
                color: .blue
            ) {
                Text(overview)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        // 2. Decisions
        if let decisions = summary.decisions, !decisions.isEmpty {
            sectionCard(
                title: "Decisions",
                icon: "checkmark.seal",
                color: .green
            ) {
                ForEach(decisions, id: \.self) { item in
                    bulletItem(item)
                }
            }
        }

        // 3. Action Items
        if let actions = summary.actionItems, !actions.isEmpty {
            sectionCard(
                title: "Action Items",
                icon: "checklist",
                color: .orange
            ) {
                ForEach(actions, id: \.self) { item in
                    bulletItem(item)
                }
            }
        }

        // 4. Key Discussion Points
        if let keyPoints = summary.keyPoints, !keyPoints.isEmpty {
            sectionCard(
                title: "Key Discussion Points",
                icon: "bubble.left.and.bubble.right",
                color: .purple
            ) {
                ForEach(keyPoints, id: \.self) { item in
                    bulletItem(item)
                }
            }
        }

        // Fallback for old summaries without parsed sections
        if summary.overview == nil && summary.decisions == nil
            && summary.actionItems == nil && summary.keyPoints == nil
        {
            fallbackContent(summary)
        }
    }

    @ViewBuilder
    private func fallbackContent(_ summary: Summary) -> some View {
        // Legacy: extract overview as text before first ## header
        let overviewText = extractOverview(from: summary.content)
        if !overviewText.isEmpty {
            sectionCard(title: "Overview", icon: "doc.text", color: .blue) {
                Text(overviewText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        // If nothing was parseable at all, show raw content
        if overviewText.isEmpty {
            Text(summary.content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Section Card

    private func sectionCard<Content: View>(
        title: String, icon: String, color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.subheadline)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func extractOverview(from content: String) -> String {
        if let headerRange = content.range(of: "\n## ") {
            return String(content[content.startIndex..<headerRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if let statusMessage, statusMessage.contains("ailed") {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text("Summarization failed")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Text("Click Regenerate to try again.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No summary yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Click Regenerate to generate a summary.\nThe summarization model (~3 GB) will download on first use.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func bulletItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}
