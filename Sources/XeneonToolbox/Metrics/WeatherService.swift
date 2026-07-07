import Foundation
import CoreLocation

/// One-shot CoreLocation fix. On a Mac this resolves via Wi-Fi positioning
/// (typically ~50 m) — far more accurate than IP geolocation, which only finds
/// the ISP's endpoint. Resolves nil silently when denied or unavailable so the
/// caller can fall through to IP.
private final class SystemLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func locate() async -> CLLocation? {
        let status = manager.authorizationStatus
        AppLog.info("location", "authorization=\(status.rawValue) servicesEnabled=\(CLLocationManager.locationServicesEnabled())")
        guard status != .denied, status != .restricted else { return nil }
        guard continuation == nil else { return nil }   // a fix is already in flight
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()   // show the consent prompt explicitly
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            continuation = cont
            manager.requestLocation()
            // If CoreLocation never calls back (consent prompt pending, services
            // off), resume with nil so the weather refresh falls through to the
            // IP path instead of hanging forever. finish() ignores double calls.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.finish(nil)
            }
        }
    }

    private func finish(_ loc: CLLocation?) {
        continuation?.resume(returning: loc)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.first)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }
}

struct DayForecast: Equatable, Identifiable {
    let date: Date
    let code: Int
    let highC: Double
    let lowC: Double
    var id: Double { date.timeIntervalSince1970 }
    var symbol: String { Weather.symbol(for: code) }
    func high() -> String { Weather.temp(highC) }
    func low() -> String { Weather.temp(lowC) }
    var weekday: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: date)
    }
}

struct HourForecast: Equatable, Identifiable {
    let date: Date
    let code: Int
    let tempC: Double
    var id: Double { date.timeIntervalSince1970 }
    var symbol: String { Weather.symbol(for: code) }
    func temp() -> String { Weather.temp(tempC) }
    var hourLabel: String {
        if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .hour) { return "Now" }
        let f = DateFormatter(); f.dateFormat = "ha"; return f.string(from: date).lowercased()
    }
}

struct Weather: Equatable {
    let tempC: Double
    let code: Int
    let city: String
    var highC: Double? = nil
    var lowC: Double? = nil
    var windKph: Double? = nil
    var humidity: Int? = nil
    var days: [DayForecast] = []
    var hours: [HourForecast] = []

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2, 3: return "cloud.sun.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...67: return "cloud.rain.fill"
        case 71...77: return "snowflake"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func conditionText(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Rain showers"
        case 95...99: return "Thunderstorm"
        default: return "Cloudy"
        }
    }

    static func temp(_ c: Double) -> String {
        let us = Locale.current.measurementSystem == .us
        let t = us ? c * 9 / 5 + 32 : c
        return "\(Int(t.rounded()))°"
    }

    var symbol: String { Weather.symbol(for: code) }
    var condition: String { Weather.conditionText(code) }
    var displayTemp: String { Weather.temp(tempC) }
    var displayHigh: String? { highC.map { Weather.temp($0) } }
    var displayLow: String? { lowC.map { Weather.temp($0) } }
    var displayWind: String? {
        guard let w = windKph else { return nil }
        let us = Locale.current.measurementSystem == .us
        return us ? "\(Int((w * 0.621371).rounded())) mph" : "\(Int(w.rounded())) km/h"
    }
}

/// A user-chosen weather location (IP geolocation is only ISP-accurate; this lets
/// the user pin their real city from Settings).
struct WeatherLocation: Codable, Equatable, Identifiable {
    let name: String
    let region: String    // "admin1, country" for disambiguation
    let lat: Double
    let lon: Double
    var id: String { "\(lat),\(lon)" }
}

/// Fetches current weather + a short forecast with no API key: IP geolocation
/// (ipapi.co) + the free Open-Meteo forecast. Refreshes every 15 minutes.
@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var weather: Weather?
    @Published private(set) var customPlace: WeatherLocation?
    /// False until the first fetch attempt resolves, so the UI can show a loading
    /// state on a cold launch instead of a misleading "unavailable".
    @Published private(set) var firstAttemptDone = false
    private var timer: Timer?
    private static let placeKey = "weather.place.v1"

    init() {
        if let data = AppDefaults.shared.data(forKey: Self.placeKey) {
            customPlace = try? JSONDecoder().decode(WeatherLocation.self, from: data)
        }
    }

    /// Pin the weather to a chosen city (nil returns to automatic IP location).
    func setPlace(_ place: WeatherLocation?) {
        customPlace = place
        if let place, let data = try? JSONEncoder().encode(place) {
            AppDefaults.shared.set(data, forKey: Self.placeKey)
        } else {
            AppDefaults.shared.removeObject(forKey: Self.placeKey)
        }
        weather = nil
        Task { await refresh() }
    }

    /// City search via Open-Meteo's free geocoding (no key).
    static func searchCities(_ query: String) async -> [WeatherLocation] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2,
              let escaped = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(escaped)&count=6&language=en&format=json"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { r in
            guard let name = r["name"] as? String,
                  let lat = r["latitude"] as? Double,
                  let lon = r["longitude"] as? Double else { return nil }
            let region = [r["admin1"] as? String, r["country"] as? String]
                .compactMap { $0 }.joined(separator: ", ")
            return WeatherLocation(name: name, region: region, lat: lat, lon: lon)
        }
    }

    func start() {
        guard timer == nil else { return }
        Task { await refresh() }
        let t = Timer(timeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        retryTimer?.invalidate()
        retryTimer = nil
    }

    func refresh() async {
        guard let loc = await geolocate(),
              let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(loc.lat)&longitude=\(loc.lon)&current=temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m&hourly=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=6"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = json["current"] as? [String: Any],
              let temp = cur["temperature_2m"] as? Double,
              let code = cur["weather_code"] as? Int else { firstAttemptDone = true; scheduleRetry(); return }

        var w = Weather(tempC: temp, code: code, city: loc.city)
        w.humidity = (cur["relative_humidity_2m"] as? Double).map { Int($0.rounded()) } ?? (cur["relative_humidity_2m"] as? Int)
        w.windKph = cur["wind_speed_10m"] as? Double

        if let daily = json["daily"] as? [String: Any],
           let times = daily["time"] as? [String],
           let codes = daily["weather_code"] as? [Int],
           let highs = daily["temperature_2m_max"] as? [Double],
           let lows = daily["temperature_2m_min"] as? [Double] {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = .current
            var days: [DayForecast] = []
            for i in 0..<min(times.count, codes.count, highs.count, lows.count) {
                guard let d = f.date(from: times[i]) else { continue }
                days.append(DayForecast(date: d, code: codes[i], highC: highs[i], lowC: lows[i]))
            }
            w.days = days
            if let today = days.first { w.highC = today.highC; w.lowC = today.lowC }
        }

        if let hourly = json["hourly"] as? [String: Any],
           let times = hourly["time"] as? [String],
           let codes = hourly["weather_code"] as? [Int],
           let temps = hourly["temperature_2m"] as? [Double] {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
            let plain = DateFormatter(); plain.dateFormat = "yyyy-MM-dd'T'HH:mm"; plain.timeZone = .current
            let now = Date()
            var hours: [HourForecast] = []
            for i in 0..<min(times.count, codes.count, temps.count) {
                guard let d = plain.date(from: times[i]) ?? f.date(from: times[i]) else { continue }
                if d < now.addingTimeInterval(-3600) { continue }   // from the current hour on
                hours.append(HourForecast(date: d, code: codes[i], tempC: temps[i]))
                if hours.count >= 12 { break }
            }
            w.hours = hours
        }
        weather = w
        firstAttemptDone = true
    }

    /// A failed launch-time fetch (offline, rate-limited geolocation) used to mean
    /// "Weather unavailable" for the full 15-minute cycle. Retry in a minute
    /// instead, until the first success.
    private var retryTimer: Timer?
    private func scheduleRetry() {
        AppLog.error("weather", "refresh failed (geolocation or forecast fetch) — retrying in 60s")
        guard weather == nil, retryTimer == nil else { return }
        let t = Timer(timeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.retryTimer = nil
                await self?.refresh()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        retryTimer = t
    }

    // MARK: - Geolocation

    private struct GeoCache: Codable {
        let lat: Double, lon: Double
        let city: String
        let at: Date
    }
    private static let geoCacheKey = "weather.geo.v1"

    private let locator = SystemLocator()

    /// The Mac's location, best source first: the user's pinned city, then
    /// CoreLocation (Wi-Fi positioning, ~50 m — IP lookup only finds the ISP's
    /// endpoint), then a day-long cache, then IP providers. The cache also stops
    /// the free IP services rate-limiting us (which used to kill weather
    /// entirely); a stale location beats showing nothing.
    private func geolocate() async -> (lat: Double, lon: Double, city: String)? {
        if let p = customPlace { return (p.lat, p.lon, p.name) }   // the user's pinned city
        if let loc = await locator.locate() {
            let coord = loc.coordinate
            let city = await Self.cityName(for: loc)
                ?? Self.loadGeoCache().map(\.city) ?? ""
            let c = GeoCache(lat: coord.latitude, lon: coord.longitude, city: city, at: Date())
            if let data = try? JSONEncoder().encode(c) { AppDefaults.shared.set(data, forKey: Self.geoCacheKey) }
            return (coord.latitude, coord.longitude, city)
        }
        if let c = Self.loadGeoCache(), Date().timeIntervalSince(c.at) < 86_400 {
            return (c.lat, c.lon, c.city)
        }
        if let fresh = await fetchLocation() {
            let c = GeoCache(lat: fresh.lat, lon: fresh.lon, city: fresh.city, at: Date())
            if let data = try? JSONEncoder().encode(c) { AppDefaults.shared.set(data, forKey: Self.geoCacheKey) }
            return fresh
        }
        // Everything down or rate-limited — a stale location beats no weather.
        if let c = Self.loadGeoCache() { return (c.lat, c.lon, c.city) }
        return nil
    }

    /// Reverse-geocode the neighbourhood/city name for a CoreLocation fix.
    private static func cityName(for location: CLLocation) async -> String? {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        let p = placemarks?.first
        return p?.locality ?? p?.subLocality ?? p?.administrativeArea
    }

    private static func loadGeoCache() -> GeoCache? {
        guard let data = AppDefaults.shared.data(forKey: geoCacheKey) else { return nil }
        return try? JSONDecoder().decode(GeoCache.self, from: data)
    }

    private func fetchLocation() async -> (lat: Double, lon: Double, city: String)? {
        if let url = URL(string: "https://ipapi.co/json/"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let lat = json["latitude"] as? Double, let lon = json["longitude"] as? Double {
            return (lat, lon, (json["city"] as? String) ?? "")
        }
        // Fallback provider (also free / keyless) in case ipapi.co is rate-limited.
        if let url = URL(string: "https://ipwho.is/"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (json["success"] as? Bool) != false,
           let lat = json["latitude"] as? Double, let lon = json["longitude"] as? Double {
            return (lat, lon, (json["city"] as? String) ?? "")
        }
        return nil
    }
}
