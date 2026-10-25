import SwiftUI

/// Компактная плашка прогресса передачи снимков в стиле Liquid Glass.
/// 
/// Поддерживает два режима согласно дизайн-макету:
/// 1. Режим активной пофайловой передачи:
///    Имя файла, переданный объем (МБ/МБ), текущая скорость (МБ/с),
///    прогресс-бар и кнопка отмены (min 44 × 44 pt).
/// 2. Режим суммарного прогресса очереди/сессии (как на референсе iPhone/iPad):
///    «Загружено 24 из 48» или «24 из 48», плавный синий индикатор и кнопка «Очередь >».
public struct TransferProgressStrip: View {
    
    public enum Mode {
        case singleFile(
            filename: String,
            transferredBytes: Int64,
            totalBytes: Int64?,
            speedMBs: Double,
            isUSB: Bool,
            onCancel: (() -> Void)?
        )
        case summary(
            completedCount: Int,
            totalCount: Int,
            label: String?,
            actionTitle: String?
        )
    }
    
    public let mode: Mode
    public let onTap: (() -> Void)?
    
    /// Инициализатор пофайловой активной передачи
    public init(
        filename: String,
        transferredBytes: Int64,
        totalBytes: Int64?,
        speedMBs: Double = 0.0,
        isUSB: Bool = true,
        onTap: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.mode = .singleFile(
            filename: filename,
            transferredBytes: transferredBytes,
            totalBytes: totalBytes,
            speedMBs: speedMBs,
            isUSB: isUSB,
            onCancel: onCancel
        )
        self.onTap = onTap
    }
    
    /// Инициализатор суммарного прогресса (референс: «24 из 48» или «Загружено 24 из 48»)
    public init(
        completedCount: Int,
        totalCount: Int,
        label: String? = nil,
        actionTitle: String? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.mode = .summary(
            completedCount: completedCount,
            totalCount: totalCount,
            label: label,
            actionTitle: actionTitle
        )
        self.onTap = onTap
    }
    
    public var body: some View {
        Group {
            switch mode {
            case .singleFile(let filename, let transferredBytes, let totalBytes, let speedMBs, let isUSB, let onCancel):
                singleFileLayout(
                    filename: filename,
                    transferredBytes: transferredBytes,
                    totalBytes: totalBytes,
                    speedMBs: speedMBs,
                    isUSB: isUSB,
                    onCancel: onCancel
                )
            case .summary(let completedCount, let totalCount, let label, let actionTitle):
                summaryLayout(
                    completedCount: completedCount,
                    totalCount: totalCount,
                    label: label,
                    actionTitle: actionTitle
                )
            }
        }
        .frame(minHeight: AppTheme.Dimensions.buttonHeight)
        .glassPill(shadowRadius: 6, shadowY: 2)
    }
    
    // MARK: - 1. Пофайловый лейаут
    
    private func singleFileLayout(
        filename: String,
        transferredBytes: Int64,
        totalBytes: Int64?,
        speedMBs: Double,
        isUSB: Bool,
        onCancel: (() -> Void)?
    ) -> some View {
        let fraction = progressFraction(transferred: transferredBytes, total: totalBytes)
        let transferredMBText = formatMBText(transferred: transferredBytes, total: totalBytes)
        
        return HStack(spacing: AppTheme.Spacing.sm) {
            Button {
                onTap?()
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: isUSB ? "cable.connector" : "wifi")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .frame(width: 20, height: 20)
                    
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Text(filename)
                                .font(AppTheme.Typography.captionBold)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(1)
                            
                            if let progress = fraction {
                                Text(String(format: "%.0f%%", progress * 100))
                                    .font(AppTheme.Typography.caption2Bold)
                                    .foregroundStyle(AppTheme.Colors.accent)
                                    .monospacedDigit()
                            }
                        }
                        
                        HStack(spacing: AppTheme.Spacing.xs) {
                            Text(transferredMBText)
                                .monospacedDigit()
                            
                            if speedMBs > 0.05 {
                                Text(String(format: tr("• %.1f МБ/с", "• %.1f MB/s"), speedMBs))
                                    .foregroundStyle(AppTheme.Colors.statusGreen)
                                    .monospacedDigit()
                            }
                        }
                        .font(AppTheme.Typography.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    
                    Spacer(minLength: AppTheme.Spacing.xs)
                    
                    if let progress = fraction {
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.Colors.accent))
                            .frame(maxWidth: 64)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Активная передача: \(filename), \(transferredMBText)")
            
            if let onCancel {
                Button(role: .destructive, action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: AppTheme.Dimensions.minTouchTarget, height: AppTheme.Dimensions.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Отменить передачу файла \(filename)")
            }
            
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .padding(.trailing, AppTheme.Spacing.xs)
            }
        }
        .padding(.leading, AppTheme.Spacing.md)
        .padding(.trailing, AppTheme.Spacing.xs)
        .padding(.vertical, AppTheme.Spacing.xxs)
    }
    
    // MARK: - 2. Суммарный лейаут очереди (референс)
    
    private func summaryLayout(
        completedCount: Int,
        totalCount: Int,
        label: String?,
        actionTitle: String?
    ) -> some View {
        let fraction = totalCount > 0 ? min(max(Double(completedCount) / Double(totalCount), 0.0), 1.0) : 0.0
        let displayLabel = label ?? "\(completedCount) из \(totalCount)"
        
        return Button {
            onTap?()
        } label: {
            HStack(spacing: AppTheme.Spacing.md) {
                Text(displayLabel)
                    .font(AppTheme.Typography.subheadlineBold)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                
                ProgressView(value: fraction)
                    .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.Colors.accent))
                    .frame(maxWidth: .infinity)
                
                HStack(spacing: AppTheme.Spacing.xxs) {
                    if let actionTitle {
                        Text(actionTitle)
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(actionTitle != nil ? AppTheme.Colors.accent : AppTheme.Colors.textTertiary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayLabel), прогресс \(Int(fraction * 100)) процентов")
        .accessibilityHint(actionTitle != nil ? "Нажмите для перехода в \(actionTitle!)" : "Нажмите для открытия очереди передачи")
    }
    
    // MARK: - Хелперы расчетов
    
    private func progressFraction(transferred: Int64, total: Int64?) -> Double? {
        guard let total = total, total > 0 else { return nil }
        return min(max(Double(transferred) / Double(total), 0.0), 1.0)
    }
    
    private func formatMBText(transferred: Int64, total: Int64?) -> String {
        let transferredMB = Double(transferred) / 1_048_576.0
        let unit = tr("МБ", "MB")
        if let total = total, total > 0 {
            let totalMB = Double(total) / 1_048_576.0
            return String(format: "%.1f / %.1f %@", transferredMB, totalMB, unit)
        } else {
            return String(format: "%.1f %@", transferredMB, unit)
        }
    }
}
