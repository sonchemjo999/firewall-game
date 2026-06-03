#!/bin/bash
# ============================================================================
# NRO Shield — Master Health Check
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}--- NRO SHIELD MASTER HEALTH CHECK ---${NC}"

check_service() {
    if systemctl is-active --quiet $1; then
        echo -e "[ OK ] $2 ($1)"
    else
        echo -e "${RED}[FAIL] $2 ($1) is NOT running${NC}"
    fi
}

echo "1. System Services Status:"
check_service nroshield-api "Backend API"
check_service nroshield-ai  "AI Engine"
check_service nroshield-bot "Telegram Bot"

echo -e "\n2. Port Connectivity:"
netstat -tuln | grep -E ":5000|:3000|:8000"

echo -e "\n3. Database Connectivity:"
if mysqladmin ping -u nroshield -pNroShield2026 --silent; then
    echo -e "[ OK ] MariaDB is responsive"
else
    echo -e "${RED}[FAIL] MariaDB is NOT responsive${NC}"
fi

echo -e "\n4. Recent Errors (last 5 lines):"
tail -n 5 /var/log/nroshield/*-error.log 2>/dev/null

echo -e "\n${CYAN}--- CHECK COMPLETE ---${NC}"
