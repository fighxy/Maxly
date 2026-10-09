import SwiftUI

/// Логотип Maxly в двух видах.
///
/// Картинки лежат в каталоге приложения (`Assets.xcassets`): `OrbitleLogo` — логотип целиком
/// на чёрном фоне, `OrbitleMark` — только силуэт знака на прозрачном фоне, его цвет задаёт
/// экран. Иконка приложения (`AppIcon`) и экран запуска (`LaunchLogo` на чёрном
/// `LaunchBackground`) собраны из того же рисунка.
enum OrbitleBrand {
    /// Фон экрана запуска и заставки: чёрный, как фон логотипа.
    static let background = Color("LaunchBackground")
}

/// Логотип целиком, скруглённый как иконка приложения. Одинаков в светлой и тёмной теме.
struct OrbitleLogoTile: View {
    var size: CGFloat = 88

    var body: some View {
        Image("OrbitleLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            // Доля скругления та же, что у иконок iOS.
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityLabel("Maxly")
    }
}

/// Только знак без фона. Цвет берётся из `foregroundStyle` (по умолчанию основной цвет текста),
/// поэтому знак виден и в светлой, и в тёмной теме.
struct OrbitleMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image("OrbitleMark")
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Maxly")
    }
}

/// Заставка, пока открывается база и ядро подключается. Продолжает экран запуска:
/// тот же фон и тот же логотип, поэтому переход от системной заставки незаметен.
struct OrbitleSplash: View {
    var caption: String?

    var body: some View {
        ZStack {
            OrbitleBrand.background
            VStack(spacing: 28) {
                Image("LaunchLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 200, height: 200)
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    if let caption {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .frame(height: 44, alignment: .top)
            }
            // Знак стоит там же, где на экране запуска (по центру экрана без учёта
            // безопасных зон), подпись уходит ниже.
            .offset(y: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption ?? "Maxly, загрузка")
    }
}
