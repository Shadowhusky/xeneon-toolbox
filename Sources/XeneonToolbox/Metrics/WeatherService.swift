import Foundation

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

struct Weather: Equatable {
    let tempC: Double
    let code: Int
    let city: String
    var highC: Double? = nil
    var lowC: Double? = nil
    var windKph: Double? = nil
    var humidity: Int? = nil
    var days: [DayForecast] = []

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

/// Fetches current weather + a short forecast with no API key: IP geolocation
/// (ipapi.co) + the free Open-Meteo forecast. Refreshes every 15 minutes.
@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var weather: Weather?
    private var timer: Timer?

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
    }

    func refresh() async {
        guard let loc = await geolocate(),
              let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(loc.lat)&longitude=\(loc.lon)&current=temperature_2m,weather_code,relative_humidity_2m,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=6"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = json["current"] as? [String: Any],
              let temp = cur["temperature_2m"] as? Double,
              let code = cur["weather_code"] as? Int else { return }

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
        weather = w
    }

    private func geolocate() async -> (lat: Double, lon: Double, city: String)? {
        guard let url = URL(string: "https://ipapi.co/json/"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = json["latitude"] as? Double, let lon = json["longitude"] as? Double else { return nil }
        return (lat, lon, (json["city"] as? String) ?? "")
    }
}
