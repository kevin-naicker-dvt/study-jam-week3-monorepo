# GKE Lab Setup — Study Jam Week 3 on Google Kubernetes Engine

**Styled HTML (sidebar, tables, hero):** [GKE-SETUP.html](./GKE-SETUP.html)

> **Purpose:** Deploy the same **React + NestJS + PostgreSQL** stack to **GKE** in your **existing** GCP project, reusing **Cloud SQL**, **Artifact Registry**, and **Secret Manager** from [GCP-SETUP.md](./GCP-SETUP.md) where possible. Kubernetes manifests live under **[`api/Kubernetes/`](./api/Kubernetes/)** (Kustomize: **`kubectl apply -k api/Kubernetes`**).  
> **GitHub Repo:** `https://github.com/kevin-naicker-dvt/study-jam-week3-monorepo`  
> **Project:** `dvt-lab-devfest-2025`  
> **Region:** `africa-south1`  
> **Console URL:** https://console.cloud.google.com/kubernetes/list?project=dvt-lab-devfest-2025

---

## How this differs from Cloud Run

| Topic | Cloud Run (GCP-SETUP) | GKE (this lab) |
|--------|------------------------|----------------|
| Workloads | Managed revisions | Pods, Deployments, Services |
| Networking | VPC connector to Cloud SQL | Cluster nodes in VPC reach Cloud SQL **private IP** |
| Public HTTP | Cloud Run URLs | **Ingress** (or `LoadBalancer` services) |
| Frontend `VITE_API_URL` | Injected in Cloud Build from Run URL | You choose a **stable URL** (Ingress hostname) **before** building the frontend image |
| Scaling | Automatic | HPA / cluster autoscaler (configurable) |
| **`DB_PASSWORD` / `JWT_SECRET`** | Cloud Run **`--set-secrets`** maps [Secret Manager](https://console.cloud.google.com/security/secret-manager) secrets → container env vars at deploy time | You must create a **Kubernetes Secret** in the cluster (this guide uses `studyjam-k8s-runtime` with keys `DB_PASSWORD` and `JWT_SECRET`). GKE does **not** pull from Secret Manager unless you add CSI / External Secrets / sync |

The backend serves **`/health`** (no `/api` prefix) and **`/api/*`** for the API ([`main.ts`](backend/src/main.ts)). The production frontend listens on **8080** (nginx); the backend on **3000**.

---

## Can you do this lab from the Google Cloud Console?

**Yes, for almost everything.** You do **not** need the `gcloud` or `kubectl` CLIs installed on your laptop if you use the Console plus **Cloud Shell** (the browser terminal: **Activate Cloud Shell** in the header).

| What | Console / Cloud Shell? |
|------|-------------------------|
| Enable APIs, VPC firewall rules | **Console** (APIs & Services, VPC Network) |
| Create / delete GKE cluster | **Console** (Kubernetes Engine) |
| Connect `kubectl` to the cluster | **Console** → cluster **Connect** → **Run in Cloud Shell** (runs one `gcloud ... get-credentials` command for you) |
| Build container images | There is **no** “Docker build” button in the Console. Use **images already in Artifact Registry** (e.g. from your Cloud Run / Cloud Build lab), or start a **Cloud Build** from the Console / repo |
| Create namespace, Secrets, ConfigMaps | **Console** (GKE cluster → **Configuration** → Secrets / ConfigMaps; namespaces may appear when you create a workload, or create via one `kubectl` line in Cloud Shell) |
| Deployments, Services, Ingress, Jobs | **Console** **Deploy** wizard for simple cases; **Apply YAML** / **kubectl apply** in **Cloud Shell** is still the most reliable for this repo (multi-path Ingress, env from `secretKeyRef`, migration **Job**) |
| View logs, events, Ingress IP | **Console** (Workloads, Services & Ingress) |
| Verify app / DB | **Console** (browser + Cloud SQL Studio); optional `curl` in Cloud Shell |

**“Limited `gcloud`”** usually means: open **Cloud Shell** from the Console, run **Connect** once, then use short `kubectl` commands (or paste YAML). That is still “from Google Cloud” in practice, just not a local SDK install.

The sections below use **CLI examples** for copy-paste; each step notes the **Console** equivalent where it applies.

---

## Prerequisites

- Completed (or equivalent) **Cloud SQL**, **Artifact Registry**, and **Secret Manager** setup from [GCP-SETUP.md](./GCP-SETUP.md):
  - Instance `studyjam-db` with private IP, database `studyjam`, user `studyjam_user`
  - Repository `studyjam-repo` (`africa-south1`)
  - Secrets `studyjam-db-password`, `studyjam-jwt-secret`
- **Owner** or **Editor** on the project, or sufficient permissions to create GKE clusters and firewall rules
- **Either** a local install of **`gcloud`** and **`kubectl`**, **or** use **Cloud Shell** from the Console (recommended for a Console-first lab):
  ```bash
  gcloud config set project dvt-lab-devfest-2025
  ```

---

## Step 1 — Enable APIs

In **APIs & Services > Library**, enable any that are not already on (Cloud Run lab may have skipped GKE):

| API | Purpose |
|-----|---------|
| **Kubernetes Engine API** | GKE clusters |
| **Compute Engine API** | Nodes, load balancers, firewall rules (often auto-enabled with GKE) |

---

## Step 2 — Networking and Cloud SQL

Your Cloud SQL instance should use **private IP** on the **default VPC** (as in GCP-SETUP). GKE nodes must be able to reach **`DB_HOST:5432`** on that private IP.

1. Note the **private IP** of `studyjam-db` (Cloud SQL → instance → **Connect to this instance** / **Overview**).
2. Create the cluster in **`africa-south1`** on the **default VPC** so pod/node traffic can route to the SQL private IP.
3. If connections time out, add a **VPC firewall rule** (**VPC network** → **Firewall** → **Create firewall rule**) allowing **TCP 5432** from **GKE node** / **pod** subnets to the Cloud SQL private IP (or use a permissive lab rule for sources in your VPC — tighten for production).

**Verify (after `kubectl` is configured — Cloud Shell is enough):**

```bash
# Replace CLOUD_SQL_PRIVATE_IP with your instance private IP
kubectl run psql-test --rm -it --restart=Never --image=postgres:15-alpine -- \
  psql "postgresql://studyjam_user@CLOUD_SQL_PRIVATE_IP:5432/studyjam"
```

Use the password from Secret Manager when prompted. Exit with `\q`. Delete succeeds when the pod exits.

---

## Step 3 — Create a GKE cluster

**Lab cluster name in this guide:** **`studyjam-k8s-v2`** (Autopilot, regional **`africa-south1`**, default VPC, same networking assumptions as below). If you created the cluster with a different name, substitute it in every `gcloud container clusters ...` command and in **Connect**.

### Create the cluster (Google Cloud Console)

1. Open **Kubernetes Engine** → **Clusters** → **Create**.
2. Choose **Autopilot** (or **Standard** if your course requires it).
3. Set **Name** to `studyjam-k8s-v2`, **Region** to `africa-south1`.
4. Keep the **default VPC** so nodes can reach Cloud SQL **private IP** (same assumption as [GCP-SETUP.md](./GCP-SETUP.md)).
5. Click **Create** and wait until the cluster is **Running**.

### Connect Cloud Shell to the cluster (minimal CLI)

1. On the **Clusters** list, click **Connect** on `studyjam-k8s-v2`.
2. Choose **Run in Cloud Shell** (or copy the `gcloud container clusters get-credentials ...` command into Cloud Shell).
3. When the prompt is ready, `kubectl get nodes` should list your nodes.

---

### Create the cluster (`gcloud`, optional)

**Autopilot** (recommended for labs: less node tuning):

```bash
gcloud container clusters create-auto studyjam-k8s-v2 \
  --region=africa-south1 \
  --project=dvt-lab-devfest-2025 \
  --release-channel=regular
```

**Standard** (if you need full control over node pools):

```bash
gcloud container clusters create studyjam-k8s-v2 \
  --region=africa-south1 \
  --project=dvt-lab-devfest-2025 \
  --num-nodes=2 \
  --machine-type=e2-medium \
  --enable-ip-alias \
  --release-channel=regular
```

Fetch credentials for `kubectl` (not needed if you already used **Connect → Run in Cloud Shell**):

```bash
gcloud container clusters get-credentials studyjam-k8s-v2 \
  --region=africa-south1 \
  --project=dvt-lab-devfest-2025
```

---

## Step 4 — Build and push images

### Images from the Console workflow (no local Docker)

- **Reuse existing images:** If you already deployed with [GCP-SETUP.md](./GCP-SETUP.md) / Cloud Build, open **Artifact Registry** → repository **`studyjam-repo`** → confirm tags for `studyjam-backend` and `studyjam-frontend` (for example `:latest` or a commit SHA). Use those image URIs in your Deployments instead of `:gke-latest`.
- **New frontend URL:** If you need a new `VITE_API_URL`, you must **rebuild** the frontend image. In the Console, use **Cloud Build** → **Triggers** or **Repositories** / **Run a build** so a build runs your `frontend/Dockerfile` with the correct `--build-arg` (your course may supply a `cloudbuild` step or you run a custom build config in Cloud Shell).

### Local Docker + `gcloud` (optional)

From the repo root, authenticate Docker to Artifact Registry:

```bash
gcloud auth configure-docker africa-south1-docker.pkg.dev
```

### Backend

```bash
docker build -t africa-south1-docker.pkg.dev/dvt-lab-devfest-2025/studyjam-repo/studyjam-backend:gke-latest ./backend
docker push africa-south1-docker.pkg.dev/dvt-lab-devfest-2025/studyjam-repo/studyjam-backend:gke-latest
```

### Frontend — `VITE_API_URL` and CORS

The frontend bakes **`VITE_API_URL`** at **image build** time ([`frontend/Dockerfile`](frontend/Dockerfile)). The backend uses **`FRONTEND_URL`** for CORS ([`backend/src/main.ts`](backend/src/main.ts)).

Pick the **exact HTTPS origin** users will use in the browser (your Ingress hostname), for example:

- `FRONTEND_URL=https://studyjam.example.com`
- `VITE_API_URL=https://studyjam.example.com/api`

Build and push:

```bash
docker build \
  --build-arg VITE_API_URL=https://studyjam.example.com/api \
  -t africa-south1-docker.pkg.dev/dvt-lab-devfest-2025/studyjam-repo/studyjam-frontend:gke-latest \
  ./frontend

docker push africa-south1-docker.pkg.dev/dvt-lab-devfest-2025/studyjam-repo/studyjam-frontend:gke-latest
```

> **Lab tip:** You can use a placeholder hostname first, create the Ingress, then update DNS and **rebuild** the frontend if the public URL changes. For a quick test without a domain, some classes use **nip.io** with the Ingress IP (still use **https** only if your Ingress serves TLS).

---

## Step 5 — Kubernetes secrets (DB password and JWT)

### Why Cloud Run works but GKE fails until you do this step

The **same Docker image** reads **`DB_PASSWORD`** and **`JWT_SECRET`** from the process environment. Nothing about NestJS or the image changes between Cloud Run and GKE.

| | Cloud Run ([GCP-SETUP.md](./GCP-SETUP.md), [`cloudbuild.yaml`](./cloudbuild.yaml)) | GKE (this lab, [`api/Kubernetes/deployment-backend.yaml`](./api/Kubernetes/deployment-backend.yaml) via [`kubectl apply -k api/Kubernetes`](./api/Kubernetes/)) |
|---|----------------------|-----|
| **Where secrets live in GCP** | Secret Manager secrets `studyjam-db-password` and `studyjam-jwt-secret` (from [GCP-SETUP Step 5](./GCP-SETUP.md#step-5--store-secrets-in-secret-manager)) | Same — you still use those values |
| **How they get into the container** | **`gcloud run deploy --set-secrets=...`** binds each GCP secret to an **environment variable name** (`DB_PASSWORD`, `JWT_SECRET`) on the Cloud Run service | Kubernetes only sees **Kubernetes `Secret` objects**. You must **`kubectl create secret …`** (or Console) in namespace **`studyjam-k8s`**, name **`studyjam-k8s-runtime`**, with keys **`DB_PASSWORD`** and **`JWT_SECRET`** — then the Deployment uses `secretKeyRef` |

**Typical symptom if you skip the Kubernetes Secret:** backend crashes on startup with **`JwtStrategy requires a secret or key`** (or a message that **`JWT_SECRET` is missing or empty**) because the pod never received those env vars.

**Fix:** complete the steps below (or pull from Secret Manager into the K8s Secret using the `gcloud secrets versions access` example). After changing the Secret, restart the Deployment: `kubectl rollout restart deployment/studyjam-k8s-be -n studyjam-k8s`.

---

### Google Cloud Console

1. Open **Kubernetes Engine** → select cluster **`studyjam-k8s-v2`**.
2. Go to **Configuration** (or **Secrets & ConfigMaps**, depending on Console version) → **Secrets** → **Create**.
3. **Namespace:** create or choose **`studyjam-k8s`** (if the UI asks for a namespace first, create it from **Namespaces** in the same area, or use Cloud Shell once: `kubectl create namespace studyjam-k8s`).
4. Create an **Opaque** secret named **`studyjam-k8s-runtime`** with data keys **`DB_PASSWORD`** and **`JWT_SECRET`** (values from Secret Manager or your records).

### `kubectl` (Cloud Shell or local)

Simplest path for the lab: create a namespace and a **generic** secret from literals (values from Secret Manager or your records).

```bash
kubectl create namespace studyjam-k8s

kubectl create secret generic studyjam-k8s-runtime \
  --namespace=studyjam-k8s \
  --from-literal=DB_PASSWORD='YOUR_DB_PASSWORD' \
  --from-literal=JWT_SECRET='YOUR_JWT_SECRET'
```

Alternatively, pull from Secret Manager (no newlines in the secret value):

```bash
DB_PW=$(gcloud secrets versions access latest --secret=studyjam-db-password --project=dvt-lab-devfest-2025)
JWT=$(gcloud secrets versions access latest --secret=studyjam-jwt-secret --project=dvt-lab-devfest-2025)

kubectl create secret generic studyjam-k8s-runtime \
  --namespace=studyjam-k8s \
  --from-literal=DB_PASSWORD="$DB_PW" \
  --from-literal=JWT_SECRET="$JWT"
```

For production, prefer **Workload Identity** + **Secret Manager CSI** or **External Secrets** instead of long-lived duplicated secrets in etcd.

### Secure secret workflow (recommended for labs)

Follow these practices so credentials are not exposed in shell history, screen shares, or Git.

| Practice | Why |
|----------|-----|
| **Use Cloud Shell** (or a dedicated admin machine) for `kubectl` / `gcloud` secret commands | Reduces copy-paste of secrets into local notes or chat |
| **Prefer reading from Secret Manager in the shell** (example under `kubectl` above) instead of typing passwords | Single source of truth; no duplicate plaintext |
| **Never commit** Secret YAML, `.env` with production values, or `stringData` dumps to the repo | Git history is forever |
| **Use `set +o history`** or `HISTCONTROL=ignorespace` and a leading space on sensitive lines in Bash if you must paste literals | Lowers risk of secrets in `~/.bash_history` |
| **Prefer apply with dry-run from stdin** | `kubectl create secret ... --dry-run=client -o yaml \| kubectl apply -f -` avoids temporary files on disk |
| **Verify without printing values** | `kubectl get secret studyjam-k8s-runtime -n studyjam-k8s` (check **DATA** = 2); list key names only: `kubectl get secret studyjam-k8s-runtime -n studyjam-k8s -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}'` |
| **After Console-only deploys**, ensure **`kubectl set env deploy/studyjam-k8s-be -n studyjam-k8s --from=secret/studyjam-k8s-runtime`** or equivalent `secretKeyRef` | Console often wires only the ConfigMap |
| **Rotate** in Secret Manager and re-create the Kubernetes Secret if exposure is suspected | Treat cluster Secret as a cache of Secret Manager for this lab |

---

## Step 6 — ConfigMap for non-sensitive backend env

**Recommended if you use [Step 7](#step-7--deploy-workloads-kustomize--gke-friendly-manifests):** put values in **[`api/Kubernetes/configmap.yaml`](./api/Kubernetes/configmap.yaml)** (replace **`DB_HOST`**, **`FRONTEND_URL`**) and run **`kubectl apply -k api/Kubernetes`** — you can skip the imperative `kubectl create configmap` below if that file is your source of truth.

### Google Cloud Console

In the same cluster **Configuration** area → **ConfigMaps** → **Create**, name **`studyjam-k8s-backend-config`**, namespace **`studyjam-k8s`**, and add key/value pairs:

| Key | Example value |
|-----|----------------|
| `NODE_ENV` | `production` |
| `PORT` | `3000` |
| `DB_HOST` | *(Cloud SQL private IP)* |
| `DB_PORT` | `5432` |
| `DB_NAME` | `studyjam` |
| `DB_USER` | `studyjam_user` |
| `FRONTEND_URL` | `https://studyjam.example.com` *(must match the browser origin you will use)* |

### `kubectl` (Cloud Shell or local)

Replace **`CLOUD_SQL_PRIVATE_IP`** with your database private IP.

```bash
kubectl create configmap studyjam-k8s-backend-config \
  --namespace=studyjam-k8s \
  --from-literal=NODE_ENV=production \
  --from-literal=PORT=3000 \
  --from-literal=DB_HOST=CLOUD_SQL_PRIVATE_IP \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_NAME=studyjam \
  --from-literal=DB_USER=studyjam_user \
  --from-literal=FRONTEND_URL=https://studyjam.example.com
```

---

## Step 6b — Confirm configuration (checklist)

Use this checklist **after** the Secret and ConfigMap exist and **before** you rely on user traffic. Run commands in Cloud Shell (or anywhere **`kubectl`** targets your cluster, e.g. **`studyjam-k8s-v2`**).

### Before `kubectl apply`

| Check | Command or action |
|-------|-------------------|
| **Cluster context** | `kubectl config current-context` → should be a `gke_...` context, not `localhost` |
| **Namespace** | `kubectl get namespace studyjam-k8s` → **Active** |
| **Secret** | `kubectl get secret studyjam-k8s-runtime -n studyjam-k8s` → **Opaque**, **DATA** = **2** |
| **Secret keys (names only)** | `kubectl get secret studyjam-k8s-runtime -n studyjam-k8s -o go-template='{{range $k,$v := .data}}{{$k}}{{"\n"}}{{end}}'` → **`DB_PASSWORD`**, **`JWT_SECRET`** |
| **ConfigMap `DB_HOST`** | Must be Cloud SQL **private IP**, not `REPLACE_CLOUD_SQL_PRIVATE_IP` |
| **ConfigMap `FRONTEND_URL`** | Matches browser origin for CORS (scheme + host) |
| **Ingress host** | Edit [`api/Kubernetes/ingress.yaml`](./api/Kubernetes/ingress.yaml) if you do not use `studyjam.example.com` |
| **Image tags** | In `deployment-*.yaml`, tags (e.g. `:gke-latest`) exist in Artifact Registry |

### After `kubectl apply -k api/Kubernetes`

| Check | Command |
|-------|---------|
| **Pods** | `kubectl get pods -n studyjam-k8s` |
| **Backend rollout** | `kubectl rollout status deployment/studyjam-k8s-be -n studyjam-k8s` |
| **Logs** | `kubectl logs -n studyjam-k8s deploy/studyjam-k8s-be --tail=40` |
| **Backend has Secret env** | `kubectl get deploy studyjam-k8s-be -n studyjam-k8s -o yaml \| grep -A2 secretKeyRef` |
| **Ingress address** | `kubectl get ingress -n studyjam-k8s` |

---

## Step 7 — Deploy workloads (Kustomize + GKE-friendly manifests)

Manifests live under **[`api/Kubernetes/`](./api/Kubernetes/)**. Layout follows common Kubernetes conventions GKE and CI tools work well with:

- **`kustomization.yaml`** — sets namespace **`studyjam-k8s`**, recommended **`app.kubernetes.io/*` labels** (no selector churn), ordered resources.
- **One resource kind per file** — `deployment-backend.yaml`, `service-backend.yaml`, etc.
- **Secrets are not in Git** — create **`studyjam-k8s-runtime`** separately ([Step 5](#step-5--kubernetes-secrets-db-password-and-jwt)).
- **Migration Job is separate** — `job-migrate.yaml` is **not** in the default Kustomize bundle (Jobs are usually applied once per schema change).

### Apply (Cloud Shell or local, repo root)

1. Edit **[`api/Kubernetes/configmap.yaml`](./api/Kubernetes/configmap.yaml)** — set **`DB_HOST`**, **`FRONTEND_URL`**, and adjust **[`api/Kubernetes/ingress.yaml`](./api/Kubernetes/ingress.yaml)** **`host`** if needed.
2. Ensure [Step 5](#step-5--kubernetes-secrets-db-password-and-jwt) Secret exists.
3. Run:

```bash
kubectl apply -k api/Kubernetes
kubectl rollout status deployment/studyjam-k8s-be -n studyjam-k8s
kubectl rollout status deployment/studyjam-k8s-fe -n studyjam-k8s
kubectl get pods,svc,ingress -n studyjam-k8s
```

**Preview** what will be applied (no cluster changes):

```bash
kubectl kustomize api/Kubernetes
```

**GKE Console / automated deploy:** point “apply directory” or your pipeline at **`api/Kubernetes`** and run the same **`kubectl apply -k api/Kubernetes`** (Cloud Build step, GitOps, etc.).

### Google Cloud Console (wizard)

You can still use **Workloads** → **Deploy** → **Existing container image** — set **Namespace** **`studyjam-k8s`**, ports **3000** / **8080**, and attach **both** ConfigMap **and** Secret keys **`DB_PASSWORD`**, **`JWT_SECRET`**.

> **Console pitfall:** Wiring **only** the ConfigMap causes **CrashLoopBackOff**. Fix with **`kubectl set env deployment/studyjam-k8s-be -n studyjam-k8s --from=secret/studyjam-k8s-runtime`** or re-apply from **`api/Kubernetes`** ([`deployment-backend.yaml`](./api/Kubernetes/deployment-backend.yaml) already includes `secretKeyRef`).

---

## Step 8 — Ingress IP and DNS

**Ingress** is included in **`kubectl apply -k api/Kubernetes`** ([`api/Kubernetes/ingress.yaml`](./api/Kubernetes/ingress.yaml)). GKE provisions an HTTP(S) load balancer; paths **`/health`** and **`/api`** go to **`studyjam-k8s-be`**, **`/`** to **`studyjam-k8s-fe`**.

```bash
kubectl get ingress -n studyjam-k8s
```

1. Wait until **ADDRESS** is assigned.
2. Point your **`spec.rules[0].host`** (e.g. **`studyjam.example.com`**) at that IP via DNS or **`/etc/hosts`**; **nip.io** works for quick tests.
3. For **HTTPS**, use a **ManagedCertificate** or **cert-manager** if your course requires TLS.

---

## Step 9 — Run database migrations (Kubernetes Job)

Same image as the API; command **`node dist/database/migrate.js`** (see [GCP-SETUP.md](./GCP-SETUP.md)). Apply **after** the base stack and reachable DB:

```bash
kubectl apply -f api/Kubernetes/job-migrate.yaml
kubectl logs -n studyjam-k8s job/studyjam-k8s-migrate -f
```

**Console:** **Workloads** → **Jobs** → **`studyjam-k8s-migrate`** → **Logs**.

Expect **`Migrations complete.`** in logs. On failure, delete and re-apply:

```bash
kubectl delete job studyjam-k8s-migrate -n studyjam-k8s
```

---

## Step 10 — Verify

- **Console:** **Services & Ingress** → open the Ingress → note the **Frontend / IP**; use your browser (and DNS or `/etc/hosts`) to open the app. **Cloud Shell:**  
  `curl -sS "https://studyjam.example.com/health"` *(after DNS or hosts file)*.

```bash
# From Cloud Shell or your machine (after DNS or /etc/hosts points host to Ingress IP)
curl -sS "https://studyjam.example.com/health"

# Register / login in the browser at https://studyjam.example.com
```

Confirm rows in Cloud SQL Studio:

```sql
SELECT * FROM drizzle_migrations;
```

---

## Step 11 — Tear down (optional)

- **Console:** **Kubernetes Engine** → **Clusters** → **`studyjam-k8s-v2`** → **Delete**; delete individual **Workloads** / the **`studyjam-k8s`** namespace from the cluster UI if you prefer not to use CLI.
- **Cloud Shell / CLI:**

```bash
kubectl delete namespace studyjam-k8s

gcloud container clusters delete studyjam-k8s-v2 \
  --region=africa-south1 \
  --project=dvt-lab-devfest-2025
```

This does **not** delete Cloud SQL, Artifact Registry, or Secret Manager resources.

---

## Architecture (GKE)

```
Browser
   │
   ▼
GKE Ingress (HTTP(S) LB)
   │
   ├─► /health, /api/*  ──► Service studyjam-k8s-be:3000  ──► Pods (NestJS)
   │                                                      │
   │                                                      ▼
   │                                              Cloud SQL (private IP)
   │
   └─► /                ──► Service studyjam-k8s-fe:8080 ──► Pods (nginx + static)
```

---

## Cost notes (approximate)

GKE **Autopilot** bills per pod resource requests; **Standard** bills for nodes + cluster management. A small lab cluster plus existing Cloud SQL is usually more expensive than Cloud Run at low traffic. Delete the cluster when finished.

---

## Troubleshooting

| Issue | What to check |
|-------|----------------|
| Pods `CrashLoopBackOff` | `kubectl logs -n studyjam-k8s deploy/studyjam-k8s-be`; verify `DB_HOST`, secrets, and image tag |
| **CrashLoop after Console deploy — env only from ConfigMap** | Inspect YAML: container must include **`DB_PASSWORD`** and **`JWT_SECRET`** via **`secretKeyRef`** (Secret **`studyjam-k8s-runtime`**). ConfigMap-only env → missing JWT/DB password. `kubectl set env deploy/studyjam-k8s-be -n studyjam-k8s --from=secret/studyjam-k8s-runtime` or apply [`api/Kubernetes`](./api/Kubernetes/). |
| **`JwtStrategy requires a secret or key` / JWT missing** | Kubernetes Secret **`studyjam-k8s-runtime`** in namespace **`studyjam-k8s`** must exist with non-empty keys **`JWT_SECRET`** and **`DB_PASSWORD`** (exact spelling). Cloud Run gets these from `--set-secrets`; GKE needs [this step](#why-cloud-run-works-but-gke-fails-until-you-do-this-step). Confirm: `kubectl get secret studyjam-k8s-runtime -n studyjam-k8s` |
| DB connection timeouts | Firewall, VPC, Cloud SQL **private IP**; same region/VPC as cluster |
| Ingress 404 / wrong backend | Path order in Ingress; backend prefix `/api` and bare `/health` |
| CORS errors in browser | `FRONTEND_URL` in ConfigMap must **exactly** match the browser origin (scheme + host, no trailing slash mismatch) |
| Frontend calls wrong API | Rebuild frontend image with correct **`VITE_API_URL`**; it is compile-time |
| Migration job hangs | Same as DB connectivity from pods; ensure Job uses same env as Deployment |
| **`connection refused` to `127.0.0.1:8080` / `localhost:8080`** | `kubectl` has **no cluster context** (default API server). Run **`gcloud container clusters get-credentials studyjam-k8s-v2 --region=africa-south1 --project=dvt-lab-devfest-2025`** (or use **GKE → cluster → Connect → Run in Cloud Shell**). Then `kubectl config current-context` should show `gke_...`, not localhost. |

---

## Optional extensions

- **Horizontal Pod Autoscaler** on CPU for `studyjam-k8s-be` and `studyjam-k8s-fe`
- **Cloud Build** trigger that builds/pushes images and runs **`kubectl apply`** (or Helm) with a deploy service account
- **Workload Identity** for pods calling Secret Manager without duplicating secrets into Kubernetes
- **Cloud SQL Auth Proxy** as a sidecar if you prefer not to use private IP routing from pods

For the original Cloud Run path, continue using [GCP-SETUP.md](./GCP-SETUP.md) and [cloudbuild.yaml](./cloudbuild.yaml).
