import BrowserCore
import SwiftUI

struct ProfilesView: View {
    let browser: BrowserModel
    var initialProfileID: UUID? = nil
    var startsCreating = false
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var color: ProfileColor = .terracotta
    @State private var creating = false
    @FocusState private var nameFocused: Bool

    private var valid: Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= BrowserProfile.maximumNameLength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your profiles").font(.system(size: 26, weight: .regular, design: .serif))
                    Text("Separate spaces for different sides of your day.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                IconButton(symbol: "xmark", label: "Done") { dismiss() }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 6) {
                    ForEach(browser.session.profiles) { profile in
                        Button { edit(profile) } label: {
                            HStack(spacing: 10) {
                                ProfileBadge(profile: profile)
                                Text(verbatim: profile.name).lineLimit(1)
                                Spacer()
                                if profile.id == browser.window.selectedProfileID {
                                    Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(10)
                            .background(.primary.opacity(editingID == profile.id ? 0.06 : 0), in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profiles.row.\(profile.name)")
                    }
                    Button {
                        editingID = nil
                        name = ""
                        color = .ocean
                        creating = true
                        nameFocused = true
                    } label: {
                        Label("Add profile", systemImage: "plus").frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profiles.add")
                }
                .frame(width: 185)

                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    Text(creating ? "New profile" : "Profile details").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name").font(.caption).foregroundStyle(.secondary)
                        TextField("Profile name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($nameFocused)
                            .accessibilityIdentifier("profiles.name")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accent color").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            ForEach(ProfileColor.allCases, id: \.self) { option in
                                Button { color = option } label: {
                                    Circle().fill(option.tint)
                                        .frame(width: 26, height: 26)
                                        .overlay { if color == option { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) } }
                                        .padding(3)
                                        .overlay(Circle().strokeBorder(color == option ? option.tint : .clear, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(option.label))
                                .accessibilityAddTraits(color == option ? .isSelected : [])
                            }
                        }
                    }
                    Label("Cookies and website sign-ins stay separate for each profile.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    HStack {
                        if let id = editingID, id != browser.window.selectedProfileID {
                            Button("Use profile") { browser.switchProfile(id); dismiss() }
                                .accessibilityIdentifier("profiles.use")
                        }
                        Spacer()
                        Button(creating ? "Create profile" : "Save changes") {
                            if browser.saveProfile(id: editingID, name: name, color: color) { dismiss() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!valid)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("profiles.save")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
        .frame(width: 640, height: 370)
        .onAppear {
            if startsCreating {
                creating = true
                color = .ocean
                nameFocused = true
            } else if let profile = browser.session.profiles.first(where: { $0.id == initialProfileID }) ?? browser.profile {
                edit(profile)
            }
        }
        .onExitCommand { dismiss() }
    }

    private func edit(_ profile: BrowserProfile) {
        editingID = profile.id
        name = profile.name
        color = profile.color
        creating = false
    }
}
