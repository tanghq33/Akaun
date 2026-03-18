import SwiftUI

struct AutoImportQueueRowView: View {
    var item: AutoImportQueueItem
    var onRetry: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .lineLimit(1)
                if let secondary = secondaryText {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(secondaryColor)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isInFlight {
                ProgressView()
                    .controlSize(.small)
            }
            if case .failed = item.state {
                if let onRetry {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Retry")
                }
                if let onRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove")
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Computed

    private var primaryText: String {
        switch item.state {
        case .ready, .imported, .failed:
            return item.itemName.isEmpty ? item.sourceFile.lastPathComponent : item.itemName
        default:
            return item.sourceFile.lastPathComponent
        }
    }

    private var secondaryText: String? {
        switch item.state {
        case .extracting:
            return "Extracting text…"
        case .calling:
            return "Analysing receipt…"
        case .ready:
            var parts: [String] = []
            if !item.supplier.isEmpty { parts.append(item.supplier) }
            if item.amountCents > 0 { parts.append(Formatters.formatCents(item.amountCents)) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .imported:
            return "Imported"
        case .failed(let msg):
            return msg
        }
    }

    private var secondaryColor: Color {
        if case .failed = item.state { return .red }
        return .secondary
    }

    private var isInFlight: Bool {
        item.state == .extracting || item.state == .calling
    }

    private var statusIcon: some View {
        Group {
            switch item.state {
            case .extracting:
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
            case .calling:
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .foregroundStyle(Color.accentColor)
            case .ready:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(.orange)
            case .imported:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline)
        .frame(width: 18)
    }
}
