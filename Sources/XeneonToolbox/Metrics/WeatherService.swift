import Foundation

struct Weather: Equatable {
    let tempC: Double
    let code: Int
    let city: String

    var symbol: String {
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

    var displayTemp: String {
        let us = Locale.current.measurementSystem == .us
        let t = us ? tempC * 9 / 5 + 32 : tempC
        return "\(Int(t.rounded()))°"
    }
}

/// Fetches current weather with no API key: IP geolocation (ipapi.co) + the
/// free Open-Meteo forecast. Refreshes every 15 minutes.
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
              let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(loc.lat)&longitude=\(loc.lon)&current=temperature_2m,weather_code"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = json["current"] as? [String: Any],
              let temp = cur["temperature_2m"] as? Double,
              let code = cur["weather_code"] as? Int else { return }
        weather = Weather(tempC: temp, code: code, city: loc.city)
    }

    private func geolocate() async -> (lat: Double, lon: Double, city: String)? {
        guard let url = URL(string: "https://ipapi.co/json/"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = json["latitude"] as? Double, let lon = json["longitude"] as? Double else { return nil }
        return (lat, lon, (json["city"] as? String) ?? "")
    }
}
