import SwiftUI

private struct FocusDrivenInputBorderModifier: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    let showsBaseBorder: Bool

    private var baseBorderColor: Color {
        Color.accentColor.opacity(isFocused ? 0.28 : 0.09)
    }

    private var focusBorderColor: Color {
        Color.accentColor.opacity(isFocused ? 0.68 : 0.22)
    }

    private var focusGlowColor: Color {
        Color.accentColor.opacity(isFocused ? 0.14 : 0.04)
    }

    private var tintFillColor: Color {
        Color.accentColor.opacity(isFocused ? 0.055 : 0.018)
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tintFillColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(showsBaseBorder ? baseBorderColor : .clear, lineWidth: isFocused ? 1.1 : 1.0)
            }
            .overlay {
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(focusBorderColor, lineWidth: isFocused ? 1.3 : 1.0)
                        .shadow(color: focusGlowColor, radius: isFocused ? 4 : 1.5, y: 0)
                        .mask {
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                Rectangle()
                                    .frame(width: geometry.size.width * revealProgress)
                                Spacer(minLength: 0)
                            }
                        }
                        .opacity(isFocused ? 0.92 : 0.58)
                }
            }
            .animation(.timingCurve(0.22, 0.82, 0.24, 1.0, duration: 0.32), value: isFocused)
    }

    private var revealProgress: CGFloat {
        isFocused ? 1 : 0
    }
}

struct FocusTextField: View {
    let titleKey: LocalizedStringKey
    @Binding var text: String
    var axis: Axis = .horizontal
    var cornerRadius: CGFloat = 6
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 5

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(titleKey, text: $text, axis: axis)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.textBackgroundColor))
            )
            .modifier(
                FocusDrivenInputBorderModifier(
                    isFocused: isFocused,
                    cornerRadius: cornerRadius,
                    showsBaseBorder: true
                )
            )
    }
}

struct FocusSecureField: View {
    let titleKey: LocalizedStringKey
    @Binding var text: String
    var cornerRadius: CGFloat = 6
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 5

    @FocusState private var isFocused: Bool

    var body: some View {
        SecureField(titleKey, text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.textBackgroundColor))
            )
            .modifier(
                FocusDrivenInputBorderModifier(
                    isFocused: isFocused,
                    cornerRadius: cornerRadius,
                    showsBaseBorder: true
                )
            )
    }
}

struct FocusValueField<Value>: View {
    let titleKey: LocalizedStringKey
    @Binding var value: Value
    let formatter: Formatter
    var cornerRadius: CGFloat = 6
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 5

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(titleKey, value: $value, formatter: formatter)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(.textBackgroundColor))
            )
            .modifier(
                FocusDrivenInputBorderModifier(
                    isFocused: isFocused,
                    cornerRadius: cornerRadius,
                    showsBaseBorder: true
                )
            )
    }
}

struct FocusTextEditor: View {
    @Binding var text: String
    var cornerRadius: CGFloat = 6
    var padding: CGFloat = 8

    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .focused($isFocused)
            .padding(padding)
            .background(Color(.textBackgroundColor))
            .modifier(
                FocusDrivenInputBorderModifier(
                    isFocused: isFocused,
                    cornerRadius: cornerRadius,
                    showsBaseBorder: true
                )
            )
    }
}

extension View {
    func animatedInputBorder(
        isFocused: Bool,
        cornerRadius: CGFloat = 7,
        showsBaseBorder: Bool = false
    ) -> some View {
        modifier(
            FocusDrivenInputBorderModifier(
                isFocused: isFocused,
                cornerRadius: cornerRadius,
                showsBaseBorder: showsBaseBorder
            )
        )
    }
}
