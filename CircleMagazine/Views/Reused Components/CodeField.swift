//
//  CodeField.swift
//  CircleMagazine
//
//  One box per character of a fixed-length code. A hidden text field holds the
//  real input (so the system keyboard, paste, autofill and deletion all just
//  work); the boxes only render it, with the cursor's box outlined in ink.
//
//  Written for the join-a-circle sheet, then lifted here so signing in types its
//  emailed code into the same boxes — two 6-character codes in the app, and they
//  shouldn't look like different products.
//

import SwiftUI

struct CodeField: View {
    let length: Int
    @Binding var input: String
    /// What the code is made of. Drives the keyboard and what gets filtered out
    /// of a paste — an emailed OTP is digits, an invite code is letters too.
    var kind: Kind = .alphanumeric

    @FocusState private var focused: Bool

    enum Kind {
        case alphanumeric   // invite codes: "ABC123", uppercased
        case digits         // emailed one-time codes: "123456"
    }

    var body: some View {
        ZStack {
            TextField("", text: $input)
                .keyboardType(kind == .digits ? .numberPad : .asciiCapable)
                .textInputAutocapitalization(kind == .digits ? .never : .characters)
                // Lets iOS drop the emailed code straight in from the keyboard bar.
                .textContentType(kind == .digits ? .oneTimeCode : nil)
                .autocorrectionDisabled()
                .focused($focused)
                .opacity(0)
                .frame(width: 1, height: 1)
            HStack(spacing: Style.Space.sm) {
                ForEach(0..<length, id: \.self) { i in
                    let chars = Array(input)
                    Text(i < chars.count ? String(chars[i]) : " ")
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Style.ink)
                        .frame(width: 44, height: 54)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Style.paper))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(focused && i == chars.count ? Style.ink : Style.rule,
                                    lineWidth: focused && i == chars.count ? 1.5 : 1))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            // The boxes are the visible control; the real field is 1×1 and
            // invisible, so without this the whole thing is unreachable.
            .accessibilityElement()
            .accessibilityLabel("Code")
            .accessibilityValue(input.isEmpty ? "Empty" : input)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the keyboard")
            .accessibilityAction { focused = true }
        }
        .onAppear { focused = true }
        .onChange(of: input) { _, new in
            if clean(new) != new { input = clean(new) }
        }
    }

    private func clean(_ raw: String) -> String {
        let kept = raw.filter { kind == .digits ? $0.isNumber : ($0.isLetter || $0.isNumber) }
        return String((kind == .digits ? kept : kept.uppercased()).prefix(length))
    }
}

#if DEBUG
#Preview("CodeField") {
    @Previewable @State var invite = "AB3"
    @Previewable @State var otp = "1234"
    return VStack(spacing: Style.Space.xl) {
        CodeField(length: 6, input: $invite)
        CodeField(length: 6, input: $otp, kind: .digits)
    }
    .padding()
    .background(Style.chrome)
}
#endif
