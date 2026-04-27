import SwiftUI

struct SummaryView: View {
    let summary: Summary?
    let streamingText: String
    let isLoading: Bool
    var statusMessage: String? = nil
    var entry: SessionIndex.SessionEntry? = nil
    var transcript: Transcript? = nil
    var onRegenerate: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Session header (inside scroll area for full-width scrolling)
                if let entry {
                    sessionHeader
                }

                if onRegenerate != nil || onCancel != nil {
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
                        if let onRegenerate {
                            Button {
                                onRegenerate()
                            } label: {
                                Label("Regenerate", systemImage: "arrow.clockwise")
                            }
                            .controlSize(.small)
                            .disabled(isLoading)
                        }
                    }
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
            .padding(.horizontal, 48)
            .padding(.top, 28)
            .padding(.bottom, 60)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let date = entry?.startedAt {
                Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            Text(entry?.name ?? "Session")
                .font(.system(size: 24, weight: .bold))

            // Metadata row
            HStack(spacing: 16) {
                if let duration = entry?.durationSeconds {
                    Label(formatDuration(duration), systemImage: "clock")
                }
                if let speakers = transcript?.speakers, !speakers.isEmpty {
                    Label("\(speakers.count) speakers", systemImage: "person.2")
                }
                if let model = transcript?.model {
                    Label(model, systemImage: "waveform")
                }
                if let actions = summary?.actionItems, !actions.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checklist")
                        Text("\u{2022} \(actions.count) open actions")
                    }
                    .foregroundStyle(.green)
                    .fontWeight(.medium)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
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
        // 1. Blockquote — use overview text with decorative quote mark
        if let overview = summary.overview, !overview.isEmpty {
            blockquote(overview)
        }

        // 2. Overview narrative section
        if let overview = summary.overview, !overview.isEmpty {
            sectionHeader(title: "OVERVIEW")
            Text(overview)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        // 3. Decisions
        if let decisions = summary.decisions, !decisions.isEmpty {
            sectionHeader(title: "DECISIONS", count: decisions.count, countLabel: "made")
            VStack(alignment: .leading, spacing: 10) {
                ForEach(decisions, id: \.self) { item in
                    checkmarkItem(item)
                }
            }
        }

        // 4. Action Items
        if let actions = summary.actionItems, !actions.isEmpty {
            sectionHeader(title: "ACTION ITEMS", count: actions.count)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(actions, id: \.self) { item in
                    actionItem(item)
                }
            }
        }

        // 5. Key Discussion Points
        if let keyPoints = summary.keyPoints, !keyPoints.isEmpty {
            sectionHeader(title: "KEY DISCUSSION POINTS", count: keyPoints.count)
            VStack(alignment: .leading, spacing: 10) {
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
        let overviewText = extractOverview(from: summary.content)
        if !overviewText.isEmpty {
            blockquote(overviewText)
            sectionHeader(title: "OVERVIEW")
            Text(overviewText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if overviewText.isEmpty {
            Text(summary.content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Blockquote

    private func blockquote(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\u{201C}")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .foregroundStyle(Color.secondary.opacity(0.3))
                .padding(.bottom, -12)

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.primary.opacity(0.8))
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.separatorColor).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, count: Int? = nil, countLabel: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            if let count {
                if let label = countLabel {
                    Text("\(count) \(label)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Item Styles

    private func checkmarkItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 15))
                .padding(.top, 1)
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle")
                .foregroundStyle(.orange)
                .font(.system(size: 15))
                .padding(.top, 1)
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bulletItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}
