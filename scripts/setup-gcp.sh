#!/usr/bin/env bash
# =============================================================================
# GCP Resource Setup Script — Option 2 (Automated via gcloud)
# Project: dvt-lab-devfest-2025 | Region: africa-south1
#
# Usage:
#   chmod +x scripts/setup-gcp.sh
#   ./scripts/setup-gcp.sh
#
# Prerequisites:
#   - gcloud CLI installed and authenticated: gcloud auth login
#   - Sufficient permissions (Owner or Editor) on the project
# =============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
PROJECT_ID="dvt-lab-devfest-2025"
PROJECT_NUMBER="882266340372"
REGION="africa-south1"
REPO_NAME="studyjam-repo"
DB_INSTANCE="studyjam-db"
DB_NAME="studyjam"
DB_USER="studyjam_user"
SA_NAME="studyjam-cloudrun-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
CLOUD_BUILD_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }

# ── Validate gcloud is authenticated ──────────────────────────────────────────
info "Checking gcloud authentication..."
gcloud config set project "${PROJECT_ID}"
CURRENT_PROJECT=$(gcloud config get-value project)
[ "${CURRENT_PROJECT}" = "${PROJECT_ID}" ] || error "Failed to set project to ${PROJECT_ID}"
success "Project set to ${PROJECT_ID}"

# ── Step 1: Enable APIs ────────────────────────────────────────────────────────
info "Enabling required GCP APIs..."
APIS=(
  "cloudbuild.googleapis.com"
  "run.googleapis.com"
  "artifactregistry.googleapis.com"
  "sqladmin.googleapis.com"
  "secretmanager.googleapis.com"
  "cloudresourcemanager.googleapis.com"
  "iam.googleapis.com"
  "servicenetworking.googleapis.com"
)
gcloud services enable "${APIS[@]}" --project="${PROJECT_ID}"
success "APIs enabled"

# ── Step 2: Create Artifact Registry ──────────────────────────────────────────
info "Creating Artifact Registry repository: ${REPO_NAME}..."
if gcloud artifacts repositories describe "${REPO_NAME}" \
    --location="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
  warn "Artifact Registry '${REPO_NAME}' already exists — skipping"
else
  gcloud artifacts repositories create "${REPO_NAME}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="Study Jam Week 3 Docker images" \
    --project="${PROJECT_ID}"
  success "Artifact Registry created: ${REPO_NAME}"
fi

# ── Step 3: Create Cloud SQL instance ─────────────────────────────────────────
info "Creating Cloud SQL PostgreSQL instance: ${DB_INSTANCE}..."

# Prompt for DB password securely
read -rsp "Enter DB password for user '${DB_USER}': " DB_PASSWORD
echo
[ -n "${DB_PASSWORD}" ] || error "DB password cannot be empty"

if gcloud sql instances describe "${DB_INSTANCE}" --project="${PROJECT_ID}" &>/dev/null; then
  warn "Cloud SQL instance '${DB_INSTANCE}' already exists — skipping creation"
else
  gcloud sql instances create "${DB_INSTANCE}" \
    --database-version=POSTGRES_15 \
    --tier=db-f1-micro \
    --region="${REGION}" \
    --network=default \
    --no-assign-ip \
    --root-password="${DB_PASSWORD}" \
    --project="${PROJECT_ID}"
  success "Cloud SQL instance created: ${DB_INSTANCE}"
fi

# Create database
info "Creating database: ${DB_NAME}..."
gcloud sql databases create "${DB_NAME}" \
  --instance="${DB_INSTANCE}" \
  --project="${PROJECT_ID}" 2>/dev/null || warn "Database '${DB_NAME}' may already exist"
success "Database ready: ${DB_NAME}"

# Create DB user
info "Creating database user: ${DB_USER}..."
gcloud sql users create "${DB_USER}" \
  --instance="${DB_INSTANCE}" \
  --password="${DB_PASSWORD}" \
  --project="${PROJECT_ID}" 2>/dev/null || warn "User '${DB_USER}' may already exist"
success "Database user ready: ${DB_USER}"

# Get Cloud SQL private IP
DB_HOST=$(gcloud sql instances describe "${DB_INSTANCE}" \
  --project="${PROJECT_ID}" \
  --format='value(ipAddresses[0].ipAddress)' 2>/dev/null || echo "")
info "Cloud SQL IP: ${DB_HOST}"

# ── Step 4: Store Secrets in Secret Manager ───────────────────────────────────
info "Creating Secret Manager secrets..."

# DB Password secret
if gcloud secrets describe "studyjam-db-password" --project="${PROJECT_ID}" &>/dev/null; then
  warn "Secret 'studyjam-db-password' already exists — adding new version"
  echo -n "${DB_PASSWORD}" | gcloud secrets versions add "studyjam-db-password" \
    --data-file=- --project="${PROJECT_ID}"
else
  echo -n "${DB_PASSWORD}" | gcloud secrets create "studyjam-db-password" \
    --data-file=- \
    --replication-policy=user-managed \
    --locations="${REGION}" \
    --project="${PROJECT_ID}"
  success "Secret created: studyjam-db-password"
fi

# JWT Secret
JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')
if gcloud secrets describe "studyjam-jwt-secret" --project="${PROJECT_ID}" &>/dev/null; then
  warn "Secret 'studyjam-jwt-secret' already exists — adding new version"
  echo -n "${JWT_SECRET}" | gcloud secrets versions add "studyjam-jwt-secret" \
    --data-file=- --project="${PROJECT_ID}"
else
  echo -n "${JWT_SECRET}" | gcloud secrets create "studyjam-jwt-secret" \
    --data-file=- \
    --replication-policy=user-managed \
    --locations="${REGION}" \
    --project="${PROJECT_ID}"
  success "Secret created: studyjam-jwt-secret"
fi

# ── Step 5: Create Service Account for Cloud Run ──────────────────────────────
info "Creating service account: ${SA_NAME}..."
if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
  warn "Service account '${SA_NAME}' already exists — skipping"
else
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name="Study Jam Cloud Run Service Account" \
    --project="${PROJECT_ID}"
  success "Service account created: ${SA_EMAIL}"
fi

# Grant Cloud SQL Client role
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/cloudsql.client" --quiet
# Grant Secret Manager accessor role
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" --quiet
success "IAM roles granted to service account"

# ── Step 6: Grant Cloud Build permissions ─────────────────────────────────────
info "Granting permissions to Cloud Build service account..."
CLOUD_BUILD_ROLES=(
  "roles/run.admin"
  "roles/artifactregistry.writer"
  "roles/iam.serviceAccountUser"
  "roles/secretmanager.secretAccessor"
)
for ROLE in "${CLOUD_BUILD_ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role="${ROLE}" --quiet
done
success "Cloud Build permissions granted"

# ── Step 7: Create Cloud Build Trigger ────────────────────────────────────────
info "Creating Cloud Build trigger..."
TRIGGER_NAME="studyjam-deploy"

if gcloud builds triggers describe "${TRIGGER_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
  warn "Build trigger '${TRIGGER_NAME}' already exists — skipping"
else
  gcloud builds triggers create github \
    --name="${TRIGGER_NAME}" \
    --repo-name="study-jam-week3-monorepo" \
    --repo-owner="kevin-naicker-dvt" \
    --branch-pattern="^gcp/dev$" \
    --build-config="cloudbuild.yaml" \
    --substitutions="_REGION=${REGION},_REPO_NAME=${REPO_NAME},_BACKEND_SERVICE=studyjam-backend,_FRONTEND_SERVICE=studyjam-frontend,_DB_HOST=${DB_HOST},_DB_NAME=${DB_NAME},_DB_USER=${DB_USER},_DB_PASSWORD_NAME=studyjam-db-password,_JWT_SECRET_NAME=studyjam-jwt-secret" \
    --project="${PROJECT_ID}"
  success "Cloud Build trigger created: ${TRIGGER_NAME}"
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  GCP Setup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""
echo "Project ID:        ${PROJECT_ID}"
echo "Region:            ${REGION}"
echo "Artifact Registry: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"
echo "Cloud SQL:         ${DB_INSTANCE} (IP: ${DB_HOST})"
echo "Service Account:   ${SA_EMAIL}"
echo "Build Trigger:     ${TRIGGER_NAME}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Connect your GitHub repo in Cloud Build Console if not done"
echo "  2. Push to 'main' branch to trigger your first deployment"
echo "  3. Monitor at: https://console.cloud.google.com/cloud-build/builds?project=${PROJECT_ID}"
echo ""
echo -e "${YELLOW}Run DB migrations after first deploy:${NC}"
echo "  cd backend && npm run db:migrate"
