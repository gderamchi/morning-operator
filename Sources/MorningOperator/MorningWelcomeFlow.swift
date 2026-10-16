import SwiftUI
import MorningCore

/// Price and trial eligibility come from StoreKit, never from marketing copy.
struct MorningSubscriptionOffer {
    let monthlyPrice: String
    let includesFreeTrial: Bool
}

enum MorningPurchasePresentation: Equatable {
    case loading, ready, purchasing, restoring, pending, unavailable, failed(String)

    var isBusy: Bool { self == .loading || self == .purchasing || self == .restoring }
}

enum MorningSubscriptionLegalDocument: String, Identifiable {
    case terms, privacy
    var id: String { rawValue }
}

/// Presentation only. Its owner advances to setup after a verified entitlement.
struct MorningWelcomeFlow: View {
    let offer: MorningSubscriptionOffer?
    let purchaseState: MorningPurchasePresentation
    let subscribe: () -> Void
    let restore: () -> Void
    let retry: () -> Void
    let showLegal: (MorningSubscriptionLegalDocument) -> Void
    @State private var page = 0
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var headingFocused: Bool

    private var french: Bool { locale.language.languageCode?.identifier == "fr" }
    private func text(_ fr: String, _ en: String) -> String { french ? fr : en }
    private var clock: MorningThemeClock { .shared }
    private var night: Bool { clock.celestial.moon.opacity > 0.57 }
    private var palette: MorningPaletteValues { .resolve(clock.blend, dark: night) }
    private func color(_ value: MorningRGB) -> Color { Color(red: value.red, green: value.green, blue: value.blue) }
    private var ink: Color { color(palette.ink) }
    private var muted: Color { color(contrast == .increased ? palette.ink : palette.inkSoft) }
    private var surface: Color { color(palette.surface) }
    private var isPaywall: Bool { page == 3 }
    private var heading: String {
        switch page {
        case 0: text("Retrouvez\nvotre matin.", "Meet your\nmorning.")
        case 1: text("Gardez ce qui\nvous plaît.", "Keep what\nyou love.")
        case 2: text("Votre matin,\nles mains libres.", "Your morning,\nhands free.")
        default: text("Un peu plus de\ntemps pour vous.", "A little more\ntime for you.")
        }
    }
    private var detail: String {
        switch page {
        case 0: text("MORE apprend vos habitudes avec les sources que vous choisissez : Temps d’écran, vidéos et navigation dans MORE.",
                     "MORE learns your habits from the sources you choose: Screen Time, videos and browsing in MORE.")
        case 1: text("Découvrez votre routine. Ajustez les étapes et leur durée, puis choisissez ce que vous confiez à MORE.",
                     "See your routine. Adjust its steps and timing, then choose what you entrust to MORE.")
        case 2: text("MORE déroule votre routine pendant que vous vous préparez. Interrompez-le à la voix pour une question, une pause ou la suite.",
                     "MORE runs your routine while you get ready. Interrupt by voice to ask a question, pause or move on.")
        default: text("Vos habitudes, votre rythme. MORE s’occupe de la routine que vous avez choisie.",
                      "Your habits, your pace. MORE takes care of the routine you choose.")
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                color(palette.paper).ignoresSafeArea()
                VStack(spacing: 0) {
                    navigation
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            MorningQuietLandscape(scene: clock.celestial, animated: !reduceMotion,
                                                  active: scenePhase == .active,
                                                  strongInk: reduceTransparency || contrast == .increased)
                                .frame(height: isPaywall ? 100 : 150)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 16) {
                                Text(heading)
                                    .font(.serif(.largeTitle))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityFocused($headingFocused)
                                    .accessibilityIdentifier("onboarding.heading")
                                Text(detail).font(MorningTheme.Typography.body)
                                    .foregroundStyle(muted).lineSpacing(4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if isPaywall { subscriptionDetails }
                            else { illustration }
                            if typeSize.isAccessibilitySize { footer }
                        }
                        .frame(maxWidth: 480, alignment: .leading)
                        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 36)
                        .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 240), alignment: .top)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("onboarding.content")
                    .id(page)
                    if !typeSize.isAccessibilitySize { footer }
                }
            }
        }
        .foregroundStyle(ink)
        .font(MorningTheme.Typography.body)
        .tint(ink)
        .preferredColorScheme(night ? .dark : .light)
        .onChange(of: page) { _, _ in headingFocused = true }
    }

    private var navigation: some View {
        HStack(spacing: 16) {
            if page > 0 {
                Button { move(to: page - 1) } label: {
                    Image(systemName: "arrow.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel(text("Retour", "Back"))
                .accessibilityIdentifier("onboarding.back")
            } else {
                Text(verbatim: "MORE").font(.raleway(.subheadline, .semibold)).tracking(4)
                    .frame(minHeight: 44)
            }
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<4) { index in
                    Circle().fill(ink.opacity(index == page ? 1 : 0.25))
                        .frame(width: index == page ? 7 : 4, height: index == page ? 7 : 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text("Étape \(page + 1) sur 4", "Step \(page + 1) of 4"))
            .accessibilityIdentifier("onboarding.progress")
            Spacer()
            if !isPaywall {
                Button(text("Voir l’offre", "View offer")) { move(to: 3) }
                    .font(.raleway(.caption, .medium)).frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.offer")
            } else {
                Text(verbatim: "MORE").font(.raleway(.caption, .semibold)).tracking(3)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 28).padding(.top, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var illustration: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(text("UN APERÇU DE VOTRE MATIN", "A GLIMPSE OF YOUR MORNING"))
                .font(.raleway(.caption2, .medium)).tracking(1.4).foregroundStyle(muted)
            if page == 0 {
                sourceRow("chart.bar.xaxis", text("Temps d’écran", "Screen Time"), text("Vos habitudes prennent forme", "Your habits take shape"))
                dottedRule
                sourceRow("play.rectangle", text("Vos vidéos", "Your videos"), text("Les moments qui comptent pour vous", "The moments that matter to you"))
                dottedRule
                sourceRow("globe", text("Le navigateur MORE", "The MORE browser"), text("Vos gestes précisent la routine", "Your actions refine your routine"))
            } else if page == 1 {
                routineRow("01", text("Prendre des nouvelles", "Catch up"), "5 min")
                dottedRule
                routineRow("02", text("Regarder ma journée", "See my day"), "2 min")
                dottedRule
                routineRow("03", text("Un moment pour moi", "A moment for me"), "8 min")
            } else {
                Image(systemName: "waveform").font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(color(palette.accentText)).accessibilityHidden(true)
                Text(text("« MORE, qu’est-ce qui m’attend aujourd’hui ? »", "“MORE, what’s ahead today?”"))
                    .font(.serif(.title2)).fixedSize(horizontal: false, vertical: true)
                Text(text("Posez une question. Changez d’avis. Votre matin continue à votre rythme.",
                          "Ask a question. Change your mind. Your morning keeps moving at your pace."))
                    .font(.raleway(.subheadline)).foregroundStyle(muted).lineSpacing(3)
            }
            Text(text("Exemple · vous choisirez votre propre routine", "Example · you’ll choose your own routine"))
                .font(.raleway(.caption)).foregroundStyle(muted)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(MorningDottedFrame(cornerRadius: 10, spacing: 6, dotRadius: 0.8).fill(ink.opacity(0.45)))
        .padding(.top, 12)
    }

    private func sourceRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.raleway(.title3)).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.raleway(.subheadline, .semibold))
                Text(detail).font(.raleway(.caption)).foregroundStyle(muted)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func routineRow(_ number: String, _ title: String, _ duration: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number).font(.raleway(.caption).monospacedDigit()).foregroundStyle(muted)
            Text(title).font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(duration).font(.raleway(.caption).monospacedDigit()).fixedSize()
        }
    }

    private var dottedRule: some View {
        MorningDottedFrame(cornerRadius: 0, spacing: 6, dotRadius: 0.7)
            .fill(ink.opacity(0.3)).frame(height: 1).accessibilityHidden(true)
    }

    private var subscriptionDetails: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text(text("MORE · ABONNEMENT MENSUEL", "MORE · MONTHLY MEMBERSHIP"))
                    .font(.raleway(.caption, .medium)).tracking(1.1).foregroundStyle(muted)
                if let offer {
                    if offer.includesFreeTrial {
                        Text(text("7 jours gratuits", "7 days free")).font(.serif(.title))
                        Text(text("Puis \(offer.monthlyPrice) par mois", "Then \(offer.monthlyPrice) per month"))
                            .font(.raleway(.body, .semibold)).accessibilityIdentifier("paywall.price")
                    } else {
                        Text(text("\(offer.monthlyPrice) par mois", "\(offer.monthlyPrice) per month"))
                            .font(.serif(.title)).accessibilityIdentifier("paywall.price")
                    }
                    dottedRule
                    benefit("checkmark", text("Une routine qui vous ressemble", "A routine that feels like you"))
                    benefit("checkmark", text("Vos matins délégués à MORE", "Your mornings entrusted to MORE"))
                    benefit("checkmark", text("La liberté d’interrompre à tout moment", "The freedom to interrupt anytime"))
                } else {
                    Text(text("Votre offre se prépare", "Getting your offer ready")).font(.serif(.title2))
                    Text(text("Le prix et l’essai disponibles s’afficheront ici après la connexion à l’App Store.",
                              "Your available price and trial will appear here after connecting to the App Store."))
                        .font(.raleway(.subheadline)).foregroundStyle(muted)
                }
            }
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(MorningDottedFrame(cornerRadius: 10, spacing: 5, dotRadius: 1).fill(ink))

            if let offer, offer.includesFreeTrial {
                VStack(alignment: .leading, spacing: 14) {
                    benefit("sun.max", text("Aujourd’hui · votre essai commence", "Today · your trial begins"))
                    benefit("calendar", text("Après 7 jours · \(offer.monthlyPrice) par mois", "After 7 days · \(offer.monthlyPrice) per month"))
                }
            }
            Text(text("Après l’abonnement, vous choisirez les accès utiles à votre routine. Chaque accès vous sera expliqué avant de l’autoriser.",
                      "After subscribing, choose the access your routine needs. Each request will be explained before you allow it."))
                .font(.raleway(.subheadline)).foregroundStyle(muted).lineSpacing(3)
            if let offer {
                Text(offer.includesFreeTrial
                     ? text("7 jours gratuits, puis \(offer.monthlyPrice)/mois. Renouvellement automatique, sauf résiliation au moins 24 h avant la fin de l’essai ou de la période en cours. Gérez votre abonnement dans les réglages de l’App Store.",
                            "7 days free, then \(offer.monthlyPrice)/month. Automatically renews unless cancelled at least 24 hours before the trial or current period ends. Manage your subscription in App Store settings.")
                     : text("\(offer.monthlyPrice)/mois. Renouvellement automatique, sauf résiliation au moins 24 h avant la fin de la période en cours. Gérez votre abonnement dans les réglages de l’App Store.",
                            "\(offer.monthlyPrice)/month. Automatically renews unless cancelled at least 24 hours before the current period ends. Manage your subscription in App Store settings."))
                    .font(.raleway(.caption)).foregroundStyle(muted).lineSpacing(3)
            }
            legalActions
        }
    }

    private func benefit(_ symbol: String, _ title: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 18).accessibilityHidden(true)
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        .font(.raleway(.subheadline))
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if isPaywall, let notice {
                Text(notice).font(.raleway(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("paywall.notice")
            }
            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    if isPaywall && purchaseState.isBusy { ProgressView().tint(ink) }
                    Text(primaryTitle).fixedSize(horizontal: false, vertical: true)
                    if !isPaywall { Spacer(); Image(systemName: "arrow.right") }
                }
                .font(MorningTheme.Typography.control)
                .frame(maxWidth: .infinity, minHeight: 26)
                .padding(.horizontal, 20).padding(.vertical, 16)
                .background(surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(MorningDottedFrame(cornerRadius: 8, spacing: 5, dotRadius: 1).fill(ink))
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(isPaywall && (purchaseState.isBusy || purchaseState == .pending))
            .accessibilityIdentifier(isPaywall ? "paywall.subscribe" : "onboarding.next")
            Text(isPaywall ? paymentSummary
                          : text("À votre rythme. Vous gardez la main.", "At your pace. You stay in control."))
                .font(.raleway(.caption)).foregroundStyle(muted)
            if isPaywall {
                Button(text("Déjà abonné ? Restaurer mes achats", "Already subscribed? Restore purchases"), action: restore)
                    .font(.raleway(.caption, .medium)).frame(minHeight: 44)
                    .disabled(purchaseState.isBusy)
                    .accessibilityIdentifier("paywall.restore")
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 480)
        .padding(.horizontal, typeSize.isAccessibilitySize ? 0 : 28).padding(.top, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            // Reading and purchasing controls stay opaque over the landscape.
            color(palette.paper).ignoresSafeArea(edges: .bottom)
        }
    }

    private var legalActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) { legalButtons }
            VStack(alignment: .leading, spacing: 4) { legalButtons }
        }
        .font(.raleway(.caption, .medium)).buttonStyle(.plain)
    }
    @ViewBuilder private var legalButtons: some View {
        Button(text("Conditions", "Terms")) { showLegal(.terms) }
            .frame(minHeight: 44).accessibilityIdentifier("paywall.terms")
        Button(text("Confidentialité", "Privacy")) { showLegal(.privacy) }
            .frame(minHeight: 44).accessibilityIdentifier("paywall.privacy")
    }
    private var primaryTitle: String {
        guard isPaywall else {
            return page == 2 ? text("Découvrir mon offre", "See my offer") : text("Continuer", "Continue")
        }
        if offer == nil && !purchaseState.isBusy { return text("Réessayer", "Try again") }
        switch purchaseState {
        case .loading: return text("Connexion à l’App Store…", "Connecting to the App Store…")
        case .purchasing: return text("Confirmation en cours…", "Confirming your purchase…")
        case .restoring: return text("Restauration en cours…", "Restoring purchases…")
        case .pending: return text("En attente de confirmation", "Awaiting confirmation")
        case .unavailable: return text("Réessayer", "Try again")
        default:
            return offer?.includesFreeTrial == true
                ? text("Commencer mes 7 jours gratuits", "Start my 7 days free")
                : text("M’abonner", "Subscribe")
        }
    }
    private var paymentSummary: String {
        guard let offer else { return text("Achat sécurisé avec l’App Store", "Secure purchase with the App Store") }
        return offer.includesFreeTrial
            ? text("7 jours gratuits, puis \(offer.monthlyPrice)/mois", "7 days free, then \(offer.monthlyPrice)/month")
            : text("\(offer.monthlyPrice)/mois · renouvellement automatique", "\(offer.monthlyPrice)/month · auto-renewing")
    }
    private var notice: String? {
        switch purchaseState {
        case .pending: text("Votre achat attend la confirmation de l’App Store. Vous pourrez continuer dès qu’il sera validé.",
                            "Your purchase is awaiting App Store confirmation. You can continue once it is approved.")
        case .unavailable: text("L’App Store est indisponible pour le moment. Réessayez dans un instant.",
                                "The App Store is unavailable right now. Please try again shortly.")
        case .failed(let message): message
        default: nil
        }
    }
    private func primaryAction() {
        if !isPaywall { move(to: page + 1) }
        else if purchaseState == .unavailable || offer == nil { retry() }
        else { subscribe() }
    }
    private func move(to next: Int) {
        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.15)) { page = next }
    }
}
