# GCP Resource Setup Guide — Option 1 (Manual via Console)

> **Github Repo:** `https://github.com/kevin-naicker-dvt/study-jam-week3-monorepo`  
> **Project:** `dvt-lab-devfest-2025`  
> **Project Number:** `882266340372`  
> **Region:** `africa-south1`  
> **Console URL:** https://console.cloud.google.com/welcome?project=dvt-lab-devfest-2025

---

## Prerequisites

- A Google Cloud account with billing enabled
- Owner or Editor role on the project
- GitHub repository connected to GCP (see Step 0)

---

## Step 0 — Connect GitHub Repository to GCP

1. Go to **Cloud Build > Repositories** in the GCP Console
2. Click **Connect Repository**
3. Select **GitHub** as the source provider
4. Authenticate with GitHub and select your repository: `study-jam-week3-monorepo`
5. Click **Connect**

---

## Step 1 — Enable Required APIs

Go to **APIs & Services > Library** and enable:

| API | Purpose |
|-----|---------|
| Cloud Build API | CI/CD builds |
| Cloud Run API | Container hosting |
| Artifact Registry API | Docker image storage |
| Cloud SQL Admin API | Managed PostgreSQL |
| Secret Manager API | Secure secrets storage |
| Cloud Resource Manager API | Project management |

**How to enable:** Search for each API name → Click **Enable**

---

## Step 2 — Create Artifact Registry

1. Go to **Artifact Registry > Repositories**
2. Click **+ Create Repository**
3. Fill in:
   - **Name:** `studyjam-repo`
   - **Format:** Docker
   - **Mode:** Standard
   - **Location type:** Region → `africa-south1`
   - **Encryption:** Google-managed
4. Click **Create**

---

## Step 3 — Create Cloud SQL (PostgreSQL) Instance

1. Go to **SQL > Create Instance**
2. Select **PostgreSQL**
3. Fill in:
   - **Instance ID:** `studyjam-db`
   - **Password:** *(set a strong password — save it for Secret Manager)*
   - **Database version:** PostgreSQL 15
   - **Region:** `africa-south1`
   - **Zone:** Single zone (for cost savings)
4. Under **Machine type:** Choose `db-f1-micro` (for dev/testing)
5. Under **Connections:**
   - Enable **Private IP** (VPC: default)
   - Disable Public IP (for security)
6. Click **Create Instance** *(takes ~5 minutes)*

### Create the Database

1. Once the instance is running, click on `studyjam-db`
2. Go to **Databases > Create Database**
   - **Name:** `studyjam`
3. Go to **Users > Add User Account**
   - **Username:** `studyjam_user`
   - **Password:** *(set a strong password — save it)*
   - **Host:** `%` (any host)

---

## Step 4 — Store Secrets in Secret Manager

1. Go to **Secret Manager > Create Secret**

### Secret 1: DB Password
- **Name:** `studyjam-db-password`
- **Secret value:** *(the DB password you set above)*
- Click **Create Secret**

### Secret 2: JWT Secret
- **Name:** `studyjam-jwt-secret`
- **Secret value:** *(generate a strong random string, e.g. 64 chars)*
- Click **Create Secret**

> **Tip:** Generate a JWT secret: `openssl rand -base64 64`

---

## Step 5 — Create Service Account for Cloud Run

1. Go to **IAM & Admin > Service Accounts**
2. Click **+ Create Service Account**
3. Fill in:
   - **Name:** `studyjam-cloudrun-sa`
   - **Description:** Service account for Cloud Run services
4. Click **Create and Continue**
5. Grant these roles:
   - `Cloud SQL Client`
   - `Secret Manager Secret Accessor`
6. Click **Done**

---

## Step 6 — Grant Cloud Build Permissions

> **Note:** The Cloud Build service account is created automatically by GCP when the Cloud Build API is enabled. You do **not** need to create it manually. If you cannot see it, make sure the Cloud Build API is enabled (Step 1) and then wait ~30 seconds before refreshing.

1. Go to **IAM & Admin > IAM**
2. At the top of the member list, tick **"Include Google-provided role grants"** — this reveals system-managed accounts that are hidden by default
3. In the filter/search box, paste the Cloud Build service account email:
   {project-id}@cloudbuild.gserviceaccount.com
4. Click the **pencil (Edit principals)** icon on the right of that row
5. Click **+ Add Another Role** and add each of the following:
   - `Cloud Run Admin`
   - `Artifact Registry Writer`
   - `Service Account User`
   - `Secret Manager Secret Accessor`
6. Click **Save**

> **Tip:** If the account still does not appear, go to **Cloud Build > Settings** — this page lists all roles and lets you enable them with a single toggle, which is often easier than the IAM page.


## Step 7 — Create Cloud Build Trigger

1. Go to **Cloud Build > Triggers**
2. Click **+ Create Trigger**
3. Fill in:
   - **Name:** `studyjam-deploy`
   - **Event:** Push to a branch
   - **Repository:** `kevin-naicker-dvt/study-jam-week3-monorepo` (if not listed, click "Connect new repository" and authenticate with GitHub)
   - **Branch:** `^gcp/dev$` -- this is our GCP build branch, do not use MAIN
   - **Configuration:** Cloud Build configuration file (YAML)
   - **File location:** `cloudbuild.yaml`
4. Under **Substitution variables**, add:

   | Variable | Value |
   |----------|-------|
   | `_REGION` | `africa-south1` |
   | `_REPO_NAME` | `studyjam-repo` |
   | `_BACKEND_SERVICE` | `studyjam-backend` |
   | `_FRONTEND_SERVICE` | `studyjam-frontend` |
   | `_DB_HOST` | *(Cloud SQL private IP — see SQL instance page)* |
   | `_DB_NAME` | `studyjam` |
   | `_DB_USER` | `studyjam_user` |
   | `_DB_PASSWORD_NAME` | `studyjam-db-password` |
   | `_JWT_SECRET_NAME` | `studyjam-jwt-secret` |

5. Click **Create**

---

## Step 8 — Run Database Migrations

After the first deployment, run migrations manually:

1. Go to **Cloud Run > studyjam-backend**
2. Click **Edit & Deploy New Revision**
3. Override the command temporarily to: `node dist/database/migrate.js`
4. Deploy, then revert the command back to the default

> **Alternatively**, you can run migrations from your local machine using Cloud SQL Auth Proxy:
> ```bash
> ./cloud-sql-proxy dvt-lab-devfest-2025:africa-south1:studyjam-db &
> cd backend
> cp .env.example .env   # fill in DB_HOST=127.0.0.1 and credentials
> npm run db:migrate
> ```

---

## Step 9 — Trigger First Deployment

1. Push a commit to the `main` branch of your GitHub repository
2. Go to **Cloud Build > History** to monitor the build
3. Build steps:
   - Build backend image
   - Push backend to Artifact Registry
   - Deploy backend to Cloud Run
   - Health check backend (`/health` endpoint)
   - Build frontend image (with backend URL injected)
   - Push frontend to Artifact Registry
   - Deploy frontend to Cloud Run

---

## Step 10 — Access Your App

After deployment completes:

1. Go to **Cloud Run**
2. Click `studyjam-backend` → copy the URL (e.g. `https://studyjam-backend-xxxxx-uc.a.run.app`)
3. Click `studyjam-frontend` → copy the URL
4. Open the frontend URL in your browser

---

## Deployment Architecture

```
GitHub Push (main)
       │
       ▼
 GCP Cloud Build
       │
       ├─► Build Backend Docker Image
       │         │
       │         ▼
       │   Artifact Registry
       │   (africa-south1)
       │         │
       │         ▼
       │   Cloud Run: studyjam-backend
       │   (Health Check: /health)
       │
       ├─► Build Frontend Docker Image
       │   (VITE_API_URL injected from backend URL)
       │         │
       │         ▼
       │   Artifact Registry
       │         │
       │         ▼
       └─► Cloud Run: studyjam-frontend
                 │
                 ▼
           Users Browser
                 │ API calls
                 ▼
       Cloud Run: Backend API
                 │
                 ▼
       Cloud SQL: PostgreSQL
       (africa-south1)
```

---

## Cost Estimates (africa-south1)

| Resource | Tier | Est. Monthly Cost |
|----------|------|-------------------|
| Cloud Run (backend) | min-instances=0 | ~$0-5 |
| Cloud Run (frontend) | min-instances=0 | ~$0-5 |
| Cloud SQL | db-f1-micro | ~$10-15 |
| Artifact Registry | <1GB storage | ~$0-1 |
| Cloud Build | 120 free mins/day | ~$0 |

> **Note:** Costs scale with usage. Cloud Run scales to zero when not in use.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Build fails at push step | Check Artifact Registry permissions for Cloud Build SA |
| Backend fails health check | Check Cloud SQL IP in `_DB_HOST` variable |
| Frontend shows API errors | Verify `VITE_API_URL` in Cloud Run env vars |
| 403 Forbidden on Cloud Run | Ensure `--allow-unauthenticated` flag is set |
| DB connection refused | Check Cloud SQL Client role on service account |
