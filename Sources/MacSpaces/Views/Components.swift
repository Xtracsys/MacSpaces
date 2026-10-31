import MacSpacesCore
import SwiftUI

// MARK: - Volume usage ring

struct UsageRing: View {
    let usedFraction: Double
    let centerTitle: String
    let centerSubtitle: String
    var ringSize: CGFloat = 160

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: ringSize * 0.09)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, usedFraction)))
                .stroke(
                    AngularGradient(
                        colors: usedFraction > 0.9 ? [.orange, .red] : [.blue, .teal],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: ringSize * 0.09, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(centerTitle)
                    .font(.system(size: ringSize * 0.17, weight: .bold, design: .rounded))
                Text(centerSubtitle)
                    .font(.system(size: ringSize * 0.085))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityElement()
        .accessibilityLabel("Disk usage \(Int(usedFraction * 100)) percent")
    }
}

// MARK: - Stat card

struct StatCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    var systemImage: String? = nil
    var color: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Proportional size bar

struct SizeBar: View {
    let fraction: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.12))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, fraction)))))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Badge

struct StatusBadge: View {
    let text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Section header helper

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> AnyView

    init(title: String, subtitle: String? = nil, trailing: @escaping () -> AnyView = { AnyView(EmptyView()) }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.top, 8)
    }
}
