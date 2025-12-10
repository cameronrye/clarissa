import Foundation
import CoreLocation

/// Helper class for CLLocationManager delegate
private final class LocationHelper: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    let locationManager = CLLocationManager()
    var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
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

/// Tool for getting current location
final class LocationTool: ClarissaTool, @unchecked Sendable {
    let name = "location"
    let description = "Get the user's current location. Returns coordinates and address."
    let priority = ToolPriority.extended
    let requiresConfirmation = true

    private let helper = LocationHelper()

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
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ToolError.invalidArguments("Invalid arguments")
        }

        let includeAddress = args["includeAddress"] as? Bool ?? true
        let accuracy = args["accuracy"] as? String ?? "medium"

        // Set accuracy
        switch accuracy {
        case "best":
            helper.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        case "high":
            helper.locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        case "medium":
            helper.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        case "low":
            helper.locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        default:
            helper.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        }

        // Check authorization
        let status = helper.locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            helper.locationManager.requestWhenInUseAuthorization()
            try await Task.sleep(nanoseconds: 500_000_000)
        case .denied, .restricted:
            throw ToolError.notAvailable("Location access denied. Please enable in Settings.")
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            break
        }

        // Get location
        let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            helper.continuation = continuation
            helper.locationManager.requestLocation()
        }

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

