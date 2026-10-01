# timescaledb-cnpg

TimescaleDB extension image for [CloudNativePG](https://cloudnative-pg.io) `ImageVolume` built for both AMD64 and ARM64.

Minimal `FROM scratch` image containing only the TimescaleDB shared libraries, extension control file, and SQL migration scripts — mountable via Kubernetes [ImageVolume](https://kubernetes.io/docs/concepts/storage/volumes/#image) into a CNPG PostgreSQL pod.

Uses the **full Timescale-licensed package** from [Timescale's apt repo](https://packagecloud.io/timescale/timescaledb) (not the PGDG `+dfsg` repack which strips TSL code). Includes the TSL module required for compression, continuous aggregates, and other licensed features.

## Usage

Requires:
- Kubernetes ≥ 1.33 with `ImageVolume` feature gate enabled (beta/default in 1.35+)
- CloudNativePG ≥ 1.27
- PostgreSQL 18 (for `extension_control_path` GUC)

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-cluster
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18-minimal-trixie
  instances: 1
  storage:
    size: 10Gi
  postgresql:
    extensions:
      - name: timescaledb
        image:
          reference: ghcr.io/adampetrovic/timescaledb-cnpg:2.26.1-18-trixie
    shared_preload_libraries:
      - timescaledb
    parameters:
      timescaledb.license: "timescale"
      timescaledb.telemetry_level: "off"
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: my-cluster-app
spec:
  name: app
  owner: app
  cluster:
    name: my-cluster
  extensions:
    - name: timescaledb
      version: "2.26.1"
```

## How it works

Follows the pattern from [postgres-extensions-containers](https://github.com/cloudnative-pg/postgres-extensions-containers):

1. Installs `timescaledb-2-<version>-postgresql-18` (and the loader at the same version) from Timescale's packagecloud apt repository
2. Extracts the previous release's package (the newest stable release in the repo older than `<version>`, overridable with the `PREV_EXT_VERSION` build arg)
3. Copies only the extension files into a `FROM scratch` image:
   - `/lib/timescaledb.so` — loader module
   - `/lib/timescaledb-<version>.so` — core extension
   - `/lib/timescaledb-tsl-<version>.so` — TSL-licensed module (compression, caggs, etc.)
   - `/lib/timescaledb-<prev>.so`, `/lib/timescaledb-tsl-<prev>.so` — previous release's libraries
   - `/share/extension/timescaledb*` — control file + SQL scripts
   - `/licenses/` — copyright files
4. CNPG mounts the image via `ImageVolume` and configures `extension_control_path` + `dynamic_library_path`

### Upgrades

The loader loads `timescaledb-<installed version>.so` by filename, based on the version recorded in each database. Because the previous release's libraries ship alongside the current ones, a database still on the old version keeps working after the new image rolls out, until you run `ALTER EXTENSION timescaledb UPDATE` (or bump `version` on the CNPG `Database` resource). Only the current and the immediately preceding release are included, so don't skip more than one release between rollouts without updating the extension first.

## Image tags

```
ghcr.io/adampetrovic/timescaledb-cnpg:<tsdb_version>-<pg_major>-<debian_codename>
```

Example: `ghcr.io/adampetrovic/timescaledb-cnpg:2.26.1-18-trixie`

## Automated updates

[Renovate](https://github.com/renovatebot/renovate) monitors for new TimescaleDB releases and opens auto-merge PRs. On merge, GitHub Actions builds and publishes the updated image.
