import SwiftUI

/// Нижняя панель управления в зоне досягаемости большого пальца (согласно референсу iPhone).
/// Включает плавающие стеклянные капсулы:
/// - Верхний ряд: 5 звезд рейтинга и 5 цветовых меток отбора (Red, Green, Blue, Yellow, Orange);
/// - Нижний ряд: капсула живого статуса переноса с желтым бейджем и кнопка быстрого экспорта.
public struct FloatingThumbZoneView: View {
    public let rating: Int
    public let selectedColorTag: Int? // 0: Red, 1: Green, 2: Blue, 3: Yellow, 4: Orange
    public let isTransferring: Bool
    public let transferStatusText: String
    public let transferPercent: Int
    
    public var onRatingChanged: ((Int) -> Void)? = nil
    public var onColorTagChanged: ((Int) -> Void)? = nil
    public var onExport: (() -> Void)? = nil
    public var onTransferTap: (() -> Void)? = nil
    public var onCancelTransfer: (() -> Void)? = nil
    
    public init(
        rating: Int = 4,
        selectedColorTag: Int? = 1,
        isTransferring: Bool = true,
        transferStatusText: String = "14/158 (NEF) • 25MB/s • 34s rem.",
        transferPercent: Int = 42,
        onRatingChanged: ((Int) -> Void)? = nil,
        onColorTagChanged: ((Int) -> Void)? = nil,
        onExport: (() -> Void)? = nil,
        onTransferTap: (() -> Void)? = nil,
        onCancelTransfer: (() -> Void)? = nil
    ) {
        self.rating = rating
        self.selectedColorTag = selectedColorTag
        self.isTransferring = isTransferring
        self.transferStatusText = transferStatusText
        self.transferPercent = min(100, max(0, transferPercent))
        self.onRatingChanged = onRatingChanged
        self.onColorTagChanged = onColorTagChanged
        self.onExport = onExport
        self.onTransferTap = onTransferTap
        self.onCancelTransfer = onCancelTransfer
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Верхний ряд: Рейтинг 1..5 и Цветовые метки
            HStack(spacing: 8) {
                // Левая капсула: Рейтинг 5 звёзд
                ratingPill
                
                // Правая капсула: Цветовые метки
                colorTagsPill
            }
            
            // Нижний ряд: Живой статус передачи и кнопка Экспорта
            HStack(spacing: 8) {
                // Левая капсула: Прогресс передачи
                transferStatusPill
                
                // Правая кнопка: Экспорт
                exportButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
    
    // MARK: - 1. Капсула рейтинга 1..5
    
    private var ratingPill: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    let newRating = (rating == star) ? 0 : star
                    onRatingChanged?(newRating)
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(star <= rating ? Color.white.opacity(0.95) : Color.white.opacity(0.25))
                        .frame(width: 22, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(glassCapsuleBackground)
    }
    
    // MARK: - 2. Капсула цветовых меток
    
    private var colorTagsPill: some View {
        HStack(spacing: 10) {
            let colors: [Color] = [
                Color(red: 235/255.0, green: 77/255.0, blue: 75/255.0),   // Red
                Color(red: 46/255.0, green: 204/255.0, blue: 113/255.0),  // Green
                Color(red: 52/255.0, green: 152/255.0, blue: 219/255.0),  // Blue
                Color(red: 241/255.0, green: 196/255.0, blue: 15/255.0),  // Yellow
                Color(red: 230/255.0, green: 126/255.0, blue: 34/255.0)   // Orange
            ]
            
            ForEach(0..<colors.count, id: \.self) { idx in
                let isSelected = (selectedColorTag == idx)
                Button {
                    let newTag = isSelected ? nil : idx
                    onColorTagChanged?(newTag ?? -1)
                } label: {
                    Circle()
                        .fill(colors[idx])
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(colors[idx].opacity(0.8), lineWidth: isSelected ? 2.5 : 0)
                                .scaleEffect(isSelected ? 1.6 : 1.0)
                        )
                        .frame(width: 20, height: 28)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(glassCapsuleBackground)
    }
    
    // MARK: - 3. Капсула передачи
    
    private var transferStatusPill: some View {
        Button {
            onTransferTap?()
        } label: {
            HStack(spacing: 8) {
                // Желтый бейдж TRANSFERRING
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppTheme.Colors.onAccent)
                        .frame(width: 5, height: 5)
                    
                    Text("TRANSFERRING:")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(AppTheme.Colors.onAccent)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(AppTheme.Colors.accent)
                .clipShape(Capsule())
                
                // Текст статуса передачи
                Text(transferStatusText)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Spacer(minLength: 0)
                
                // Кнопка отмены / закрытия
                if let onCancelTransfer {
                    Button(role: .destructive, action: onCancelTransfer) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(glassCapsuleBackground)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 4. Кнопка Экспорта
    
    private var exportButton: some View {
        Button {
            onExport?()
        } label: {
            HStack(spacing: 6) {
                Text("EXPORT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
                
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(glassCapsuleBackground)
        }
        .buttonStyle(.plain)
    }
    
    private var glassCapsuleBackground: some View {
        Capsule()
            .fill(Color(red: 26/255.0, green: 28/255.0, blue: 34/255.0).opacity(0.75))
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
    }
}
