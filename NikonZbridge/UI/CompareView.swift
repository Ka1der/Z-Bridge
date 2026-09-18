import SwiftUI

/// Режим двухкадрового сравнения (Side-by-Side Compare) с синхронным зумом и панорамированием
public struct CompareView: View {
    @ObservedObject var appState: AppState
    @State private var groupA: CaptureGroup
    @State private var groupB: CaptureGroup
    
    // Синхронизация масштаба и панорамы
    @State private var isSynchronized: Bool = true
    
    // Zoom & Pan для кадра A
    @State private var zoomA: CGFloat = 1.0
    @State private var baseZoomA: CGFloat = 1.0
    @State private var panA: CGSize = .zero
    @State private var basePanA: CGSize = .zero
    
    // Zoom & Pan для кадра B
    @State private var zoomB: CGFloat = 1.0
    @State private var baseZoomB: CGFloat = 1.0
    @State private var panB: CGSize = .zero
    @State private var basePanB: CGSize = .zero
    
    // Состояния загрузки превью
    @State private var previewA: PlatformImage?
    @State private var previewB: PlatformImage?
    @State private var isLoadingA: Bool = false
    @State private var isLoadingB: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    
    public init(appState: AppState, initialGroupA: CaptureGroup? = nil, initialGroupB: CaptureGroup? = nil) {
        self.appState = appState
        let a = initialGroupA ?? appState.selectedGroup ?? appState.filteredGroups.first ?? CaptureGroup(baseName: "A", sessionID: UUID())
        let b = initialGroupB ?? appState.filteredGroups.first(where: { $0.id != a.id }) ?? a
        _groupA = State(initialValue: a)
        _groupB = State(initialValue: b)
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Верхняя панель управления сравнением
                topToolbar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.85))
                
                // Двухкадровое поле сравнения
                GeometryReader { geo in
                    let isLandscape = geo.size.width > geo.size.height
                    if isLandscape {
                        HStack(spacing: 4) {
                            framePane(for: $groupA, isA: true, size: CGSize(width: (geo.size.width - 4) / 2, height: geo.size.height))
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 2)
                            framePane(for: $groupB, isA: false, size: CGSize(width: (geo.size.width - 4) / 2, height: geo.size.height))
                        }
                    } else {
                        VStack(spacing: 4) {
                            framePane(for: $groupA, isA: true, size: CGSize(width: geo.size.width, height: (geo.size.height - 4) / 2))
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 2)
                            framePane(for: $groupB, isA: false, size: CGSize(width: geo.size.width, height: (geo.size.height - 4) / 2))
                        }
                    }
                }
                
                // Нижняя лента для быстрой смены кадра B
                bottomCandidateFilmstrip
                    .frame(height: 80)
                    .background(Color.black.opacity(0.9))
            }
        }
        .task(id: groupA.id) {
            await loadPreviewA()
        }
        .task(id: groupB.id) {
            await loadPreviewB()
        }
        .onAppear {
            appState.isUserInspecting = true
        }
        .onDisappear {
            appState.isUserInspecting = false
        }
    }
    
    // MARK: - Top Toolbar
    
    private var topToolbar: some View {
        HStack(spacing: 12) {
            // Кнопка закрытия
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                    Text("Закрыть")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }
            
            Text("Сравнение кадров (Side-by-Side)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            
            Spacer()
            
            // Кнопка синхронизации масштаба и панорамы
            Button {
                isSynchronized.toggle()
                if isSynchronized {
                    // При выравнивании синхронизируем B по A
                    zoomB = zoomA
                    baseZoomB = baseZoomA
                    panB = panA
                    basePanB = basePanA
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSynchronized ? "lock.fill" : "lock.open.fill")
                    Text(isSynchronized ? "Синхронно" : "Раздельно")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(isSynchronized ? Color.white : Color.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSynchronized ? Color.blue : Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
            
            // Кнопка сброса зума
            Button {
                withAnimation(.spring(response: 0.25)) {
                    zoomA = 1.0; baseZoomA = 1.0; panA = .zero; basePanA = .zero
                    zoomB = 1.0; baseZoomB = 1.0; panB = .zero; basePanB = .zero
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            
            // Кнопка рокировки A <-> B (Swap)
            Button {
                swapFrames()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                    Text("Поменять")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }
        }
    }
    
    private func swapFrames() {
        let tempG = groupA
        groupA = groupB
        groupB = tempG
        
        let tempPrev = previewA
        previewA = previewB
        previewB = tempPrev
    }
    
    // MARK: - Frame Pane
    
    @ViewBuilder
    private func framePane(for group: Binding<CaptureGroup>, isA: Bool, size: CGSize) -> some View {
        let currentZoom = isA ? zoomA : zoomB
        let currentPan = isA ? panA : panB
        let preview = isA ? previewA : previewB
        let isLoading = isA ? isLoadingA : isLoadingB
        
        let maxPanX = max(0, (size.width * currentZoom - size.width) / 2)
        let maxPanY = max(0, (size.height * currentZoom - size.height) / 2)
        
        ZStack(alignment: .top) {
            Color.black
            
            if let img = preview {
                #if canImport(UIKit)
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(max(1.0, currentZoom))
                    .offset(currentPan)
                    .frame(width: size.width, height: size.height)
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { val in
                                let newZoom = max(1.0, min(8.0, (isA ? baseZoomA : baseZoomB) * val))
                                if isSynchronized {
                                    zoomA = newZoom
                                    zoomB = newZoom
                                } else if isA {
                                    zoomA = newZoom
                                } else {
                                    zoomB = newZoom
                                }
                            }
                            .onEnded { val in
                                let newBase = max(1.0, min(8.0, (isA ? zoomA : zoomB)))
                                if isSynchronized {
                                    baseZoomA = newBase
                                    baseZoomB = newBase
                                    zoomA = newBase
                                    zoomB = newBase
                                } else if isA {
                                    baseZoomA = newBase
                                    zoomA = newBase
                                } else {
                                    baseZoomB = newBase
                                    zoomB = newBase
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { val in
                                guard (isA ? zoomA : zoomB) > 1.05 else { return }
                                let baseOffset = isA ? basePanA : basePanB
                                let proposedX = baseOffset.width + val.translation.width
                                let proposedY = baseOffset.height + val.translation.height
                                let clamped = CGSize(
                                    width: min(maxPanX, max(-maxPanX, proposedX)),
                                    height: min(maxPanY, max(-maxPanY, proposedY))
                                )
                                if isSynchronized {
                                    panA = clamped
                                    panB = clamped
                                } else if isA {
                                    panA = clamped
                                } else {
                                    panB = clamped
                                }
                            }
                            .onEnded { _ in
                                if isSynchronized {
                                    basePanA = panA
                                    basePanB = panB
                                } else if isA {
                                    basePanA = panA
                                } else {
                                    basePanB = panB
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.25)) {
                            let targetZoom: CGFloat = (isA ? zoomA : zoomB) > 1.05 ? 1.0 : 2.5
                            if isSynchronized {
                                zoomA = targetZoom; baseZoomA = targetZoom; panA = .zero; basePanA = .zero
                                zoomB = targetZoom; baseZoomB = targetZoom; panB = .zero; basePanB = .zero
                            } else if isA {
                                zoomA = targetZoom; baseZoomA = targetZoom; panA = .zero; basePanA = .zero
                            } else {
                                zoomB = targetZoom; baseZoomB = targetZoom; panB = .zero; basePanB = .zero
                            }
                        }
                    }
                #elseif canImport(AppKit)
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(max(1.0, currentZoom))
                    .offset(currentPan)
                #endif
            } else if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Загрузка кадра...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Заголовок кадра (A или B) и его контролы отбора
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Text(isA ? "Эталон (A)" : "Кандидат (B)")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(isA ? Color.blue : Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        Text(group.wrappedValue.baseName)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    
                    Spacer()
                    
                    // Кнопки отбора для данного кадра
                    paneCullingControls(group: group)
                }
                .padding(8)
                
                Spacer()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
    
    // MARK: - Pane Culling Controls
    
    private func paneCullingControls(group: Binding<CaptureGroup>) -> some View {
        HStack(spacing: 4) {
            // Звезды
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        let newRating = (group.wrappedValue.rating == star) ? 0 : star
                        group.wrappedValue.setRating(newRating)
                        appState.setRating(newRating, for: group.wrappedValue)
                    } label: {
                        Image(systemName: star <= group.wrappedValue.rating ? "star.fill" : "star")
                            .font(.system(size: 13))
                            .foregroundStyle(star <= group.wrappedValue.rating ? Color.yellow : Color.white.opacity(0.35))
                    }
                }
            }
            
            Divider()
                .frame(height: 14)
                .background(Color.white.opacity(0.3))
                .padding(.horizontal, 2)
            
            // Pick (флаг)
            Button {
                let newStatus: PickStatus = (group.wrappedValue.pickStatus == .picked) ? .unflagged : .picked
                group.wrappedValue.setPickStatus(newStatus)
                appState.setPickStatus(newStatus, for: group.wrappedValue)
            } label: {
                Image(systemName: "flag.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(group.wrappedValue.pickStatus == .picked ? Color.green : Color.white.opacity(0.4))
            }
            
            // Reject (крестик)
            Button {
                let newStatus: PickStatus = (group.wrappedValue.pickStatus == .rejected) ? .unflagged : .rejected
                group.wrappedValue.setPickStatus(newStatus)
                appState.setPickStatus(newStatus, for: group.wrappedValue)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(group.wrappedValue.pickStatus == .rejected ? Color.red : Color.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
    
    // MARK: - Bottom Candidate Filmstrip
    
    private var bottomCandidateFilmstrip: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Выберите кадр (B) для сравнения:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.filteredGroups.count) кадров")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(appState.filteredGroups) { g in
                        let isA = (g.id == groupA.id)
                        let isB = (g.id == groupB.id)
                        
                        Button {
                            groupB = g
                        } label: {
                            VStack(spacing: 2) {
                                FilmstripTile(group: g, isSelected: isB)
                                    .overlay(
                                        isA ? RoundedRectangle(cornerRadius: 8).stroke(Color.blue, lineWidth: 2) : nil
                                    )
                                
                                if isA {
                                    Text("A")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(.blue)
                                } else if isB {
                                    Text("B")
                                        .font(.system(size: 9, weight: .black))
                                        .foregroundStyle(.orange)
                                } else {
                                    Text(g.baseName)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 6)
    }
    
    private func loadPreviewA() async {
        guard let url = groupA.primaryAsset?.fileURL else { return }
        isLoadingA = true
        let res = await PreviewPipeline.shared.loadThumbnail(for: url, maxPixelSize: 2048)
        if case .success(let img) = res {
            previewA = img
        }
        isLoadingA = false
    }
    
    private func loadPreviewB() async {
        guard let url = groupB.primaryAsset?.fileURL else { return }
        isLoadingB = true
        let res = await PreviewPipeline.shared.loadThumbnail(for: url, maxPixelSize: 2048)
        if case .success(let img) = res {
            previewB = img
        }
        isLoadingB = false
    }
}
