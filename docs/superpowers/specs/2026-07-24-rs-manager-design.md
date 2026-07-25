# RS Manager Unified Deployment Design

**Date:** 2026-07-24

**Status:** v1.0 implementation scope recorded; later sections also retain post-v1 design targets

## 1. Purpose

Build a one-command, command-line-only VPS manager that combines the useful capabilities of the existing Realm and Sing-box deployment scripts and adds a safe BBR/TCP tuning module.

The first release must solve the current Sing-box lifecycle limitation: protocols omitted during initial installation must be addable later without reinstalling or replacing the existing configuration. The same design may also support multiple independent instances of one protocol.

The project uses `zt1001zt/realm` as the published integration repository. The existing Realm script remains available for compatibility while the new unified command is introduced as `rs`.

## 2. Supported Environments

- Debian and Ubuntu using systemd.
- CentOS, RHEL, Rocky Linux, AlmaLinux, and compatible distributions using systemd.
- Alpine Linux using OpenRC.
- CPU architectures supported by the upstream Realm and Sing-box releases, initially `amd64` and `arm64`.
- Bash is the required shell. Alpine installation must install Bash before launching the manager.

The manager must isolate package-manager and init-system behavior behind shared adapters instead of duplicating operating-system branches in each feature module.

## 3. User Interface and Installation

Users install the project with one shell command. The bootstrap installer performs environment checks, downloads a fixed release manifest and module bundle, verifies SHA-256 checksums, and installs the manager under `/usr/local/lib/rs-manager/`.

The installer creates:

- `/usr/local/bin/rs` as the unified entry point.
- `/usr/local/bin/sb` as a compatibility shortcut to the Sing-box submenu.

The v1 `rs` main menu contains Sing-box management, Realm forwarding management, BBR/TCP tuning, basic diagnostics, migration, and service control.

### v1.0 Scope Boundary

The broader descriptions below are the target architecture, not a claim that every item ships in v1.0. Manager self-update commands, named snapshot/restore UI, full log and firewall diagnostics, credential regeneration, automated repair, and uninstall workflows are explicitly deferred until after v1.0. The v1 installer itself is rollback-safe when reinstalling or updating from a verified release bundle; automatic update orchestration is not yet exposed in `rs`.

## 4. Project Structure

The implementation will use these responsibility boundaries:

- `install.sh`: minimal bootstrap and verified release installation.
- `bin/rs`: command dispatcher and top-level menu.
- `lib/core/system.sh`: distribution, architecture, package manager, init system, privilege, and dependency detection.
- `lib/core/service.sh`: systemd and OpenRC service operations.
- `lib/core/validation.sh`: ports, addresses, names, paths, and common input validation.
- `lib/core/transaction.sh`: locking, candidate files, backups, atomic replacement, health checks, and rollback.
- `lib/core/state.sh`: manager metadata and migration records.
- `lib/modules/singbox.sh`: Sing-box installation, upgrade, instances, certificates, links, and service operations.
- `lib/modules/realm.sh`: Realm installation, upgrade, forwarding rules, and service operations.
- `lib/modules/tuning.sh`: BBR, queue discipline, TCP profiles, Realm-specific tuning, preview, and restore.
- `lib/modules/diagnostics.sh`: unified configuration, port, service, log, and kernel diagnostics.

Each module exposes command functions to `bin/rs` and does not directly invoke another module's interactive menu.

## 5. Configuration Ownership

Native service configuration remains authoritative:

- Sing-box: `/etc/sing-box/config.json`.
- Realm: `/root/.realm/config.toml`.

Manager-owned metadata is stored under `/etc/rs-manager/` and includes stable instance and forwarding-rule identifiers, names, migration history, backup indexes, tuning state, original runtime values, and information that cannot be reconstructed safely from native configuration.

The metadata must not replace native configuration or make the services unusable without the manager. Unknown or externally managed configuration entries are preserved and marked as external.

## 6. Existing Installation Migration

On first launch, the manager detects existing Sing-box and Realm installations. Before migration it creates a complete snapshot containing native configuration, certificates, legacy helper files, service definitions, and manager metadata if present.

Sing-box migration enumerates the actual `.inbounds[]` array instead of trusting legacy `ENABLE_*` Boolean flags. Known protocol entries are registered as managed instances while preserving their tags, ports, credentials, certificates, SNI values, and route references. Legacy `.protocols`, `.config_cache`, node-name, URI, and Reality-public-key files are used only as auxiliary recovery sources.

Realm migration parses existing TOML endpoints and assigns stable metadata identifiers without rewriting the configuration unless a later user action requires it. Entries that cannot be mapped safely remain unchanged and are reported as external.

## 7. Sing-box Instance Model

Sing-box management is based on protocol instances, not one Boolean flag per protocol. Managed protocols are Shadowsocks, Hysteria2, TUIC, VLESS Reality, and AnyTLS Reality.

Every new instance receives a stable identifier and unique tag such as `rs-ss-a1b2`. An instance stores its protocol-specific settings independently, including port, credentials, certificate references, SNI, Reality key material, short ID, link name, and custom connection address.

The submenu supports:

- Adding a protocol after initial installation.
- Listing all instances and their status.
- Viewing and exporting one or all share links.
- Editing one selected instance.
- Regenerating selected credentials with explicit confirmation.
- Deleting one selected instance.
- Cloning an instance with a new port and credentials.

When an instance of the selected protocol already exists, the manager offers to edit it or create another instance. Multiple instances are supported but are not forced on simple users.

Port selection checks Sing-box configuration, Realm listeners, system listeners, and other candidate changes. Generated tags must be unique. Reality instances do not share global key or SNI variables. HY2 and TUIC may reuse a manager certificate or reference user-supplied certificate files; existing certificates are never overwritten silently.

Custom inbounds, outbounds, routes, DNS settings, and experimental fields are preserved during managed changes.

## 8. Realm Management and Sing-box Assistance

Realm retains full independent management. Supported actions are:

- Install, upgrade, uninstall, start, stop, restart, and inspect Realm.
- Add, edit, disable, enable, and delete a single forwarding rule.
- Add a sequential port range.
- List rules with stable IDs, targets, and listener status.
- Create a forwarding rule from a supported Sing-box share link by extracting its host and port.
- Select a local Sing-box instance as a target to prefill its port.

Associations between Realm rules and Sing-box instances are advisory metadata. Deleting an associated instance displays the affected rules and requires an explicit decision. It does not silently delete or rewrite forwarding rules.

Realm and Sing-box use one shared port-conflict detector. The implementation must respect Realm's TOML format and current configuration path; it must not apply JSON-specific transformations from unrelated Realm scripts.

## 9. Transactional Configuration Changes

Every managed configuration mutation follows this transaction:

1. Acquire a process lock.
2. Create a timestamped backup.
3. Generate a candidate configuration in a permission-restricted directory created with `mktemp`.
4. Validate syntax, stable identifiers, tags, ports, references, and required fields.
5. Run `sing-box check` for Sing-box candidates.
6. Atomically replace the native configuration.
7. Restart or reload the affected service.
8. Verify service health and expected listeners.
9. Restore the previous configuration and service state if validation or health checks fail.

Automatic backups retain the most recent ten snapshots. Users may create named snapshots excluded from automatic rotation. Restores display affected files before applying them.

No credential or private key may be printed in diagnostic logs unless the user explicitly requests the corresponding share link or configuration view.

## 10. BBR and TCP Tuning

Tuning is optional and separate from service installation. Initial setup does not replace the kernel or alter firewall, DNS, SSH, or reboot state.

The status page shows the running kernel, available and active congestion-control algorithms, active queue discipline, relevant TCP/UDP buffers, connection-tracking capacity, and whether a reboot is required.

The tuning menu supports:

1. Enable kernel-provided BBR with `fq` when supported.
2. Preview and apply low-memory, standard, or high-bandwidth TCP profiles.
3. Apply Realm-specific connection-tracking, file-descriptor, and keepalive tuning.
4. Display the exact parameter diff before writing.
5. Restore the state captured before manager tuning.
6. Optionally install XanMod/BBR v3 on supported Debian or Ubuntu systems.

CentOS/RHEL and Alpine use their current kernel's supported congestion control. Debian kernel packages are never installed on those systems. XanMod installation requires a second confirmation, validates distribution and architecture support, verifies repository keys and package availability, and never reboots automatically.

Manager sysctl settings live only in `/etc/sysctl.d/99-rs-manager.conf`. Existing `/etc/sysctl.conf` and unrelated sysctl files are not edited. Restore removes or replaces only manager-owned settings and reapplies captured previous runtime values where possible.

TCP profile sizes use conservative fixed bounds. v1 writes `net.core.default_qdisc=fq`, which affects newly created interfaces/qdiscs; it deliberately does not replace the qdisc already attached to the active interface because an exact reversible hierarchy restore is not portable. MSS clamping is not enabled by default.

Realm-specific tuning must not force IPv4-only listeners or transform Realm TOML. It may manage connection tracking, service file-descriptor limits, and conservative keepalive values through manager-owned files.

Substantial concepts adapted from `Eric86777/vps-tcp-tune` must retain the upstream MIT attribution and license notice.

## 11. Diagnostics and Safety

Diagnostics include:

- Sing-box and Realm versions, service states, listeners, and recent logs.
- Sing-box JSON validation and Realm TOML structure checks.
- Duplicate ports, occupied ports, invalid targets, duplicate tags, and broken references.
- Share-link regeneration checks.
- BBR, queue discipline, connection tracking, and file-descriptor checks.
- Firewall detection and explanatory warnings without automatic changes.
- A sanitized support report that removes passwords, UUIDs, tokens, private keys, certificate secrets, and public connection addresses when requested.

Safe repair handles only deterministic issues such as missing manager directories, stale metadata, invalid permissions, or a stopped service with valid configuration. Kernel changes, firewall changes, destructive configuration changes, and credential regeneration always require separate confirmation.

Downloads use HTTPS, restricted temporary directories, fixed release manifests, and checksum verification. Self-update creates a snapshot and restores the previous manager version if installation fails.

## 12. Uninstall Behavior

Removing RS Manager defaults to preserving Sing-box, Realm, native configuration, certificates, and backups. Users may separately uninstall either service. Destructive service removal shows the exact directories and service files to be removed and requires confirmation.

The manager removes only files it owns. Tuning removal restores captured settings and removes manager-owned sysctl and service override files.

## 13. Testing Strategy

Automated Bash tests use temporary filesystem roots and fake external commands. They must not write to the host `/etc`, manipulate the host kernel, or restart real services.

Tests cover:

- Distribution, package-manager, architecture, and init-system detection.
- Port, address, name, and path validation.
- Sing-box instance creation, editing, deletion, cloning, migration, unique tags, and links.
- Preservation of custom Sing-box fields.
- Realm rule creation, editing, disabling, deletion, range generation, and migration.
- Cross-service port conflicts and advisory associations.
- Candidate validation, atomic replacement, backup rotation, failed health checks, and rollback.
- Sysctl profile generation, preview, ownership boundaries, and restore.
- Secret redaction in diagnostics.

ShellCheck is required. Compatibility tests run in Debian, Ubuntu, Rocky Linux, and Alpine containers with mocked service managers. Real service lifecycle, network tuning, and kernel replacement receive a separate disposable-VM acceptance checklist.

## 14. First-Release Scope

The first release includes:

- Unified `rs` command and `sb` compatibility command.
- Five managed Sing-box protocols with post-install addition and optional multi-instance support.
- Existing Sing-box and Realm configuration migration.
- Realm single-rule, range, and enable/disable management.
- Transactional backup, validation, health check, and rollback.
- BBR plus a default-`fq` setting, three TCP profiles, Realm-specific tuning, preview, and restore.
- Basic redacted diagnostics and service control. Manager self-update commands are post-v1.
- Debian/Ubuntu, CentOS/RHEL-compatible distributions, and Alpine support through systemd or OpenRC.

The first release excludes:

- Web management.
- Named snapshot/restore UI, full log/firewall reports, credential regeneration, automated repair, and uninstall commands.
- Subscription hosting, accounts, traffic billing, quotas, and expiration automation.
- Automatic VPS reboot.
- Unconfirmed firewall, SSH, DNS, or kernel changes.

## 15. Success Criteria

The design is successful when an existing user can install RS Manager, retain current Sing-box and Realm services, add a previously omitted protocol from the `sb` menu, validate and start the new configuration, export all links, and recover automatically from an invalid change.

A fresh user must be able to install and manage both services from `rs` on every supported distribution family. Tuning must be optional, previewable, attributable, and reversible. Unknown existing configuration must survive all supported managed operations unchanged.
