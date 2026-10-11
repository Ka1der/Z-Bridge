import SwiftUI

/// Плавающая капсула прогресса переноса файлов над лентой кадров (согласно референсу iPad).
/// Отображает процент загрузки, желтую шкалу прогресса и количество оставшихся файлов.
public struct FloatingTransferPill: View {
    public let progressPercent: Int
    public let statusText: String
    public let remainingFilesText: String
    public var onTap: (() -> Void)? = nil
    
    public init(
        progressPercent: Int = 65,
        statusText: String? = nil,
        remainingFilesText: String = "34 files left",
        onTap: (() -> Void)? = nil
    ) {
        self.progressPercent = min(100, max(0, progressPercent))
        self.statusText = statusText ?? "\(self.progressPercent)% transferred"
        self.remainingFilesText = remainingFilesText
        self.onTap = onTap
    }
    
    public var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 16) {
                // Левая часть: процент и желтая полоска прогресса
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                    
                    // Желтая шкала прогресса Nikon
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 130, height: 4)
                        
                        Capsule()
                            .fill(AppTheme.Colors.accent)
                            .frame(width: max(4, 130 * CGFloat(progressPercent) / 100.0), height: 4)
                            .shadow(color: AppTheme.Colors.accent.opacity(0.5), radius: 3)
                    }
                }
                
                // Правая часть: количество оставшихся файлов
                Text(remainingFilesText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color(red: 22/255.0, green: 24/255.0, blue: 29/255.0).opacity(0.85))
                    .background(.ultraThinMaterial, in: Capsule())
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.40), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}
