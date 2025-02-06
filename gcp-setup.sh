#!/bin/bash

# run the following command to execute this script
# wget -qO- https://raw.githubusercontent.com/Findings-co/gcp-cloudvrm/refs/heads/main/gcp-setup.sh | bash

# Set variables
SERVICE_ACCOUNT_NAME="FindingsCloudVRM"
ORG_ID=$(gcloud organizations list --format="value(ID)")
PROJECT_ID=$(gcloud config get-value project)
SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"
KEY_FILE="gcp_findings_cloudvrm.json"

# Function to handle errors
echo_error() {
  echo -e "\e[31m[ERROR]\e[0m $1"
}

echo_success() {
  echo -e "\e[32m[SUCCESS]\e[0m $1"
}

echo_info() {
  echo -e "\e[34m[INFO]\e[0m $1"
}

# Check for --uninstall flag
if [[ "$1" == "--uninstall" ]]; then
  echo_info "Uninstalling service account: $SERVICE_ACCOUNT_NAME..."
  
  echo_info "Removing IAM policy bindings..."
  gcloud organizations remove-iam-policy-binding $ORG_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/securitycenter.findingsViewer"
  gcloud organizations remove-iam-policy-binding $ORG_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
    --role="roles/viewer"
  
  echo_info "Deleting service account..."
  if gcloud iam service-accounts delete $SERVICE_ACCOUNT_EMAIL --quiet; then
    echo_success "Service account deleted successfully."
  else
    echo_error "Failed to delete service account."
  fi
  
  echo_info "Removing key file..."
  rm -f $KEY_FILE && echo_success "Key file removed."
  
  echo_success "Uninstallation complete."
  exit 0
fi

# Retrieve and display the Organization ID
echo_info "Retrieved Organization ID: $ORG_ID"

# Get the active project ID
echo_info "Active Project ID: $PROJECT_ID"

# Create a new service account
echo_info "Creating service account: $SERVICE_ACCOUNT_NAME..."
if ! gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME --display-name "Findings CloudVRM"; then
  echo_error "Service account ID '$SERVICE_ACCOUNT_NAME' already exists or another error occurred."
  exit 1
fi

echo_success "Service account '$SERVICE_ACCOUNT_NAME' created successfully."

# Assign Security Center Findings Viewer role to the service account
echo_info "Assigning Security Center Findings Viewer role..."
if gcloud organizations add-iam-policy-binding $ORG_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
  --role="roles/securitycenter.findingsViewer"; then
  echo_success "Security Center Findings Viewer role assigned."
else
  echo_error "Failed to assign Security Center Findings Viewer role."
fi

# Assign Viewer role to the service account
echo_info "Assigning Viewer role..."
if gcloud organizations add-iam-policy-binding $ORG_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT_EMAIL" \
  --role="roles/viewer"; then
  echo_success "Viewer role assigned."
else
  echo_error "Failed to assign Viewer role."
fi

# Generate and download the service account key
echo_info "Generating service account key: $KEY_FILE..."
if gcloud iam service-accounts keys create $KEY_FILE --iam-account=$SERVICE_ACCOUNT_EMAIL; then
  echo_success "Service account key generated successfully."
else
  echo_error "Failed to generate service account key."
  exit 1
fi

# Enable Security Command Center API
echo_info "Enabling Security Command Center API..."
if gcloud services enable securitycenter.googleapis.com; then
  echo_success "Security Command Center API enabled."
else
  echo_error "Failed to enable Security Command Center API."
  exit 1
fi

# Installation summary
echo -e "\n\e[32m=========================\e[0m"
echo -e "\e[32m Installation Summary \e[0m"
echo -e "\e[32m=========================\e[0m"
echo_success "Setup completed successfully!"
echo_info "Organization ID: $ORG_ID"
echo_info "Service account: $SERVICE_ACCOUNT_EMAIL"
echo_info "To download the key file, use: \e[33mcat $KEY_FILE\e[0m or click on the three dots in the Cloud Shell menu and select 'Download'."
echo -e "\e[32m=========================\e[0m"

