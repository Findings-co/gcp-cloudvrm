#!/bin/bash
# run this script from Cloud Shell:
# wget -qO- https://raw.githubusercontent.com/Findings-co/gcp-cloudvrm/refs/heads/main/gcp-setup.sh | bash

# Check for gcloud CLI
command -v gcloud >/dev/null || { echo "Error: gcloud CLI is not installed."; exit 1; }

BASE_SA_NAME="FindingsCloudVRM"
SERVICE_ACCOUNT_NAME=""
PROJECT_ID=""
ORG_ID=""
UNINSTALL=false

usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  --service-account-name NAME   Specify the service account name"
  echo "  --project PROJECT_ID          Specify the GCP project ID (default: gcloud config get-value project)"
  echo "  --org-id ORG_ID               Specify the GCP organization ID (default: first listed org)"
  echo "  --uninstall                   Uninstall the specified service account (requires --service-account-name)"
  echo "  --help, -h                    Show this help message"
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service-account-name)
      if [[ $# -lt 2 ]]; then echo "Error: --service-account-name requires an argument."; usage; exit 1; fi
      SERVICE_ACCOUNT_NAME="$2"; shift 2;;
    --project)
      if [[ $# -lt 2 ]]; then echo "Error: --project requires an argument."; usage; exit 1; fi
      PROJECT_ID="$2"; shift 2;;
    --org-id)
      if [[ $# -lt 2 ]]; then echo "Error: --org-id requires an argument."; usage; exit 1; fi
      ORG_ID="$2"; shift 2;;
    --uninstall)
      UNINSTALL=true; shift;;
    --help|-h)
      usage; exit 0;;
    *)
      echo "Unknown option: $1"; usage; exit 1;;
  esac
done

check_sa_exists() {
  gcloud iam service-accounts list \
    --filter="email:${SERVICE_ACCOUNT_EMAIL}" \
    --format="value(email)" | grep -q .
}

uninstall_sa() {
  if [[ -z "$SERVICE_ACCOUNT_NAME" ]]; then
    echo "❌ ERROR: --uninstall requires --service-account-name"
    usage
    exit 1
  fi

  [[ -z "$PROJECT_ID" ]] && PROJECT_ID=$(gcloud config get-value project)

  if [[ "$SERVICE_ACCOUNT_NAME" == *@* ]]; then
    SERVICE_ACCOUNT_EMAIL="$SERVICE_ACCOUNT_NAME"
  else
    SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  fi

  [[ -z "$ORG_ID" ]] && ORG_ID=$(gcloud organizations list --format="value(ID)" --limit=1)

  echo "Removing SCC findingsViewer binding for ${SERVICE_ACCOUNT_EMAIL}…"
  FOUND=$(gcloud organizations get-iam-policy "$ORG_ID" \
    --flatten="bindings[].members" \
    --filter="bindings.role=roles/securitycenter.findingsViewer AND bindings.members:serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --format="value(bindings.role)")
  if [[ -n "$FOUND" ]]; then
    gcloud organizations remove-iam-policy-binding "$ORG_ID" \
      --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
      --role="roles/securitycenter.findingsViewer"
    echo "✔️  Removed findingsViewer."
  else
    echo "— No findingsViewer binding found, skipping."
  fi

  echo "Deleting service account ${SERVICE_ACCOUNT_EMAIL}…"
  gcloud iam service-accounts delete "${SERVICE_ACCOUNT_EMAIL}" --quiet || {
    echo "❌ ERROR: Failed to delete service account."
    exit 1
  }

  KEY_FILE="$(basename "${SERVICE_ACCOUNT_EMAIL%@*}")-key.json"
  echo "Removing key file ${KEY_FILE}…"
  rm -f "${KEY_FILE}" || echo "⚠️ Warning: Could not remove key file."

  echo "✅ Uninstallation complete."
  exit 0
}

install_sa() {
  [[ -z "$SERVICE_ACCOUNT_NAME" ]] && SERVICE_ACCOUNT_NAME="${BASE_SA_NAME}-$(tr -dc 'a-z0-9' </dev/urandom | head -c 8)"
  [[ -z "$PROJECT_ID" ]] && PROJECT_ID=$(gcloud config get-value project)
  [[ -z "$ORG_ID" ]] && ORG_ID=$(gcloud organizations list --format="value(ID)" --limit=1)
  SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
  KEY_FILE="${SERVICE_ACCOUNT_NAME}-key.json"

  echo "Creating service account ${SERVICE_ACCOUNT_NAME} in project ${PROJECT_ID}..."
  gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="Findings CloudVRM" || { echo "❌ ERROR: Could not create service account."; exit 1; }

  echo "Assigning Security Center Findings Viewer role..."
  gcloud organizations add-iam-policy-binding "${ORG_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/securitycenter.findingsViewer" || { echo "❌ ERROR: Failed to bind findingsViewer."; exit 1; }

  echo "Generating service account key ${KEY_FILE}..."
  gcloud iam service-accounts keys create "${KEY_FILE}" \
    --iam-account="${SERVICE_ACCOUNT_EMAIL}" || { echo "❌ ERROR: Failed to generate key."; exit 1; }

  echo "Enabling Security Command Center API..."
  gcloud services enable securitycenter.googleapis.com \
    --project="${PROJECT_ID}" || { echo "❌ ERROR: Failed to enable API."; exit 1; }

  echo -e "
Installation Summary
===================="
  echo "Service Account Email: ${SERVICE_ACCOUNT_EMAIL}"
  echo "Organization ID: ${ORG_ID}"
  echo "Key File: ${KEY_FILE}"
  echo
  echo "To download the key file from Cloud Shell, run:"
  echo "  cloudshell download ${KEY_FILE}"
  echo "Or click the three dots in the Cloud Shell window and select 'Download'."
  echo "✅ Setup completed successfully."
}

# Main logic
if [[ "${UNINSTALL}" == true ]]; then
  uninstall_sa
else
  install_sa
fi
