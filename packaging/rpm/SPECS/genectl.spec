# SPDX-License-Identifier: Apache-2.0
# Packages the prebuilt genectl binary
# Built by packaging/rpm/build.sh

%global debug_package %{nil}
%global __os_install_post %{nil}

Name:           genectl
Version:        %{?pkgver}%{!?pkgver:0}
Release:        1%{?dist}
Summary:        Genestack Cluster Installation CLI

License:        Apache-2.0
Vendor:         Racker Labs
Packager:       Racker Labs <feedback@rackersystems.com>
URL:            https://github.com/rackerlabs/genestack
Source0:        genectl
Source1:        LICENSE

%description
Genestack Cluster Installation CLI (genectl) is a cross-platform command-line
tool for installing and managing Genestack OpenStack Kubernetes Stack clusters.

Features:
- Interactive installation wizard for cluster configuration
- Declarative YAML-based cluster specs
- Service, node, and secret management
- Dependency-ordered installation pipeline
- Pre-flight checks and cluster status monitoring
- Upgrade orchestration

Requires Swift 6.3+ runtime (static binary in release builds).

%prep
# Prebuilt binary release; nothing to unpack.

%build
# Prebuilt binary release; nothing to build.

%install
install -D -m 0755 %{SOURCE0} %{buildroot}%{_bindir}/genectl
install -D -m 0644 %{SOURCE1} %{buildroot}%{_datadir}/licenses/%{name}/LICENSE

%files
%license %{_datadir}/licenses/%{name}/LICENSE
%{_bindir}/genectl

%changelog
* Mon Aug 18 2026 Genestack Contributors <feedback@rackersystems.com> - 1.0.0-1
- Initial package
- Includes full cluster installation wizard
- Supports hyperconverged mode, service catalog parsing, and dependency resolution
EOF
