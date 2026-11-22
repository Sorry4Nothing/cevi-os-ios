import Foundation

// MARK: Weather (Wetter)

/// The weather of a camp holds only the place of the camp (coordinates), never data of people.
nonisolated enum CampWeatherWarning: String, CampTolerantEnum {
    case thunderstorm = "gewitter"
    /// Gusts from 60 km/h.
    case gusts = "boeen"
    /// From 30 degrees.
    case heat = "hitze"
    /// From 20 mm a day.
    case rain = "regen"
    case unknown

    static var fallback: Self { .unknown }
}

nonisolated struct CampWeatherDay: Codable, Equatable, Sendable {
    let date: Date
    /// WMO weather code; the app picks the symbol.
    let code: Int?
    /// Degrees Celsius.
    let maxTemperature: Double?
    let minTemperature: Double?
    /// Millimetres per day.
    let rain: Double?
    /// Strongest gust in km/h.
    let gusts: Double?
    /// The word for the weather, for example «Klar».
    let condition: String?
    let warnings: [CampWeatherWarning]

    enum CodingKeys: String, CodingKey {
        case code, date = "datum", maxTemperature = "tmax", minTemperature = "tmin", rain = "regen", gusts = "boeen"
        case condition = "zustand", warnings = "warnungen"
    }
}

/// The place of the camp as the weather service gets it: degrees, rounded to two decimals.
nonisolated struct CampWeatherPlace: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey { case latitude = "breite", longitude = "laenge" }
}

/// The forecast: from two days back to 16 days ahead. Without a place, on an outage of the service and when the
/// values are older than 24 hours, `days` is empty (no error).
nonisolated struct CampWeather: Codable, Equatable, Sendable {
    /// `nil` until the camp leadership sets one.
    let place: CampWeatherPlace?
    /// When the values were fetched last; `nil` without values.
    let asOf: Date?
    let days: [CampWeatherDay]

    enum CodingKeys: String, CodingKey { case place = "ort", asOf = "stand", days = "tage" }
}

/// Both `nil` switches the weather off. Sent as `null`.
nonisolated struct CampWeatherPlaceSetting: Codable, Equatable, Sendable {
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey { case latitude = "breite", longitude = "laenge" }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

// MARK: Day pages (Tagesseiten)

/// A camp day without version, as the day pages and «today» name it.
nonisolated struct CampDayRef: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let label: String?

    enum CodingKeys: String, CodingKey { case id, date = "datum", label }
}

/// The page of a day: day chief and note. `chief` is only present when reading (not in the answer to writing).
nonisolated struct CampDayPage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let dayId: UUID
    let chiefPersonId: UUID?
    /// Up to 5000 characters.
    let note: String?
    let chief: CampPersonRef?

    enum CodingKeys: String, CodingKey {
        case id, version, dayId = "lagertagId", chiefPersonId = "tageschefPersonId", note = "notiz", chief = "tageschef"
    }
}

/// A day of the list; `page` is `nil` if the day has none yet.
nonisolated struct CampDayPageEntry: Codable, Equatable, Identifiable, Sendable {
    let dayId: UUID
    let date: Date
    let label: String?
    let page: CampDayPage?

    var id: UUID { dayId }

    enum CodingKeys: String, CodingKey { case dayId = "lagertagId", date = "datum", label, page = "seite" }
}

nonisolated struct CampDayPageList: Codable, Equatable, Sendable {
    let days: [CampDayPageEntry]

    enum CodingKeys: String, CodingKey { case days = "tage" }
}

nonisolated enum CampDayBlockKind: String, CampTolerantEnum {
    /// «Wichtig»: shown first on the day.
    case important = "wichtig"
    case idea = "idee"
    /// Needs a file (picture of the programme).
    case programPicture = "programmbild"
    case unknown

    static var fallback: Self { .unknown }
}

nonisolated struct CampDayBlock: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let version: Int
    let pageId: UUID
    let kind: CampDayBlockKind
    /// Up to 1000 characters.
    let text: String
    let fileId: UUID?
    let order: Int
    /// The link to the file of a programme picture; only in `campDayPage(…)`.
    let file: CampFileRef?

    enum CodingKeys: String, CodingKey {
        case id, version, text, file = "datei"
        case pageId = "seiteId", kind = "art", fileId = "dateiId", order = "reihenfolge"
    }
}

/// What a day shows, in one answer. The to-dos of the day are the tasks with a deadline on that day (no table of their own):
/// who may not read all tasks sees only the own ones.
nonisolated struct CampDayPageDetail: Codable, Equatable, Sendable {
    let day: CampDayRef
    let page: CampDayPage?
    let blocks: [CampDayBlock]
    /// `nil` without the right, without a place and on an outage of the weather service.
    let weather: CampWeatherDay?
    let weatherAsOf: Date?
    let tasks: [CampTask]

    enum CodingKeys: String, CodingKey {
        case day = "lagertag", page = "seite", blocks = "bloecke", weather = "wetter", weatherAsOf = "wetterStand", tasks = "aufgaben"
    }
}

nonisolated struct CampDayPageCreate: Encodable, Sendable {
    /// A member of the camp, else 400 `KEIN_MITGLIED`.
    var chiefPersonId: UUID?
    var note: String?

    enum CodingKeys: String, CodingKey { case chiefPersonId = "tageschefPersonId", note = "notiz" }
}

nonisolated struct CampDayPagePatch: Encodable, Sendable {
    let version: Int
    var chiefPersonId: CampField<UUID>?
    var note: CampField<String>?

    enum CodingKeys: String, CodingKey { case version, chiefPersonId = "tageschefPersonId", note = "notiz" }
}

nonisolated struct CampDayBlockCreate: Encodable, Sendable {
    let kind: CampDayBlockKind
    let text: String
    /// Required for a programme picture, not allowed otherwise.
    var fileId: UUID?
    var order: Int?

    enum CodingKeys: String, CodingKey { case text, kind = "art", fileId = "dateiId", order = "reihenfolge" }
}

/// The kind and the file of a block do not change.
nonisolated struct CampDayBlockPatch: Encodable, Sendable {
    let version: Int
    var text: String?
    var order: Int?

    enum CodingKeys: String, CodingKey { case version, text, order = "reihenfolge" }
}

// MARK: «Today» (Heute) and «My week» (Meine Woche)

/// The part of today the day page gives: page, blocks and the tasks due today.
nonisolated struct CampTodayPage: Codable, Equatable, Sendable {
    let page: CampDayPage?
    let blocks: [CampDayBlock]
    let tasks: [CampTask]

    enum CodingKeys: String, CodingKey { case page = "seite", blocks = "bloecke", tasks = "aufgaben" }
}

nonisolated struct CampTodayWeather: Codable, Equatable, Sendable {
    let day: CampWeatherDay?
    let asOf: Date?

    enum CodingKeys: String, CodingKey { case day = "tag", asOf = "stand" }
}

nonisolated struct CampTodayShifts: Codable, Equatable, Sendable {
    let duties: [CampDuty]
    let shifts: [CampShift]

    enum CodingKeys: String, CodingKey { case duties = "dienste", shifts = "schichten" }
}

/// Today in the camp (date in Zurich time). Every part follows the right to read its source and is `nil` without it; a part with
/// the right but without data is empty. Without any readable part the server answers 403. Shifts name people: only for screens
/// of the camp members. Emergency contacts are not part of it (`campEmergency`).
nonisolated struct CampToday: Codable, Equatable, Sendable {
    let date: Date
    /// `nil` if there is no camp day today.
    let day: CampDayRef?
    let page: CampTodayPage?
    let weather: CampTodayWeather?
    /// Numbers only, no names.
    let attendance: CampAttendanceSummary?
    let shifts: CampTodayShifts?
    /// At most 50; roles with only the team meetings see date, time, title and place.
    let meetings: [CampMeetingView<CampMeetingSummary>]?

    enum CodingKeys: String, CodingKey {
        case date = "datum", day = "lagertag", page = "tagesseite", weather = "wetter", attendance = "anwesenheit"
        case shifts = "schichten", meetings = "hoecks"
    }
}

nonisolated struct CampOwnShiftDuty: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let night: Bool

    enum CodingKeys: String, CodingKey { case id, name, night = "nacht" }
}

/// A shift of the signed-in person with the duty it belongs to.
nonisolated struct CampOwnShift: Codable, Equatable, Identifiable, Sendable {
    let shift: CampShift
    let duty: CampOwnShiftDuty?

    var id: UUID { shift.id }

    private enum ExtraKeys: String, CodingKey { case duty = "dienst" }

    init(from decoder: any Decoder) throws {
        shift = try CampShift(from: decoder)
        duty = try decoder.container(keyedBy: ExtraKeys.self).decodeIfPresent(CampOwnShiftDuty.self, forKey: .duty)
    }

    func encode(to encoder: any Encoder) throws {
        try shift.encode(to: encoder)
        var container = encoder.container(keyedBy: ExtraKeys.self)
        try container.encode(duty, forKey: .duty)
    }
}

/// The seven days from today on (`from` to `to`, Zurich time), from the view of the signed-in person. A part is `nil` without
/// the right to read its source; without any readable part the server answers 403.
nonisolated struct CampMyWeek: Codable, Equatable, Sendable {
    let from: Date
    let to: Date
    /// The own tasks that are not done, with a deadline up to `to` (also overdue ones), at most 100.
    let tasks: [CampTask]?
    let shifts: [CampOwnShift]?
    /// At most 50.
    let meetings: [CampMeetingView<CampMeetingSummary>]?

    enum CodingKeys: String, CodingKey { case from = "von", to = "bis", tasks = "aufgaben", shifts = "schichten", meetings = "hoecks" }
}
