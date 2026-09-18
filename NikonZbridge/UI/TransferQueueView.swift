import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Экран очереди импорта, детального прогресса, ошибок и журнала диагностики
public struct TransferQueueView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: QueueTab = .all
    @State private var isExportingLog = false
    @State private var exportedLogText = ""
    @State private var copiedNotice = false
    
    public enum QueueTab: String, CaseIterable, Identifiable {
        case all = "Все"
        case pending = "В очереди"
        case failed = "Ошибки"
        case completed = "Завершенные"
        
        public var id: String { rawValue }
    }
    
    public init(appState: AppState) {
        self.appState = appState
    }
    
    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation {
            copiedNotice = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedNotice = false
            }
        }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Текущая активная передача
                    if let activeJob = appState.activeTransferJob {
                        activeTransferCard(job: activeJob)
                    }
                    
                    // 2. Сводная статистика (Сохраненные оригиналы vs Текущая попытка)
                    summaryStatsCard
                    
                    // 3. Табы очереди
                    tabPicker
                    
                    // 4. Список заданий в зависимости от вкладки
                    jobsListSection
                    
                    // 5. Управление экраном и фоновый режим
                    lifecycleAndNoticeCard
                    
                    // 6. Диагностический журнал и экспорт
                    diagnosticsCard
                }
                .padding(16)
            }
            .background(Color.black.opacity(0.95))
            .navigationTitle("Очередь и прогресс")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - 1. Карточка активной передачи
    
    private func activeTransferCard(job: TransferJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                Text("ПЕРЕДАЧА СЕЙЧАС")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.blue)
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: job.source.transportType == .usb ? "cable.connector" : "wifi")
                    Text(job.source.displayName)
                }
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.filename)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    let transferredMB = Double(job.transferredBytes) / 1_048_576.0
                    if let total = job.totalBytes, total > 0 {
                        let totalMB = Double(total) / 1_048_576.0
                        Text(String(format: "%.1f МБ из %.1f МБ", transferredMB, totalMB))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(format: "Получено %.1f МБ (размер потоковый)", transferredMB))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                
                Button(role: .destructive) {
                    appState.cancelJob(id: job.id)
                } label: {
                    Text("Отменить")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.2))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
            }
            
            // Прогресс-бар и процент ТОЛЬКО при известном полном размере
            if let total = job.totalBytes, total > 0 {
                let progress = min(max(Double(job.transferredBytes) / Double(total), 0.0), 1.0)
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue)
                                .frame(width: geo.size.width * CGFloat(progress), height: 6)
                        }
                    }
                    .frame(height: 6)
                    
                    HStack {
                        Text(String(format: "%.0f%%", progress * 100))
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                        Spacer()
                        if let eta = appState.currentETASeconds {
                            Text(String(format: "Осталось ~%.0f с", eta))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                // Если размер неизвестен — пульсирующая линия приема без фиктивного процента
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(height: 6)
            }
            
            // Скорость с интервалом измерения
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                    .font(.caption2)
                Text(String(format: "Скорость: %.1f МБ/с (сглаживание за 1.0 с)", appState.currentTransferSpeedMBs))
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
        .background(Color(white: 0.15).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - 2. Сводная статистика
    
    private var summaryStatsCard: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("СОХРАНЕНО ОРИГИНАЛОВ:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    let savedGB = Double(appState.savedOriginalsBytes) / 1_073_741_824.0
                    Text(String(format: "%.2f ГБ (%d файлов)", savedGB, appState.receivedFiles.count))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ТЕКУЩАЯ ПОПЫТКА:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    let attemptMB = Double(appState.currentAttemptBytes) / 1_048_576.0
                    Text(String(format: "%.1f МБ", attemptMB))
                        .font(.subheadline.bold())
                        .foregroundStyle(.blue)
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            HStack(spacing: 12) {
                statBadge(label: "Ожидают", count: appState.pendingJobs.count, color: .orange)
                statBadge(label: "Завершено", count: appState.completedJobs.count, color: .green)
                statBadge(label: "Ошибки", count: appState.failedJobs.count, color: .red)
            }
        }
        .padding(12)
        .background(Color(white: 0.15).opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func statBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label):")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
    
    // MARK: - 3. Табы
    
    private var tabPicker: some View {
        Picker("Фильтр заданий", selection: $selectedTab) {
            ForEach(QueueTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }
    
    // MARK: - 4. Список заданий
    
    private var jobsListSection: some View {
        VStack(spacing: 8) {
            let filtered = filteredJobs
            if filtered.isEmpty {
                Text("Нет заданий в этой категории")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                ForEach(filtered) { job in
                    jobRowView(job: job)
                }
            }
        }
    }
    
    private var filteredJobs: [TransferJob] {
        switch selectedTab {
        case .all:
            return appState.activeJobs
        case .pending:
            return appState.pendingJobs
        case .failed:
            return appState.failedJobs
        case .completed:
            return appState.completedJobs
        }
    }
    
    private func jobRowView(job: TransferJob) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.filename)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                
                HStack(spacing: 6) {
                    Text(job.source.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if let size = job.totalBytes {
                        Text(String(format: "• %.1f МБ", Double(size) / 1_048_576.0))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Описание ошибки при сбое
                if case .failed(let err) = job.state {
                    Text(DiagnosticLogger.userFriendlyMessage(for: err))
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else if case .interrupted(let reason) = job.state {
                    Text("Прервано: \(reason)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
            
            // Действия для заданий
            switch job.state {
            case .pending:
                Button(role: .destructive) {
                    appState.cancelJob(id: job.id)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                }
            case .failed, .interrupted:
                Button {
                    appState.retryJob(id: job.id)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                        Text("Повтор")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            default:
                EmptyView()
            }
        }
        .padding(10)
        .background(Color(white: 0.15).opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // MARK: - 5. Управление экраном и фоновым режимом
    
    private var lifecycleAndNoticeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Не выключать экран при съемке", isOn: $appState.lifecycleManager.isIdleTimerDisabledDuringShooting)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .tint(.green)
            
            Text(LifecycleManager.backgroundLimitationNotice)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(white: 0.15).opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - 6. Диагностический журнал
    
    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.yellow)
                Text("ДИАГНОСТИЧЕСКИЙ ЖУРНАЛ")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.yellow)
                Spacer()
                
                Button {
                    let log = appState.diagnosticLogger.exportDiagnosticReport(
                        sessionName: appState.currentSession?.name,
                        cameraModel: appState.connectionStatusTitle,
                        totalAssets: appState.receivedFiles.count,
                        networkIPs: appState.activeIPs.map { "\($0.interfaceName): \($0.ipAddress)" }
                    )
                    self.exportedLogText = log
                    copyToClipboard(log)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                        Text(copiedNotice ? "Скопирован!" : "Экспорт журнала")
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
            
            Text("Журнал содержит технические детали и сетевые события. Все пароли и секреты автоматически маскируются перед сохранением.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(white: 0.15).opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
