import SwiftUI

enum AppTheme {
    static let tint = Color(red: 0.26, green: 0.93, blue: 0.98)
    static let tabSelected = Color(red: 0.67, green: 0.29, blue: 1.05)
    static let tabBar = Color(red: 0.24, green: 0.10, blue: 0.40)
    static let itemText = Color(red: 0.36, green: 0.12, blue: 0.56)

    static let background = LinearGradient(
        colors: [
            Color(red: 0.21, green: 0.07, blue: 0.38),
            Color(red: 0.39, green: 0.13, blue: 0.59),
            Color(red: 0.55, green: 0.20, blue: 0.72)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let rowSurface = Color.white.opacity(0.96)
    static let expiringRow = Color(red: 1.0, green: 0.94, blue: 0.55)
    static let expiredRow = Color(red: 1.0, green: 0.42, blue: 0.42)

    static func categoryColor(for name: String) -> Color {
        switch name.freezerNormalized {
        case "meat":
            return Color(red: 0.83, green: 0.22, blue: 0.32)
        case "fish":
            return Color(red: 0.18, green: 0.45, blue: 0.87)
        case "dairy":
            return Color(red: 0.18, green: 0.64, blue: 0.56)
        case "fruit & veg", "fruit and veg":
            return Color(red: 0.37, green: 0.70, blue: 0.22)
        case "ready meal":
            return Color(red: 0.70, green: 0.43, blue: 0.15)
        default:
            let scalarSum = name.freezerNormalized.unicodeScalars.map { Int($0.value) }.reduce(0, +)
            let bucket = abs(scalarSum % 6)
            switch bucket {
            case 0: return Color(red: 0.58, green: 0.30, blue: 0.82)
            case 1: return Color(red: 0.24, green: 0.57, blue: 0.88)
            case 2: return Color(red: 0.29, green: 0.66, blue: 0.42)
            case 3: return Color(red: 0.86, green: 0.37, blue: 0.28)
            case 4: return Color(red: 0.86, green: 0.63, blue: 0.20)
            default: return Color(red: 0.72, green: 0.32, blue: 0.64)
            }
        }
    }
}

extension FreezerStore.ItemExpiryState {
    var rowColor: Color {
        switch self {
        case .normal:
            return AppTheme.rowSurface
        case .expiringSoon:
            return AppTheme.expiringRow
        case .expired:
            return AppTheme.expiredRow
        }
    }
}

struct FreezerScreenStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .listRowBackground(AppTheme.rowSurface)
            .background(AppTheme.background.ignoresSafeArea())
         
    }
}

extension View {
    func freezerScreenStyle() -> some View {
        modifier(FreezerScreenStyle())
    }
}

struct CategoryBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(AppTheme.categoryColor(for: text))
            )
    }
}
