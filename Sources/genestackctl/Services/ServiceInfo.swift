//
// ServiceInfo.swift
// genestack-cli
//
// Data models for parsing individual service YAML files from bin/services/
//

import Foundation
import Yams

/// Helm chart configuration for a service
struct HelmChartInfo: Codable, Equatable {
    let repository: String?
    let name: String
    let version: String?
    let values: [String: String]?
    let namespace: String?
    let extraValues: String?
    let overrideValues: String?
    let extraArgs: [String]?
    
    enum CodingKeys: String, CodingKey {
        case repository, name, version, values, namespace
        case extraValues = "extra_values"
        case overrideValues = "override_values"
        case extraArgs = "extra_args"
    }
}

/// Secret definition within a service
struct SecretInfo: Codable, Equatable {
    let name: String
    let type: String?
    let rotateWithService: Bool?
    let keys: [String]?
    let path: String?
    let createOnUpgrade: Bool?
    let skipRotation: Bool?
    let annotations: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case name, type, keys, path, annotations
        case rotateWithService = "rotate_with_service"
        case createOnUpgrade = "create_on_upgrade"
        case skipRotation = "skip_rotation"
    }
}

/// Dependency on another service (can be string or object)
struct DependencyInfo: Codable, Equatable {
    let name: String
    let secrets: [String]?
    let optional: Bool?
    
    // Handle both string and object forms in YAML
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try decoding as string first
        if let stringValue = try? container.decode(String.self) {
            self.name = stringValue
            self.secrets = nil
            self.optional = nil
        } else {
            // Decode as object
            let keyedContainer = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try keyedContainer.decode(String.self, forKey: .name)
            self.secrets = try keyedContainer.decodeIfPresent([String].self, forKey: .secrets)
            self.optional = try keyedContainer.decodeIfPresent(Bool.self, forKey: .optional)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case name, secrets, optional
    }
    
    func encode(to encoder: Encoder) throws {
        if secrets == nil && optional == nil {
            // Encode as string
            var container = encoder.singleValueContainer()
            try container.encode(name)
        } else {
            // Encode as object
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(secrets, forKey: .secrets)
            try container.encodeIfPresent(optional, forKey: .optional)
        }
    }
}

/// Complete service definition parsed from bin/services/<name>.yaml
struct ServiceInfo: Codable, Equatable {
    let name: String
    let namespace: String
    let helmChart: HelmChartInfo
    let secrets: [SecretInfo]?
    let dependencies: [DependencyInfo]?
    let labels: [DependencyInfo]?
    let enabled: Bool?
    let kustomize: String?
    let overlayPath: String?
    let description: String?
    let skipOnNewCluster: Bool?
    let skipIfExisting: Bool?
    let preInstallTasks: [String]?
    let postInstallTasks: [String]?
    let waitConditions: [WaitCondition]?
    
    enum CodingKeys: String, CodingKey {
        case name, namespace, secrets, labels, enabled, kustomize, description
        case helmChart = "helm_chart"
        case overlayPath = "overlay_path"
        case dependencies
        case skipOnNewCluster = "skip_on_new_cluster"
        case skipIfExisting = "skip_if_existing"
        case preInstallTasks = "pre_install_tasks"
        case postInstallTasks = "post_install_tasks"
        case waitConditions = "wait_conditions"
    }
    
    // Custom decoder to handle helm_chart as either string or object
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        namespace = try container.decode(String.self, forKey: .namespace)
        
        // Handle helm_chart as either a string or complex object
        if let chartString = try? container.decode(String.self, forKey: .helmChart) {
            helmChart = HelmChartInfo(
                repository: nil,
                name: chartString,
                version: nil,
                values: nil,
                namespace: nil,
                extraValues: nil,
                overrideValues: nil,
                extraArgs: nil
            )
        } else if let chartDict = try? container.decode([String: String].self, forKey: .helmChart) {
            // Fallback: try dictionary decoding
            let data = try JSONSerialization.data(withJSONObject: chartDict)
            helmChart = try JSONDecoder().decode(HelmChartInfo.self, from: data)
        } else {
            helmChart = try container.decode(HelmChartInfo.self, forKey: .helmChart)
        }
        
        secrets = try container.decodeIfPresent([SecretInfo].self, forKey: .secrets)
        dependencies = try container.decodeIfPresent([DependencyInfo].self, forKey: .dependencies) ?? []
        labels = try container.decodeIfPresent([DependencyInfo].self, forKey: .labels)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        kustomize = try container.decodeIfPresent(String.self, forKey: .kustomize)
        overlayPath = try container.decodeIfPresent(String.self, forKey: .overlayPath)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        skipOnNewCluster = try container.decodeIfPresent(Bool.self, forKey: .skipOnNewCluster)
        skipIfExisting = try container.decodeIfPresent(Bool.self, forKey: .skipIfExisting)
        preInstallTasks = try container.decodeIfPresent([String].self, forKey: .preInstallTasks)
        postInstallTasks = try container.decodeIfPresent([String].self, forKey: .postInstallTasks)
        waitConditions = try container.decodeIfPresent([WaitCondition].self, forKey: .waitConditions)
    }
}

/// Wait condition for pods/services
struct WaitCondition: Codable, Equatable {
    let type: String?
    let labelSelector: String?
    let timeout: String?
    let count: Int?
    let namespace: String?
    let jsonPath: String?
    let desiredValue: String?
    
    enum CodingKeys: String, CodingKey {
        case type, timeout, count, namespace
        case labelSelector = "label_selector"
        case jsonPath = "json_path"
        case desiredValue = "desired_value"
    }
}
