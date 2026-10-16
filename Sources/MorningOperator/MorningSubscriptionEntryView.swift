import SwiftUI
import MorningCore

/// Keep setup and its permission requests outside the unpaid presentation tree.
struct MorningSubscriptionEntryView: View {
    @Bindable var store: MorningStore
    @State private var subscription = MorningSubscriptionStore()
    @State private var legalDocument: MorningSubscriptionLegalDocument?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !subscription.hasResolvedAccess {
                ZStack {
                    MorningQuietLandscape(scene: MorningThemeClock.shared.celestial, animated: false)
                        .ignoresSafeArea()
                    ProgressView().accessibilityLabel(AppLanguage.isFrench ? "Vérification de l’abonnement" : "Checking your subscription")
                }
            } else if subscription.hasAccess {
                MorningRootView(store: store)
            } else {
                MorningWelcomeFlow(offer: subscription.offer, purchaseState: subscription.state,
                                   subscribe: { Task { await subscription.purchase() } },
                                   restore: { Task { await subscription.restore() } },
                                   retry: { Task { await subscription.load() } },
                                   showLegal: { legalDocument = $0 })
            }
        }
        .sheet(item: $legalDocument) { document in
            MorningSubscriptionLegalSheet(document: document, store: store)
        }
        .task { await subscription.load() }
        .task {
            while !Task.isCancelled {
                MorningThemeClock.shared.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                MorningThemeClock.shared.refresh()
                Task { await subscription.load() }
            }
        }
        .onChange(of: subscription.hasAccess) { wasActive, isActive in
            guard wasActive && !isActive else { return }
            if store.session?.status == .running { store.pause() }
            store.suspendHandsFreeVoice()
        }
    }
}

/// Readable before subscribing; local privacy controls never depend on payment.
struct MorningSubscriptionLegalSheet: View {
    let document: MorningSubscriptionLegalDocument
    var store: MorningStore? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingData = false
    private var french: Bool { AppLanguage.isFrench }
    private func text(_ fr: String, _ en: String) -> String { french ? fr : en }
    private var night: Bool { MorningThemeClock.shared.celestial.moon.opacity > 0.57 }
    private var values: MorningPaletteValues { .resolve(MorningThemeClock.shared.blend, dark: night) }
    private func color(_ value: MorningRGB) -> Color { Color(red: value.red, green: value.green, blue: value.blue) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(document == .terms ? text("Votre abonnement", "Your subscription") : text("Vos données, vos choix.", "Your data, your choices."))
                        .font(.serif(.largeTitle)).accessibilityAddTraits(.isHeader)
                    if document == .terms {
                        Text(text("L’offre affichée avant l’achat indique le prix, la durée et l’essai auquel votre compte est éligible. L’App Store confirme ces conditions avant toute souscription.",
                                  "The offer shown before purchase includes the price, duration and trial your account is eligible for. The App Store confirms these terms before you subscribe."))
                        Text(text("Vous pouvez gérer ou résilier votre abonnement dans les réglages de votre compte App Store. La résiliation prend effet à la fin de la période en cours.",
                                  "Manage or cancel your subscription in your App Store account settings. Cancellation takes effect at the end of the current period."))
                        Link(text("Lire les conditions d’utilisation Apple", "Read Apple’s terms of use"),
                             destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    } else {
                        Text(text("Vous choisissez les sources à partager avec MORE. Les autorisations et les connexions seront expliquées une par une, après l’abonnement.",
                                  "You choose which sources to share with MORE. Permissions and connections will be explained one by one after subscribing."))
                        Text(text("L’analyse des vidéos et les apprentissages restent sur cet iPhone par défaut. Les services que vous connectez peuvent traiter les informations nécessaires à leurs fonctions, selon leurs propres conditions.",
                                  "Video analysis and learning stay on this iPhone by default. Services you connect may process the information needed for their features under their own terms."))
                        Text(text("Les achats sont gérés par Apple. MORE n’a pas accès aux coordonnées de votre carte bancaire.",
                                  "Apple manages purchases. MORE does not have access to your payment card details."))
                        if store != nil {
                            Button(text("Gérer mes données sur cet iPhone", "Manage my data on this iPhone")) { showingData = true }
                                .frame(minHeight: 44).accessibilityIdentifier("paywall.manageData")
                        }
                    }
                }
                .font(MorningTheme.Typography.body).lineSpacing(5)
                .frame(maxWidth: 520, alignment: .leading).padding(28).frame(maxWidth: .infinity)
            }
            .background(color(values.paper).ignoresSafeArea())
            .foregroundStyle(color(values.ink)).tint(color(values.ink))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(text("Fermer", "Close")) { dismiss() }.font(.raleway(.body, .semibold))
                }
            }
            .navigationDestination(isPresented: $showingData) {
                if let store {
                    MorningPrivacyView(store: store)
                        .preferredColorScheme(.light).foregroundStyle(MorningStyle.ink)
                }
            }
        }
        .preferredColorScheme(night ? .dark : .light)
    }
}

#if DEBUG
/// An explicit preview can never buy a product or unlock the permission flow.
struct MorningWelcomePreview: View {
    @State private var state: MorningPurchasePresentation = .ready
    @State private var legalDocument: MorningSubscriptionLegalDocument?
    private var french: Bool { AppLanguage.isFrench }
    var body: some View {
        MorningWelcomeFlow(offer: .init(monthlyPrice: french ? "4,99 €" : "€4.99", includesFreeTrial: true),
                           purchaseState: state,
                           subscribe: { state = .failed(french ? "Aperçu : aucun achat effectué. Vous pouvez réessayer."
                                                       : "Preview: no purchase made. You can try again.") },
                           restore: { state = .failed(french ? "Aperçu : aucun abonnement à restaurer."
                                                     : "Preview: no subscription to restore.") },
                           retry: { state = .ready }, showLegal: { legalDocument = $0 })
            .environment(\.accessibilityReduceMotion, ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion"))
            .environment(\.accessibilityReduceTransparency, ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-transparency"))
            .sheet(item: $legalDocument) { MorningSubscriptionLegalSheet(document: $0) }
            .overlay(alignment: .top) {
                Text(french ? "APERÇU · AUCUN ACHAT" : "PREVIEW · NO PURCHASE")
                    .font(.raleway(.caption2)).padding(3)
                    .background(.regularMaterial).allowsHitTesting(false)
                    .accessibilityIdentifier("onboarding.preview")
            }
    }
}
#endif
