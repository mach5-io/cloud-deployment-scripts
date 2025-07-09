## Steps to setup Mach5 Search EKS deployment using Terraform

### Prerequisites
- File values.yaml contains the configuration settings for the mach5-search helmcharts. Make necessary changes to this, as required.
  - Add a valid value for **mach5ImagePullSecret.dockerconfigjson**. Contact Mach5 Search administrator for this.
- File values_cp.yaml contains the configuration settings for the mach5-cache-proxy helmcharts. Make necessary changes to this, as required.
  - Add a valid value for **mach5ImagePullSecret.dockerconfigjson**, same as above. Contact Mach5 Search administrator for this.
- File variables.tf has all the variables declared with a default value. Specify values for fields marked as CHANGE_ME:
  - **artifact_registry_password**: Base64 encoded password key to access Mach5 Artifact registry. Contact Mach5 Search administrator for this.
  - **mach5_helm_chart_version**: Specify the exact helm chart version to install (Contact Mach5 Search administrator for the latest release version)
  - **artifact_registry_email**: GCP service account email to access Mach5 Artifact registry
  - **enable_cluster_autoscaling**: Specify whether you want to enable cluster autoscaling in the EKS cluster
  Change any other setting if needed in this file too.
- File values_ca.yaml contains the configuration settings for the EKS cluster-autoscaler helmcharts. Make necessary changes to this, as required.

### Running Terraform Scripts
- Bring up the EKS cluster using:
````
terraform init
terraform apply
````
- This could take anywhere around 20-30 minutes to bring up the infrastructure and install the Mach5 Search charts.
- Bring down the cluster using:
````
terraform destroy
````