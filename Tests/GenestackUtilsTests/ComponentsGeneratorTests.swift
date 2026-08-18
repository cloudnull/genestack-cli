//
// ComponentsGeneratorTests.swift
// genestack-cli Tests
//

import XCTest
@testable import genestackctl

final class ComponentsGeneratorTests: XCTestCase {
    
    func testGenerateComponentsFromSpec() throws {
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
                ServiceSpec(name: "cinder", enabled: false, version: nil, helmArgs: nil),
                ServiceSpec(name: "glance", enabled: false, version: nil, helmArgs: nil),
                ServiceSpec(name: "designate", enabled: false, version: nil, helmArgs: nil)
            ],
            environment: nil
        )
        
        let generator = ComponentsGenerator()
        let components = try generator.generate(spec: spec)
        
        // Verify structure
        XCTAssertTrue(components.contains("components:"))
        
        // Verify services are listed correctly
        XCTAssertTrue(components.contains("  cinder: false"))
        XCTAssertTrue(components.contains("  designate: false"))
        XCTAssertTrue(components.contains("  glance: false"))
        XCTAssertTrue(components.contains("  keystone: true"))
        XCTAssertTrue(components.contains("  neutron: true"))
        XCTAssertTrue(components.contains("  nova: true"))
    }
    
    func testGenerateComponentsSortedByName() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "test", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [
                ServiceSpec(name: "zebra", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "alpha", enabled: true, version: nil, helmArgs: nil),
                ServiceSpec(name: "beta", enabled: false, version: nil, helmArgs: nil)
            ],
            environment: nil
        )
        
        let generator = ComponentsGenerator()
        let components = try generator.generate(spec: spec)
        
        // Verify alphabetical ordering
        let alphaIndex = components.range(of: "alpha:")!
        let betaIndex = components.range(of: "beta:")!
        let zIndex = components.range(of: "zebra:")!
        
        XCTAssertTrue(alphaIndex.lowerBound < betaIndex.lowerBound)
        XCTAssertTrue(betaIndex.lowerBound < zIndex.lowerBound)
    }
    
    func testGenerateComponentsFromCatalog() throws {
        // Create test catalog
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let servicesDir = tempDir.appendingPathComponent("bin/services")
        try FileManager.default.createDirectory(at: servicesDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create service files including some not in the spec
        let keystoneYAML = """
name: keystone
namespace: openstack
description: "Identity Service"
helm_chart:
  name: keystone
secrets:
  - name: keystone-admin-password
    type: Opaque
    rotate_with_service: true
    keys:
      - password
"""
        
        let novaYAML = """
name: nova
namespace: openstack
description: "Compute Service"
helm_chart:
  name: nova
dependencies:
  - keystone
"""
        
        let neutronYAML = """
name: neutron
namespace: openstack
description: "Networking Service"
helm_chart:
  name: neutron
dependencies:
  - keystone
"""
        
        try keystoneYAML.write(to: servicesDir.appendingPathComponent("keystone.yaml"), atomically: true, encoding: .utf8)
        try novaYAML.write(to: servicesDir.appendingPathComponent("nova.yaml"), atomically: true, encoding: .utf8)
        try neutronYAML.write(to: servicesDir.appendingPathComponent("neutron.yaml"), atomically: true, encoding: .utf8)
        
        let catalog = try ServiceCatalog(path: servicesDir.path)
        
        // Create spec with only keystone enabled
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
                ServiceSpec(name: "neutron", enabled: false, version: nil, helmArgs: nil)
            ],
            environment: nil
        )
        
        let generator = ComponentsGenerator()
        let components = try generator.generateFromCatalog(spec: spec, catalog: catalog)
        
        // Should include all services from catalog
        XCTAssertTrue(components.contains("  keystone: true"))
        XCTAssertTrue(components.contains("  nova: true"))
        XCTAssertTrue(components.contains("  neutron: false"))
    }
    
    func testGenerateComponentsWithNoServices() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "test", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [],
            environment: nil
        )
        
        let generator = ComponentsGenerator()
        let components = try generator.generate(spec: spec)
        
        XCTAssertEqual(components, "components:")
    }
    
    func testGenerateComponentsFormat() throws {
        let spec = ClusterSpec(
            version: "1.0",
            metadata: MetadataSpec(clusterName: "test", gatewayDomain: nil, acmeEmail: nil),
            overrides: nil,
            kubernetes: nil,
            nodes: [],
            network: nil,
            storage: nil,
            services: [
                ServiceSpec(name: "keystone", enabled: true, version: nil, helmArgs: nil)
            ],
            environment: nil
        )
        
        let generator = ComponentsGenerator()
        let components = try generator.generate(spec: spec)
        
        // Verify exact format matches expected output
        let expectedLines = [
            "components:",
            "  keystone: true"
        ]
        
        for line in expectedLines {
            XCTAssertTrue(components.contains(line), "Missing expected line: \(line)")
        }
    }
}
