# Mach5 Deployment Scripts

This repo contains shell scripts to provision Mach5 infrastructure on AKS and install Mach5 Helm charts, then perform the initial Mach5 Search setup (store, store route, and warehouse).

## Prerequisites

- Azure CLI (`az`) logged in to the target subscription.
- `jq` insalled.
- `helm` installed.
- A Mach5 reader key JSON file at `reader-key.json` (or update `MACH5_READER_KEY_PATH`).

## Configure Before You Run

Edit `configs/mach5.env` and update these values for your environment:

- Azure / AKS
  - `RESOURCE_GROUP`
  - `LOCATION`
  - `AKS_CLUSTER_NAME`
  - `KUBERNETES_VERSION`
  - `SERVICE_CIDR`, `DNS_SERVICE_IP` (if you need custom networking)

- Storage (used for both Azure and Mach5 Search store)
  - `STORAGE_ACCOUNT_NAME`
  - `STORAGE_ACCOUNT_RESOURCE_GROUP`
  - `STORAGE_CONTAINER_NAME`

- Node pools
  - `MAIN_NODEPOOL_*`
  - `NODEPOOLS` (size/count/labels for specialized roles)

- Helm charts / registry
  - `MACH5_ARTIFACT_REGISTRY`
  - `MACH5_ARTIFACT_REGISTRY_URL`
  - `MACH5_CACHE_PROXY_VERSION`
  - `MACH5_SEARCH_VERSION`
  - `MACH5_READER_KEY_PATH`

- Mach5 Search store + access
  - `MACH5_STORE_NAME`
  - `MACH5_STORE_PREFIX`
  - `MACH5_STORE_TYPE`
  - `MACH5_NGINX_SERVICE_NAME`
  - `MACH5_NGINX_PORT`
  - `MACH5_STORE_LOCAL_PORT`
  - `MACH5_STORE_ROUTE_PATTERN`
  - `MACH5_STORE_ROUTE_PRIORITY`

Mach5 configuration files:
- `values/values_aks.yaml` (Mach5 Search Helm values)
- `values/values_cp.yaml` (cache-proxy Helm values)
- `values/values_cm.yaml` (cert-manager Helm values)

## Update CHANGE_ME Fields In `values/*`

Some Helm values files include placeholders marked as `CHANGE_ME`. Update these before running installs:

- `values/values_cp.yaml`
  - `imagePullSecrets.dockerconfigjson` (image pull secret for Mach5 registry)

- `values/values_aks.yaml`
  - `imagePullSecrets.dockerconfigjson` (image pull secret for Mach5 registry)
  - `license.token`
  - `metadatadb.name`
  - `metadatadb.host`
  - `metadatadb.port`
  - `metadatadb.user`
  - `metadatadb.password`

## Scripts

### 1) Infrastructure Only

```bash
./scripts/deploy-mach5.sh
```

After the cluster and nodepools are created, this script checks `license.token` in `values/values_aks.yaml`. If it is still `CHANGE_ME`, it prints the `kube-system` namespace UID and stops. Send that UID to the Mach5 administrator to generate a license. Once you receive the license, update `license.token` in `values/values_aks.yaml` and rerun the script; it will continue automatically.

Options:
- `-v` / `--verbose`
- `--dry-run`
- `--config PATH` (custom env file)

### 2) Helm Install + Mach5 Search Setup

```bash
./scripts/install-mach5-helm.sh
```

This script:
- Pulls AKS credentials
- Installs cert-manager, cache-proxy, and Mach5 Search
- Waits for Mach5 pods to be ready
- Port-forwards the Mach5 Search nginx service to `localhost:$MACH5_STORE_LOCAL_PORT`
- Creates the store, store route, and warehouse
- Prints the dashboards and OpenSearch-compatible URLs

The port-forward is left running. The script prints commands to stop and recreate it.

### 3) Full Deployment

```bash
./scripts/deploy-full-mach5.sh
```

This script orchestrates the full flow and runs both the infrastructure deployment and the Helm install steps.

## Useful URLs (printed after install)

- Dashboards:
  - `http://localhost:8888/warehouse/default/m5warehouse/dashboards/`
- OpenSearch-compatible API:
  - `http://localhost:8888/warehouse/default/m5warehouse/opensearch/`

These URLs use `MACH5_STORE_LOCAL_PORT`. If you change that, the script will print the updated URLs.
