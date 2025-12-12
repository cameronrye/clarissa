import Foundation
import Contacts

/// Tool for contacts operations
final class ContactsTool: ClarissaTool, @unchecked Sendable {
    let name = "contacts"
    let description = "Search and access contacts from the address book. Can find contacts by name, phone number, or email."
    let priority = ToolPriority.important
    let requiresConfirmation = false
    
    private let store = CNContactStore()
    
    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["search", "get"],
                    "description": "The action to perform"
                ],
                "query": [
                    "type": "string",
                    "description": "Search query - name, phone, or email"
                ],
                "contactId": [
                    "type": "string",
                    "description": "Contact identifier (for get action)"
                ],
                "limit": [
                    "type": "integer",
                    "description": "Maximum results (default: 10)"
                ]
            ],
            "required": ["action"]
        ]
    }
    
    func execute(arguments: String) async throws -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = args["action"] as? String else {
            throw ToolError.invalidArguments("Missing action parameter")
        }
        
        // Request access if needed
        let granted = try await requestAccess()
        guard granted else {
            throw ToolError.permissionDenied("Contacts access denied")
        }
        
        switch action {
        case "search":
            return try searchContacts(args)
        case "get":
            return try getContact(args)
        default:
            throw ToolError.invalidArguments("Unknown action: \(action)")
        }
    }
    
    private func requestAccess() async throws -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return try await store.requestAccess(for: .contacts)
        default:
            return false
        }
    }
    
    private func searchContacts(_ args: [String: Any]) throws -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            throw ToolError.invalidArguments("Query is required for search")
        }
        
        let limit = args["limit"] as? Int ?? 10
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.predicate = CNContact.predicateForContacts(matchingName: query)
        
        var contacts: [[String: Any]] = []
        
        try store.enumerateContacts(with: request) { contact, stop in
            if contacts.count >= limit {
                stop.pointee = true
                return
            }
            
            let phones = contact.phoneNumbers.map { $0.value.stringValue }
            let emails = contact.emailAddresses.map { $0.value as String }
            
            contacts.append([
                "id": contact.identifier,
                "name": "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces),
                "phones": phones,
                "emails": emails
            ])
        }
        
        let result = try JSONSerialization.data(withJSONObject: ["contacts": contacts, "query": query])
        return String(data: result, encoding: .utf8) ?? "{}"
    }
    
    private func getContact(_ args: [String: Any]) throws -> String {
        guard let contactId = args["contactId"] as? String else {
            throw ToolError.invalidArguments("contactId is required for get action")
        }
        
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactNoteKey as CNKeyDescriptor
        ]
        
        let predicate = CNContact.predicateForContacts(withIdentifiers: [contactId])
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
        
        guard let contact = contacts.first else {
            throw ToolError.executionFailed("Contact not found")
        }
        
        let phones = contact.phoneNumbers.map {
            ["label": $0.label ?? "other", "number": $0.value.stringValue]
        }
        
        let emails = contact.emailAddresses.map {
            ["label": $0.label ?? "other", "address": $0.value as String]
        }
        
        var contactDict: [String: Any] = [
            "id": contact.identifier,
            "firstName": contact.givenName,
            "lastName": contact.familyName,
            "phones": phones,
            "emails": emails
        ]
        
        if !contact.organizationName.isEmpty {
            contactDict["organization"] = contact.organizationName
        }
        
        if !contact.jobTitle.isEmpty {
            contactDict["jobTitle"] = contact.jobTitle
        }
        
        let result = try JSONSerialization.data(withJSONObject: ["contact": contactDict])
        return String(data: result, encoding: .utf8) ?? "{}"
    }
}

