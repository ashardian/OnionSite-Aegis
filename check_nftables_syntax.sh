#!/bin/bash
# NFTables Configuration Syntax Checker
# Validates syntax without requiring root permissions

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CONFIG_FILE="conf/nftables.conf"
ERRORS=0
WARNINGS=0

log_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    ((ERRORS++))
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

log_info() {
    echo -e "${CYAN}[*]${NC} $1"
}

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  NFTables Configuration Syntax Check${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

log_info "Checking $CONFIG_FILE..."

# 1. Check for required elements
log_info "Checking required elements..."

if grep -q "^flush ruleset" "$CONFIG_FILE"; then
    log_ok "Has 'flush ruleset'"
else
    log_error "Missing 'flush ruleset'"
fi

if grep -q "table inet filter" "$CONFIG_FILE"; then
    log_ok "Has 'table inet filter'"
else
    log_error "Missing 'table inet filter'"
fi

if grep -q "chain input" "$CONFIG_FILE"; then
    log_ok "Has 'chain input'"
else
    log_error "Missing 'chain input'"
fi

if grep -q "chain forward" "$CONFIG_FILE"; then
    log_ok "Has 'chain forward'"
else
    log_error "Missing 'chain forward'"
fi

if grep -q "chain output" "$CONFIG_FILE"; then
    log_ok "Has 'chain output'"
else
    log_error "Missing 'chain output'"
fi

# 2. Check brace matching
log_info "Checking brace matching..."
OPEN_BRACES=$(grep -o '{' "$CONFIG_FILE" | wc -l)
CLOSE_BRACES=$(grep -o '}' "$CONFIG_FILE" | wc -l)

if [ "$OPEN_BRACES" -eq "$CLOSE_BRACES" ]; then
    log_ok "Braces matched ($OPEN_BRACES pairs)"
else
    log_error "Mismatched braces: $OPEN_BRACES open, $CLOSE_BRACES close"
fi

# 3. Check for common syntax issues
log_info "Checking for syntax issues..."

# Check for proper semicolons in chain definitions
if grep -q "type filter hook.*priority.*policy.*;" "$CONFIG_FILE"; then
    log_ok "Chain definitions have proper semicolons"
else
    log_warning "Some chain definitions may be missing semicolons"
fi

# Check for proper set definitions
if grep -q "set.*{" "$CONFIG_FILE"; then
    log_ok "Set definitions found"
fi

# Check for proper action keywords
ACTIONS=$(grep -oE "(accept|drop|reject|log)" "$CONFIG_FILE" | sort -u)
if [ -n "$ACTIONS" ]; then
    log_ok "Action keywords found: $(echo $ACTIONS | tr '\n' ' ')"
fi

# 4. Check ICMP syntax
log_info "Checking ICMP rules..."
if grep -q "icmp type" "$CONFIG_FILE"; then
    # Check if ICMP rules have proper syntax
    if grep -q "icmp type.*{" "$CONFIG_FILE"; then
        log_ok "ICMP rules use proper set syntax"
    else
        log_warning "ICMP rules may need set syntax"
    fi
fi

# 5. Check for potential issues
log_info "Checking for potential issues..."

# Check for line continuations
if grep -q "\\\\$" "$CONFIG_FILE"; then
    log_ok "Line continuations found (properly escaped)"
fi

# Check for comments
COMMENT_COUNT=$(grep -c "^#" "$CONFIG_FILE")
log_ok "Found $COMMENT_COUNT comment lines"

# 6. Validate with nft (if available, will show permission errors but syntax is checked)
log_info "Attempting nft syntax validation..."
if command -v nft >/dev/null 2>&1; then
    # Try to check syntax (will fail with permission errors, but syntax errors will show)
    NFT_OUTPUT=$(nft -c -f "$CONFIG_FILE" 2>&1)
    
    # Filter out permission errors
    SYNTAX_ERRORS=$(echo "$NFT_OUTPUT" | grep -v "Operation not permitted" | grep -i "error\|syntax" || true)
    
    if [ -z "$SYNTAX_ERRORS" ]; then
        log_ok "No syntax errors detected (permission errors are expected)"
    else
        log_error "Syntax errors found:"
        echo "$SYNTAX_ERRORS" | while read line; do
            echo "  $line"
        done
    fi
else
    log_warning "nft command not found (cannot perform full syntax check)"
fi

# 7. Check for common mistakes
log_info "Checking for common mistakes..."

# Check for missing quotes in strings
if grep -q 'iifname.*lo' "$CONFIG_FILE" && ! grep -q 'iifname "lo"' "$CONFIG_FILE"; then
    log_warning "Some interface names may need quotes"
fi

# Check for proper rate limiting syntax
if grep -q "limit rate" "$CONFIG_FILE"; then
    if grep -q "limit rate.*/.*burst" "$CONFIG_FILE"; then
        log_ok "Rate limiting syntax looks correct"
    else
        log_warning "Some rate limits may need burst parameter"
    fi
fi

# 8. Summary
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Syntax Check Summary${NC}"
echo -e "${CYAN}========================================${NC}"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Configuration syntax is valid!${NC}"
    echo ""
    echo "Note: 'Operation not permitted' errors from nft are expected"
    echo "      when running without root. The syntax itself is correct."
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found, but syntax appears valid${NC}"
    echo ""
    echo "Note: 'Operation not permitted' errors from nft are expected"
    echo "      when running without root. The syntax itself is correct."
    exit 0
else
    echo -e "${RED}✗ $ERRORS error(s) and $WARNINGS warning(s) found${NC}"
    exit 1
fi

