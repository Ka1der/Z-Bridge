import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Пошаговый интерактивный мастер подключения камеры Nikon Z
public struct ConnectionWizardView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentStep: Int = 1
    @State private var selectedModel: NikonCameraModel = .z8
    @State private var selectedTransport: NikonConnectionTransport = .directUSB
    @State private var isTestingProbe: Bool = false
    @State private var probeSuccessMessage: String?
    @State private var probeErrorMessage: String?
    @State private var copiedNotice: String = ""
    
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
            VStack(spacing: 0) {
                // Индикатор шагов 1..6
                stepProgressIndicator
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.12))
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Контент текущего шага
                ScrollView {
                    VStack(spacing: 20) {
                        switch currentStep {
                        case 1:
                            step1ModelSelection
                        case 2:
                            step2TransportSelection
                        case 3:
                            step3InstructionsView
                        case 4:
                            step4PermissionsAndStatus
                        case 5:
                            step5CredentialsAndParameters
                        case 6:
                            step6ReadinessAndProbe
                        default:
                            EmptyView()
                        }
                    }
                    .padding()
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Панель навигации назад/вперед
                navigationControls
                    .padding()
                    .background(Color(white: 0.12))
            }
            .background(Color.black.opacity(0.96))
            .navigationTitle("Мастер подключения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
    
    // MARK: - Индикатор шагов
    
    private var stepProgressIndicator: some View {
        HStack(spacing: 6) {
            ForEach(1...6, id: \.self) { step in
                HStack(spacing: 4) {
                    Circle()
                        .fill(step <= currentStep ? Color.blue : Color.white.opacity(0.2))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text("\(step)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(step <= currentStep ? .white : .secondary)
                        )
                    
                    if step < 6 {
                        Rectangle()
                            .fill(step < currentStep ? Color.blue : Color.white.opacity(0.15))
                            .frame(height: 2)
                    }
                }
            }
        }
    }
    
    // MARK: - ШАГ 1: Выбор модели камеры
    
    private var step1ModelSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ШАГ 1 ИЗ 6")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text("Выберите модель вашей камеры Nikon Z")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Каждая модель имеет свои особенности портов (Ethernet RJ-45, двойной USB-C) и меню.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(NikonCameraModel.allCases) { model in
                    let isSelected = selectedModel == model
                    Button {
                        selectedModel = model
                        // Если выбранный транспорт не поддерживается этой моделью, переключаем на первый доступный
                        if !model.supportedTransports.contains(selectedTransport) {
                            selectedTransport = model.supportedTransports.first ?? .directUSB
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(model.fullName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                            
                            Text(model.processor.rawValue)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                            
                            Text(model.sensorDescription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            if model.hasBuiltInRJ45 {
                                Text("• Встроенный RJ-45 LAN")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            } else if model.hasDualUSBPorts {
                                Text("• Двойной USB-C (Data + PD)")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.blue.opacity(0.25) : Color(white: 0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - ШАГ 2: Выбор транспорта + Разъяснение прямого USB и USB-Ethernet
    
    private var step2TransportSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ШАГ 2 ИЗ 6")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text("Выберите способ подключения для \(selectedModel.fullName)")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
            
            // Карточка разъяснения разницы между прямым USB и USB-Ethernet
            usbVersusEthernetExplainerCard
            
            // Список поддерживаемых транспортов для выбранной модели
            VStack(spacing: 12) {
                ForEach(selectedModel.supportedTransports) { transport in
                    let isSelected = selectedTransport == transport
                    Button {
                        selectedTransport = transport
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: transportIcon(for: transport))
                                .font(.system(size: 22))
                                .foregroundStyle(isSelected ? .blue : .white)
                                .frame(width: 32)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(transport.title)
                                    .font(.headline)
                                    .foregroundStyle(isSelected ? .white : .primary)
                                Text(transport.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(14)
                        .background(isSelected ? Color.blue.opacity(0.2) : Color(white: 0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var usbVersusEthernetExplainerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("В ЧЁМ РАЗНИЦА: ПРЯМОЙ USB И USB–ETHERNET?")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Прямой USB-кабель (PTP / MTP)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        Text("Камера работает как периферийное устройство. Приложение само видит файлы на карте памяти и инициирует загрузку. Не требует настройки сети и IP-адресов. Длина кабеля ограничена 2–3 метрами.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "network")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("USB–Ethernet адаптер (FTP поверх витой пары)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        Text("В порт камеры вставляется адаптер USB-C ➔ RJ-45. Камера работает как полноценный сетевой хост и отправляет снимки на наш FTP-сервер. Позволяет использовать кабели длиной до 100 метров без потери стабильности.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.blue.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - ШАГ 3: Точные инструкции для выбранной модели
    
    private var step3InstructionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ШАГ 3 ИЗ 6")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text("Настройка меню \(selectedModel.fullName)")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Точные разделы меню вашей камеры для режима «\(selectedTransport.title)»:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            let steps = selectedModel.instructions(for: selectedTransport)
            VStack(spacing: 12) {
                ForEach(steps) { step in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Text("\(step.id)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                )
                            Text(step.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        
                        // Путь в меню (RU)
                        HStack(alignment: .top, spacing: 6) {
                            Text("RU:")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                            Text(step.menuPathRu)
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        // Путь в меню (EN)
                        HStack(alignment: .top, spacing: 6) {
                            Text("EN:")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(step.menuPathEn)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Text(step.details)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                        
                        if let tip = step.tip {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                Text(tip)
                                    .font(.caption2)
                                    .foregroundStyle(.yellow.opacity(0.9))
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(white: 0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    // MARK: - ШАГ 4: Проверка разрешений и статуса
    
    private var step4PermissionsAndStatus: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ШАГ 4 ИЗ 6")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text("Проверка готовности системы")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Диагностика сетевого интерфейса, прав доступа и состояния приёма:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            let readiness = ConnectionReadinessChecker.shared.checkReadiness(
                model: selectedModel,
                transport: selectedTransport,
                isServerRunning: appState.isServerRunning,
                serverPort: appState.serverPort,
                isUSBConnected: appState.usbConnected,
                storageDirectory: appState.currentSessionDirectory,
                activeInterfaces: appState.activeIPs
            )
            
            VStack(spacing: 12) {
                statusRow(
                    title: "Хранилище сессии",
                    subtitle: "Папка: \(appState.currentSession?.name ?? "Сессия")",
                    isSuccess: !readiness.issues.contains { $0.contains("защищен от записи") }
                )
                
                if selectedTransport == .directUSB {
                    statusRow(
                        title: "USB-подключение камеры",
                        subtitle: appState.usbConnected ? "Камера обнаружена по кабелю" : "Ожидание подключения кабеля",
                        isSuccess: appState.usbConnected
                    )
                } else {
                    statusRow(
                        title: "Служба приёма FTP",
                        subtitle: appState.isServerRunning ? "Сервер активен на порту \(appState.serverPort)" : "Сервер остановлен",
                        isSuccess: appState.isServerRunning
                    )
                    
                    statusRow(
                        title: "Сетевой интерфейс (\(selectedTransport.title))",
                        subtitle: readiness.matchedIPAddress != nil ? "Активный IP: \(readiness.matchedIPAddress!) (\(readiness.networkInterfaceName ?? "eth"))" : "Нет подходящего активного сетевого адреса",
                        isSuccess: readiness.matchedIPAddress != nil
                    )
                }
            }
            
            if !readiness.issues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("РЕКОМЕНДАЦИИ:")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    ForEach(readiness.recommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text(rec)
                                .font(.caption)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Все системные требования соблюдены. Тракт готов к приёму.")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private func statusRow(title: String, subtitle: String, isSuccess: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isSuccess ? .green : .red)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(white: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - ШАГ 5: Параметры подключения и учетные данные
    
    private var step5CredentialsAndParameters: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ШАГ 5 ИЗ 6")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text("Параметры для ввода в меню камеры")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Введите эти данные в профиле FTP-сервера вашей камеры:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !copiedNotice.isEmpty {
                Text(copiedNotice)
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }
            
            let (interface, matchedIP) = ConnectionReadinessChecker.shared.resolveBestEndpoint(
                for: selectedTransport,
                availableInterfaces: appState.activeIPs
            )
            
            if selectedTransport == .directUSB {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "cable.connector")
                            .foregroundStyle(.green)
                        Text("ПРЯМОЙ USB НЕ ТРЕБУЕТ НАСТРОЙКИ IP")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                    Text("Для прямого кабельного импорта ввод IP-адресов, портов и паролей в камере не требуется. Просто убедитесь, что кабель вставлен, и переходите к пробному снимку.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(white: 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 12) {
                    parameterCard(
                        title: "IP-АДРЕС СЕРВЕРА (HOST IP)",
                        value: matchedIP ?? (appState.primaryIP?.ipAddress ?? "192.168.1.100"),
                        note: "Интерфейс: \(interface?.interfaceName ?? "en0")",
                        copyValue: matchedIP ?? appState.primaryIP?.ipAddress ?? ""
                    )
                    
                    parameterCard(
                        title: "ПОРТ FTP СЕРВЕРА",
                        value: "\(appState.serverPort)",
                        note: "Внимание: порт 2121 (не 21!)",
                        copyValue: "\(appState.serverPort)"
                    )
                    
                    parameterCard(
                        title: "ЛОГИН (USER ID)",
                        value: appState.ftpUsername,
                        note: "По умолчанию: nikon",
                        copyValue: appState.ftpUsername
                    )
                    
                    parameterCard(
                        title: "ПАРОЛЬ (PASSWORD)",
                        value: appState.ftpPassword,
                        note: "Сгенерирован для вашей студии",
                        copyValue: appState.ftpPassword
                    )
                }
            }
        }
    }
    
    private func parameterCard(title: String, value: String, note: String, copyValue: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Spacer()
            
            Button {
                copyToClipboard(copyValue, notice: "Скопировано: \(value)")
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 16))
                    .foregroundStyle(.blue)
                    .padding(8)
                    .background(Color.blue.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(14)
        .background(Color(white: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - ШАГ 6: Проверка готовности и приёма пробного файла
    
    private var step6ReadinessAndProbe: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ШАГ 6 ИЗ 6")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text("Проверка готовности и тестовый снимок")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Убедитесь в готовности системы перед началом реальной фотосессии:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Статус готовности
            HStack(spacing: 12) {
                Circle()
                    .fill(appState.isCameraConnected ? Color.green : Color.orange)
                    .frame(width: 14, height: 14)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.isCameraConnected ? "Камера подключена и готова" : "Ожидание кадра от камеры")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Сделайте тестовый спуск затвора на камере. Снимок мгновенно появится в ленте.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color(white: 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Кнопка программного пробного файла (Test Probe)
            VStack(alignment: .leading, spacing: 10) {
                Text("ПРОВЕРКА ТРАКТА СОХРАНЕНИЯ (TEST PROBE)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                Text("Вы можете сгенерировать пробный кадр, чтобы удостовериться, что staging-файлы, атомарный move, верификация контрольных сумм и база данных SQLite работают исправно.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button {
                    executeTestProbe()
                } label: {
                    HStack {
                        if isTestingProbe {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark.shield.fill")
                        }
                        Text(isTestingProbe ? "Проверка тракта..." : "Отправить пробный тестовый кадр")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isTestingProbe)
                
                if let success = probeSuccessMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(success)
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                    .padding(.top, 4)
                }
                
                if let err = probeErrorMessage {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.caption.bold())
                            .foregroundStyle(.red)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .background(Color(white: 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func executeTestProbe() {
        guard let session = appState.currentSession else { return }
        isTestingProbe = true
        probeSuccessMessage = nil
        probeErrorMessage = nil
        
        let source = CameraSource(
            id: "wizard-probe",
            model: selectedModel.fullName,
            transportType: selectedTransport.isFTP ? .ftp : .usb
        )
        
        Task {
            do {
                let ingested = try await ConnectionReadinessChecker.shared.sendTestProbeFile(
                    coordinator: appState.coordinator,
                    session: session,
                    source: source
                )
                await MainActor.run {
                    appState.receivedFiles.insert(ingested, at: 0)
                    isTestingProbe = false
                    probeSuccessMessage = "Тестовый кадр \(ingested.filename) успешно сохранён и верифицирован!"
                }
            } catch {
                await MainActor.run {
                    isTestingProbe = false
                    probeErrorMessage = "Ошибка пробного сохранения: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Навигационные кнопки Вперёд / Назад
    
    private var navigationControls: some View {
        HStack {
            if currentStep > 1 {
                Button {
                    withAnimation {
                        currentStep -= 1
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Назад")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            if currentStep < 6 {
                Button {
                    withAnimation {
                        currentStep += 1
                    }
                } label: {
                    HStack {
                        Text("Далее")
                        Image(systemName: "chevron.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(Capsule())
                }
            } else {
                Button {
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Завершить")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .clipShape(Capsule())
                }
            }
        }
    }
    
    private func transportIcon(for transport: NikonConnectionTransport) -> String {
        switch transport {
        case .directUSB:
            return "cable.connector"
        case .builtInEthernet:
            return "network"
        case .usbToEthernet:
            return "arrow.left.arrow.right"
        case .builtInWiFiFTP:
            return "wifi"
        case .wt7Transmitter:
            return "antenna.radiowaves.left.and.right"
        }
    }
}
