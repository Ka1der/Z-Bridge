import SwiftUI

/// Экран раздела «Настройки» в адаптивном каркасе Liquid Glass.
/// Включает выбор языка интерфейса (Системный / Русский / English), параметры автозагрузки,
/// управление кэшем миниатюр, клиентский экран и системную диагностику.
public struct SettingsSectionView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var locManager = LocalizationManager.shared
    
    @State private var isCacheClearedNoticePresented: Bool = false
    @State private var isMatrixPresented: Bool = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                // 1. Заголовок экрана
                headerCard
                
                // 2. Блок выбора языка интерфейса
                languageSelectionCard
                
                // 3. Блок параметров импорта и съемки в реальном времени (live tethering)
                importParametersCard
                
                // 4. Блок кэша и хранилища
                storageAndCacheCard
                
                // 5. Блок клиентского монитора
                clientScreenCard
                
                // 6. О приложении
                aboutCard
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.xxl + 40)
        }
        .studioBackground()
        .sheet(isPresented: $isMatrixPresented) {
            CompatibilityMatrixView()
        }
    }
    
    // MARK: - 1. Шапка настроек
    
    private var headerCard: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.accent.opacity(0.18))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Настройки", "Settings"))
                    .font(AppTheme.Typography.title2.weight(.bold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                
                Text(tr("Конфигурация приложения и передача", "Application configuration & transfer"))
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
    }
    
    // MARK: - 2. Язык интерфейса
    
    private var languageSelectionCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                    
                    Text(tr("Язык приложения", "Application Language"))
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Spacer()
                }
                
                Text(tr(
                    "Базово используется язык вашей системы. Если язык системы не реализован в приложении, автоматически включается английский.",
                    "By default, system language is used. If your system language is not implemented in the app, English is automatically selected."
                ))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                
                // Переключатель языка
                Picker(tr("Язык", "Language"), selection: $locManager.selectedLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                
                // Плашка системного статуса
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppTheme.Colors.statusGreen)
                        .frame(width: 6, height: 6)
                    
                    Text(tr("Язык системы: ", "System language: ") + locManager.detectedSystemLanguageDisplayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    
                    Spacer()
                    
                    Text(tr("Активен: ", "Active: ") + (locManager.activeLanguage == .ru ? "RU" : "EN"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.Colors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 3. Параметры импорта
    
    private var importParametersCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                    
                    Text(tr("Импорт и съемка (Tethering)", "Import & Tethering"))
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Spacer()
                }
                
                // Тумблер live tethering
                Toggle(isOn: Binding(
                    get: { appState.currentUSBManager.isAutoDownloadNewShotsEnabled },
                    set: { appState.currentUSBManager.isAutoDownloadNewShotsEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Автозагрузка новых кадров (Live Tethering)", "Auto-download new shots (Live Tethering)"))
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(tr("Автоматически скачивать снимки при нажатии спуска на камере", "Automatically download photos upon camera shutter release"))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .tint(AppTheme.Colors.accent)
                
                Divider()
                    .background(AppTheme.Colors.borderSubtle)
                
                // Тумблер загрузки всей карты
                Toggle(isOn: Binding(
                    get: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled },
                    set: { appState.currentUSBManager.isAutoDownloadCardOnConnectEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Загружать все кадры при подключении", "Download all frames on connection"))
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(tr("Автоматически ставить в очередь все кадры с карты памяти при соединении", "Automatically queue all frames from memory card upon USB connection"))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
                .tint(AppTheme.Colors.accent)
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 4. Хранилище и кэш
    
    private var storageAndCacheCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                    
                    Text(tr("Хранилище и кэш", "Storage & Cache"))
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Место сохранения", "Save Destination"))
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(tr("Медиатека «Фото» iOS (альбом Nikon Z Bridge)", "iOS «Photos» library (Nikon Z Bridge album)"))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "photo.stack")
                        .foregroundStyle(AppTheme.Colors.accent)
                }
                
                Divider()
                    .background(AppTheme.Colors.borderSubtle)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Кэш миниатюр", "Thumbnail Cache"))
                            .font(AppTheme.Typography.subheadlineBold)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(tr("Освобождает оперативную память от предпросмотров", "Frees up RAM used by photo previews"))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        PreviewMemoryCache.shared.clear()
                        withAnimation {
                            isCacheClearedNoticePresented = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation {
                                isCacheClearedNoticePresented = false
                            }
                        }
                    } label: {
                        Text(isCacheClearedNoticePresented ? tr("Очищено ✓", "Cleared ✓") : tr("Очистить", "Clear"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isCacheClearedNoticePresented ? AppTheme.Colors.statusGreen : Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isCacheClearedNoticePresented ? AppTheme.Colors.statusGreen.opacity(0.18) : Color.white.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 5. Клиентский монитор
    
    private var clientScreenCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "display.2")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                    
                    Text(tr("Клиентский экран", "Client Monitor"))
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Spacer()
                }
                
                Text(tr(
                    "Трансляция свежих кадров на отдельный внешний монитор, iPad или телевизор для заказчика во время съемки.",
                    "Stream new photos to an external monitor, iPad, or TV for your client during tethered shooting."
                ))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 12) {
                    Button {
                        appState.isClientControlSheetPresented = true
                    } label: {
                        Label(tr("Управление монитором", "Monitor Controls"), systemImage: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .glassSurface(shape: Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        appState.isClientMonitorPresented = true
                    } label: {
                        Label(tr("Открыть экран", "Open Monitor"), systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.onAccent)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(AppTheme.Colors.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }
    
    // MARK: - 6. О приложении
    
    private var aboutCard: some View {
        GlassCard(cornerRadius: AppTheme.Radius.lg) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.accent)
                    
                    Text(tr("О программе", "About Nikon Z Bridge"))
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    
                    Spacer()
                    
                    Text("v1.0")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                
                Text(tr(
                    "Nikon Z Bridge — специализированное решение для проводного и беспроводного тетеринга камер Nikon Z. Обеспечивает мгновенный доступ к RAW и JPEG кадрам, быстрый отбор и передачу в медиатеку в концепции Liquid Glass.",
                    "Nikon Z Bridge is a specialized solution for tethered and wireless shooting with Nikon Z cameras. Delivers instant access to RAW and JPEG files, quick culling, and photo library transfers in Liquid Glass design."
                ))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                
                Button {
                    isMatrixPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                        Text(tr("Таблица совместимости камер Nikon Z", "Nikon Z Compatibility Matrix"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(AppTheme.Spacing.md)
        }
    }
}
