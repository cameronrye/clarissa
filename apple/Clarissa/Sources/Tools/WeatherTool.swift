import Foundation
import WeatherKit
import CoreLocation
import MapKit

/// Helper for getting current location - must be used from MainActor
@available(iOS 16.0, macOS 13.0, *)
@MainActor
private final class WeatherLocationHelper: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var isWaitingForAuthorization = false
    private var isRequestingLocation = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer // Weather doesn't need high accuracy
    }

    /// Timeout for location requests (30 seconds)
    private nonisolated static let locationTimeoutSeconds: UInt64 = 30

    /// Request location with proper continuation handling
    /// Throws if a location request is already in progress
    func requestLocation() async throws -> CLLocation {
        // Guard against concurrent requests to prevent continuation crash
        guard !isRequestingLocation else {
            throw ToolError.executionFailed("Location request already in progress")
        }
        isRequestingLocation = true

        defer { isRequestingLocation = false }

        // Create the location task on MainActor
        let locationTask = Task { @MainActor in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
                self.locationContinuation = continuation
                self.locationManager.requestLocation()
            }
        }

        // Create a timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: Self.locationTimeoutSeconds * 1_000_000_000)
            locationTask.cancel()
            // Also cancel the continuation if it exists
            await MainActor.run {
                if let continuation = self.locationContinuation {
                    self.locationContinuation = nil
                    continuation.resume(throwing: ToolError.executionFailed("Location request timed out after \(Self.locationTimeoutSeconds) seconds"))
                }
            }
        }

        do {
            let result = try await locationTask.value
            timeoutTask.cancel()
            return result
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }

    /// Request authorization and wait for user response
    /// Returns current status immediately if authorization is already determined or a request is pending
    func requestAuthorizationAndWait() async -> CLAuthorizationStatus {
        let currentStatus = locationManager.authorizationStatus

        // If already determined, return immediately
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        // Guard against concurrent authorization requests
        guard !isWaitingForAuthorization else {
            // Return current status if already waiting
            return currentStatus
        }

        // Mark that we're waiting so we know to resume the continuation
        isWaitingForAuthorization = true

        return await withCheckedContinuation { continuation in
            self.authorizationContinuation = continuation
            self.locationManager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.isRequestingLocation = false
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isRequestingLocation = false
            self.locationContinuation?.resume(throwing: error)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // Only resume if we're actively waiting for authorization
            guard self.isWaitingForAuthorization else { return }
            self.isWaitingForAuthorization = false
            self.authorizationContinuation?.resume(returning: status)
            self.authorizationContinuation = nil
        }
    }
}

/// Actor to hold the MainActor-isolated WeatherLocationHelper
@available(iOS 16.0, macOS 13.0, *)
private actor WeatherLocationHelperHolder {
    private var helper: WeatherLocationHelper?

    private func getOrCreateHelper() async -> WeatherLocationHelper {
        if let existing = helper {
            return existing
        }
        let newHelper = await MainActor.run { WeatherLocationHelper() }
        helper = newHelper
        return newHelper
    }

    func requestAuthorizationAndWait() async -> CLAuthorizationStatus {
        let h = await getOrCreateHelper()
        return await h.requestAuthorizationAndWait()
    }

    func requestLocation() async throws -> CLLocation {
        let h = await getOrCreateHelper()
        return try await h.requestLocation()
    }
}

/// Tool for getting weather information
@available(iOS 16.0, macOS 13.0, *)
final class WeatherTool: ClarissaTool, @unchecked Sendable {
    let name = "weather"
    let description = "Get current weather and forecast. If no location is provided, uses the user's current location."
    /// Weather is core priority since it's one of the most commonly requested features
    /// and must be included in the limited tool slots for Foundation Models
    let priority = ToolPriority.core
    let requiresConfirmation = false

    // Lazily initialize heavy helpers so that unit tests which only
    // touch static properties (and don't execute the tool) don't
    // instantiate WeatherKit or CLLocationManager in the SPM test
    // environment.
    private lazy var weatherService = WeatherService.shared
    private lazy var locationHelperHolder = WeatherLocationHelperHolder()

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

    /// Execute the weather tool.
    ///
    /// **Input (arguments JSON):**
    /// - `location: String?` (optional) – human‑readable place name
    ///   (for example, "San Francisco, CA").
    /// - `latitude: Double?` / `longitude: Double?` (optional) – explicit
    ///   coordinates. If provided, these take precedence over `location`.
    /// - `forecast: Bool?` (optional) – include a 5‑day forecast when true.
    ///   Defaults to `false`.
    ///
    /// Resolution order for where to fetch weather:
    /// 1. If `latitude` and `longitude` are present, use those.
    /// 2. Else if `location` is a non‑empty string, forward‑geocode it.
    /// 3. Else, use the user's current location (via Core Location).
    ///
    /// **Output (JSON string):**
    /// - `location: Object` – the resolved location
    ///   - `latitude: Double`
    ///   - `longitude: Double`
    ///   - `name: String?` – best‑effort human‑friendly name
    /// - `current: Object` – current weather snapshot
    ///   - `temperature: { value: Double, unit: String }`
    ///   - `feelsLike: { value: Double, unit: String }`
    ///   - `condition: String`
    ///   - `humidity: Double` (percentage 0–100)
    ///   - `windSpeed: { value: Double, unit: String }`
    ///   - `windDirection: String`
    ///   - `uvIndex: Double`
    ///   - `visibility: { value: Double, unit: String }`
    /// - `forecast: [Object]` (optional) – present when `forecast` is true.
    ///   Each element represents a day:
    ///   - `date: String` (ISO‑8601)
    ///   - `condition: String`
    ///   - `highTemperature: { value: Double, unit: String }`
    ///   - `lowTemperature: { value: Double, unit: String }`
    ///   - `precipitationChance: Double` (percentage 0–100)
    ///   - `uvIndex: Double`
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
            location = try await geocodeLocationName(name)
        } else {
            // Use current location
            location = try await getCurrentLocation()
            // Reverse geocode to get location name (best-effort)
            locationName = await reverseGeocodeLocation(location)
        }

        let includeForecast = args["forecast"] as? Bool ?? false

        // Fetch weather with proper error handling for WeatherKit errors
        let weather: Weather
        do {
            weather = try await weatherService.weather(for: location)
        } catch {
            // Translate WeatherKit errors to user-friendly messages
            throw mapWeatherKitError(error)
        }

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

    /// Map WeatherKit errors to user-friendly ToolError messages
    private func mapWeatherKitError(_ error: Error) -> ToolError {
        let description = error.localizedDescription.lowercased()

        // Check for common WeatherKit error patterns
        if description.contains("not authorized") || description.contains("unauthorized") {
            return .notAvailable("Weather service not configured. Please ensure the app has WeatherKit entitlements.")
        }

        if description.contains("network") || description.contains("internet") || description.contains("connection") {
            return .executionFailed("Unable to fetch weather data. Please check your internet connection.")
        }

        if description.contains("rate limit") || description.contains("too many requests") {
            return .executionFailed("Weather service is temporarily busy. Please try again in a moment.")
        }

        if description.contains("location") {
            return .executionFailed("Could not determine location for weather data.")
        }

        // For URLError, provide network-specific messages
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .executionFailed("Unable to connect to weather service. Please check your internet connection.")
            case .timedOut:
                return .executionFailed("Weather request timed out. Please try again.")
            default:
                return .executionFailed("Network error fetching weather: \(urlError.localizedDescription)")
            }
        }

        // Generic fallback with the actual error for debugging
        return .executionFailed("Unable to fetch weather: \(error.localizedDescription)")
    }

    // MARK: - Geocoding Helpers

    /// Forward geocode a human-readable location name into a CLLocation.
    private func geocodeLocationName(_ name: String) async throws -> CLLocation {
        #if os(macOS)
        // On macOS, use the new MapKit geocoding APIs to avoid deprecated CLGeocoder.
        if #available(macOS 15.0, *) {
            guard let request = MKGeocodingRequest(addressString: name) else {
                throw ToolError.executionFailed("Could not find location: \(name)")
            }
            let items = try await request.mapItems
            guard let item = items.first else {
                throw ToolError.executionFailed("Could not find location: \(name)")
            }
            return item.location
        } else {
            // Older macOS versions: MapKit geocoding may not be available.
            throw ToolError.notAvailable("Location search is not available on this version of macOS. Please specify coordinates instead.")
        }
        #else
        // On iOS, CLGeocoder is still supported and widely available.
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(name)
        guard let placemark = placemarks.first, let location = placemark.location else {
            throw ToolError.executionFailed("Could not find location: \(name)")
        }
        return location
        #endif
    }

    /// Best-effort reverse geocoding to get a friendly location name from coordinates.
    private func reverseGeocodeLocation(_ location: CLLocation) async -> String? {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else {
                return nil
            }
            do {
                let items = try await request.mapItems
                // Prefer the map item's name; address formatting can be added later if desired.
                return items.first?.name
            } catch {
                return nil
            }
        } else {
            return nil
        }
        #else
        let geocoder = CLGeocoder()
        if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
           let placemark = placemarks.first {
            return [placemark.locality, placemark.administrativeArea]
                .compactMap { $0 }
                .joined(separator: ", ")
        }
        return nil
        #endif
    }

    /// Get the user's current location
    private func getCurrentLocation() async throws -> CLLocation {
        // Request authorization and wait if needed
        let status = await locationHelperHolder.requestAuthorizationAndWait()

        // Check authorization status
        switch status {
        case .denied, .restricted:
            throw ToolError.notAvailable("Location access denied. Please enable in Settings or specify a location.")
        case .notDetermined:
            throw ToolError.notAvailable("Location authorization not granted.")
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            break
        }

        // Get location
        return try await locationHelperHolder.requestLocation()
    }

    /// Temperature unit based on user's locale (Fahrenheit for US, Celsius elsewhere)
    private var preferredTemperatureUnit: UnitTemperature {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// Speed unit based on user's locale (mph for US/UK, km/h elsewhere)
    private var preferredSpeedUnit: UnitSpeed {
        Locale.current.measurementSystem == .us ? .milesPerHour : .kilometersPerHour
    }

    /// Distance unit based on user's locale (miles for US/UK, km elsewhere)
    private var preferredDistanceUnit: UnitLength {
        Locale.current.measurementSystem == .us ? .miles : .kilometers
    }

    private func formatCurrentWeather(_ current: CurrentWeather) -> [String: Any] {
        let temp = current.temperature.converted(to: preferredTemperatureUnit)
        let feelsLike = current.apparentTemperature.converted(to: preferredTemperatureUnit)
        let windSpeed = current.wind.speed.converted(to: preferredSpeedUnit)
        let visibility = current.visibility.converted(to: preferredDistanceUnit)

        return [
            "temperature": [
                "value": round(temp.value),
                "unit": temp.unit.symbol
            ],
            "feelsLike": [
                "value": round(feelsLike.value),
                "unit": feelsLike.unit.symbol
            ],
            "condition": current.condition.description,
            "humidity": current.humidity * 100,
            "windSpeed": [
                "value": round(windSpeed.value),
                "unit": windSpeed.unit.symbol
            ],
            "windDirection": current.wind.direction.description,
            "uvIndex": current.uvIndex.value,
            "visibility": [
                "value": round(visibility.value * 10) / 10,
                "unit": visibility.unit.symbol
            ]
        ]
    }

    private func formatForecast(_ forecast: Forecast<DayWeather>) -> [[String: Any]] {
        let tempUnit = preferredTemperatureUnit
        return forecast.prefix(5).map { day in
            let high = day.highTemperature.converted(to: tempUnit)
            let low = day.lowTemperature.converted(to: tempUnit)
            return [
                "date": ISO8601DateFormatter().string(from: day.date),
                "condition": day.condition.description,
                "highTemperature": [
                    "value": round(high.value),
                    "unit": high.unit.symbol
                ],
                "lowTemperature": [
                    "value": round(low.value),
                    "unit": low.unit.symbol
                ],
                "precipitationChance": day.precipitationChance * 100,
                "uvIndex": day.uvIndex.value
            ]
        }
    }
}

