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
Once the infrastructure is created, run the following command to configure kubectl so that you can connect to an Amazon EKS cluster locally and install helm-charts in the cluster:
````
aws eks --region us-east-1 update-kubeconfig --name <cluster-name>
````
Sample: 
````
aws eks --region us-east-1 update-kubeconfig --name mach5-cluster
````

#### License Setup
A license token is required to install Mach5. Please follow the instructions at https://mach5.io/docs/licensetokensetupguide  and provide the requested details to the Mach5 Administrator to obtain your license.
Once you receive the token, update this token into the license.token parameter in the values.yaml file.
Run the following commands to update the Mach5 installation with the license token:
````
terraform apply
Type yes to proceed with the update
````
Once this update is complete, you are ready to initialize and access Mach5 Search.

- This could take anywhere around 20-30 minutes to bring up the infrastructure and install the Mach5 Search charts.

### Teardown
- Bring down the cluster using:
````
terraform destroy
````