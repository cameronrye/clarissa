import Foundation
import CoreLocation

// MARK: - Typed Arguments

/// Typed arguments for LocationTool using Codable
struct LocationArguments: Codable {
    let includeAddress: Bool?
    let accuracy: String?
}

/// Helper class for CLLocationManager delegate - must be used from MainActor
@MainActor
private final class LocationHelper: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var isWaitingForAuthorization = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func setAccuracy(_ accuracy: String) {
        switch accuracy {
        case "best":
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
        case "high":
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        case "medium":
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        case "low":
            locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        default:
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }
    }

    /// Request location with proper continuation handling
    func requestLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            self.locationManager.requestLocation()
        }
    }

    /// Request authorization and wait for user response
    func requestAuthorizationAndWait() async -> CLAuthorizationStatus {
        let currentStatus = locationManager.authorizationStatus

        // If already determined, return immediately
        guard currentStatus == .notDetermined else {
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
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
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

/// Actor to hold the MainActor-isolated LocationHelper
private actor LocationHelperHolder {
    @MainActor private let helper = LocationHelper()

    func setAccuracy(_ accuracy: String) async {
        await helper.setAccuracy(accuracy)
    }

    func requestAuthorizationAndWait() async -> CLAuthorizationStatus {
        await helper.requestAuthorizationAndWait()
    }

    func requestLocation() async throws -> CLLocation {
        try await helper.requestLocation()
    }
}

/// Tool for getting current location
final class LocationTool: ClarissaTool, @unchecked Sendable {
    let name = "location"
    let description = "Get the user's current location. Returns coordinates and address."
    let priority = ToolPriority.extended
    let requiresConfirmation = true

    private let helperHolder = LocationHelperHolder()

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "includeAddress": [
                    "type": "boolean",
                    "description": "Include reverse geocoded address (default: true)"
                ],
                "accuracy": [
                    "type": "string",
                    "enum": ["best", "high", "medium", "low"],
                    "description": "Location accuracy level (default: medium)"
                ]
            ]
        ]
    }

    func execute(arguments: String) async throws -> String {
        guard let data = arguments.data(using: .utf8) else {
            throw ToolError.invalidArguments("Invalid argument encoding")
        }

        // Decode using typed arguments with defaults for optional fields
        let args = (try? JSONDecoder().decode(LocationArguments.self, from: data)) ?? LocationArguments(includeAddress: nil, accuracy: nil)
        let includeAddress = args.includeAddress ?? true
        let accuracy = args.accuracy ?? "medium"

        // Set accuracy
        await helperHolder.setAccuracy(accuracy)

        // Request authorization and wait if needed
        let status = await helperHolder.requestAuthorizationAndWait()

        // Check authorization status
        switch status {
        case .denied, .restricted:
            throw ToolError.notAvailable("Location access denied. Please enable in Settings.")
        case .notDetermined:
            throw ToolError.notAvailable("Location authorization not granted.")
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            break
        }

        // Get location
        let location = try await helperHolder.requestLocation()

        var response: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "horizontalAccuracy": location.horizontalAccuracy,
            "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
        ]

        // Reverse geocode if requested
        if includeAddress {
            do {
                let address = try await reverseGeocode(location: location)
                response["address"] = address
            } catch {
                response["addressError"] = error.localizedDescription
            }
        }

        let responseData = try JSONSerialization.data(withJSONObject: response)
        return String(data: responseData, encoding: .utf8) ?? "{}"
    }

    @available(iOS, deprecated: 26.0, message: "Use MapKit geocoding APIs")
    @available(macOS, deprecated: 26.0, message: "Use MapKit geocoding APIs")
    private func reverseGeocode(location: CLLocation) async throws -> [String: Any] {
        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else {
            throw ToolError.executionFailed("No address found")
        }
        return formatPlacemark(placemark)
    }

    private func formatPlacemark(_ placemark: CLPlacemark) -> [String: Any] {
        var address: [String: Any] = [:]

        if let name = placemark.name { address["name"] = name }
        if let street = placemark.thoroughfare { address["street"] = street }
        if let subStreet = placemark.subThoroughfare { address["streetNumber"] = subStreet }
        if let city = placemark.locality { address["city"] = city }
        if let state = placemark.administrativeArea { address["state"] = state }
        if let postalCode = placemark.postalCode { address["postalCode"] = postalCode }
        if let country = placemark.country { address["country"] = country }
        if let isoCountry = placemark.isoCountryCode { address["countryCode"] = isoCountry }

        var components: [String] = []
        if let subStreet = placemark.subThoroughfare, let street = placemark.thoroughfare {
            components.append("\(subStreet) \(street)")
        } else if let street = placemark.thoroughfare {
            components.append(street)
        }
        if let city = placemark.locality { components.append(city) }
        if let state = placemark.administrativeArea { components.append(state) }
        if let postalCode = placemark.postalCode { components.append(postalCode) }

        address["formatted"] = components.joined(separator: ", ")
        return address
    }
}

