import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Модальное окно подключения с управлением FTP-сервером, авторизацией и инструкциями
public struct ConnectionSheetView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var copiedNotice = ""
    @State private var isPasswordVisible = false
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private func copyToClipboard(_ text: String, notice: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation {
            copiedNotice = notice
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedNotice = ""
            }
        }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Статус подключения
                    statusCard
                    
                    // Мастер подключения и совместимость (Этап 7)
                    VStack(spacing: 10) {
                        Button {
                            appState.isWizardPresented = true
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Мастер подключения Nikon Z")
                                        .font(.headline.bold())
                                    Text("Пошаговый подбор настроек и точные пункты меню вашей модели")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                            }
                            .padding(14)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        
                        Button {
                            appState.isMatrixPresented = true
                        } label: {
                            HStack {
                                Image(systemName: "checklist")
                                    .font(.headline)
                                Text("Таблица совместимости моделей и прошивок")
                                    .font(.subheadline.bold())
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .padding(12)
                            .background(Color(white: 0.18))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    // 2. Управление FTP-сервером и настройки
                    ftpSettingsCard
                    
                    // 3. Способ 1: По кабелю USB-C (Без FTP)
                    usbGuideCard
                    
                    // 4. Способ 2: По воздуху (Wi-Fi через FTP)
                    wifiGuideCard
                }
                .padding()
            }
            .background(Color.black.opacity(0.95))
            .navigationTitle("Подключение камеры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $appState.isWizardPresented) {
            ConnectionWizardView(appState: appState)
        }
        .sheet(isPresented: $appState.isMatrixPresented) {
            CompatibilityMatrixView()
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(appState.isCameraConnected ? Color.green : Color.orange)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.connectionStatusTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(appState.isCameraConnected ? "Камера готова к передаче снимков" : "Ожидание подключения кабеля или Wi-Fi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(white: 0.15).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - FTP Settings Card
    
    private var ftpSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.orange)
                Text("УПРАВЛЕНИЕ ПРИЁМОМ FTP")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.orange)
                Spacer()
                
                switch appState.serverState {
                case .running(let port):
                    Text("Порт \(port) активен")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                case .starting:
                    Text("Запуск...")
                        .font(.caption2.bold())
                        .foregroundStyle(.yellow)
                case .stopped:
                    Text("Остановлен")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                case .failed(let err):
                    Text("Ошибка: \(err)")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
            
            // Переключатель приёма
            Toggle(isOn: Binding(
                get: { appState.isFTPReceivingEnabled },
                set: { appState.toggleFTPReceiving($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Приём по FTP")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("Разрешить входящие соединения от камер")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.green)
            
            // Переключатель автозапуска
            Toggle(isOn: Binding(
                get: { appState.isFTPAutoStartEnabled },
                set: { appState.toggleFTPAutoStart($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Автозапуск при старте")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("Запускать приём автоматически при открытии программы")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)
            
            // Кнопка перезапуска
            HStack {
                Button {
                    appState.restartServer()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Перезапустить FTP-сервер")
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(white: 0.15).opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - USB Guide
    
    private var usbGuideCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cable.connector")
                    .foregroundStyle(.green)
                Text("СПОСОБ 1: ПО КАБЕЛЮ USB-C (БЕЗ FTP)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.green)
                Spacer()
                Text("Рекомендуется")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
            
            Text("1. В меню камеры: **Настройки ➔ USB ➔ «Передача файлов»**.")
            Text("2. Соедините камеру и устройство кабелем Type-C.")
            Text("3. **Всё! Настраивать FTP в камере НЕ НУЖНО.** Приложение сразу распознает камеру.")
                .foregroundStyle(.white.opacity(0.8))
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.85))
        .padding()
        .background(Color(white: 0.15).opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Wi-Fi Guide & Credentials
    
    private var wifiGuideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundStyle(.blue)
                Text("СПОСОБ 2: ПО ВОЗДУХУ (WI-FI ЧЕРЕЗ FTP)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.blue)
            }
            
            if !copiedNotice.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(copiedNotice)
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 4)
            }
            
            // IP и порт
            if let primary = appState.primaryIP {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("СЕРВЕР (IP И ПОРТ):")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("\(primary.ipAddress) : \(appState.serverPort)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button {
                        copyToClipboard(primary.ipAddress, notice: "IP скопирован!")
                    } label: {
                        Text("Копировать IP")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Учетные данные для камеры (Логин и Пароль из Keychain)
            VStack(spacing: 8) {
                // Логин
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ИМЯ ПОЛЬЗОВАТЕЛЯ (USER):")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(appState.ftpUsername)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button {
                        copyToClipboard(appState.ftpUsername, notice: "Логин скопирован!")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .padding(6)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                }
                
                Divider().background(Color.white.opacity(0.1))
                
                // Пароль
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ПАРОЛЬ (PASS) В KEYCHAIN:")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(isPasswordVisible ? appState.ftpPassword : "••••••••")
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .font(.caption)
                            .padding(6)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                    
                    Button {
                        copyToClipboard(appState.ftpPassword, notice: "Пароль скопирован!")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .padding(6)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                    
                    Button {
                        appState.regenerateFTPPassword()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .padding(6)
                            .background(Color.orange.opacity(0.3))
                            .foregroundStyle(.orange)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Text("1. В меню камеры: **Сеть 📡 ➔ «Подключение к FTP-серверу»**.")
            Text("2. Создайте профиль, укажите IP, порт, логин и пароль выше.")
            Text("3. Включите «Автоматическая отправка» — кадры будут передаваться по Wi-Fi.")
            
            Text("Примечание: Передача по Wi-Fi выполняется по стандартному открытому протоколу FTP для локальной сети студии (без TLS). Пароль хранится в защищенной системной связке ключей Keychain.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.85))
        .padding()
        .background(Color(white: 0.15).opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
