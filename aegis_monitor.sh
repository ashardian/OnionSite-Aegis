#!/bin/bash

# ==============================================================================
# ONIONSITE-AEGIS | HUD Monitor (Session-Based Architect Edition)
# FIX: Ignores old history. Starts fresh every time you run it.
# ==============================================================================

# --- CONFIGURATION ---
REFRESH_RATE=2
SENTRY_LOG="/var/log/tor/sentry.log"
TOR_LOG="/var/log/tor/notices.log"
ONION_KEY="/var/lib/tor/hidden_service/hostname"

# --- VISUALS ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
GREY='\033[0;90m'
NC='\033[0m'

# --- ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[CRITICAL] This dashboard requires ROOT access.${NC}"
   exit 1
fi

# --- SESSION INITIALIZATION (The Fix) ---
# We calculate the current line count of the log file.
# The monitor will ONLY look at lines added AFTER this point.
if [ -f "$SENTRY_LOG" ]; then
    START_LINE=$(wc -l < "$SENTRY_LOG")
else
    START_LINE=0
fi

# --- HELPER FUNCTIONS ---

get_cpu_mem() {
    PID=$(pgrep -f "$1" | head -n 1)
    if [ -n "$PID" ]; then
        ps -p "$PID" -o %cpu,%mem --no-headers | awk '{print $1"% / "$2"%"}'
    else
        echo "0.0% / 0.0%"
    fi
}

get_status_icon() {
    if systemctl is-active --quiet "$1"; then echo -e "${GREEN}● ONLINE ${NC}"; else echo -e "${RED}✖ OFFLINE${NC}"; fi
}

get_process_icon() {
    if pgrep -f "$1" > /dev/null; then echo -e "${GREEN}● ACTIVE ${NC}"; else echo -e "${RED}✖ STOPPED${NC}"; fi
}

draw_bar() {
    PERC=$1
    BAR_LEN=20
    if ! [[ "$PERC" =~ ^[0-9]+$ ]]; then PERC=0; fi
    FILLED=$(awk -v p="$PERC" -v l="$BAR_LEN" 'BEGIN { printf "%.0f", (p/100)*l }')
    EMPTY=$((BAR_LEN - FILLED))
    printf "["
    if [ "$FILLED" -gt 0 ]; then printf "%0.s#" $(seq 1 $FILLED); fi
    if [ "$EMPTY" -gt 0 ]; then printf "%0.s." $(seq 1 $EMPTY); fi
    printf "]"
}

# --- SETUP SCREEN ---
clear

# --- MAIN RENDER LOOP ---
trap 'echo -e "\n${GREEN}Monitor closed.${NC}"; exit 0' SIGINT

while true; do
    tput cup 0 0

    # 1. GATHER DATA
    LOAD_AVG=$(awk '{print $1}' /proc/loadavg)
    RAM_USED=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    UPTIME=$(uptime -p | cut -d " " -f2-)
    
    # --- SESSION LOGIC ---
    # Only count lines starting from START_LINE to END
    if [ -f "$SENTRY_LOG" ]; then
        CURRENT_LINE=$(wc -l < "$SENTRY_LOG")
        # Ensure we don't crash if log rotated (became smaller)
        if [ "$CURRENT_LINE" -lt "$START_LINE" ]; then START_LINE=0; fi
        
        # Extract ONLY the new lines for this session
        NEW_LOGS=$(tail -n +$((START_LINE + 1)) "$SENTRY_LOG" 2>/dev/null)
        
        # Count stats only from this session's logs
        ATTACKS=$(echo "$NEW_LOGS" | grep -c "ATTACK")
        WARNINGS=$(echo "$NEW_LOGS" | grep -c "WARNING")
    else
        ATTACKS=0
        WARNINGS=0
    fi
    
    # 2. RENDER HEADER
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "   ${CYAN}🛡️  ONIONSITE-AEGIS HUD Monitor${NC}   |   ${GREY}SESSION LIVE${NC}"
    echo -e "${BLUE}======================================================================${NC}"
    
    # 3. SYSTEM VITALS
    printf "${WHITE}%-20s %-20s %-20s${NC}\033[K\n" "SYSTEM LOAD" "RAM USAGE" "UPTIME"
    printf "${GREEN}%-20s %-20s %-20s${NC}\033[K\n" "$LOAD_AVG" "$RAM_USED" "$UPTIME"
    echo -e "\033[K"

    # 4. INFRASTRUCTURE
    echo -e "${YELLOW}[ INFRASTRUCTURE STATUS ]${NC}\033[K"
    printf "${GREY}%-15s %-12s %-15s %-15s${NC}\033[K\n" "SERVICE" "STATUS" "CPU/MEM" "PORT"
    printf "%-15s %-20s %-15s %-15s\033[K\n" "Tor Daemon" "$(get_status_icon tor@default)" "$(get_cpu_mem /usr/bin/tor)" "9050/9051"
    printf "%-15s %-20s %-15s %-15s\033[K\n" "Nginx Web" "$(get_status_icon nginx)" "$(get_cpu_mem nginx)" "80 (Local)"
    printf "%-15s %-20s %-15s %-15s\033[K\n" "Neural Sentry" "$(get_process_icon neural_sentry.py)" "$(get_cpu_mem neural_sentry.py)" "Internal"
    echo -e "\033[K"

    # 5. LIVE DEFENSE STATS
    echo -e "${YELLOW}[ LIVE DEFENSE STATS ]${NC}\033[K"
    
    if [ "$ATTACKS" -gt 0 ]; then
        STATUS_MSG="UNDER ATTACK"
        STATUS_COLOR=$RED
    else
        STATUS_MSG="SECURE"
        STATUS_COLOR=$GREEN
    fi
    
    printf "Session Status: ${STATUS_COLOR}%-18s${NC} [ New Attacks: ${RED}%s${NC} | New Warnings: ${YELLOW}%s${NC} ]\033[K\n" "$STATUS_MSG" "$ATTACKS" "$WARNINGS"
    
    # RAM Check
    if mount | grep -q "/var/log/tor type tmpfs"; then
        RAM_USAGE=$(df -h /var/log/tor | awk 'NR==2 {print $5}' | tr -d '%')
        echo -n "Amnesic Logs:   "
        draw_bar "$RAM_USAGE"
        echo -e " ${GREEN}SECURE (RAM)${NC}\033[K"
    else
        echo -e "Amnesic Logs:   ${RED}CRITICAL FAIL (HDD WRITE DETECTED)${NC}\033[K"
    fi
    echo -e "\033[K"
    
    # 6. ONION ID
    if [ -f "$ONION_KEY" ]; then
        ADDR=$(cat "$ONION_KEY")
        echo -e "${CYAN}[ HIDDEN SERVICE ]${NC} ${WHITE}$ADDR${NC}\033[K"
    else
        echo -e "${CYAN}[ HIDDEN SERVICE ]${NC} ${YELLOW}Generating Keys...${NC}\033[K"
    fi

    # 7. LIVE TICKER (Strict Filter)
    echo -e "\033[K"
    echo -e "${GREY}--- REAL-TIME SECURITY FEED (Session Only) ---${NC}\033[K"
    
    # Logic: Show the last 3 *relevant* lines from the NEW logs
    if [ -n "$NEW_LOGS" ]; then
        EVENTS=$(echo "$NEW_LOGS" | grep -E "CRITICAL|WARNING|ATTACK" | tail -n 3)
        
        if [ -n "$EVENTS" ]; then
             echo "$EVENTS" | while read line; do
                clean_line=$(echo "$line" | cut -c 1-80)
                if [[ "$clean_line" == *"CRITICAL"* ]] || [[ "$clean_line" == *"ATTACK"* ]]; then
                    echo -e "${RED}> $clean_line${NC}\033[K"
                elif [[ "$clean_line" == *"WARNING"* ]]; then
                    echo -e "${YELLOW}> $clean_line${NC}\033[K"
                else
                    echo -e "${GREY}> $clean_line${NC}\033[K"
                fi
            done
            # Pad empty lines
            count=$(echo "$EVENTS" | wc -l)
            remaining=$((3 - count))
            for ((i=0; i<remaining; i++)); do echo -e "\033[K"; done
        else
            echo -e "${GREY}> No new threats detected in this session.${NC}\033[K"
            echo -e "\033[K"
            echo -e "\033[K"
        fi
    else
        echo -e "${GREY}> Session Started. Waiting for activity...${NC}\033[K"
        echo -e "\033[K"
        echo -e "\033[K"
    fi

    echo -e "${BLUE}======================================================================${NC}\033[K"
    
    sleep "$REFRESH_RATE"
done
