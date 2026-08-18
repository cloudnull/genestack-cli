//
// ServiceDependencyResolverTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl

final class ServiceDependencyResolverTests: XCTestCase {
    
    /// Helper: Create a mock service catalog
    func createMockCatalog() throws -> (ServiceCatalog, String) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let servicesDir = tempDir.appendingPathComponent("bin/services")
        try FileManager.default.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        
        // Keystone (no deps)
        let keystoneYAML = """
name: keystone
namespace: openstack
helm_chart:
  name: keystone
secrets:
  - name: keystone-admin-password
    type: Opaque
    rotate_with_service: true
    keys:
      - password
"""
        
        // Nova (depends on keystone)
        let novaYAML = """
name: nova
namespace: openstack
helm_chart:
  name: nova
dependencies:
  - keystone
secrets:
  - name: nova-service-password
    type: Opaque
    rotate_with_service: true
    keys:
      - password
"""
        
        // Neutron (depends on keystone)
        let neutronYAML = """
name: neutron
namespace: openstack
helm_chart:
  name: neutron
dependencies:
  - keystone
"""
        
        // Cinder (depends on keystone and nova)
        let cinderYAML = """
name: cinder
namespace: openstack
helm_chart:
  name: cinder
dependencies:
  - keystone
  - nova
"""
        
        // Glance (depends on keystone)
        let glanceYAML = """
name: glance
namespace: openstack
helm_chart:
  name: glance
dependencies:
  - keystone
secrets:
  - name: glance-password
    type: Opaque
    rotate_with_service: true
    keys:
      - password
"""
        
        try keystoneYAML.write(to: servicesDir.appendingPathComponent("keystone.yaml"), atomically: true, encoding: .utf8)
        try novaYAML.write(to: servicesDir.appendingPathComponent("nova.yaml"), atomically: true, encoding: .utf8)
        try neutronYAML.write(to: servicesDir.appendingPathComponent("neutron.yaml"), atomically: true, encoding: .utf8)
        try cinderYAML.write(to: servicesDir.appendingPathComponent("cinder.yaml"), atomically: true, encoding: .utf8)
        try glanceYAML.write(to: servicesDir.appendingPathComponent("glance.yaml"), atomically: true, encoding: .utf8)
        
        let catalog = try ServiceCatalog(path: servicesDir.path)
        return (catalog, tempDir.path)
    }
    
    func testResolveOrderWithSimpleDependencies() throws {
        let (catalog, tempPath) = try createMockCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }
        
        let resolver = ServiceDependencyResolver(catalog: catalog)
        
        let ordered = try resolver.resolveOrder(for: ["keystone", "nova", "neutron"])
        
        // Keystone should come before nova and neutron
        XCTAssertTrue(ordered.firstIndex(of: "keystone")! < ordered.firstIndex(of: "nova")!)
        XCTAssertTrue(ordered.firstIndex(of: "keystone")! < ordered.firstIndex(of: "neutron")!)
    }
    
    func testResolveOrderWithComplexDependencies() throws {
        let (catalog, tempPath) = try createMockCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }
        
        let resolver = ServiceDependencyResolver(catalog: catalog)
        
        let ordered = try resolver.resolveOrder(for: ["keystone", "nova", "neutron", "cinder"])
        
        // Verify dependency ordering
        XCTAssertTrue(ordered.firstIndex(of: "keystone")! < ordered.firstIndex(of: "nova")!)
        XCTAssertTrue(ordered.firstIndex(of: "keystone")! < ordered.firstIndex(of: "neutron")!)
        XCTAssertTrue(ordered.firstIndex(of: "keystone")! < ordered.firstIndex(of: "cinder")!)
        XCTAssertTrue(ordered.firstIndex(of: "nova")! < ordered.firstIndex(of: "cinder")!)
    }
    
    func testResolveOrderWithNoDependencies() throws {
        let (catalog, tempPath) = try createMockCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }
        
        let resolver = ServiceDependencyResolver(catalog: catalog)
        
        let ordered = try resolver.resolveOrder(for: ["keystone"])
        
        XCTAssertEqual(ordered, ["keystone"])
    }
    
    func testResolveOrderFromSpec() throws {
        let (catalog, tempPath) = try createMockCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }
        
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "test", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [
                ServiceSpec(name: "keystone", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "nova", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "neutron", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "cinder", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "glance", enabled: false, version: nil, helmArgs: nil)
            ],
            environment: nil
        )
        
        let resolver = ServiceDependencyResolver(catalog: catalog)
        let ordered = try resolver.resolveOrder(from: spec)
        
        // Should include only enabled services, in dependency order
        XCTAssertTrue(ordered.contains("keystone"))
        XCTAssertTrue(ordered.contains("nova"))
        XCTAssertTrue(ordered.contains("neutron"))
        XCTAssertTrue(ordered.contains("cinder"))
        XCTAssertFalse(ordered.contains("glance"))
        
        // Verify order
        XCTAssertTrue(ordered.firstIndex(of: "keystone")! < ordered.firstIndex(of: "nova")!)
        XCTAssertTrue(ordered.firstIndex(of: "keystone")! < ordered.firstIndex(of: "cinder")!)
        XCTAssertTrue(ordered.firstIndex(of: "nova")! < ordered.firstIndex(of: "cinder")!)
    }
    
    func testCircularDependencyDetection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let servicesDir = tempDir.appendingPathComponent("bin/services")
        try FileManager.default.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create circular dependency: a -> b -> a
        let aYAML = """
name: service-a
namespace: test
helm_chart:
  name: service-a
dependencies:
  - service-b
"""
        
        let bYAML = """
name: service-b
namespace: test
helm_chart:
  name: service-b
dependencies:
  - service-a
"""
        
        try aYAML.write(to: servicesDir.appendingPathComponent("a.yaml"), atomically: true, encoding: .utf8)
        try bYAML.write(to: servicesDir.appendingPathComponent("b.yaml"), atomically: true, encoding: .utf8)
        
        let catalog = try ServiceCatalog(path: servicesDir.path)
        let resolver = ServiceDependencyResolver(catalog: catalog)
        
        XCTAssertThrowsError(try resolver.resolveOrder(for: ["service-a", "service-b"])) { error in
            XCTAssertTrue(error is DependencyResolutionError)
            if case DependencyResolutionError.circularDependency(let cycle) = error {
                XCTAssertTrue(cycle.contains("service-a"))
                XCTAssertTrue(cycle.contains("service-b"))
            }
        }
    }
    
    func testGetDependents() throws {
        let (catalog, tempPath) = try createMockCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }
        
        let resolver = ServiceDependencyResolver(catalog: catalog)
        
        let keystoneDependents = resolver.getDependents(of: "keystone")
        XCTAssertTrue(keystoneDependents.contains("nova"))
        XCTAssertTrue(keystoneDependents.contains("neutron"))
        XCTAssertTrue(keystoneDependents.contains("cinder"))
        XCTAssertTrue(keystoneDependents.contains("glance"))
    }
    
    func testGetImpactedServices() throws {
        let (catalog, tempPath) = try createMockCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }
        
        let resolver = ServiceDependencyResolver(catalog: catalog)
        
        let impacted = try resolver.getImpactedServices(for: "keystone")
        
        // Should include keystone itself and all services that depend on it
        XCTAssertTrue(impacted.contains("keystone"))
        XCTAssertTrue(impacted.contains("nova"))
        XCTAssertTrue(impacted.contains("neutron"))
        XCTAssertTrue(impacted.contains("cinder"))
        XCTAssertTrue(impacted.contains("glance"))
        
        // Keystone should come first (since its secrets are being rotated)
        XCTAssertEqual(impacted.first, "keystone")
    }
    
    func testGetParallelGroups() throws {
        let (catalog, tempPath) = try createMockCatalog()
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }
        
        let resolver = ServiceDependencyResolver(catalog: catalog)
        let ordered = try resolver.resolveOrder(for: ["keystone", "nova", "neutron", "cinder", "glance"])
        let groups = resolver.getParallelGroups(from: ordered)
        
        // First group should be keystone (no dependencies)
        XCTAssertEqual(groups[0], ["keystone"])
        
        // Remaining services can potentially be parallelized
        XCTAssertTrue(groups.count > 1)
    }
}
