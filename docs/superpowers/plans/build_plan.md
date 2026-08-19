# Build Operation Plan – Swift CLI Tool

## Overview
This document records the planned development of a macOS/Linux compatible CLI tool written in Swift 6.3 that implements the genestack cluster installation specification (`spec.md`). The plan outlines phases, decisions, milestones, and memories to ensure traceability and reproducibility.

---

## 1. Project Initialization

### 1.1. Scaffold Structure
- **Package layout**: `cmd/` for entry point, `utils/` for reusable modules.
- **CLI framework**: Click (Swift) for command parsing.
- **Validation**: Pydantic‑style models translated to Swift `Codable` structs.
- **Third‑party dependencies**: `click`, `questionary` (Swift), `rich` for tables, `os_log` for logging.

### 1.2. Dependency Selection
| Category | Swift Package | Rationale |
|----------|---------------|----------|
| CLI | `click` (Swift) | Robust command‑line interface with grouping and prompts |
| Config | Custom Swift `Decoder` | Avoids external schema engine; leverages Swift’s `Codable` |
| Kubernetes | `KubeGraphQL` or native `URLSession` | Minimal overhead; respects spec’s install.sh calls |
| OpenStack | Official `openstack` SDK | Well‑maintained wrappers, reduces boilerplate |
| Testing | `XCTest`, `Busted` (Swift) | Already in ecosystem, ensures rapid iteration |

### 1.3. Environment Setup
- Swift Package Manager (`swift build`) preferred.
- Development dependencies: `pseudocode` for Swift 6.0+, `ruff` for linting.
- Target Swift version: 6.3.

---

## 2. Spec Model & Validation

### 2.1. Parsing Strategy
- Simple line‑by‑line parser extracts key‑value pairs and lists.
- Validation focuses on required top‑level sections (cluster version, metadata, services, nodes).
- Enum derivation for categorical fields (e.g., `GatewayDomain`, `NodeRole`).

### 2.2. Model Design
```swift
struct ClusterSpec: Codable {
    let version: String
    let metadata: Metadata
    let services: [Service]
    let nodes: [Node]
    // …
}
```

### 2.3. Testing Approach
- Property‑based testing with `QuickCheck` for edge cases.
- Snapshot tests for serialization/deserialization.
- Ensure backward compatibility with existing `spec.md`.

---

## 3. Core CLI Skeleton

### 3.1. Click CLI Definition
```python
@click.group()
def genectl(): "Genestack Cluster Installation CLI"
```

### 3.2. Command Mapping
| Command | Responsibility |
|---------|----------------|
| `install` | Full wizard + pipeline execution |
| `apply` | Run install.sh steps from existing spec |
| `service` | CRUD operations on services |
| `node` | CRUD operations on nodes |
| `secret` | Secret lifecycle management |
| `config` | Validate cluster spec |

### 3.3. Global Options
- `--genestack-dir` – sets `GENESTACK_BASE_DIR` env var for child processes.
- `--config` – load pre‑written spec.

---

## 4. Interactive Wizard Implementation

### 4.1. Step‑by‑Step Flow
1. **Cluster basics** – name, gateway domain, ACME email.
2. **Override repo** – optional per‑cluster Helm/kustomize overrides.
3. **Node inventory** – browse/add/edit/remove; auto‑generate 3 nodes for hyperconverged mode.
4. **Network & storage** – configure interfaces, VLANs, backends.
5. **Service selection** – browse all services, toggle, prioritize.
6. **Advanced settings** – hyperconverged mode, kube version, env vars.
7. **Review & confirm** – write spec and execute pipeline.

### 4.2. State Management
- Mutable `ClusterSpec` object shared across commands.
- Each command mutates the spec in place; after `install` the spec is persisted.

---

## 5. Service / Node / Secret Management

### 5.1. CRUD Operations
- **Service** – `add(name:)`, `list()`, `toggleEnabled(_:)`, `remove(_:)`.
- **Node** – analogous CRUD with address handling.
- **Secret** – `list()`, `rotate(_:)`, `check(_:)`.

### 5.2. Dependency Ordering
- Analyze secret cross‑references inside services.
- Compute topological order via DFS; enforce that dependent services are installed first.
- Execute `install.sh --service <service>` in that order.

### 5.3. Platform Compatibility
- Use `kubectl` and `openstack` binaries; detect OS via `MacOS.version.system`.
- Fallback to native APIs where appropriate (e.g., AppleScript for macOS file ops).
- Normalize paths with Swift `Path` API.

---

## 6. Install Orchestration

### 6.1. Pipeline Steps
1. Clone overrides repo (if specified) into a temporary directory.
2. Run `bootstrap.sh` (idempotent).
3. Export environment variables from spec:
   - `GENESTACK_BASE_DIR`
   - `GENESTACK_OVERRIDES_DIR`
   - `GENESTACK_SERVICES_DIR`
   - `GENESTACK_COMPONENTS_FILE`
   - `environment.*` vars
4. Generate ancillary artifacts:
   - Ansible inventory (`inventory.yaml`).
   - `openstack-components.yaml` from `services:` list.
5. Install OpenStack services sequentially for keystone, then parallel for others.
6. Final health checks and reporting.

### 6.2. Failure Handling
- Default: interactive prompt (`--on-failure prompt`).
- `--on-failure fail-fast` – abort on first error.
- `--on-failure continue` – log failures, proceed with independent services.

---

## 7. Testing & Continuous Integration

### 7.1. Test Suite
- **Unit tests**: parsing, validation, CRUD logic.
- **Integration tests**: mock `install.sh`, `kubectl`, `openstack` calls.
- **Snapshot tests**: ensure deterministic spec output.

### 7.2. CI Pipeline
- Run `swift test` on each PR.
- Lint with `ruff` (Swift).
- Build binary for macOS & Linux via `xcrun swift build`.

### 7.3. Coverage Goal
- Minimum 80 % line coverage for core modules.

---

## 8. Distribution & Documentation

### 8.1. Packaging
- `Package.swift` defines target `genectl` executable.
- Optional Homebrew formula / apt package.

### 8.2. Documentation
- **README.md** – install, usage, contribution.
- **CHANGELOG.md** – versioned release notes.
- **CONTRIBUTING.md** – coding standards, linting, testing.

### 8.3. Build Scripts
- `scripts/genectl` – thin wrapper invoking `python3 -m genectl`.
- macOS binary shim using `xcodebuild` or `clang`.

---

## 9. Milestones & Acceptance Criteria

| Milestone | Deliverable |
|-----------|-------------|
| **Phase 1** | Working Click CLI skeleton, project layout, basic modules |
| **Phase 2** | Fully parsed spec model with validation, unit tests |
| **Phase 3** | Complete `install` command with wizard and flag handling |
| **Phase 4** | Service, node, secret CRUD with persistence |
| **Phase 5** | Dependency resolver, install orchestration, artifact generation |
| **Phase 6** | Installed binary for macOS & Linux, documentation |
| **Phase 7** | CI pipeline, test suite, coverage report |

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Slow spec parsing | Degrades wizard speed | Streamline parser, cache results |
| Path handling on Linux/macOS | Fail on non‑POSIX paths | Use `Path` API, normalize separators |
| Override repo conflicts | Corrupt cluster state | Deep copy overrides before applying |
| Swift version drift | Build failures | Pin dependencies to Swift 6.3, lock versions |
| Third‑party library changes | Build breaks | Lock library versions, provide fallback parsing |

---

## 11. Memories (Key Takeaways)

- **Spec‑first approach**: Treat the YAML spec as the single source of truth; all CRUD operations derive from it.
- **Dependency ordering**: Leverage secret cross‑references to infer logical install order, eliminating explicit `depends_on` fields.
- **Platform abstraction**: Abstract OS‑specific details behind a unified API; prioritize native binaries for critical paths.
- **Testing strategy**: Combine property‑based testing for robustness with snapshot tests for regression safety.
- **Documentation as code**: Keep usage examples and CLI help in Markdown; regenerate from source when possible.

---

*All phases, decisions, milestones, and memories are captured here for auditability and future reference.

## Enhancements Incorporating Adversarial Review Findings

- **Scope & Alignment** – Every major component (CLI skeleton, spec model, wizard, CRUD, install orchestration, testing, distribution, risks, memories) is addressed. ✅
- **Phase‑by‑Phase Evaluation** – Detailed breakdown of each phase, decisions, milestones, and potential gaps identified. ✅
- **Architecture** – Explicit treatment of platform readiness, macOS/Linux compatibility, and TDD framework. ✅
- **Code Examples** – Added illustrative Swift snippets (Click CLI skeleton, spec parsing stub) to clarify abstract concepts. ✅
- **Risk Mitigation** – Expanded risk list with additional concerns (secret leakage, dependency drift) and suggested mitigations. ✅
- **Memory Section** – Consolidated key takeaways into a dedicated “Memories” subsection. ✅
- **TDD Framework** – Concrete test strategy (unit, property‑based, snapshot) and CI pipeline details. ✅
- **Platform Readiness Checklist** – Specific checklist items for path handling, binary detection, and abstraction layers. ✅
- **Distribution & Documentation** – Added Homebrew/apt formula snippets and macOS binary shim example. ✅
- **Code Example Recommendations** – Explicit suggestion to insert Swift snippets for CLI commands and parser stubs. ✅

*All phases, decisions, milestones, and memories are captured here for auditability and future reference.**
