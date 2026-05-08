import AppKit
import Foundation
import UniformTypeIdentifiers

/// Builds Copy / Word / PDF / Plain-Text exports of a `Summary`.
///
/// Copy, Word and PDF share a single `NSAttributedString` source so formatting
/// stays consistent. Plain Text is hand-built so the output is clean for paste
/// into terminals or code editors.
@MainActor
enum SummaryExporter {
    enum Format {
        case doc
        case pdf
        case plainText

        var fileExtension: String {
            switch self {
            case .doc: return "doc"
            case .pdf: return "pdf"
            case .plainText: return "txt"
            }
        }

        var contentType: UTType {
            switch self {
            case .doc: return UTType(filenameExtension: "doc") ?? .data
            case .pdf: return .pdf
            case .plainText: return .plainText
            }
        }

        var savePanelTitle: String {
            switch self {
            case .doc: return "Export as Word Document"
            case .pdf: return "Export as PDF"
            case .plainText: return "Export as Plain Text"
            }
        }
    }

    enum ExportError: LocalizedError {
        case cancelled
        case writeFailed(Error)
        case docConversionFailed
        case pdfRenderFailed

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Export cancelled"
            case .writeFailed(let e): return "Could not write file: \(e.localizedDescription)"
            case .docConversionFailed: return "Could not produce Word document"
            case .pdfRenderFailed: return "Could not render PDF"
            }
        }
    }

    // MARK: - Public API

    /// Copies the summary to the system pasteboard with both rich-text (RTF) and
    /// plain-string representations. Paste targets pick the best they support.
    static func copyToPasteboard(summary: Summary,
                                 entry: SessionIndex.SessionEntry?,
                                 transcript: Transcript?) {
        let attr = attributedString(summary: summary, entry: entry, transcript: transcript)
        let plain = plainText(summary: summary, entry: entry, transcript: transcript)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.rtf, .string], owner: nil)

        if let rtf = try? attr.data(from: NSRange(location: 0, length: attr.length),
                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pb.setData(rtf, forType: .rtf)
        }
        pb.setString(plain, forType: .string)
    }

    /// Presents an `NSSavePanel` and writes the summary in the chosen format.
    /// Throws `ExportError.cancelled` if the user dismisses the panel.
    static func export(summary: Summary,
                       entry: SessionIndex.SessionEntry?,
                       transcript: Transcript?,
                       format: Format) throws {
        let url = try runSavePanel(format: format, defaultName: defaultFilename(entry: entry, format: format))

        switch format {
        case .doc:
            try writeDoc(summary: summary, entry: entry, transcript: transcript, to: url)
        case .pdf:
            try writePDF(summary: summary, entry: entry, transcript: transcript, to: url)
        case .plainText:
            try writePlainText(summary: summary, entry: entry, transcript: transcript, to: url)
        }
    }

    // MARK: - Save panel

    private static func runSavePanel(format: Format, defaultName: String) throws -> URL {
        let panel = NSSavePanel()
        panel.title = format.savePanelTitle
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            throw ExportError.cancelled
        }
        return url
    }

    private static func defaultFilename(entry: SessionIndex.SessionEntry?, format: Format) -> String {
        let raw = entry?.name ?? "Summary"
        let safe = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safe.isEmpty ? "Summary" : safe
        return "\(base)_Summary.\(format.fileExtension)"
    }

    // MARK: - Format writers

    private static func writeDoc(summary: Summary,
                                 entry: SessionIndex.SessionEntry?,
                                 transcript: Transcript?,
                                 to url: URL) throws {
        let attr = attributedString(summary: summary, entry: entry, transcript: transcript)
        guard let data = try? attr.data(
            from: NSRange(location: 0, length: attr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.docFormat]
        ) else {
            throw ExportError.docConversionFailed
        }
        do {
            try data.write(to: url)
        } catch {
            throw ExportError.writeFailed(error)
        }
    }

    private static func writePlainText(summary: Summary,
                                       entry: SessionIndex.SessionEntry?,
                                       transcript: Transcript?,
                                       to url: URL) throws {
        let text = plainText(summary: summary, entry: entry, transcript: transcript)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(error)
        }
    }

    private static func writePDF(summary: Summary,
                                 entry: SessionIndex.SessionEntry?,
                                 transcript: Transcript?,
                                 to url: URL) throws {
        let attr = attributedString(summary: summary, entry: entry, transcript: transcript)

        // US Letter content area (612 x 792) minus 0.75" margins on all sides.
        let pageWidth: CGFloat = 612
        let margin: CGFloat = 54
        let contentWidth = pageWidth - margin * 2

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 800))
        textView.isEditable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(attr)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)

        let info = (NSPrintInfo.shared.copy() as! NSPrintInfo)
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let op = NSPrintOperation(view: textView, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else {
            throw ExportError.pdfRenderFailed
        }
    }

    // MARK: - Attributed-string builder (shared by Copy, Word, PDF)

    static func attributedString(summary: Summary,
                                 entry: SessionIndex.SessionEntry?,
                                 transcript: Transcript?) -> NSAttributedString {
        let out = NSMutableAttributedString()

        // --- Title ---
        if let name = entry?.name, !name.isEmpty {
            out.append(string("\(name)\n", attrs: [
                .font: NSFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph(spacingAfter: 4)
            ]))
        }

        // --- Date kicker (uppercase tracked) ---
        if let date = entry?.startedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
            let dateStr = formatter.string(from: date).uppercased()
            out.append(string("\(dateStr)\n", attrs: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
                .kern: 0.6,
                .paragraphStyle: paragraph(spacingAfter: 4)
            ]))
        }

        // --- Meta row (duration · speakers · model) ---
        let meta = metaRowText(entry: entry, transcript: transcript, summary: summary)
        if !meta.isEmpty {
            out.append(string("\(meta)\n", attrs: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph(spacingAfter: 18)
            ]))
        }

        // --- TL;DR block ---
        if let overview = summary.overview, !overview.isEmpty {
            let tldrPara = paragraph(spacingAfter: 24, headIndent: 0, firstLineIndent: 0)
            out.append(string("TL;DR\n", attrs: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 0.8,
                .paragraphStyle: paragraph(spacingAfter: 6)
            ]))
            out.append(string("\(overview)\n", attrs: [
                .font: NSFont.systemFont(ofSize: 16, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: tldrPara
            ]))
        }

        // --- Overview ---
        if let overview = summary.overview, !overview.isEmpty {
            appendSectionHeader(into: out, title: "OVERVIEW")
            out.append(string("\(overview)\n", attrs: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph(spacingAfter: 22, lineSpacing: 3)
            ]))
        }

        // --- Decisions ---
        if let decisions = summary.decisions, !decisions.isEmpty {
            appendSectionHeader(into: out, title: "DECISIONS",
                                hint: "\(decisions.count) made")
            for item in decisions {
                appendBulletItem(into: out,
                                 marker: "✓",
                                 markerColor: .systemGreen,
                                 text: item)
            }
            appendSpacer(into: out)
        }

        // --- Action items ---
        if let actions = summary.actionItems, !actions.isEmpty {
            appendSectionHeader(into: out, title: "ACTION ITEMS",
                                hint: "\(actions.count)")
            for item in actions {
                appendBulletItem(into: out,
                                 marker: "○",
                                 markerColor: .systemOrange,
                                 text: item)
            }
            appendSpacer(into: out)
        }

        // --- Key discussion points ---
        if let points = summary.keyPoints, !points.isEmpty {
            appendSectionHeader(into: out, title: "KEY DISCUSSION POINTS",
                                hint: "\(points.count)")
            for (i, item) in points.enumerated() {
                let number = String(format: "%02d.", i + 1)
                appendBulletItem(into: out,
                                 marker: number,
                                 markerColor: .tertiaryLabelColor,
                                 text: item,
                                 markerFont: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular))
            }
            appendSpacer(into: out)
        }

        // --- Fallback if no structured fields parsed ---
        if summary.overview == nil && summary.decisions == nil
            && summary.actionItems == nil && summary.keyPoints == nil {
            out.append(string("\(summary.content)\n", attrs: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph(spacingAfter: 16, lineSpacing: 3)
            ]))
        }

        // --- Footer ---
        let footer = footerText(summary: summary)
        out.append(string(footer, attrs: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraph(spacingBefore: 12)
        ]))

        return out
    }

    // MARK: - Plain text builder

    static func plainText(summary: Summary,
                          entry: SessionIndex.SessionEntry?,
                          transcript: Transcript?) -> String {
        var lines: [String] = []

        if let name = entry?.name, !name.isEmpty {
            lines.append(name)
        }

        if let date = entry?.startedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
            lines.append(formatter.string(from: date))
        }

        let meta = metaRowText(entry: entry, transcript: transcript, summary: summary)
        if !meta.isEmpty { lines.append(meta) }

        if let overview = summary.overview, !overview.isEmpty {
            lines.append("")
            lines.append("TL;DR")
            lines.append(overview)
        }

        if let overview = summary.overview, !overview.isEmpty {
            lines.append("")
            lines.append("OVERVIEW")
            lines.append(overview)
        }

        if let decisions = summary.decisions, !decisions.isEmpty {
            lines.append("")
            lines.append("DECISIONS (\(decisions.count) made)")
            for item in decisions {
                lines.append("  [✓] \(item)")
            }
        }

        if let actions = summary.actionItems, !actions.isEmpty {
            lines.append("")
            lines.append("ACTION ITEMS (\(actions.count))")
            for item in actions {
                lines.append("  [ ] \(item)")
            }
        }

        if let points = summary.keyPoints, !points.isEmpty {
            lines.append("")
            lines.append("KEY DISCUSSION POINTS (\(points.count))")
            for (i, item) in points.enumerated() {
                lines.append(String(format: "  %02d. %@", i + 1, item))
            }
        }

        if summary.overview == nil && summary.decisions == nil
            && summary.actionItems == nil && summary.keyPoints == nil {
            lines.append("")
            lines.append(summary.content)
        }

        lines.append("")
        lines.append(footerText(summary: summary))

        return lines.joined(separator: "\n")
    }

    // MARK: - Internals

    private static func metaRowText(entry: SessionIndex.SessionEntry?,
                                    transcript: Transcript?,
                                    summary: Summary) -> String {
        var parts: [String] = []
        if let dur = entry?.durationSeconds {
            parts.append(formatDuration(dur))
        }
        if let speakers = transcript?.speakers, !speakers.isEmpty {
            parts.append("\(speakers.count) speakers")
        }
        if let model = transcript?.model, !model.isEmpty {
            parts.append(model)
        }
        return parts.joined(separator: "  ·  ")
    }

    private static func footerText(summary: Summary) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        let dateStr = formatter.string(from: summary.created)
        return "Generated by Gist  ·  \(summary.model)  ·  \(dateStr)"
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Attributed-string helpers

    private static func string(_ s: String, attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        NSAttributedString(string: s, attributes: attrs)
    }

    private static func paragraph(spacingBefore: CGFloat = 0,
                                  spacingAfter: CGFloat = 0,
                                  headIndent: CGFloat = 0,
                                  firstLineIndent: CGFloat = 0,
                                  lineSpacing: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = spacingBefore
        p.paragraphSpacing = spacingAfter
        p.headIndent = headIndent
        p.firstLineHeadIndent = firstLineIndent
        p.lineSpacing = lineSpacing
        return p
    }

    private static func appendSectionHeader(into out: NSMutableAttributedString,
                                            title: String,
                                            hint: String? = nil) {
        out.append(string(title, attrs: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.8,
            .paragraphStyle: paragraph(spacingBefore: 4)
        ]))
        if let hint, !hint.isEmpty {
            out.append(string("  \(hint)", attrs: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]))
        }
        out.append(string("\n", attrs: [
            .paragraphStyle: paragraph(spacingAfter: 8)
        ]))
    }

    private static func appendBulletItem(into out: NSMutableAttributedString,
                                         marker: String,
                                         markerColor: NSColor,
                                         text: String,
                                         markerFont: NSFont? = nil) {
        let bulletPara = NSMutableParagraphStyle()
        bulletPara.headIndent = 22
        bulletPara.firstLineHeadIndent = 0
        bulletPara.paragraphSpacing = 6
        bulletPara.lineSpacing = 2
        bulletPara.tabStops = [NSTextTab(textAlignment: .left, location: 22)]

        let line = NSMutableAttributedString()
        line.append(string("\(marker)\t", attrs: [
            .font: markerFont ?? NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: markerColor,
            .paragraphStyle: bulletPara
        ]))
        line.append(string("\(text)\n", attrs: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: bulletPara
        ]))
        out.append(line)
    }

    private static func appendSpacer(into out: NSMutableAttributedString) {
        out.append(string("\n", attrs: [
            .font: NSFont.systemFont(ofSize: 8),
            .paragraphStyle: paragraph(spacingAfter: 10)
        ]))
    }
}
