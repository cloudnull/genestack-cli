//
// ServiceCatalogTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl
import Foundation

final class ServiceCatalogTests: XCTestCase {
    
    /// Helper: Create a temporary services directory with test YAML files
    func createTestServiceCatalog() throws -> String {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let servicesDir = tempDir.appendingPathComponent("bin/services")
        try FileManager.default.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        
        // Create test service files
        let keystoneYAML = """
name: keystone
namespace: openstack
description: "OpenStack Identity Service"
helm_chart:
  repository: https://starlingx.dev/releases
  name: keystone
  version: "1.0.0"
  namespace: openstack
secrets:
  - name: keystone-fernet-key
    type: Opaque
    rotate_with_service: true
    keys:
      - fernet-key
  - name: keystone-admin-password
    type: Opaque
    rotate_with_service: true
    keys:
      - password
dependencies: []
labels:
  - name: openstack-identity
"""
        
        let novaYAML = """
name: nova
namespace: openstack
description: "OpenStack Compute Service"
helm_chart:
  repository: https://starlingx.dev/releases
  name: nova
  version: "1.0.0"
dependencies:
  - keystone
  - glance
  - neutron
secrets:
  - name: nova-service-password
    type: Opaque
    rotate_with_service: true
    keys:
      - password
"""
        
        let commonYAML = """
name: common-service
namespace: common
helm_chart:
  name: common-service
"""
        
        // Write files
        try keystoneYAML.write(to: servicesDir.appendingPathComponent("keystone.yaml"), atomically: true, encoding: .utf8)
        try novaYAML.write(to: servicesDir.appendingPathComponent("nova.yaml"), atomically: true, encoding: .utf8)
        try commonYAML.write(to: servicesDir.appendingPathComponent("common-service-common.yaml"), atomically: true, encoding: .utf8)
        
        // Create a template file that should be skipped
        let templateYAML = """
name: template-service
namespace: template
helm_chart:
  name: template-service
"""
        
        try templateYAML.write(to: servicesDir.appendingPathComponent("template-service-template.yaml"), atomically: true, encoding: .utf8)
        
        return servicesDir.path
    }
    
    func testLoadServicesFromDirectory() throws {
        let servicesPath = try createTestServiceCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: servicesPath)
        }
        
        let catalog = try ServiceCatalog(path: servicesPath)
        let services = catalog.getAllServices()
        
        // Should load 2 services (excluding template and common files)
        XCTAssertEqual(services.count, 2)
        
        // Should have keystone and nova
        let names = services.map { $0.name }.sorted()
        XCTAssertEqual(names, ["keystone", "nova"])
    }
    
    func testGetServiceByName() throws {
        let servicesPath = try createTestServiceCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: servicesPath)
        }
        
        let catalog = try ServiceCatalog(path: servicesPath)
        let keystone = catalog.getService(named: "keystone")
        
        XCTAssertNotNil(keystone)
        XCTAssertEqual(keystone?.namespace, "openstack")
        XCTAssertEqual(keystone?.helmChart.name, "keystone")
        XCTAssertEqual(keystone?.helmChart.repository, "https://starlingx.dev/releases")
        XCTAssertEqual(keystone?.helmChart.version, "1.0.0")
        XCTAssertEqual(keystone?.description, "OpenStack Identity Service")
    }
    
    func testParseServiceSecrets() throws {
        let servicesPath = try createTestServiceCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: servicesPath)
        }
        
        let catalog = try ServiceCatalog(path: servicesPath)
        let keystone = catalog.getService(named: "keystone")
        
        XCTAssertNotNil(keystone)
        XCTAssertEqual(keystone?.secrets?.count, 2)
        
        let fernetSecret = keystone?.secrets?.first { $0.name == "keystone-fernet-key" }
        XCTAssertNotNil(fernetSecret)
        XCTAssertTrue(fernetSecret?.rotateWithService == true)
        XCTAssertTrue(fernetSecret?.keys?.contains("fernet-key") == true)
    }
    
    func testGetSecretsForRotation() throws {
        let servicesPath = try createTestServiceCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: servicesPath)
        }
        
        let catalog = try ServiceCatalog(path: servicesPath)
        let rotatableSecrets = catalog.getSecretsForRotation(service: "keystone")
        
        XCTAssertEqual(rotatableSecrets.count, 2)
        XCTAssertTrue(rotatableSecrets.allSatisfy { $0.rotateWithService == true })
    }
    
    func testGetDependentServices() throws {
        let servicesPath = try createTestServiceCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: servicesPath)
        }
        
        let catalog = try ServiceCatalog(path: servicesPath)
        
        // Nova depends on keystone
        let dependents = catalog.getDependentServices(of: "keystone")
        XCTAssertTrue(dependents.contains("nova"))
    }
    
    func testServiceCatalogWithNonExistentPath() {
        XCTAssertThrowsError(try ServiceCatalog(path: "/nonexistent/path"))
    }
    
    func testHelmChartAsObject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let servicesDir = tempDir.appendingPathComponent("bin/services")
        try FileManager.default.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Service with helm_chart as an object
        let serviceYAML = """
name: test-object-chart
namespace: openstack
helm_chart:
  repository: https://example.com
  name: test-chart
  version: "2.3.4"
"""
        
        try serviceYAML.write(to: servicesDir.appendingPathComponent("test-object-chart.yaml"), atomically: true, encoding: .utf8)
        
        let catalog = try ServiceCatalog(path: servicesDir.path)
        let service = catalog.getService(named: "test-object-chart")
        
        XCTAssertNotNil(service)
        XCTAssertEqual(service?.helmChart.name, "test-chart")
        XCTAssertEqual(service?.helmChart.repository, "https://example.com")
        XCTAssertEqual(service?.helmChart.version, "2.3.4")
    }
}
