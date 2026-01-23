import SwiftUI

struct MenuBarIcon: View {
    let aircraftCount: Int
    let status: ProviderStatus
    let hasAlert: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: iconName)
                .font(.system(size: 14))
                .foregroundColor(iconColor)

            if hasAlert {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .offset(x: 6, y: -4)
            } else if aircraftCount > 0 && status.isConnected {
                Text("\(aircraftCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Circle().fill(Color.blue))
                    .offset(x: 6, y: -4)
            }
        }
    }

    private var iconName: String {
        switch status {
        case .error:
            return "airplane.circle.fill"
        case .disconnected:
            return "airplane"
        default:
            return "airplane"
        }
    }

    private var iconColor: Color? {
        if hasAlert {
            return .orange
        }
        switch status {
        case .error:
            return .red
        case .disconnected:
            return .secondary
        default:
            return nil
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        MenuBarIcon(aircraftCount: 0, status: .disconnected, hasAlert: false)
        MenuBarIcon(aircraftCount: 3, status: .connected(aircraftCount: 3), hasAlert: false)
        MenuBarIcon(aircraftCount: 3, status: .connected(aircraftCount: 3), hasAlert: true)
    }
    .padding()
}
