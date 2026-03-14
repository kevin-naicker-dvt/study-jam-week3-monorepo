#!/usr/bin/env bash
# =============================================================================
# GCP Resource Teardown Script
# Deletes all resources created by setup-gcp.sh
# Use with caution — this is destructive!
# =============================================================================

set -euo pipefail

PROJECT_ID="dvt-lab-devfest-2025"
REGION="africa-south1"
REPO_NAME="studyjam-repo"
DB_INSTANCE="studyjam-db"
SA_NAME="studyjam-cloudrun-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${RED}WARNING: This will DELETE all Study Jam GCP resources!${NC}"
read -rp "Type 'DELETE' to confirm: " CONFIRM
[ "${CONFIRM}" = "DELETE" ] || { echo "Cancelled."; exit 0; }

gcloud config set project "${PROJECT_ID}"

echo -e "${YELLOW}Deleting Cloud Run services...${NC}"
gcloud run services delete studyjam-backend --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud run services delete studyjam-frontend --region="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

echo -e "${YELLOW}Deleting Cloud Build trigger...${NC}"
gcloud builds triggers delete studyjam-deploy --project="${PROJECT_ID}" --quiet 2>/dev/null || true

echo -e "${YELLOW}Deleting Artifact Registry repository...${NC}"
gcloud artifacts repositories delete "${REPO_NAME}" \
  --location="${REGION}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

echo -e "${YELLOW}Deleting Cloud SQL instance...${NC}"
gcloud sql instances delete "${DB_INSTANCE}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

echo -e "${YELLOW}Deleting Secret Manager secrets...${NC}"
gcloud secrets delete studyjam-db-password --project="${PROJECT_ID}" --quiet 2>/dev/null || true
gcloud secrets delete studyjam-jwt-secret --project="${PROJECT_ID}" --quiet 2>/dev/null || true

echo -e "${YELLOW}Deleting service account...${NC}"
gcloud iam service-accounts delete "${SA_EMAIL}" --project="${PROJECT_ID}" --quiet 2>/dev/null || true

echo -e "${GREEN}Teardown complete.${NC}"
