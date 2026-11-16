import SwiftUI

/// La sobriété des apps Osa : fond presque noir, blanc à différentes opacités, police système en gras,
/// pilules blanches. Une seule couleur, le vert d'eau du costume, pour ce qui est fait.
enum Theme {
    static let bg = Color(red: 0.04, green: 0.04, blue: 0.06)
    static let card = Color.white.opacity(0.05)
    static let stroke = Color.white.opacity(0.08)
    static let done = Boule.scrub
    static let soft = Color(red: 1, green: 0.62, blue: 0.66)
}

struct PillStyle: ButtonStyle {
    var primary = false
    var onLight = false
    func makeBody(configuration: Configuration) -> some View {
        let fg: Color, bgc: Color
        if onLight {
            fg = primary ? .white : Color(red: 0.11, green: 0.11, blue: 0.14)
            bgc = primary ? Color(red: 0.11, green: 0.11, blue: 0.14) : Color.black.opacity(0.07)
        } else {
            fg = primary ? .black : .white
            bgc = primary ? .white : Color.white.opacity(0.1)
        }
        return configuration.label
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(bgc, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct Card<Content: View>: View {
    var title: String? = nil
    var trailing: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack {
                    Text(title.uppercased()).font(.system(size: 10.5, weight: .bold)).kerning(0.8).foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    if let trailing { Text(trailing).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.45)) }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
    }
}

/// Case ronde qui se remplit de vert quand c'est fait.
struct CheckCircle: View {
    var on: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Theme.done : .white.opacity(0.3), lineWidth: 1.5)
            if on {
                Circle().fill(Theme.done)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(.black.opacity(0.75))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 18, height: 18)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
    }
}

struct Field: View {
    var placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.3)))
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.stroke))
            .onSubmit(onSubmit)
    }
}
