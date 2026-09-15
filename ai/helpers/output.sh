#!/bin/sh

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output functions
error() {
    printf '%b%s%b\n' "$RED" "Error: $1" "$NC" >&2
}

warning() {
    printf '%b%s%b\n' "$YELLOW" "Warning: $1" "$NC"
}

success() {
    printf '%b%s%b\n' "$GREEN" "✓ $1" "$NC"
}

info() {
    printf '%b%s%b\n' "$BLUE" "$1" "$NC"
}

# Exit with error message
die() {
    error "$1"
    exit 1
}
