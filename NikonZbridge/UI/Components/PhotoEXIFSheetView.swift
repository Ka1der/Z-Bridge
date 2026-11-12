import SwiftUI

/// Модальный экран детального просмотра параметров съемки (EXIF) в дизайн-системе Liquid Glass
public struct PhotoEXIFSheetView: View {
    public let item: CameraFileItem
    public let usbManager: USBCameraManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var exifData: PhotoEXIFData
    @State private var isLoading: Bool = true
    
    public init(item: CameraFileItem, usbManager: USBCameraManager) {
        self.item = item
        self.usbManager = usbManager
        _exifData = State(initialValue: PhotoEXIFData(
            item: item,
            defaultCameraName: usbManager.cameraName ?? "Nikon Z",
            rawProperties: nil,
            pixelWidth: item.thumbnail?.width,
            pixelHeight: item.thumbnail?.height
        ))
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Карточка заголовка файла
                    headerCard
                    
                    // Крупные параметры экспозиции (выдержка, диафрагма, ISO, фокус)
                    exposureSummaryCard
                    
                    // Секция 1: Камера и оптика
                    cameraHardwareSection
                    
                    // Секция 2: Параметры и режимы съёмки
                    shootingSettingsSection
                    
                    // Секция 3: Файл и изображение
                    fileDetailsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(AppTheme.Colors.background.ignoresSafeArea())
            .navigationTitle(tr("Сведения EXIF", "EXIF Info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(tr("Готово", "Done"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.accent)
                    }
                }
            }
            .task {
                await loadEXIFMetadata()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Карточка файла в шапке
    
    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "camera.aperture")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.accent)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.filename)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    
                    Text(item.isRAW ? "RAW" : "JPEG")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.isRAW ? AppTheme.Colors.accent : Color.white.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                Text("\(exifData.cameraModel ?? "Nikon Z") • \(item.formattedSize)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(AppTheme.Colors.accent)
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: AppTheme.Radius.md)
    }
    
    // MARK: - Карточка ключевых параметров экспозиции (4 колонки)
    
    private var exposureSummaryCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            HStack(spacing: 0) {
                exposureMetricColumn(
                    title: tr("Выдержка", "Shutter"),
                    value: exifData.shutterSpeed ?? "—",
                    icon: "timer"
                )
                
                Divider()
                    .frame(height: 38)
                    .background(Color.white.opacity(0.12))
                
                exposureMetricColumn(
                    title: tr("Диафрагма", "Aperture"),
                    value: exifData.aperture ?? "—",
                    icon: "camera.aperture"
                )
                
                Divider()
                    .frame(height: 38)
                    .background(Color.white.opacity(0.12))
                
                exposureMetricColumn(
                    title: "ISO",
                    value: exifData.iso ?? "—",
                    icon: "bolt.fill"
                )
                
                Divider()
                    .frame(height: 38)
                    .background(Color.white.opacity(0.12))
                
                exposureMetricColumn(
                    title: tr("Фокус", "Focal"),
                    value: exifData.focalLength ?? "—",
                    icon: "arrow.left.and.right"
                )
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
    }
    
    private func exposureMetricColumn(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.Colors.accent)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.60))
            }
            
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Секция: Камера и оптика
    
    private var cameraHardwareSection: some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "camera.fill", title: tr("Оборудование", "Camera & Lens"))
                
                infoRow(label: tr("Камера", "Camera"), value: exifData.cameraModel ?? (usbManager.cameraName ?? "Nikon Z"))
                if let make = exifData.cameraMake {
                    infoRow(label: tr("Производитель", "Make"), value: make)
                }
                if let lens = exifData.lensModel {
                    infoRow(label: tr("Объектив", "Lens"), value: lens)
                }
                if let soft = exifData.softwareVersion {
                    infoRow(label: tr("Версия прошивки", "Firmware"), value: soft)
                }
            }
            .padding(14)
        }
    }
    
    // MARK: - Секция: Параметры и режимы съёмки
    
    private var shootingSettingsSection: some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "slider.horizontal.3", title: tr("Параметры съёмки", "Shooting Settings"))
                
                if let prog = exifData.exposureProgram {
                    infoRow(label: tr("Режим экспозиции", "Exposure Program"), value: prog)
                }
                if let bias = exifData.exposureBias {
                    infoRow(label: tr("Экспокоррекция", "Exposure Bias"), value: bias)
                }
                if let meter = exifData.meteringMode {
                    infoRow(label: tr("Режим замера", "Metering Mode"), value: meter)
                }
                if let wb = exifData.whiteBalance {
                    infoRow(label: tr("Баланс белого", "White Balance"), value: wb)
                }
                if let flash = exifData.flash {
                    infoRow(label: tr("Вспышка", "Flash"), value: flash)
                }
                if let f35 = exifData.focalLength35mm {
                    infoRow(label: tr("Фокусное расстояние (35мм)", "35mm Equivalent"), value: f35)
                }
                if exifData.exposureProgram == nil && exifData.meteringMode == nil {
                    infoRow(label: tr("Статус метаданных", "Metadata Status"), value: tr("Чтение с карты памяти...", "Reading from memory card..."))
                }
            }
            .padding(14)
        }
    }
    
    // MARK: - Секция: Файл и изображение
    
    private var fileDetailsSection: some View {
        GlassCard(cornerRadius: AppTheme.Radius.md) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(icon: "doc.text.fill", title: tr("Сведения о файле", "File Information"))
                
                infoRow(label: tr("Имя файла", "Filename"), value: item.filename)
                infoRow(label: tr("Формат", "Format"), value: exifData.fileFormatString)
                infoRow(label: tr("Размер файла", "File Size"), value: item.formattedSize)
                if let dim = exifData.dimensions {
                    infoRow(label: tr("Разрешение", "Dimensions"), value: dim)
                }
                if let date = exifData.dateTimeOriginal {
                    infoRow(label: tr("Дата и время съёмки", "Date & Time"), value: date)
                }
                if let cs = exifData.colorSpace {
                    infoRow(label: tr("Цветовой профиль", "Color Space"), value: cs)
                }
            }
            .padding(14)
        }
    }
    
    // MARK: - Вспомогательные элементы UI
    
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.Colors.accent)
            Text(title)
                .font(AppTheme.Typography.captionBold)
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.bottom, 2)
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(AppTheme.Typography.captionBold)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
    
    // MARK: - Загрузка реальных метаданных
    
    private func loadEXIFMetadata() async {
        isLoading = true
        let raw = await usbManager.requestEXIFMetadata(for: item)
        
        await MainActor.run {
            self.exifData = PhotoEXIFData(
                item: self.item,
                defaultCameraName: self.usbManager.cameraName ?? "Nikon Z",
                rawProperties: raw,
                pixelWidth: self.item.thumbnail?.width,
                pixelHeight: self.item.thumbnail?.height
            )
            self.isLoading = false
        }
    }
}
