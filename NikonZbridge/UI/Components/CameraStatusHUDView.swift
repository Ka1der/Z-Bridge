import SwiftUI

/// Плавающий полупрозрачный HUD параметров камеры в дизайн-системе Liquid Glass (согласно референсу iPad).
/// Отображает заряд аккумулятора, выдержку, диафрагму, ISO и статус подключения с желтым индикатором.
public struct CameraStatusHUDView: View {
    public let cameraName: String
    public let batteryLevel: Int
    public let shutterSpeed: String
    public let aperture: String
    public let iso: String
    public let isConnected: Bool
    public var onDismiss: (() -> Void)? = nil
    
    @State private var isCollapsed: Bool = false
    
    public init(
        cameraName: String = "Nikon Z",
        batteryLevel: Int = 87,
        shutterSpeed: String = "1/250s",
        aperture: String = "f/2.8",
        iso: String = "100",
        isConnected: Bool = true,
        onDismiss: (() -> Void)? = nil
    ) {
        self.cameraName = cameraName
        self.batteryLevel = batteryLevel
        self.shutterSpeed = shutterSpeed
        self.aperture = aperture
        self.iso = iso
        self.isConnected = isConnected
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        Group {
            if isCollapsed {
                collapsedHUD
            } else {
                expandedHUD
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isCollapsed)
    }
    
    // MARK: - Развернутый HUD (в точности как на референсе iPad)
    
    private var expandedHUD: some View {
        VStack(spacing: 0) {
            // Верхняя часть: 4 колонки параметров экспозиции
            HStack(spacing: 0) {
                hudColumn(title: "Battery", value: "\(batteryLevel)%")
                
                Divider()
                    .frame(height: 32)
                    .background(Color.white.opacity(0.10))
                
                hudColumn(title: "Shutter Speed", value: shutterSpeed)
                
                Divider()
                    .frame(height: 32)
                    .background(Color.white.opacity(0.10))
                
                hudColumn(title: "Aperture", value: aperture)
                
                Divider()
                    .frame(height: 32)
                    .background(Color.white.opacity(0.10))
                
                hudColumn(title: "ISO", value: iso)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
            
            Divider()
                .background(Color.white.opacity(0.10))
            
            // Нижняя строка: желтый индикатор и статус камеры
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? AppTheme.Colors.accent : AppTheme.Colors.statusNeutral)
                    .frame(width: 7, height: 7)
                    .shadow(color: AppTheme.Colors.accent.opacity(isConnected ? 0.6 : 0), radius: 4)
                
                Text("\(cameraName.uppercased()) - \(isConnected ? "CONNECTED" : "DISCONNECTED")")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.25))
        }
        .frame(maxWidth: 390)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 22/255.0, green: 24/255.0, blue: 29/255.0).opacity(0.72))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.40), radius: 20, x: 0, y: 8)
        .onTapGesture {
            isCollapsed.toggle()
        }
    }
    
    // MARK: - Компактный свернутый вид
    
    private var collapsedHUD: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isConnected ? AppTheme.Colors.accent : AppTheme.Colors.statusNeutral)
                .frame(width: 7, height: 7)
            
            Text("\(cameraName) • \(shutterSpeed) • \(aperture) • ISO \(iso)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white)
            
            Text("\(batteryLevel)%")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppTheme.Colors.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(red: 22/255.0, green: 24/255.0, blue: 29/255.0).opacity(0.75))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 4)
        .onTapGesture {
            isCollapsed.toggle()
        }
    }
    
    private func hudColumn(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.60))
                .lineLimit(1)
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .default))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}
