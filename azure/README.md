# Mach5 Deployment Scripts

This repo contains shell scripts to provision Mach5 infrastructure on AKS and install Mach5 Helm charts, then perform the initial Mach5 Search setup (store, store route, and warehouse).

## Prerequisites

- Azure CLI (`az`) logged in to the target subscription.
- `kubectl` client installed.
- `helm` v3.x installed.
- A Mach5 reader key JSON file at `reader-key.json` (or update `MACH5_READER_KEY_PATH`).

Azure vCPU quota (East US): based on the current `configs/mach5.env` minimums, the baseline requires 24 vCPUs total.

| Nodepool | VM Size | Desired Count | vCPUs Each | Total vCPUs |
| --- | --- | --- | --- | --- |
| main | Standard_D4s_v4 | 2 | 4 | 8 |
| fdbnode | Standard_DS3_v2 | 2 | 4 | 8 |
| ingestnode | Standard_D2ads_v6 | 0 | 2 | 0 |
| compactnode | Standard_D2ads_v6 | 0 | 2 | 0 |
| whworkernode | Standard_D4ads_v6 | 1 | 4 | 4 |
| whheadnode | Standard_D4ads_v6 | 1 | 4 | 4 |

## Configure Before You Run

Edit `configs/mach5.env` and update the values for your environment. Review the rest of the file as well to tailor settings to your needs.

- Azure / AKS
  - `RESOURCE_GROUP`
  - `LOCATION`
  - `AKS_CLUSTER_NAME`

- Storage (used for both Azure and Mach5 Search store)
  - `STORAGE_ACCOUNT_NAME`
  - `STORAGE_ACCOUNT_RESOURCE_GROUP`
  - `STORAGE_CONTAINER_NAME`

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
  - `license.token` (Change this only when the cluster and nodepools are created and the script prompts you to update this)
  - `metadatadb.name`
  - `metadatadb.host`
  - `metadatadb.port`
  - `metadatadb.user`
  - `metadatadb.password`

## End-to-End Mach5 Setup

```bash
./scripts/setup-mach5.sh
```

This script creates the full Mach5 environment by running:
- `./scripts/mach5-infrastructure.sh` to provision the AKS cluster and nodepools (it pauses if `license.token` is still `CHANGE_ME` and prints the `kube-system` namespace UID).
- `./scripts/mach5-helm.sh` to install cert-manager, cache-proxy, and Mach5 Search, then set up the initial store, store route, and warehouse.

## Useful URLs (printed after install)

- Dashboards:
  - `http://localhost:8888/warehouse/default/m5warehouse/dashboards/`
- OpenSearch-compatible API:
  - `http://localhost:8888/warehouse/default/m5warehouse/opensearch/`

These URLs use `MACH5_STORE_LOCAL_PORT`. If you change that, the script will print the updated URLs.

## Cleanup

```bash
./scripts/cleanup-mach5.sh
```

This script tears down the Mach5 setup by removing deployed Kubernetes resources and related Azure infrastructure.
