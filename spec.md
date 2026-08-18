# genectl — Genestack Cluster Installation CLI

## Overview

`genectl` is a Python-based CLI tool that interactively guides an operator through
generating and executing a full Genestack cluster deployment. It replaces the
manual, scattered question-asking previously found in `bootstrap.sh`,
`setup-infrastructure.sh`, `setup-openstack.sh`, and the `read -p` prompts
throughout the install scripts.

`genectl` writes a single declarative YAML file (`genestack-cluster.yaml`) that
captures all cluster configuration, then uses that spec to orchestrate the full
installation by directly calling `install.sh --service <name>` for each component
in the correct dependency order.

## Quick Start

```bash
# Interactive full cluster installation
genectl install

# Generate config only (dry-run, no changes to cluster)
genectl install --skip-install

# Add a service to an existing cluster spec
genectl service add nova

# Remove a service from the cluster spec
genectl service remove nova

# List all secrets and their ownership
genectl secret list

# Rotate secrets for a specific service
genectl secret rotate nova

# Reinstall all services from existing spec (e.g. after config change)
genectl apply --yes
```

---

## 1. Commands

### 1.1 `genectl install`

Full cluster installation wizard. Interactive interview of all required parameters,
writes `genestack-cluster.yaml` (or `--output` path if specified), then executes the
install pipeline. If `--config <file>` is provided, pre-fills wizard answers from
the existing spec (for iterative refinement).

### 1.1a `genectl apply`

Executes the install pipeline from an existing `genestack-cluster.yaml` without the wizard.
Useful for re-runs, CI/CD pipelines, and testing.

```
genectl apply [--config <file>] [--yes] [--overrides-repo <url>] [--on-failure <mode>] [--genestack-dir <path>] [--upgrade]
genectl install [--config <file>] [--yes] [--skip-install] [--output <file>] [--overrides-repo <url>] [--on-failure <mode>] [--genestack-dir <path>] [--upgrade]
```

**Flags (install):**
- `--config <file>` — Load existing cluster spec to pre-fill wizard answers (default: read `genestack-cluster.yaml` if it exists)
- `--yes` — Skip confirmation prompts; use defaults for unanswered questions
- `--skip-install` — Generate `genestack-cluster.yaml` only; don't execute installer
- `--output <file>` — Override default output path (`genestack-cluster.yaml`)
- `--overrides-repo <url>` — Git repository URL for per-cluster helm/kustomize overrides
- `--on-failure <mode>` — Pipeline failure behavior: `fail-fast`, `continue`, or `prompt` (default). In CI/CD, use `--on-failure fail-fast --yes`
- `--genestack-dir <path>` — Override genestack installation directory (default: `$GENESTACK_BASE_DIR` env var or `/opt/genestack`). Sets `GENESTACK_BASE_DIR` for all child processes (`install.sh`, `bootstrap.sh`, `setup-openstack-rc.sh`).
- `--upgrade` — Force re-install of already-provisioned services (default: auto-detect and skip)

**Flags (apply):**
- `--config <file>` — Cluster spec to execute (default: `genestack-cluster.yaml`)
- `--yes` / `--overrides-repo` / `--on-failure` / `--genestack-dir` / `--upgrade` — Same as `install`

**Wizard steps:**
1. Cluster basics (name, gateway domain, ACME email)
2. Overrides repo (optional — e.g. `https://github.com/rackerlabs/flex-overrides-template`)
3. Node inventory (add/edit/remove nodes — name, IP, roles, per-network addresses, labels, taints). When hyperconverged: true, auto-generates 3 nodes with all roles, editable before proceeding.
4. Network configuration (interfaces with auto-detection, OVN settings, VLAN)
5. Storage configuration (longhorn replicas, Cinder backend type, backend-specific settings)
6. Service selection (browse and toggle all 50+ services)
7. Advanced settings (hyperconverged mode, kube version, env vars)
8. Review & confirm → Write spec → Execute pipeline

**Installation pipeline (Phase 4):**
After the spec is written, `genectl install` executes:
1. Clone overrides repo (if `--overrides-repo` or `overrides.repo` in spec) to `${GENESTACK_OVERRIDES_DIR}` (default `/etc/genestack`) or `${GENESTACK_BASE_DIR}` (default `/opt/genestack`) if `replace_base: true`
2. Always run `bootstrap.sh` (idempotent — skips if OS packages already installed)
3. Export env vars from spec:
   - `GENESTACK_BASE_DIR` (from `--genestack-dir`, defaults to `$GENESTACK_BASE_DIR` env or `/opt/genestack`)
   - `GENESTACK_OVERRIDES_DIR` (defaults to `/etc/genestack` — where overrides repo is cloned)
   - `GENESTACK_SERVICES_DIR` (defaults to `${GENESTACK_BASE_DIR}/bin/services`)
   - `GENESTACK_COMPONENTS_FILE` (defaults to `${GENESTACK_OVERRIDES_DIR}/openstack-components.yaml`)
   - All `environment.*` vars from spec
4. Detect existing cluster state: check if each service's k8s resources already exist
   - Without `--upgrade`: skip already-installed services (check if helm release exists)
   - With `--upgrade`: re-run all enabled services (force helm `upgrade --install`)
5. Generate Ansible inventory at `${GENESTACK_OVERRIDES_DIR}/inventory/inventory.yaml` (default `/etc/genestack/inventory/inventory.yaml`) from `nodes:` list
6. Generate `openstack-components.yaml` at `${GENESTACK_OVERRIDES_DIR}/openstack-components.yaml` (default `/etc/genestack/openstack-components.yaml`) from `services:` list:

   ```yaml
   components:
     keystone: true
     nova: true
     neutron: true
     cinder: false
     glance: false
     # ... (all 50+ services)
   ```
7. Infrastructure installs (in dependency order, skipping already-provisioned unless --upgrade):
   - Node labeling (apply OpenStack labels based on roles: `openstack-control-plane`, `openstack-compute-node`, `openstack-network-node`, `openstack-storage-node`, `kube-ovn/role`, `longhorn.io/storage-node`) → OVN annotations → `install.sh --service kube-ovn` → wait for kube-ovn-controller
   - → `install.sh --service longhorn` + `kubectl apply -f ${GENESTACK_OVERRIDES_DIR}/manifests/longhorn/longhorn-general-storageclass.yaml`
   - → `install.sh --service kube-prometheus-stack`
   - → `install.sh --service cert-manager`
   - → `install.sh --service metallb` + wait for webhook + `kubectl apply -f ${GENESTACK_OVERRIDES_DIR}/manifests/metallb/metallb-openstack-service-lb.yml`
   - → `kubectl apply -k ${GENESTACK_OVERRIDES_DIR}/kustomize/openstack/base`
   - → `install.sh --service envoy-gateway`
     - If `ENVOY_GATEWAY_CONFIG_FILE` set: install with `--config` flag (no wait, no setup-envoy-gateway.sh)
     - If not set: wait for envoy-gateway to be available → `setup-envoy-gateway.sh -e <ACME_EMAIL> -d <GATEWAY_DOMAIN>`
   - → Wait for cert-manager to be available → `install.sh --service mariadb-operator` → wait for webhook → `kubectl apply -k ${GENESTACK_OVERRIDES_DIR}/kustomize/mariadb-cluster/overlay`
   - → `kubectl apply -k ${GENESTACK_OVERRIDES_DIR}/kustomize/rabbitmq-operator/base` → `kubectl apply -k ${GENESTACK_OVERRIDES_DIR}/kustomize/rabbitmq-topology-operator/base` → wait for webhooks → `kubectl apply -k ${GENESTACK_OVERRIDES_DIR}/kustomize/rabbitmq-cluster/overlay`
   - → `kubectl apply -k ${GENESTACK_OVERRIDES_DIR}/kustomize/ovn/base`
   - → `install.sh --service memcached` → `install.sh --service libvirt`
   - → `install.sh --service redis-operator` → `install.sh --service redis-replication` → `install.sh --service redis-sentinel`
8. OpenStack service installs:
   - `install.sh --service keystone` (sequential — other services depend on it)
   - Remaining enabled services in parallel (dependency-ordered, via `concurrent.futures`)
   - On failure: `--on-failure prompt` (default) offers retry/skip/abort per service; `--on-failure fail-fast` stops immediately; `--on-failure continue` collects failures and proceeds with independent services
9. Generate OpenStack RC file (`setup-openstack-rc.sh`) for cluster access

### 1.2 `genectl service list`

Lists all available services from the `bin/services/` catalog, showing which are
enabled in the current cluster spec. Excludes template and common-family files
(e.g. `example-service.yaml`, `*-common.yaml`, `*-template.yaml`).

```
genectl service list [--config <file>]
```

**Output columns:** Service | Namespace | Enabled | Helm repo | Owned secrets

### 1.3 `genectl service add <name>`

Adds a service to the cluster spec, marking it enabled.

```
genectl service add <name> [--config <file>]
```

Validates that `bin/services/<name>.yaml` exists. Fails if already enabled.

### 1.4 `genectl service remove <name>`

Removes a service from the cluster spec.

```
genectl service remove <name> [--config <file>] [--purge]
```

- Without `--purge`: marks `enabled: false`
- With `--purge`: removes the entry entirely

### 1.5 `genectl node list`

Lists all nodes in the cluster spec.

```
genectl node list [--config <file>]
```

**Output columns:** Name | IP | Roles | Labels

### 1.6 `genectl node add`

Interactive wizard to add a new node.

```
genectl node add [--config <file>] [--name <hostname>] [--ip <ip>] [--roles <role1,role2,...>]
```

Prompts for hostname, IP, roles, per-network addresses (management, ansible, storage, overlay), and optional labels/taints.
When `--name`, `--ip`, and `--roles` are provided, skips prompts and uses the provided values (for CI/CD).

### 1.7 `genectl node remove <name>`

Removes a node from the cluster spec.

```
genectl node remove <name> [--config <file>]
```

### 1.8 `genectl secret list`

Lists all secrets known to the cluster, showing ownership and status.

```
genectl secret list [--config <file>] [--namespace <ns>]
```

- `--namespace <ns>`: Filter secrets by namespace (e.g. `openstack`, `longhorn-system`)

**Output columns:** Namespace | Secret | Owner | Data keys | In k8s? | Helm flags

### 1.9 `genectl secret rotate <service>`

Rotates service-owned secrets and reinstalls impacted services.

```
genectl secret rotate <service> [--config <file>] [--yes] [--dry-run] [--on-failure <mode>]
```

- Shows rotation plan (owned secrets + impacted services in dependency order)
- `--dry-run`: print plan without executing
- `--yes`: skip confirmation prompt
- `--on-failure <mode>`: `prompt` (default), `fail-fast`, or `continue` for the reinstall phase
- Rotates only secrets with `rotate_with_service: true` in `<service>.yaml`
- Reinstalls service + all dependents (derived from cross-references in `bin/services/*.yaml`)

### 1.10 `genectl secret check <service>`

Checks whether all secrets required by a service exist in k8s.

```
genectl secret check <service> [--config <file>]
```

Exit 0 if all present, 1 if any missing.

### 1.11 `genectl config validate`

Validates the cluster spec.

```
genectl config validate [--config <file>]
```

Checks: all services exist in catalog, node IPs unique, no conflicting labels,
OVN/VLAN settings consistent.

### 1.12 `genectl config edit`

Opens the cluster spec in `$EDITOR` (defaults to `vi` if unset).

```
genectl config edit [--config <file>]
```

---

## 2. Cluster Spec Schema (`genestack-cluster.yaml`)

```yaml
# Cluster spec schema (genestack-cluster.yaml)
#
# This file captures all configuration needed to install a Genestack cluster.
# The genectl install wizard generates this file interactively.
# The genectl apply command consumes this file to run the install pipeline.
#
# Example adapted from a DFW dev environment (real IPs/hostnames replaced with placeholders).

version: "1.0"

metadata:
  cluster_name: mycloud
  gateway_domain: cluster.local
  acme_email: admin@example.com

# Per-cluster overrides repository
overrides:
  repo: "https://github.com/rackerlabs/flex-overrides-template"   # optional, empty = use defaults from /opt/genestack/
  ref: main
  replace_base: false   # If true, overrides repo replaces /opt/genestack/ (GENESTACK_BASE_DIR) instead of /etc/genestack/ (GENESTACK_OVERRIDES_DIR)

kubernetes:
  hyperconverged: false
  kube_version: "v1.35.6"   # k8s version (defaults to kubespray's kube_version in group_vars if empty)
  # Group-level vars applied to all hosts in each role group
  group_vars:
    openstack_compute_nodes:
      enable_iscsi: true
      custom_multipath: true
    storage_nodes:
      enable_iscsi: true
      storage_network_multipath: true
  vars:
    cloud_name: mycloud-1
    host_pin_kernel: true

nodes:
  - name: controller01.mycloud.local
    ip: 10.0.0.10
    roles: [control-plane, etcd, kube-node, openstack-control-plane]
    labels:
      node-role.kubernetes.io/worker: worker
    taints: []
    addresses:
      management_ip: 10.0.0.10
      ansible_host: 172.28.0.10
      network_mgmt_address: 172.28.0.10
      network_storage_address: 172.28.1.10
      network_overlay_address: 172.28.2.10
  - name: compute01.mycloud.local
    ip: 10.0.0.11
    roles: [kube-node, openstack-compute-node]
    addresses:
      management_ip: 10.0.0.11
      ansible_host: 172.28.0.11
      network_mgmt_address: 172.28.0.11
      network_overlay_address: 172.28.2.11
      network_storage_address: 172.28.1.11
      network_storage_a_address: 172.28.3.11
      network_storage_b_address: 172.28.4.11
  - name: block01.mycloud.local
    ip: 10.0.1.10
    roles: [kube-node, openstack-storage-node]
    addresses:
      management_ip: 10.0.1.10
      ansible_host: 172.28.0.101
      network_mgmt_address: 172.28.0.101
      network_overlay_address: 172.28.2.101
      network_storage_address: 172.28.1.101
      network_storage_a_address: 172.28.3.101
      network_storage_b_address: 172.28.4.101

network:
  container_interface: bond0            # OVN network interface (auto-detected from default route if omitted)
  container_vlan_interface: bond0       # VLAN sub-interface for OVN (defaults to container_interface)
  compute_interface: eth0              # Compute network interface (auto-detected as last interface if omitted)
  ovn_external_interface: bond0.126    # External OVN interface (VLAN sub-interface)
  ovn_vlans: "bond0.126:bond0:126:1500"  # External VLAN spec: interface:parent:vlan_id:mtu
  ovn_external_vlan:
    interface: bond0.126
    parent: bond0
    vlan_id: 126
    mtu: 1500
  # The VLAN IDs (e.g. 126) are deployment-specific. Match these to your
  # network topology and the overrides repo's kustomize/ovn/base configuration.

storage:
  longhorn_replicas: 2
  cinder_backend: lvm              # lvm | netapp-iscsi | ceph
  # Additional backend-specific settings go here (e.g. netapp svm_name, ceph cluster_id)

services:
  # All 50+ services from bin/services/ are listed; enabled: false by default
  # Each service can override:
  #   version: chart version (~ = use default from helm-chart-versions.yaml)
  #   helm_args: list of extra helm args passed to install.sh (e.g. ["--set", "foo=bar"])
  - name: keystone
    enabled: true
    version: ~
    helm_args: []
  - name: nova
    enabled: true
    version: ~
    helm_args: []
  - name: neutron
    enabled: true
    version: ~
    helm_args: []
  - name: cinder
    enabled: false
    version: ~
    helm_args: []
  - name: glance
    enabled: false
    version: ~
    helm_args: []
  # ... (all 50+ services, disabled by default)

environment:
  SKIP_PROMPTS: "true"
  ANSIBLE_FORKS: "24"
```

---

## 3. Architecture

### 3.1 Relationship to the Unified Installer (PR #1641)

`genectl` builds on top of the PR #1641 unified install framework:

- **`bin/install.sh`** — genectl calls this directly for each service
- **`bin/services/*.yaml`** — genectl reads this catalog to know available services, their secrets, and helm settings
- **`bin/helpers.sh`** — genectl reuses the same env vars and conventions (e.g. `GENESTACK_COMPONENTS_FILE`, `GENESTACK_SERVICES_DIR`)

### 3.2 Node Inventory Generation

`genectl` generates a kubespray-format `inventory.yaml` at `${GENESTACK_OVERRIDES_DIR}/inventory/inventory.yaml`
(default `/etc/genestack/inventory/inventory.yaml`) from the `nodes:` list in the
cluster spec. Each node's roles determine which kubespray groups it joins:

| genectl role | kubespray groups |
|---|---|
| `control-plane` | `kube_control_plane`, `kube_node` |
| `etcd` | `etcd` |
| `openstack-control-plane` | `openstack_control_plane` |
| `openstack-compute-node` | `openstack_compute_nodes` |
| `openstack-network-node` | `ovn_network_nodes` |
| `openstack-storage-node` | `storage_nodes` → `cinder_storage_nodes` |

Per-node network addresses in the kubespray inventory are mapped from the cluster spec's
per-node `addresses:` map. The generated inventory matches the format used by existing
deployments:

```yaml
all:
  vars:
    cloud_name: "mycloud-1"
    ansible_python_interpreter: "/usr/bin/python3"
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
  hosts:
    controller01.mycloud.local:
      ansible_host: 172.28.0.10
      management_ip: 10.0.0.10
      network_mgmt_address: 172.28.0.10
      network_storage_address: 172.28.1.10
      network_overlay_address: 172.28.2.10
    compute01.mycloud.local:
      ansible_host: 172.28.0.11
      management_ip: 10.0.0.11
      network_mgmt_address: 172.28.0.11
      network_overlay_address: 172.28.2.11
      network_storage_address: 172.28.1.11
      network_storage_a_address: 172.28.3.11
      network_storage_b_address: 172.28.4.11
    block01.mycloud.local:
      ansible_host: 172.28.0.101
      management_ip: 10.0.1.10
      network_mgmt_address: 172.28.0.101
      network_overlay_address: 172.28.2.101
      network_storage_address: 172.28.1.101
      network_storage_a_address: 172.28.3.101
      network_storage_b_address: 172.28.4.101
      children:
        k8s_cluster:
          vars:
            cluster_name: cluster.local
            kube_ovn_central_hosts: '{{ groups["ovn_network_nodes"] }}'
            kube_ovn_default_interface_name: bond0   # set from network.container_vlan_interface in spec
            kube_ovn_iface: bond0   # set from network.container_interface in spec
      children:
        kube_control_plane:
          hosts:
            controller01.mycloud.local: null
        etcd:
          hosts:
            controller01.mycloud.local: null
        kube_node:
          hosts:
            controller01.mycloud.local: null
            compute01.mycloud.local: null
            block01.mycloud.local: null
        openstack_control_plane:
          hosts:
            controller01.mycloud.local: null
        openstack_compute_nodes:
          vars:
            enable_iscsi: true
            custom_multipath: true
          hosts:
            compute01.mycloud.local: null
        ovn_network_nodes:
          hosts:
            {}
        storage_nodes:
          vars:
            enable_iscsi: true
            storage_network_multipath: true
          children:
            cinder_storage_nodes:
              hosts:
                block01.mycloud.local: null
```

**Address mapping** (from cluster spec `nodes[].addresses` to kubespray inventory):

| Spec address key | Kubespray host var | Description |
|---|---|---|
| `management_ip` | `management_ip` | 10.x mgmt IP (optional in inventory, used for reference) |
| `ansible_host` | `ansible_host` | SSH target IP (required, used by ansible) |
| `network_mgmt_address` | `network_mgmt_address` | Management VLAN IP (bond0) |
| `network_storage_address` | `network_storage_address` | Storage VLAN IP (bond0.354) |
| `network_storage_a_address` | `network_storage_a_address` | Storage-A VLAN IP (bond0.368) |
| `network_storage_b_address` | `network_storage_b_address` | Storage-B VLAN IP (bond0.369) |
| `network_overlay_address` | `network_overlay_address` | Overlay VLAN IP (bond1) |

> **Note:** VLAN IDs (e.g. 354, 368, 369) are deployment-specific. The `network_*`
> address keys must match the VLAN configuration in your overrides repo's
> `kustomize/ovn/base/` and `kustomize/openstack/base/` directories.

> **Note:** Nodes can have multiple roles (e.g. `[openstack-control-plane, openstack-network-node]`)
> and will appear in all matching kubespray groups. A controller that also serves as a
> network node should have both roles assigned.

Group-level vars (e.g. `enable_iscsi`, `custom_multipath`, `cinder_backend_name`,
`storage_network_multipath`) are generated from the `kubernetes.group_vars` section
of the cluster spec.

### 3.3 Dependency Ordering

The infrastructure pipeline follows a strict order determined by service dependencies.
The OpenStack service pipeline runs keystone first (all other services depend on it),
then remaining services in parallel using `concurrent.futures`.

`genectl` derives the dependency order from secret cross-references in
`bin/services/*.yaml` (the same logic that PR #1641's `rotation_collect_impacted_services`
uses). No explicit `depends_on` field is needed in the cluster spec — the graph is
inferred from which services reference which secrets (services that consume
secrets from service X are considered dependent on service X).

### 3.4 Per-Cluster Overrides Repo

The `overrides.repo` field allows operators to ship custom helm override YAMLs and
kustomize patches without forking the entire genestack repo. Example repo:
`https://github.com/rackerlabs/flex-overrides-template`.

At install time, `genectl`:
1. Clones the repo to `${GENESTACK_OVERRIDES_DIR}` (default `/etc/genestack/`, or `${GENESTACK_BASE_DIR}` / `/opt/genestack/` if `replace_base: true`)
2. Sets `GENESTACK_OVERRIDES_DIR` (or `GENESTACK_BASE_DIR` if `replace_base`) to the cloned repo path
3. The cloned `helm-configs/` directory replaces default per-service overrides
4. The cloned `kustomize/` directory replaces default kustomize overlays

### 3.5 Deprecation of Legacy Scripts

**`setup-infrastructure.sh` and `setup-openstack.sh` are removed** in this change.
`genectl install` fully replaces their functionality by directly executing the
install pipeline (node labeling, kustomize applies, `install.sh --service` calls
in dependency order, etc.). Existing automation that called these scripts should
migrate to `genectl install` or `genectl install --skip-install` (spec-only) followed
by direct `install.sh --service` calls.

---

## 4. Implementation Plan

### Phase 1: Core CLI skeleton
- Create `pyproject.toml` with `console_scripts` entry point for `genectl`
- Python package structure under `cmd/genectl/`
- Click CLI groups + questionary for interactive prompts
- Pydantic schema for `genestack-cluster.yaml`
- Dependencies: `click`, `questionary`, `pyyaml`, `rich`, `pydantic`

### Phase 2: Spec generation & wizard
- Interactive wizard for all spec fields
- Ansible inventory (`inventory.yaml`) generation from `nodes:` list
- `openstack-components.yaml` generation from `services:` list
- Environment variable export

### Phase 3: Service/node/secret management
- `service list/add/remove`
- `node list/add/remove`
- `secret list/rotate/check`
- `config validate/edit`

### Phase 4: Install orchestration
- Full pipeline execution (infrastructure → OpenStack services)
- Overrides repo cloning
- Native Python parallel install for OpenStack services (using `concurrent.futures`)
- Replaces `setup-infrastructure.sh` and `setup-openstack.sh`

### Phase 5: Testing & CI
- Unit tests for each module (pytest)
- Integration test: `genectl install --skip-install` produces valid spec
- Test fixtures: sample `bin/services/*.yaml` subset, mock k8s inventory
- Pre-commit hook for schema validation and linting
- Update `dev-requirements.txt` with `pytest`, `pytest-cov`, `pytest-mock`, `pydantic`, `questionary`
- Add `genectl` to `.pre-commit-config.yaml` (ruff lint, black format)

#### TDD approach:
- Tests written BEFORE implementation for each command/module
- `test_schema.py` — validate `genestack-cluster.yaml` pydantic models (all fields, defaults, edge cases)
- `test_services.py` — test service catalog loading, validation, list/add/remove
- `test_inventory.py` — test kubespray inventory.yaml generation from cluster spec nodes
- `test_components.py` — test openstack-components.yaml generation from services list
- `test_overrides.py` — test git cloning of overrides repo, path resolution
- `test_installer.py` — test pipeline execution order, `--upgrade` detection, `--on-failure` handling
- `test_secrets.py` — test secret discovery, ownership analysis, rotation plan
- `test_secret.py` — test `genectl secret list/rotate/check` commands
- `test_config.py` — test `genectl config validate/edit` commands
- `test_service.py` — test `genectl service list/add/remove` commands
- `test_node.py` — test `genectl node list/add/remove` commands, wizard prompts
- `test_apply.py` — test `genectl apply` pipeline execution without wizard
- Integration: test full `genectl install --skip-install` → valid YAML output
- Mock `subprocess.run` for all `install.sh`, `kubectl`, `bootstrap.sh` calls

---

## 5. File Layout

```
cmd/genectl/
├── __init__.py
├── __main__.py                 # Entry point for `python -m genectl`
├── cli.py                       # Click CLI group + command registration
├── commands/
│   ├── __init__.py
│   ├── apply.py                # apply command (pipeline execution without wizard)
│   ├── install.py               # install command + wizard
│   ├── service.py               # service list/add/remove
│   ├── node.py                  # node list/add/remove
│   ├── secret.py                # secret list/rotate/check
│   └── config.py                # config validate/edit
├── schema.py                    # Pydantic models for genestack-cluster.yaml
├── ui/
│   ├── __init__.py
│   ├── prompts.py               # questionary prompt helpers
│   └── tables.py                # rich table formatters
├── utils/
│   ├── __init__.py
│   ├── services.py              # Load/validate bin/services/*.yaml catalog
│   ├── inventory.py             # Generate Ansible inventory.yaml
│   ├── components.py            # Generate openstack-components.yaml
│   ├── overrides.py             # Clone per-cluster overrides repo
│   ├── installer.py             # Execute install.sh --service in pipeline order
│   └── secrets.py               # Secret discovery, ownership, rotation analysis
└── tests/
    ├── test_schema.py
    ├── test_services.py
    ├── test_inventory.py
    ├── test_components.py
    ├── test_overrides.py
    ├── test_installer.py
    ├── test_secrets.py
    ├── test_secret.py
    ├── test_config.py
    ├── test_service.py
    ├── test_node.py
    └── test_apply.py

scripts/genectl               # Thin wrapper: PYTHONPATH=cmd python3 -m genectl "$@" (for non-pip usage)
pyproject.toml               # Package configuration + console_scripts entry point
```

---

## 6. Decisions

All design questions resolved:

| Question | Decision |
|---|---|
| Python packaging | **Pip-installable package** with `pyproject.toml` + `console_scripts` (`python -m genectl` also supported) |
| Test framework | **pytest** with `pytest-cov`, `pytest-mock`; mock all `subprocess.run` calls; TDD — tests before implementation |
| New dependencies | **`pydantic`** (schema validation), **`questionary`** (interactive prompts), **`click`** (CLI), **`rich`** (tables/output) — all added to `dev-requirements.txt` |
| Per-service kustomize overrides | **Not supported** — controlled by `bin/services/<name>.yaml` `kustomize.overlay_path` |
| Parallel orchestration | **`concurrent.futures` + `subprocess.Popen`** for parallel `install.sh --service` calls |
| Deprecation timeline | **`setup-infrastructure.sh` and `setup-openstack.sh` removed immediately** |
| Schema versioning | `version: "1.0"` field for backward-compatible detection |
| Genestack location | **`GENESTACK_BASE_DIR` env var** (default `/opt/genestack`) with **`--genestack-dir` CLI flag** taking precedence |
| helm_args format | **String list** — pass-through to `install.sh` as individual CLI args (e.g. `["--set", "foo=bar"]` passes `--set foo=bar` to helm) |
| Kubespray inventory | **Generated from `nodes:` list** — full kubespray-format `inventory.yaml` with standard groups (`kube_control_plane`, `etcd`, `kube_node`, `openstack_control_plane`, `openstack_compute_nodes`, `ovn_network_nodes`, `storage_nodes`) |
| bootstrap.sh detection | **Always run** — idempotent, skips if OS packages already installed |
| Failure handling | **Interactive prompt** (default) with `--on-failure fail-fast\|continue` for CI/CD |
| Existing cluster detection | **Auto-detect**: genectl checks if services are already installed; `--upgrade` flag forces re-install |
| All services listed | **Yes** — all 50+ services from `bin/services/` included in spec with `enabled: false` by default |
| Hyperconverged wizard | **3 nodes** with all roles by default; operator can edit before proceeding |
| OpenStack RC | **Included** — `setup-openstack-rc.sh` runs at end of pipeline for clouds.yaml generation |
| `--genestack-dir` propagation | **Sets `GENESTACK_BASE_DIR` env var** for all child processes |%