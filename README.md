# Study Jam Week 3 — Full Stack Monorepo

A 3-tier application built with **ReactJS**, **NestJS**, **Drizzle ORM**, and **PostgreSQL**, deployed to **Google Cloud Platform** using **Cloud Build**, **Cloud Run**, and **Artifact Registry**.

---

## Architecture

```
Frontend (React/Vite)  ──►  Backend (NestJS)  ──►  PostgreSQL (Cloud SQL)
     Cloud Run               Cloud Run              africa-south1
   Port 8080 (nginx)        Port 3000
```

**GCP Project:** `dvt-lab-devfest-2025` | **Region:** `africa-south1`

---

## App Features

- **Register** — Create an account (Name, Surname, Email, Password)
- **Login** — JWT-based authentication (Access Granted / Access Denied)
- **Protected Dashboard** — Authenticated user view

---

## Project Structure

```
study-jam-week3-monorepo/
├── frontend/               # ReactJS + Vite + TypeScript
│   ├── src/
│   │   ├── pages/          # LoginPage, RegisterPage, DashboardPage
│   │   ├── services/       # Axios API client
│   │   └── App.tsx         # React Router setup
│   ├── Dockerfile
│   ├── nginx.conf
│   └── .env.example
├── backend/                # NestJS + Drizzle ORM
│   ├── src/
│   │   ├── auth/           # Register, Login, JWT
│   │   ├── users/          # User service
│   │   └── database/       # Drizzle schema + module
│   ├── Dockerfile
│   ├── drizzle.config.ts
│   └── .env.example
├── scripts/
│   ├── setup-gcp.sh        # Automate GCP resource creation
│   ├── teardown-gcp.sh     # Clean up GCP resources
│   └── run-migrations.sh   # Run DB migrations via Cloud SQL Proxy
├── docker-compose.yml      # Local development
├── cloudbuild.yaml         # GCP CI/CD pipeline
└── GCP-SETUP.md            # Manual GCP setup guide
```

---

## Local Development

### Prerequisites
- Node.js 18+
- Docker & Docker Compose

### Quick Start

```bash
# 1. Clone the repo
git clone <your-repo-url>
cd study-jam-week3-monorepo

# 2. Start all services (DB + Backend + Frontend)
docker compose up --build

# 3. Run DB migrations (first time only)
cd backend
cp .env.example .env   # edit with your local values
npm run db:migrate

# Frontend: http://localhost:5173
# Backend:  http://localhost:3000
# Health:   http://localhost:3000/health
```

### Run Without Docker

```bash
# Start backend
cd backend
cp .env.example .env
npm install
npm run start:dev

# Start frontend (new terminal)
cd frontend
cp .env.example .env
npm install
npm run dev
```

---

## GCP Deployment

### Option 1 — Manual Setup (Beginners)
Follow the step-by-step guide: **[GCP-SETUP.md](./GCP-SETUP.md)**

### Option 2 — Automated Setup (Advanced)
```bash
chmod +x scripts/setup-gcp.sh
./scripts/setup-gcp.sh
```

### CI/CD Pipeline

Push to `main` → Cloud Build automatically:
1. Builds backend Docker image
2. Pushes to Artifact Registry
3. Deploys backend to Cloud Run
4. Runs health check on `/health`
5. Builds frontend (with backend URL injected)
6. Pushes to Artifact Registry
7. Deploys frontend to Cloud Run

---

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| POST | `/api/auth/register` | Register new user |
| POST | `/api/auth/login` | Login |
| GET | `/api/auth/profile` | Protected profile (JWT required) |

---

## Environment Variables

### Backend (`backend/.env.example`)
| Variable | Description |
|----------|-------------|
| `DB_HOST` | PostgreSQL host |
| `DB_PORT` | PostgreSQL port (5432) |
| `DB_NAME` | Database name |
| `DB_USER` | Database user |
| `DB_PASSWORD` | Database password (from GCP Secret Manager) |
| `JWT_SECRET` | JWT signing secret (from GCP Secret Manager) |
| `PORT` | Server port (3000) |
| `FRONTEND_URL` | CORS allowed origin |

### Frontend (`frontend/.env.example`)
| Variable | Description |
|----------|-------------|
| `VITE_API_URL` | Backend API base URL |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React 18, TypeScript, Vite 5, React Router v6 |
| Backend | NestJS 10, TypeScript, Passport, JWT |
| ORM | Drizzle ORM |
| Database | PostgreSQL 15 (GCP Cloud SQL) |
| Containerization | Docker, nginx |
| CI/CD | GCP Cloud Build |
| Container Registry | GCP Artifact Registry |
| Hosting | GCP Cloud Run |
| Secrets | GCP Secret Manager |
