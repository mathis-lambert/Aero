import BrowserCore
import SwiftUI

/// The saved accounts under the focused field, drawn over the page so the page keeps the keyboard.
/// See docs/PASSWORDS.md › Filling.
struct PasswordPickerView: View {
    private static let minimumWidth: CGFloat = 260
    private static let maximumWidth: CGFloat = 360
    private static let rowHeight: CGFloat = 40
    private static let fieldGap: CGFloat = 4

    let browser: BrowserModel
    let picker: PasswordPicker
    let bounds: CGSize
    @Environment(\.palette) private var palette

    var body: some View {
        let width = min(Self.maximumWidth, max(Self.minimumWidth, picker.placement?.width ?? 0))
        VStack(alignment: .leading, spacing: 2) {
            if let suggestion = picker.suggestion {
                row(action: browser.fillSuggestedPassword) {
                    Image(systemName: "key.viewfinder").foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Use strong password")
                        Text(verbatim: suggestion).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.secondary)
                    }
                }
                .accessibilityIdentifier("passwords.suggestion")
            }
            ForEach(picker.logins) { login in
                row(action: { browser.fillPassword(login) }) {
                    Image(systemName: "key").foregroundStyle(palette.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: login.username.isEmpty ? String(localized: "No username") : login.username)
                        if login.origin != picker.frame.origin {
                            Text(verbatim: login.origin.host).font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("passwords.login")
                .accessibilityLabel(Text(verbatim: login.username.isEmpty ? login.origin.host : login.username))
            }
            Divider().padding(.vertical, 2)
            Button {
                browser.passwords.closePicker()
                browser.showSettings(.section(.passwords))
            } label: {
                Text("Passwords…").foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BrowserDesign.rowInset)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
        }
        .padding(4)
        .frame(width: width)
        .browserSurface(fill: palette.raised, border: palette.line, radius: BrowserDesign.Radius.card)
        .floatShadow()
        .onHover { browser.passwords.pickerHoverChanged($0, for: picker.id) }
        .offset(origin(width: width))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("passwords.picker")
    }

    private func row<Label: View>(action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            HStack(spacing: BrowserDesign.rowInset) { label() }
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
                .padding(.horizontal, BrowserDesign.rowInset)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
    }

    /// Under the field, kept inside the page; at the top of the page for a frame that could not say where it is.
    private func origin(width: CGFloat) -> CGSize {
        guard let placement = picker.placement else { return CGSize(width: max(0, (bounds.width - width) / 2), height: BrowserDesign.floatingInset) }
        let x = min(max(BrowserDesign.floatingInset, placement.minX), max(BrowserDesign.floatingInset, bounds.width - width - BrowserDesign.floatingInset))
        return CGSize(width: x, height: placement.maxY + Self.fieldGap)
    }
}

/// Offers to save, or update, what was just submitted. See docs/PASSWORDS.md › Saving.
struct PasswordOfferView: View {
    private static let width: CGFloat = 380

    let browser: BrowserModel
    let offer: PasswordOffer
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "key.fill")
                    .font(BrowserDesign.Typography.chrome)
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(offer.isUpdate ? "Update password for \(offer.record.origin.host)?" : "Save password for \(offer.record.origin.host)?")
                        .font(BrowserDesign.Typography.heading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !offer.record.username.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "person.crop.circle").accessibilityHidden(true)
                            Text(verbatim: offer.record.username).lineLimit(1)
                        }
                        .font(BrowserDesign.Typography.label)
                        .foregroundStyle(palette.secondary)
                    }
                }
            }
            Hairline()
            HStack(spacing: 8) {
                if !offer.isUpdate {
                    Button("Never") { browser.answerPasswordOffer(.never) }
                        .buttonStyle(QuietButtonStyle())
                        .font(BrowserDesign.Typography.caption)
                        .foregroundStyle(palette.secondary)
                        .tooltip(Text("Never for this site"))
                        .accessibilityLabel(Text("Never for this site"))
                        .accessibilityIdentifier("passwords.never")
                }
                Spacer(minLength: 0)
                Button { browser.answerPasswordOffer(.notNow) } label: {
                    HStack(spacing: 8) { Text("Not now"); Keycaps(.cancelAction).accessibilityHidden(true) }
                }
                    .buttonStyle(PanelButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Not now"))
                    .accessibilityIdentifier("passwords.notNow")
                Button { browser.answerPasswordOffer(.save) } label: {
                    HStack(spacing: 8) {
                        Text(offer.isUpdate ? "Update" : "Save")
                        Keycaps(.defaultAction, onAccent: true).accessibilityHidden(true)
                    }
                }
                    .buttonStyle(PanelButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(offer.isUpdate ? Text("Update") : Text("Save"))
                    .accessibilityIdentifier("passwords.save")
            }
            .disabled(browser.passwords.isSavingOffer)
        }
        .padding(16)
        .frame(width: Self.width)
        .browserSurface(fill: palette.raised, border: palette.line, radius: BrowserDesign.Radius.card)
        .floatShadow()
        .background(KeyboardToPrompt())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("passwords.offer")
    }
}
