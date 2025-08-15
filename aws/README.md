# Mach5 Search EKS Deployment

## Overview

This repository provides the resources and instructions required to deploy Mach5 Search through the AWS Marketplace.

## Prerequisites

- Subscribe to Mach5 Search on the AWS Marketplace: https://aws.amazon.com/marketplace/pp/prodview-4cv3wvxzbopfm

## Steps to setup Mach5 Search EKS deployment

- Create a copy of `config.default.yaml` and name it `config.yaml`. This file includes all the configuration parameters required for setting up the cluster. Review the list of parameters to see if you need to modify any of them.
- To provision the infrastructure and install Mach5 Search, run following command

### Deployment using Terraform
````
bash setup-mach5-cluster.sh
````
### Deployment using eksctl
````
bash setup-mach5-cluster.sh eksctl
````

This will take around 30-40 minutes to bring up the complete infrastructure. Once the installation is successful, you can access:
- Mach5 Search Administrative UI at: http://localhost:8888/
- Dashboards at: http://localhost:8888/warehouse/default/getting-started/dashboards/
- Opensearch-compatible APIs at: http://localhost:8888/warehouse/default/getting-started/opensearch/

## Tearing Down the Infrastructure
To destroy the infrastructure and cleanup up resources, run:
````
bash destroy-mach5-cluster.sh
````