import SwiftUI
import ListedCore

/// First-launch onboarding — redesigned as the user's first "wow" moment with
/// confident typography, ambient gradients, and tactile choice cards.
public struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    @State private var working: Bool = false
    @State private var errorMessage: String?
    @State private var appeared: Bool = false

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack {
            // Ambient gradient background
            LinearGradient(
                colors: [
                    DesignTokens.accent.opacity(0.08),
                    Color.purple.opacity(0.04),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: DesignTokens.spacingSection) {
                Spacer()

                // Hero: app icon + welcome text
                VStack(spacing: DesignTokens.spacingLG) {
                    Image(systemName: "checklist")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DesignTokens.accent, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(appeared ? 1.0 : 0.5)
                        .opacity(appeared ? 1.0 : 0)

                    VStack(spacing: DesignTokens.spacingSM) {
                        Text("Welcome to Listed")
                            .font(.system(size: 32, weight: .bold))
                            .opacity(appeared ? 1.0 : 0)
                            .offset(y: appeared ? 0 : 10)

                        Text("Your tasks are plain-text todo.txt files you fully own.\nChoose where Listed should keep them.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DesignTokens.spacingXXL)
                            .opacity(appeared ? 1.0 : 0)
                            .offset(y: appeared ? 0 : 10)
                    }
                }

                // Storage choice cards
                VStack(spacing: DesignTokens.spacingMD) {
                    storageCard(
                        title: "Use iCloud Drive",
                        subtitle: model.bootstrap.isICloudAvailable
                            ? "Sync tasks across all your Apple devices."
                            : "iCloud Drive isn't available right now.",
                        icon: "icloud.fill",
                        gradientColors: [.blue, .cyan],
                        recommended: model.bootstrap.isICloudAvailable,
                        disabled: !model.bootstrap.isICloudAvailable || working
                    ) {
                        bootstrap(useICloud: true)
                    }

                    storageCard(
                        title: "Use Local Storage",
                        subtitle: "Keep tasks on this device only. You can change this later.",
                        icon: "internaldrive.fill",
                        gradientColors: [.gray, .secondary],
                        recommended: false,
                        disabled: working
                    ) {
                        bootstrap(useICloud: false)
                    }
                }
                .padding(.horizontal, DesignTokens.spacingXXL)
                .opacity(appeared ? 1.0 : 0)
                .offset(y: appeared ? 0 : 20)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.spacingSection)
                }

                Spacer()
            }
        }
        .frame(minWidth: 440, minHeight: 520)
        .padding(DesignTokens.spacingXL)
        .interactiveDismissDisabled(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }

    // MARK: - Storage choice card

    private func storageCard(
        title: String,
        subtitle: String,
        icon: String,
        gradientColors: [Color],
        recommended: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.spacingLG) {
                // Tinted icon badge
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                    )

                VStack(alignment: .leading, spacing: DesignTokens.spacingXS) {
                    HStack(spacing: DesignTokens.spacingSM) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if recommended {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(DesignTokens.accent.opacity(0.15)))
                                .foregroundStyle(DesignTokens.accent)
                        }
                    }
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(DesignTokens.spacingLG)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                    .fill(.background.secondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.cardCornerRadius, style: .continuous)
                            .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }

    private func bootstrap(useICloud: Bool) {
        working = true
        errorMessage = nil
        Task {
            do {
                let workspace = try model.bootstrap.makeInitialWorkspace(useICloud: useICloud)
                try model.workspaceStore.save(workspace)
                await model.repository.updateWorkspace(workspace)
                await MainActor.run {
                    model.replaceWorkspace(workspace)
                }
                await model.refresh()
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
                working = false
            }
        }
    }
}

extension AppModel {
    /// Replace the in-memory workspace (used after onboarding / settings changes).
    public func replaceWorkspace(_ workspace: Workspace) {
        self.workspace = workspace
    }
}
