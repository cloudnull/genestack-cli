# genestack-cli Design Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cross-platform (macOS/Linux) CLI tool in Swift 6.3 that interactively guides an operator through generating and executing a full Genestack cluster deployment via a declarative YAML spec.

**Architecture:** Swift Package Manager project with a CLI entry point using Swift Argument Parser, a YAML serialization layer using SwiftYAML, a validation module, a service catalog reader that parses `bin/services/*.yaml`, and an install orchestrator that generates Ansible inventory and `openstack-components.yaml` then calls `install.sh --service <name>` in dependency order.

**Tech Stack:** Swift 6.3, Swift Package Manager, Swift Argument Parser, SwiftYAML, Foundation (native), XCTest

## Global Constraints

- Swift version: 6.3
- Must compile and run on macOS and Linux
- Leverage native Swift APIs where possible; limited third-party libraries only with justification
- All subprocess communication must use Swift `Foundation.Process` (no Python, no shell scripts)

---

## Architecture

### Package Structure

```
Sources/
├── genestackctl/             # Main CLI executable
│   ├── Commands/             # CLI subcommands (install, apply, service, node, secret, config)
│   ├── Wizard/               # Interactive wizard logic
│   ├── Services/             # Service catalog parsing and management
│   ├── Inventory/            # Ansible inventory generation
│   ├── Components/           # openstack-components.yaml generation
│   ├── Overrides/            # Overrides repo management
│   ├── Secrets/              # Secret discovery, ownership, rotation
│   ├── Orchestration/        # Install pipeline execution
│   └── Utilities/            # Shared utilities (logging, env vars, etc.)
├── GenestackSpec/            # Shared data models (ClusterSpec, Node, Service, etc.)
└── GenestackUtils/           # Utility library (YAML parsing, path helpers, etc.)
Tests/
├── GenestackSpecTests/       # Tests for data models and serialization
└── GenestackUtilsTests/      # Tests for utility functions
```

### Data Flow

1. **CLI Parsing**: Swift Argument Parser parses command-line arguments
2. **Spec Loading**: YAML file parsed into `ClusterSpec` model using SwiftYAML
3. **Validation**: Validate spec against schema rules (required fields, valid services, unique nodes, etc.)
4. **Execution**: Depending on command:
   - `install`: Run interactive wizard → write spec → execute pipeline
   - `apply`: Load existing spec → execute pipeline
   - `service/node/secret/config`: Perform specific management operations

### Subsystems

#### Service Catalog Parser
- Reads `bin/services/*.yaml` to discover all available services
- Excludes template/common files (files matching `*template*` or `*common*`)
- Extracts secrets, helm settings, and dependencies
- Dependency inference: services that consume secrets from service X depend on X

#### Secret Analyzer
- Parses service YAML files for secret definitions
- Builds ownership maps (which service owns which secret)
- Builds dependency maps (which services use which secrets)
- Provides rotation impact analysis

#### Inventory Generator
- Converts cluster spec `nodes:` into kubespray-format `inventory.yaml`
- Maps node roles to kubespray groups
- Writes to `${GENESTACK_OVERRIDES_DIR}/inventory/inventory.yaml`

#### Components Generator
- Converts cluster spec `services:` into `openstack-components.yaml`
- Writes to `${GENESTACK_OVERRIDES_DIR}/openstack-components.yaml`

#### Install Orchestrator
- Clones overrides repo if specified
- Runs `bootstrap.sh`
- Sets environment variables from spec
- Executes services in dependency order:
  - Infrastructure first (kube-ovn, longhorn, kube-prometheus-stack, cert-manager, metallb, etc.)
  - OpenStack services in dependency order (keystone first, then parallel)
- Handles `--on-failure` modes (prompt, fail-fast, continue)
- Generates OpenStack RC file at end

### Environment Variable Management

The following environment variables are set from the spec or CLI flags:

| Variable | Source | Default |
|----------|--------|---------|
| `GENESTACK_BASE_DIR` | `--genestack-dir` flag | `$GENESTACK_BASE_DIR` env or `/opt/genestack` |
| `GENESTACK_OVERRIDES_DIR` | Always | `/etc/genestack` (or `GENESTACK_BASE_DIR` if `replace_base: true`) |
| `GENESTACK_SERVICES_DIR` | Always | `${GENESTACK_BASE_DIR}/bin/services` |
| `GENESTACK_COMPONENTS_FILE` | Always | `${GENESTACK_OVERRIDES_DIR}/openstack-components.yaml` |

All additional `environment.*` vars from the spec are exported for child processes.

### Platform Compatibility

- Path handling via Swift `URL` and `FileManager` APIs
- Subprocess execution via `Foundation.Process` with platform-specific path detection
- Network interface detection (for auto-detecting interfaces) via native socket APIs or parsing system commands

## Testing Strategy

### Unit Testing
- Use XCTest framework
- Mock subprocess calls using protocol wrappers
- Test spec parsing and validation independently

### Integration Testing
- Use mock `bin/services/` directories with sample YAML files
- Test inventory generation against known spec inputs
- Test dependency ordering algorithm

### TDD Approach
1. Write failing test for each component
2. Implement minimal code to pass
3. Run tests to verify
4. Commit

## Acceptance Criteria

1. `genectl install --skip-install` produces valid `genestack-cluster.yaml`
2. `genectl apply` executes services in correct dependency order
3. `genectl service list` correctly shows service status
4. `genectl node list` correctly shows node inventory
5. `genectl secret list` correctly shows secret ownership
6. `genectl config validate` catches all invalid configurations
7. Generated Ansible inventory matches expected kubespray format
8. Generated `openstack-components.yaml` correctly reflects enabled services
9. CLI compiles and runs on macOS and Linux
10. All unit and integration tests pass
