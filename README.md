# genestackctl

A cross-platform (macOS/Linux) CLI tool for installing and managing [Genestack](https://github.com/rackerlabs/genestack) OpenStack Kubernetes Stack clusters.

## Overview

`genestackctl` is a Swift 6.3 command-line tool that provides an intuitive interface for:
- Generating cluster configuration specs interactively
- Managing cluster services, nodes, and secrets
- Executing the full deployment pipeline from start to finish

This tool is designed to work with the [rackerlabs/genestack](https://github.com/rackerlabs/genestack) repository, which provides the underlying Ansible-based installation framework, Helm charts, and Kubernetes operators for running OpenStack on Kubernetes.

## Features

- **Interactive Installation Wizard** - Step-by-step guidance through cluster configuration
- **Declarative Spec Management** - YAML-based cluster configuration
- **Service Management** - Enable/disable services, manage dependencies
- **Node Inventory** - Add/remove nodes, configure networking and storage
- **Secret Rotation** - Safely rotate service secrets and reinstall impacted services
- **Dependency Resolution** - Automatic ordering based on secret cross-references
- **Idempotent Operations** - Safe to re-run installations
- **Cross-Platform** - Native Swift implementation for macOS and Linux

## Installation

### Prerequisites
- Swift 6.3 or later
- git
- kubectl (for cluster interactions)
- Access to a Genestack installation directory

### From Source

```bash
# Clone this repository
git clone <repository-url>
cd genestackctl

# Build in release mode
swift build -c release

# Optionally install to PATH
sudo cp .build/release/genectl /usr/local/bin/
```

### Using Make

```bash
# Debug build
make debug

# Release build
make release

# Run tests
make test

# Clean build artifacts
make clean
```

## Quick Start

### 1. Generate a Cluster Spec

```bash
# Create a minimal spec
genectl config create --yes --cluster-name mycloud --output mycluster.yaml

# Create with hyperconverged mode (3 nodes auto-generated)
genectl config create --yes --hyperconverged --cluster-name mycloud --output mycluster.yaml

# Create with common OpenStack services enabled
genectl config create --yes --common-services --cluster-name mycloud --output mycluster.yaml
```

### 2. Interactive Installation Wizard (alternative)

```bash
# Run the interactive wizard
genectl install --yes --output mycluster.yaml --skip-install

# Full installation with wizard
genectl install --yes --output mycluster.yaml
```

### 3. Apply the Configuration

```bash
# Full installation with interactive prompts
genectl apply --config mycluster.yaml

# Non-interactive with continue-on-failure
genectl apply --config mycluster.yaml --yes --on-failure continue

# Dry run first
genectl apply --config mycluster.yaml --dry-run
```

## Commands

### Core Commands

| Command | Description |
|---------|-------------|
| `genectl install` | Full cluster installation wizard |
| `genectl apply` | Execute installation from existing spec |
| `genectl config` | Validate, edit, and manage cluster config |

### Service Management

```bash
# List all available services
genectl service list --config mycluster.yaml

# Add a service to your cluster
genectl service add keystone --config mycluster.yaml

# Remove a service (disable vs purge)
genectl service remove keystone --config mycluster.yaml
genectl service remove keystone --config mycluster.yaml --purge
```

### Node Management

```bash
# List nodes
genectl node list --config mycluster.yaml

# Add a node (CLI args or interactive)
genectl node add node01.cluster.local 10.0.0.10 "control-plane,kube-node" --config mycluster.yaml

# Remove a node
genectl node remove node01.cluster.local --config mycluster.yaml
```

### Secret Management

```bash
# List all secrets and their ownership
genectl secret list

# Rotate secrets for a service
genectl secret rotate keystone --dry-run --yes
genectl secret rotate keystone

# Check if secrets exist in k8s
genectl secret check nova
```

## Configuration

### Cluster Spec Format

The cluster spec is a YAML file that defines your entire cluster configuration:

```yaml
version: "1.0"
metadata:
  cluster_name: mycloud
  gateway_domain: cloud.example.com
  acme_email: admin@example.com

overrides:
  repo: "https://github.com/example/my-overrides"
  ref: "main"
  replace_base: false

kubernetes:
  hyperconverged: false
  kube_version: "v1.35.6"
  vars:
    cloud_name: "mycloud-1"

nodes:
  - name: controller01.mycloud.local
    ip: 10.0.0.10
    roles: [control-plane, etcd, kube-node, openstack-control-plane]
    addresses:
      ansible_host: 172.28.0.10
      management_ip: 10.0.0.10
      network_mgmt_address: 172.28.0.10
      network_storage_address: 172.28.1.10
      network_overlay_address: 172.28.2.10

storage:
  longhorn_replicas: 2
  cinder_backend: "lvm"

services:
  - name: keystone
    enabled: true
  - name: nova
    enabled: true
  - name: cinder
    enabled: false

environment:
  SKIP_PROMPTS: "true"
  ANSIBLE_FORKS: "24"
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GENESTACK_BASE_DIR` | Genestack installation directory | `/opt/genestack` |
| `GENESTACK_OVERRIDES_DIR` | Overrides directory | `/etc/genestack` |
| `GENESTACK_SERVICES_DIR` | Service catalog location | `$GENESTACK_BASE_DIR/bin/services` |
| `GENESTACK_COMPONENTS_FILE` | Components file path | `$GENESTACK_OVERRIDES_DIR/openstack-components.yaml` |

## Architecture

The tool is structured as follows:

```
Sources/genestackctl/
├── CLI.swift                      # Main entry point with command registration
├── Models/
│   └── ClusterSpec.swift          # Codable spec data models
├── Services/
│   ├── ServiceCatalog.swift       # Parses bin/services/*.yaml
│   ├── ServiceInfo.swift          # Service data models
│   └── ServiceDependencyResolver.swift # Topological dependency sorting
├── Inventory/
│   ├── InventoryGenerator.swift   # Ansible inventory generation
│   └── InventoryModel.swift       # Inventory data models
├── Components/
│   └── ComponentsGenerator.swift  # openstack-components.yaml generation
├── Orchestration/
│   ├── PipelineExecutor.swift     # Installation pipeline orchestration
│   ├── ServiceInstaller.swift     # Service installation via install.sh
│   └── FailureHandler.swift       # Failure handling modes
├── Commands/
│   ├── InstallCommand.swift       # Full install wizard
│   ├── ApplyCommand.swift         # Pipeline execution from spec
│   ├── ServiceCommands.swift      # Service list/add/remove
│   ├── NodeCommands.swift         # Node list/add/remove
│   ├── SecretCommands.swift       # Secret management
│   └── ConfigCommands.swift       # Config validation/editing
├── Wizard/
│   └── Wizard.swift               # Interactive configuration wizard
├── Overrides/
│   └── OverridesManager.swift     # Overrides repo cloning
├── Secrets/
│   ├── SecretAnalyzer.swift       # Secret ownership analysis
│   └── SecretOwnershipMap.swift   # Secret ownership data structures
└── Utilities/
    ├── EnvironmentManager.swift   # Environment variable management
    ├── SpecValidator.swift        # Spec validation logic
    ├── GenestackError.swift       # Custom error types
    ├── PathResolver.swift         # Platform-aware path resolution
    └── Subprocess.swift           # Process execution wrapper
```

## Relationship to Genestack

This CLI tool ([genestackctl](https://github.com/yourorg/genestackctl)) is a client for the [rackerlabs/genestack](https://github.com/rackerlabs/genestack) project. 

The genestack repository contains:
- Ansible playbooks and roles for cluster installation
- Kubernetes manifests and Helm charts for OpenStack services
- Service YAML definitions in `bin/services/` that define how each OpenStack component is deployed
- Installation scripts (`install.sh`, `bootstrap.sh`)

The genestackctl tool provides a user-friendly interface to:
1. Understand the service catalog by parsing `bin/services/*.yaml`
2. Generate properly structured cluster specs
3. Execute the installation in the correct dependency order
4. Manage secrets and perform maintenance operations

## Development

### Testing

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter GenestackSpecTests
swift test --filter GenestackUtilsTests
swift test --filter GenestackCLITests
swift test --filter GenestackCLITests.ClusterSpecTests
```

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run the CLI
swift run genectl --help
```

### Project Structure

- **Source code**: `Sources/genestackctl/`
- **Unit tests**: `Tests/GenestackSpecTests/`, `Tests/GenestackUtilsTests/`, `Tests/GenestackCLITests/`
- **Documentation**: `docs/`
- **CI/CD**: `.github/workflows/`

## License

Apache License 2.0 - See [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Related Projects

- [rackerlabs/genestack](https://github.com/rackerlabs/genestack) - The main Genestack OpenStack Kubernetes Stack repository
- [rackerlabs/flex](https://github.com/rackerlabs/flex) - Genestack's underlying infrastructure orchestration tool

## Support

- Documentation: [Genestack Documentation](https://github.com/rackerlabs/genestack)
- Issues: [GitHub Issues](https://github.com/yourorg/genestackctl/issues)
- Community: [Genestack Slack](https://join.slack.com/t/genestack) (if available)
