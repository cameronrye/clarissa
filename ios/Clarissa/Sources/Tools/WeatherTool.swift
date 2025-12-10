import Foundation
import WeatherKit
import CoreLocation

/// Helper for getting current location
@available(iOS 16.0, macOS 13.0, *)
private final class WeatherLocationHelper: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    let locationManager = CLLocationManager()
    var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer // Weather doesn't need high accuracy
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

/// Tool for getting weather information
@available(iOS 16.0, macOS 13.0, *)
final class WeatherTool: ClarissaTool, @unchecked Sendable {
    let name = "weather"
    let description = "Get current weather and forecast. If no location is provided, uses the user's current location."
    let priority = ToolPriority.extended
    let requiresConfirmation = false

    private let weatherService = WeatherService.shared
    private let geocoder = CLGeocoder()
    private let locationHelper = WeatherLocationHelper()

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "location": [
                    "type": "string",
                    "description": "Location name (e.g., 'San Francisco, CA'). If omitted, uses current location."
                ],
                "latitude": [
                    "type": "number",
                    "description": "Latitude coordinate (optional)"
                ],
                "longitude": [
                    "type": "number",
                    "description": "Longitude coordinate (optional)"
                ],
                "forecast": [
                    "type": "boolean",
                    "description": "Include 5-day forecast (default: false)"
                ]
            ]
        ]
    }

    func execute(arguments: String) async throws -> String {
        let args: [String: Any]
        if let data = arguments.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            args = parsed
        } else {
            args = [:] // Empty args = use current location
        }

        let location: CLLocation
        var locationName: String? = nil

        // Get location from coordinates, location name, or current location
        if let lat = args["latitude"] as? Double, let lon = args["longitude"] as? Double {
            location = CLLocation(latitude: lat, longitude: lon)
        } else if let name = args["location"] as? String, !name.isEmpty {
            locationName = name
            let placemarks = try await geocoder.geocodeAddressString(name)
            guard let placemark = placemarks.first, let clLocation = placemark.location else {
                throw ToolError.executionFailed("Could not find location: \(name)")
            }
            location = clLocation
        } else {
            // Use current location
            location = try await getCurrentLocation()
            // Reverse geocode to get location name
            if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
               let placemark = placemarks.first {
                locationName = [placemark.locality, placemark.administrativeArea]
                    .compactMap { $0 }
                    .joined(separator: ", ")
            }
        }

        let includeForecast = args["forecast"] as? Bool ?? false

        // Fetch weather
        let weather = try await weatherService.weather(for: location)

        var locationDict: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude
        ]
        if let name = locationName {
            locationDict["name"] = name
        }

        var response: [String: Any] = [
            "current": formatCurrentWeather(weather.currentWeather),
            "location": locationDict
        ]

        if includeForecast {
            response["forecast"] = formatForecast(weather.dailyForecast)
        }

        let responseData = try JSONSerialization.data(withJSONObject: response)
        return String(data: responseData, encoding: .utf8) ?? "{}"
    }

    /// Get the user's current location
    private func getCurrentLocation() async throws -> CLLocation {
        // Check authorization
        let status = locationHelper.locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationHelper.locationManager.requestWhenInUseAuthorization()
            try await Task.sleep(nanoseconds: 500_000_000)
        case .denied, .restricted:
            throw ToolError.notAvailable("Location access denied. Please enable in Settings or specify a location.")
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationHelper.continuation = continuation
            locationHelper.locationManager.requestLocation()
        }
    }

    private func formatCurrentWeather(_ current: CurrentWeather) -> [String: Any] {
        [
            "temperature": [
                "value": current.temperature.value,
                "unit": current.temperature.unit.symbol
            ],
            "feelsLike": [
                "value": current.apparentTemperature.value,
                "unit": current.apparentTemperature.unit.symbol
            ],
            "condition": current.condition.description,
            "humidity": current.humidity * 100,
            "windSpeed": [
                "value": current.wind.speed.value,
                "unit": current.wind.speed.unit.symbol
            ],
            "windDirection": current.wind.direction.description,
            "uvIndex": current.uvIndex.value,
            "visibility": [
                "value": current.visibility.value,
                "unit": current.visibility.unit.symbol
            ]
        ]
    }

    private func formatForecast(_ forecast: Forecast<DayWeather>) -> [[String: Any]] {
        forecast.prefix(5).map { day in
            [
                "date": ISO8601DateFormatter().string(from: day.date),
                "condition": day.condition.description,
                "highTemperature": [
                    "value": day.highTemperature.value,
                    "unit": day.highTemperature.unit.symbol
                ],
                "lowTemperature": [
                    "value": day.lowTemperature.value,
                    "unit": day.lowTemperature.unit.symbol
                ],
                "precipitationChance": day.precipitationChance * 100,
                "uvIndex": day.uvIndex.value
            ]
        }
    }
}

