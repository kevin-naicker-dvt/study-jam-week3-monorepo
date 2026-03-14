#!/usr/bin/env bash
# =============================================================================
# Run Drizzle DB Migrations via Cloud SQL Auth Proxy
# Requires: cloud-sql-proxy binary in PATH
# =============================================================================

set -euo pipefail

PROJECT_ID="dvt-lab-devfest-2025"
REGION="africa-south1"
DB_INSTANCE="studyjam-db"
CONNECTION_NAME="${PROJECT_ID}:${REGION}:${DB_INSTANCE}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${YELLOW}Starting Cloud SQL Auth Proxy...${NC}"
cloud-sql-proxy "${CONNECTION_NAME}" --port=5432 &
PROXY_PID=$!
sleep 3

echo -e "${YELLOW}Running migrations...${NC}"
cd "$(dirname "$0")/../backend"

[ -f .env ] || { echo "Copy .env.example to .env and fill in credentials"; kill $PROXY_PID; exit 1; }

DB_HOST=127.0.0.1 npm run db:migrate

kill $PROXY_PID
echo -e "${GREEN}Migrations complete.${NC}"
