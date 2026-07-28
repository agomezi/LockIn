//
//  LockInView.swift
//  Brickable
//
//  The Lock In tab: current state, remaining auto-unlock time, the app/category
//  picker, the timeout setting, and card setup.
//

import SwiftUI
import UIKit
import FamilyControls

struct LockInView: View {
    @Bindable var manager: LockManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !manager.isAuthorized {
                        authorizationCard
                    }

                    statusCard

                    if let banner = manager.banner {
                        BannerView(banner: banner) { manager.banner = nil }
                    }

                    tapCardButton
                    blockedAppsCard
                    timeoutCard
                    cardSetupCard
                }
                .padding()
                .animation(.default, value: manager.lockState)
                .animation(.default, value: manager.banner)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Lock In")
        }
        .familyActivityPicker(isPresented: $manager.isPickerPresented,
                              selection: $manager.selection)
        .onChange(of: manager.selection) { _, _ in
            manager.persistSelection()
        }
        .onChange(of: manager.autoUnlockMinutes) { _, _ in
            manager.persistAutoUnlockMinutes()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { manager.refresh() }
        }
        .task { manager.refresh() }
    }

    // MARK: - Onboarding

    private var authorizationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Screen Time access needed", systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text(manager.authorizationStatus == .denied
                     ? "Access was declined. Turn it back on in Settings › Screen Time, then reopen Brickable."
                     : "Brickable needs Screen Time access to block apps on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await manager.requestAuthorization() }
                } label: {
                    Text("Grant Screen Time Access")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.authorizationStatus == .denied)
            }
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        Card {
            VStack(spacing: 12) {
                Image(systemName: manager.lockState.isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(manager.lockState.isLocked ? .red : .green)
                    .frame(height: 56)

                Text(manager.lockState.isLocked ? "Locked In" : "Unlocked")
                    .font(.title2.weight(.bold))

                if let remaining = manager.remainingDescription {
                    VStack(spacing: 2) {
                        Text(remaining)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                            .contentTransition(.numericText())
                        Text("until auto-unlock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if manager.lockState.isLocked {
                    Text("No auto-unlock timer — tap your card to unlock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text(manager.blockedItemCount == 0
                         ? "Nothing selected to block yet"
                         : "\(manager.blockedItemCount) app\(manager.blockedItemCount == 1 ? "" : "s") & categories ready to block")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - The tap

    private var tapCardButton: some View {
        VStack(spacing: 6) {
            Button {
                manager.tapCard()
            } label: {
                HStack(spacing: 10) {
                    if manager.isScanning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "wave.3.right.circle.fill")
                    }
                    Text(manager.lockState.isLocked ? "Tap Card to Unlock" : "Tap Card to Lock In")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(manager.lockState.isLocked ? .red : .accentColor)
            .disabled(!manager.isAuthorized || manager.isScanning || !manager.nfcAvailable)

            if !manager.nfcAvailable {
                Text("NFC isn't available on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Selection

    private var blockedAppsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Blocked Apps")
                    .font(.headline)

                HStack {
                    Text(manager.blockedItemCount == 0
                         ? "Nothing selected"
                         : "\(manager.selection.applicationTokens.count) apps · \(manager.selection.categoryTokens.count) categories")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    manager.isPickerPresented = true
                } label: {
                    Label("Choose Apps & Categories", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!manager.isAuthorized)
            }
        }
    }

    // MARK: - Timeout

    private var timeoutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Auto-Unlock Timer")
                    .font(.headline)

                Stepper(value: $manager.autoUnlockMinutes,
                        in: AutoUnlock.minimumMinutes...AutoUnlock.maximumMinutes,
                        step: 15) {
                    HStack {
                        Text("Unlock after")
                        Spacer()
                        Text("\(manager.autoUnlockMinutes) min")
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }

                Text("A fallback in case you don't re-tap the card. Minimum \(AutoUnlock.minimumMinutes) minutes — that's the shortest window iOS will schedule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Card setup

    private var cardSetupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lock Card")
                    .font(.headline)

                Text(manager.cardProvisioned
                     ? "A card has been set up. Setting up another card lets it work as a lock card too."
                     : "Write Brickable's identifier to a blank NTAG213/215 card once. After that, every tap toggles the lock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    manager.provisionCard()
                } label: {
                    Label(manager.cardProvisioned ? "Set Up Another Card" : "Set Up Card",
                          systemImage: "creditcard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(manager.isScanning || !manager.nfcAvailable)
            }
        }
    }
}

// MARK: - Small building blocks

/// Rounded container used for every block on this screen.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct BannerView: View {
    let banner: LockManager.Banner
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: banner.kind == .success ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            Text(banner.text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .foregroundStyle(banner.kind == .success ? Color.green : Color.red)
        .background((banner.kind == .success ? Color.green : Color.red).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: banner.id) {
            // Clear itself after a few seconds so messages don't pile up.
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
}

#Preview {
    LockInView(manager: LockManager())
}
