import Foundation

enum HealthMetricsBriefingComposer {
    /// A last measurement is a measurement, never an estimate of readiness.
    static func prepare(_ inputs: [HealthMetric: HealthMetricBriefingInput], at now: Date, dayEnd: Date,
                        zone: TimeZone, locale: Locale, readMaximumAge: TimeInterval) -> [PreparedHealthMetric] {
        let french = locale.language.languageCode?.identifier == "fr"
        return HealthMetric.allCases.compactMap { metric in
            guard let input = inputs[metric] else { return nil }
            let name: String
            let unit: String
            switch metric {
            case .heartRateVariabilitySDNN:
                name = french ? "Variabilité cardiaque (SDNN)" : "Heart rate variability (SDNN)"
                unit = french ? "millisecondes" : "milliseconds"
            case .restingHeartRate:
                name = french ? "Fréquence cardiaque au repos" : "Resting heart rate"
                unit = french ? "battements par minute" : "beats per minute"
            case .respiratoryRate:
                name = french ? "Fréquence respiratoire" : "Respiratory rate"
                unit = french ? "respirations par minute" : "breaths per minute"
            }
            func plain(_ status: MorningBriefingSourceStatus, _ issue: MorningBriefingSourceIssue, _ text: String,
                       readAt: Date? = nil, observation: HealthMetricSample? = nil) -> PreparedHealthMetric {
                .init(metric: metric, section: .init(status: status, issue: issue, statusText: text,
                    retrievedAt: readAt, observationAt: observation?.end,
                    sourceLabels: observation.map { [sourceLabel($0.source)] } ?? [], omissionCount: 0,
                    segments: [], validUntil: nil), observation: observation)
            }
            func sourceLabel(_ source: HealthObservationSource) -> String {
                let kind = MorningBriefingPhrases(locale: locale)!.sleepSource(source.kind)
                guard let name = source.name else { return kind }
                return source.wasUserEntered ? "\(name) (\(kind))" : name
            }
            let snapshot: HealthMetricSnapshot
            switch input {
            case .excluded:
                return plain(.notConfigured, .notConfigured, french ? "\(name) non incluse." : "\(name) is not included.")
            case .notConnected:
                return plain(.unavailable, .sourceUnavailable, french ? "La lecture des mesures Santé n’est pas disponible dans cette version." : "Health measurements are not available in this version.")
            case .unavailableOnDevice:
                return plain(.unavailable, .unavailableOnDevice, french ? "Les données de santé ne sont pas disponibles sur cet appareil." : "Health data is not available on this device.")
            case .notReadable:
                return plain(.unavailable, .notReadable, french ? "\(name) : lecture impossible." : "\(name) could not be read.")
            case .snapshot(let value): snapshot = value
            }
            guard snapshot.metric == metric, snapshot.readAt.timeIntervalSinceReferenceDate.isFinite else {
                return plain(.unavailable, .invalidSnapshot, french ? "\(name) : lecture impossible." : "\(name) could not be read.")
            }
            guard snapshot.readAt <= now else {
                return plain(.unavailable, .futureTimestamp, french ? "\(name) : lecture impossible." : "\(name) could not be read.")
            }
            guard now.timeIntervalSince(snapshot.readAt) < readMaximumAge else {
                return plain(.stale, .expired, french ? "\(name) : une nouvelle lecture est nécessaire." : "\(name) needs a fresh read.", readAt: snapshot.readAt)
            }
            guard let sample = snapshot.latest else {
                return plain(.missing, .noRecord, french ? "\(name) : aucun relevé retourné." : "No \(name.lowercased()) record was returned.", readAt: snapshot.readAt)
            }
            let number = NumberFormatter()
            number.locale = locale; number.numberStyle = .decimal; number.maximumFractionDigits = 1
            guard let formatted = number.string(from: NSNumber(value: sample.value)) else {
                return plain(.unavailable, .invalidSnapshot, french ? "\(name) : lecture impossible." : "\(name) could not be read.")
            }
            let date = DateFormatter()
            date.locale = locale; date.timeZone = zone; date.dateStyle = .medium; date.timeStyle = .short
            let source = sourceLabel(sample.source)
            let text = french ? "\(name) enregistrée : \(formatted) \(unit), le \(date.string(from: sample.end)), source \(source)."
                : "\(name) recorded: \(formatted) \(unit), on \(date.string(from: sample.end)), source \(source)."
            let observationExpiry = sample.end.addingTimeInterval(86_400)
            guard now < observationExpiry else {
                return plain(.stale, .olderRecord, (french ? "Mesure ancienne. " : "Older measurement. ") + text,
                    readAt: snapshot.readAt, observation: sample)
            }
            return .init(metric: metric, section: .init(status: .fresh, issue: nil,
                statusText: french ? "Dernière mesure enregistrée dans Santé, sans interprétation médicale." : "Latest measurement recorded in Health, without medical interpretation.",
                retrievedAt: snapshot.readAt, observationAt: sample.end, sourceLabels: [source], omissionCount: 0,
                segments: [.init(id: "health.\(metric.rawValue)", source: .healthMetrics, text: text)],
                validUntil: min(dayEnd, snapshot.readAt.addingTimeInterval(readMaximumAge), observationExpiry)), observation: sample)
        }
    }
}
