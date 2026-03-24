# GKE Lab Setup — Study Jam Week 3 on Google Kubernetes Engine

> **Purpose:** Deploy the same **React + NestJS + PostgreSQL** stack to **GKE** in your **existing** GCP project, reusing **Cloud SQL**, **Artifact Registry**, and **Secret Manager** from [GCP-SETUP.md](./GCP-SETUP.md) where possible.  
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

### Create the cluster (Google Cloud Console)

1. Open **Kubernetes Engine** → **Clusters** → **Create**.
2. Choose **Autopilot** (or **Standard** if your course requires it).
3. Set **Name** to `studyjam-gke`, **Region** to `africa-south1`.
4. Keep the **default VPC** so nodes can reach Cloud SQL **private IP** (same assumption as [GCP-SETUP.md](./GCP-SETUP.md)).
5. Click **Create** and wait until the cluster is **Running**.

### Connect Cloud Shell to the cluster (minimal CLI)

1. On the **Clusters** list, click **Connect** on `studyjam-gke`.
2. Choose **Run in Cloud Shell** (or copy the `gcloud container clusters get-credentials ...` command into Cloud Shell).
3. When the prompt is ready, `kubectl get nodes` should list your nodes.

---

### Create the cluster (`gcloud`, optional)

**Autopilot** (recommended for labs: less node tuning):

```bash
gcloud container clusters create-auto studyjam-gke \
  --region=africa-south1 \
  --project=dvt-lab-devfest-2025 \
  --release-channel=regular
```

**Standard** (if you need full control over node pools):

```bash
gcloud container clusters create studyjam-gke \
  --region=africa-south1 \
  --project=dvt-lab-devfest-2025 \
  --num-nodes=2 \
  --machine-type=e2-medium \
  --enable-ip-alias \
  --release-channel=regular
```

Fetch credentials for `kubectl` (not needed if you already used **Connect → Run in Cloud Shell**):

```bash
gcloud container clusters get-credentials studyjam-gke \
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

### Google Cloud Console

1. Open **Kubernetes Engine** → select cluster **`studyjam-gke`**.
2. Go to **Configuration** (or **Secrets & ConfigMaps**, depending on Console version) → **Secrets** → **Create**.
3. **Namespace:** create or choose **`studyjam`** (if the UI asks for a namespace first, create it from **Namespaces** in the same area, or use Cloud Shell once: `kubectl create namespace studyjam`).
4. Create an **Opaque** secret named **`studyjam-runtime`** with data keys **`DB_PASSWORD`** and **`JWT_SECRET`** (values from Secret Manager or your records).

### `kubectl` (Cloud Shell or local)

Simplest path for the lab: create a namespace and a **generic** secret from literals (values from Secret Manager or your records).

```bash
kubectl create namespace studyjam

kubectl create secret generic studyjam-runtime \
  --namespace=studyjam \
  --from-literal=DB_PASSWORD='YOUR_DB_PASSWORD' \
  --from-literal=JWT_SECRET='YOUR_JWT_SECRET'
```

Alternatively, pull from Secret Manager (no newlines in the secret value):

```bash
DB_PW=$(gcloud secrets versions access latest --secret=studyjam-db-password --project=dvt-lab-devfest-2025)
JWT=$(gcloud secrets versions access latest --secret=studyjam-jwt-secret --project=dvt-lab-devfest-2025)

kubectl create secret generic studyjam-runtime \
  --namespace=studyjam \
  --from-literal=DB_PASSWORD="$DB_PW" \
  --from-literal=JWT_SECRET="$JWT"
```

For production, prefer **Workload Identity** + **Secret Manager CSI** or **External Secrets** instead of long-lived duplicated secrets in etcd.

---

## Step 6 — ConfigMap for non-sensitive backend env

### Google Cloud Console

In the same cluster **Configuration** area → **ConfigMaps** → **Create**, name **`studyjam-backend-config`**, namespace **`studyjam`**, and add key/value pairs:

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
kubectl create configmap studyjam-backend-config \
  --namespace=studyjam \
  --from-literal=NODE_ENV=production \
  --from-literal=PORT=3000 \
  --from-literal=DB_HOST=CLOUD_SQL_PRIVATE_IP \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_NAME=studyjam \
  --from-literal=DB_USER=studyjam_user \
  --from-literal=FRONTEND_URL=https://studyjam.example.com
```

---

## Step 7 — Deploy backend and frontend

### Google Cloud Console (wizard)

For each app, you can use **Workloads** → **Deploy** → **Existing container image** → browse **Artifact Registry**, set **Namespace** to **`studyjam`**, container port **3000** (backend) or **8080** (frontend), and under **Environment variables** attach values from the **ConfigMap** and **Secret** (modern Console UIs let you reference secret keys for `DB_PASSWORD` and `JWT_SECRET`). Expose each workload with a **ClusterIP** Service on the same port.

The wizard is workable for **simple** deployments. If you cannot map **all** env vars and secret references the way the YAML below does, use **Apply YAML** (next subsection) instead.

### Apply YAML (Console or Cloud Shell)

In **Kubernetes Engine** → your cluster → open **Cloud Shell** and run `kubectl apply -f ...`, or use **Deploy** → **Apply manifest** / **YAML** if your Console exposes it. **Update image tags** in the YAML to match Artifact Registry (e.g. `:latest`).

Save the following as files (e.g. `k8s/backend.yaml`, `k8s/frontend.yaml`) or apply from stdin. **Update image tags** if you did not use `:gke-latest`.

### `backend-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: studyjam-backend
  namespace: studyjam
spec:
  replicas: 2
  selector:
    matchLabels:
      app: studyjam-backend
  template:
    metadata:
      labels:
        app: studyjam-backend
    spec:
      containers:
        - name: backend
          image: africa-south1-docker.pkg.dev/dvt-lab-devfest-2025/studyjam-repo/studyjam-backend:gke-latest
          ports:
            - containerPort: 3000
          envFrom:
            - configMapRef:
                name: studyjam-backend-config
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: studyjam-runtime
                  key: DB_PASSWORD
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: studyjam-runtime
                  key: JWT_SECRET
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
            initialDelaySeconds: 30
            periodSeconds: 15
---
apiVersion: v1
kind: Service
metadata:
  name: studyjam-backend
  namespace: studyjam
spec:
  type: ClusterIP
  selector:
    app: studyjam-backend
  ports:
    - port: 3000
      targetPort: 3000
```

### `frontend-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: studyjam-frontend
  namespace: studyjam
spec:
  replicas: 2
  selector:
    matchLabels:
      app: studyjam-frontend
  template:
    metadata:
      labels:
        app: studyjam-frontend
    spec:
      containers:
        - name: frontend
          image: africa-south1-docker.pkg.dev/dvt-lab-devfest-2025/studyjam-repo/studyjam-frontend:gke-latest
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: studyjam-frontend
  namespace: studyjam
spec:
  type: ClusterIP
  selector:
    app: studyjam-frontend
  ports:
    - port: 8080
      targetPort: 8080
```

Apply:

```bash
kubectl apply -f backend-deployment.yaml
kubectl apply -f frontend-deployment.yaml
kubectl get pods -n studyjam -w
```

---

## Step 8 — Ingress (single host)

This uses GKE’s **Ingress** controller (creates a Google HTTP(S) load balancer). Paths are ordered so **`/health`** and **`/api`** hit the backend; everything else goes to the SPA.

**Console:** **Kubernetes Engine** → **Services & Ingress** (or **Networking** for your cluster) → **Create Ingress**. Multi-path routing to two different Services is easiest if the UI offers a YAML editor; otherwise paste the manifest below into Cloud Shell: `kubectl apply -f ingress.yaml`.

### `ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: studyjam-ingress
  namespace: studyjam
  annotations:
    kubernetes.io/ingress.class: "gce"
spec:
  rules:
    - host: studyjam.example.com
      http:
        paths:
          - path: /health
            pathType: Prefix
            backend:
              service:
                name: studyjam-backend
                port:
                  number: 3000
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: studyjam-backend
                port:
                  number: 3000
          - path: /
            pathType: Prefix
            backend:
              service:
                name: studyjam-frontend
                port:
                  number: 8080
```

```bash
kubectl apply -f ingress.yaml
kubectl get ingress -n studyjam
```

1. Wait until **ADDRESS** is assigned on the Ingress.
2. Point **`studyjam.example.com`** (DNS A record) at that IP, or use the IP with **nip.io** for testing.
3. For **HTTPS**, add a **ManagedCertificate** (GKE) or use **cert-manager** — details depend on your class requirements; HTTP alone is enough to validate routing in some labs.

---

## Step 9 — Run database migrations (Kubernetes Job)

Same image as the API; override the command to run Drizzle migrations (matches [GCP-SETUP.md](./GCP-SETUP.md) Cloud Run command split: `node` + `dist/database/migrate.js`).

**Console:** Some Console versions let you create a **Job** under **Workloads** → **Create** → **Job**. If yours does not, use Cloud Shell: `kubectl apply -f migrate-job.yaml`, then **Workloads** → **Jobs** → `studyjam-migrate` → **Logs**.

### `migrate-job.yaml`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: studyjam-migrate
  namespace: studyjam
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: africa-south1-docker.pkg.dev/dvt-lab-devfest-2025/studyjam-repo/studyjam-backend:gke-latest
          command: ["node", "dist/database/migrate.js"]
          envFrom:
            - configMapRef:
                name: studyjam-backend-config
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: studyjam-runtime
                  key: DB_PASSWORD
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef:
                  name: studyjam-runtime
                  key: JWT_SECRET
```

```bash
kubectl apply -f migrate-job.yaml
kubectl logs -n studyjam job/studyjam-migrate -f
```

Expect **`Migrations complete.`** in logs. If the job fails, fix networking or credentials, then delete the job and re-apply:

```bash
kubectl delete job studyjam-migrate -n studyjam
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

- **Console:** **Kubernetes Engine** → **Clusters** → **`studyjam-gke`** → **Delete**; delete individual **Workloads** / the **`studyjam`** namespace from the cluster UI if you prefer not to use CLI.
- **Cloud Shell / CLI:**

```bash
kubectl delete namespace studyjam

gcloud container clusters delete studyjam-gke \
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
   ├─► /health, /api/*  ──► Service studyjam-backend:3000  ──► Pods (NestJS)
   │                                                      │
   │                                                      ▼
   │                                              Cloud SQL (private IP)
   │
   └─► /                ──► Service studyjam-frontend:8080 ──► Pods (nginx + static)
```

---

## Cost notes (approximate)

GKE **Autopilot** bills per pod resource requests; **Standard** bills for nodes + cluster management. A small lab cluster plus existing Cloud SQL is usually more expensive than Cloud Run at low traffic. Delete the cluster when finished.

---

## Troubleshooting

| Issue | What to check |
|-------|----------------|
| Pods `CrashLoopBackOff` | `kubectl logs -n studyjam deploy/studyjam-backend`; verify `DB_HOST`, secrets, and image tag |
| DB connection timeouts | Firewall, VPC, Cloud SQL **private IP**; same region/VPC as cluster |
| Ingress 404 / wrong backend | Path order in Ingress; backend prefix `/api` and bare `/health` |
| CORS errors in browser | `FRONTEND_URL` in ConfigMap must **exactly** match the browser origin (scheme + host, no trailing slash mismatch) |
| Frontend calls wrong API | Rebuild frontend image with correct **`VITE_API_URL`**; it is compile-time |
| Migration job hangs | Same as DB connectivity from pods; ensure Job uses same env as Deployment |

---

## Optional extensions

- **Horizontal Pod Autoscaler** on CPU for `studyjam-backend` and `studyjam-frontend`
- **Cloud Build** trigger that builds/pushes images and runs **`kubectl apply`** (or Helm) with a deploy service account
- **Workload Identity** for pods calling Secret Manager without duplicating secrets into Kubernetes
- **Cloud SQL Auth Proxy** as a sidecar if you prefer not to use private IP routing from pods

For the original Cloud Run path, continue using [GCP-SETUP.md](./GCP-SETUP.md) and [cloudbuild.yaml](./cloudbuild.yaml).
