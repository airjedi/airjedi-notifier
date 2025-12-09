import SwiftUI

struct MenuBarIcon: View {
    let aircraftCount: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "airplane")
                .font(.system(size: 14))

            if aircraftCount > 0 {
                Text("\(aircraftCount)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Circle().fill(Color.blue))
                    .offset(x: 6, y: -4)
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        MenuBarIcon(aircraftCount: 0)
        MenuBarIcon(aircraftCount: 3)
        MenuBarIcon(aircraftCount: 12)
    }
    .padding()
}
