# GCP Resource Setup Guide — Option 1 (Manual via Console)

> **Github Repo:** `https://github.com/kevin-naicker-dvt/study-jam-week3-monorepo`  
> **Project:** `dvt-lab-devfest-2025`  
> **Project Number:** `882266340372`  
> **Region:** `africa-south1`  
> **Console URL:** https://console.cloud.google.com/welcome?project=dvt-lab-devfest-2025

---

## Prerequisites

- A Google Cloud account with billing enabled (free $300)
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

## Step 1 — Enable Required APIs (If Brand new cloud account + project)

Go to **APIs & Services > Library** and enable:

| API | Purpose |
|-----|---------|
| Cloud Build API | CI/CD builds |
| Cloud Run API | Container hosting |
| Artifact Registry API | Docker image storage |
| Cloud SQL Admin API | Managed PostgreSQL |
| Secret Manager API | Secure secrets storage |
| Cloud Resource Manager API | Project management |
| Serverless VPC Access API | VPC connector for Cloud Run → Cloud SQL |

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
2. Select **PostgreSQL (Sandbox)**
3. Fill in:
   - **Instance ID:** `studyjam-db`
   - **Password:** *(set a strong password — save it for Secret Manager)*
   - **Database version:** PostgreSQL 15
   - **Region:** `africa-south1`
   - **Zone:** Single zone (for cost savings)
4. Under **Machine type:** Choose `db-f1-micro` (cheapest for dev/testing)
5. Under **Connections:**
   - Enable **Private IP** (VPC: default)
   - Disable Public IP (for security)
6. Click **Create Instance** *(takes ~5 minutes)*
7. Once created, note the **Private IP address** (e.g. `10.74.0.3`) — you'll need it in Step 7

### Create the Database

1. Once the instance is running, click on `studyjam-db`
2. Go to **Databases > Create Database**
   - **Name:** `studyjam`
3. Go to **Users > Add User Account**
   - **Username:** `studyjam_user`
   - **Password:** *(set a strong password — save it)*
   - **Host:** `%` (any host)

---

## Step 4 — Create Serverless VPC Access Connector

> **Why this is required:** Cloud SQL is configured with a **private IP only** (no public IP). Cloud Run cannot reach private IPs without a VPC connector. Without this, every database query will silently time out after ~127 seconds.

1. Go to **VPC network > Serverless VPC Access**
2. Click **+ Create Connector**
3. Fill in:
   - **Name:** `vpc-studyjam-connector`
   - **Region:** `africa-south1`
   - **Network:** `default`
   - **Subnet:** Custom IP range
   - **IP range:** `10.8.0.0/28` *(must be an unused /28 range — this does not conflict with Cloud SQL's 10.74.x.x range)*
4. Click **Create** *(takes ~1–2 minutes)*

> **Verify:** The connector status should show **Ready** (green tick) before proceeding.

---

## Step 5 — Store Secrets in Secret Manager

1. Go to **Secret Manager > Create Secret**

### Secret 1: DB Password
- **Name:** `studyjam-db-password`
- **Secret value:** *(the DB password you set in Step 3)*
- Click **Create Secret**

### Secret 2: JWT Secret
- **Name:** `studyjam-jwt-secret`
- **Secret value:** *(generate a strong random string, e.g. 64 chars)*
- Click **Create Secret**

> **Tip:** Generate a JWT secret: `openssl rand -base64 64`

> **Deploying to GKE later?** Secret Manager stores the values, but **Kubernetes does not read Secret Manager by default.** The [GKE lab](./GKE-SETUP.md) has an extra step: create a **Kubernetes Secret** in the cluster (e.g. `studyjam-k8s-runtime` in namespace `studyjam-k8s`, keys `DB_PASSWORD` and `JWT_SECRET`) so Pods get the same env vars Cloud Run receives from **`gcloud run deploy --set-secrets`**. See **GKE-SETUP.md → Step 5** (“Why Cloud Run works but GKE fails until you do this step”).

---

## Step 6 — Create Service Accounts

This project uses **two dedicated service accounts** — one for the build pipeline, one for the running app. Using dedicated accounts follows least-privilege best practices.

### 6a — Cloud Build Service Account (runs the CI/CD pipeline)

1. Go to **IAM & Admin > Service Accounts**
2. Click **+ Create Service Account**
3. Fill in:
   - **Name:** `studyjam-cloudbuild-sa`
   - **Description:** Cloud Build pipeline service account
4. Click **Create and Continue**
5. Grant these roles:
   - `Cloud Run Admin`
   - `Artifact Registry Writer`
   - `Service Account User`
   - `Secret Manager Secret Accessor`
   - `Logs Writer`
   - `Storage Object Viewer`
6. Click **Done**

### 6b — Cloud Run Service Account (runs the deployed app)

1. Click **+ Create Service Account** again
2. Fill in:
   - **Name:** `studyjam-cloudrun-sa`
   - **Description:** Cloud Run runtime service account
3. Click **Create and Continue**
4. Grant these roles:
   - `Cloud SQL Client`
   - `Secret Manager Secret Accessor`
5. Click **Done**

---

## Step 7 — Verify Service Account Roles in IAM

Confirm both service accounts created in Step 6 appear in IAM with the correct roles.

1. Go to **IAM & Admin > IAM**
2. Filter by `studyjam` — you should see both accounts:

   | Service Account | Roles |
   |----------------|-------|
   | `studyjam-cloudbuild-sa@...` | Cloud Run Admin, Artifact Registry Writer, Service Account User, Secret Manager Secret Accessor, Logs Writer, Storage Object Viewer |
   | `studyjam-cloudrun-sa@...` | Cloud SQL Client, Secret Manager Secret Accessor |

If any roles are missing, click the pencil icon on the row and add them.

---

## Step 8 — Create Cloud Build Trigger

1. Go to **Cloud Build > Triggers**
2. Click **+ Create Trigger**
3. Fill in:
   - **Name:** `studyjam-deploy`
   - **Event:** Push to a branch
   - **Repository:** `kevin-naicker-dvt/study-jam-week3-monorepo`
   - **Branch:** `^gcp/dev$` — this is the GCP build branch, **not** `main`
   - **Configuration:** Cloud Build configuration file (YAML)
   - **File location:** `cloudbuild.yaml`
   - **Service account:** Select `studyjam-cloudbuild-sa@dvt-lab-devfest-2025.iam.gserviceaccount.com`

   > **Note:** There are two service accounts — do not confuse them:
   > - `studyjam-cloudbuild-sa` → selected here, **runs the CI/CD build pipeline**
   > - `studyjam-cloudrun-sa` → **runs the deployed app** on Cloud Run (already set in `cloudbuild.yaml`)

4. Under **Substitution variables**, add:

   | Variable | Value |
   |----------|-------|
   | `_REGION` | `africa-south1` |
   | `_REPO_NAME` | `studyjam-repo` |
   | `_BACKEND_SERVICE` | `studyjam-backend` |
   | `_FRONTEND_SERVICE` | `studyjam-frontend` |
   | `_DB_HOST` | *(Cloud SQL private IP from Step 3, e.g. `10.74.0.3`)* |
   | `_DB_NAME` | `studyjam` |
   | `_DB_USER` | `studyjam_user` |
   | `_DB_PASSWORD_NAME` | `studyjam-db-password` |
   | `_JWT_SECRET_NAME` | `studyjam-jwt-secret` |
   | `_VPC_CONNECTOR` | `vpc-studyjam-connector` |

5. Click **Create**

---

## Step 9 — Trigger First Deployment

> **Do this before running migrations.** The database tables don't exist yet — migrations create them.

1. Push a commit to the **`gcp/dev`** branch:
   ```bash
   git checkout -b gcp/dev   # if the branch doesn't exist yet
   git push origin gcp/dev
   ```
2. Go to **Cloud Build > History** and click the running build to watch the logs
3. Wait for **all build steps** to complete successfully (takes ~5–10 minutes):

   | # | Cloud Build Step | What it does |
   |---|-----------------|--------------|
   | 1 | `build-backend` | Builds the backend Docker image (includes compiled `migrate.js` and `drizzle/` SQL files) |
   | 2 | `push-backend` | Pushes the image to Artifact Registry |
   | 3 | `deploy-backend` | Deploys `studyjam-backend` to Cloud Run with VPC connector attached |
   | 4 | `health-check-backend` | Polls `/health` up to 10 times — confirms backend is live |
   | 5 | `get-backend-url` | Reads the backend URL for injection into the frontend build |
   | 6 | `build-frontend` | Builds the frontend image with `VITE_API_URL` baked in |
   | 7 | `push-frontend` | Pushes the frontend image to Artifact Registry |
   | 8 | `deploy-frontend` | Deploys `studyjam-frontend` to Cloud Run |

4. When the build goes green, both services are live but **the database tables are empty** — proceed to Step 10.

---

## Step 10 — Run Database Migrations

> Migrations must run **after** Step 9 completes. They create the `users` table (and any future tables) in Cloud SQL.

The migration runner (`dist/database/migrate.js`) is compiled into the Docker image during the build. Use the **Cloud Run command override** to execute it against the live database.

> **Important:** The VPC connector from Step 4 must be active. Without it, the migration process will time out trying to reach Cloud SQL.

### How to run migrations

1. Go to **Cloud Run > studyjam-backend**
2. Click **Edit & Deploy New Revision**
3. Under the **Container** tab, set **two separate fields**:

   | Field | Value |
   |-------|-------|
   | **Container command** | `node` |
   | **Container arguments** | `dist/database/migrate.js` |

   > **Common mistake:** Do NOT put `node dist/database/migrate.js` as a single string in the Container command field. Cloud Run treats the entire string as a binary path, causing a `no such file or directory` error. The command (`node`) and argument (`dist/database/migrate.js`) must be in their respective fields.

4. Leave all other settings unchanged (env vars, secrets, service account, VPC connector)
5. Click **Deploy**
6. Go to the **Logs** tab and wait for:
   ```
   Running migrations...
   Migrations complete.
   ```
7. Once you see `Migrations complete.`, click **Edit & Deploy New Revision** again
8. **Clear both fields** (Container command and Container arguments)
9. Click **Deploy** to restore normal API server operation

### Verify migrations ran

After restoring normal operation, confirm the `users` table exists via **Cloud SQL Studio**:

1. Go to **Cloud SQL > studyjam-db > Cloud SQL Studio**
2. Connect to the `studyjam` database
3. Run:
   ```sql
   SELECT * FROM drizzle_migrations;
   ```
   You should see one row confirming the migration ran.
4. Optionally confirm the table structure:
   ```sql
   SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';
   ```

---

## Step 11 — Access Your App

After deployment and migrations complete:

1. Go to **Cloud Run**
2. Click `studyjam-backend` → copy the URL (e.g. `https://studyjam-backend-xxxxx-bq.a.run.app`)
3. Click `studyjam-frontend` → copy the URL
4. Open the frontend URL in your browser and test register/login

---

## Deployment Architecture

```
GitHub Push (gcp/dev)
       │
       ▼
 GCP Cloud Build
       │
       ├─► Build Backend Docker Image
       │   (includes compiled migrate.js + drizzle/ SQL files)
       │         │
       │         ▼
       │   Artifact Registry
       │   (africa-south1)
       │         │
       │         ▼
       │   Cloud Run: studyjam-backend
       │   (VPC Connector attached)
       │         │
       │         ▼ (via VPC Connector)
       │   Cloud SQL: PostgreSQL
       │   (Private IP only — 10.74.0.x)
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
                 │ (via VPC Connector)
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
| Serverless VPC Access | per GB transferred | ~$0-1 |

> **Note:** Costs scale with usage. Cloud Run scales to zero when not in use.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Build fails at push step | Check Artifact Registry permissions for Cloud Build SA |
| Backend fails health check | Check `_DB_HOST` variable matches Cloud SQL private IP |
| Frontend shows API errors | Verify `VITE_API_URL` in Cloud Run env vars |
| 403 Forbidden on Cloud Run | Ensure `--allow-unauthenticated` flag is set |
| DB connection refused | Check `Cloud SQL Client` role on `studyjam-cloudrun-sa` |
| Register/login returns 500 after 127s | VPC connector missing or not attached — verify Step 4 and `_VPC_CONNECTOR` in trigger variables |
| Migration fails: `no such file or directory` | Wrong command format — put `node` in **command** field and `dist/database/migrate.js` in **args** field separately |
| Migration fails: `Running migrations` but no `Migrations complete` | Check Cloud SQL is reachable — VPC connector must be **Ready** and attached to the revision |
| `COPY failed: stat app/drizzle` | The `drizzle/` folder was not present during Docker build — `npm run db:generate` runs automatically in the Dockerfile, check build logs |
