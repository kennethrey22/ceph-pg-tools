#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
DATA_PATH="/var/lib/ceph/osd/ceph-0"
JOURNAL_PATH="/var/lib/ceph/osd/ceph-0/journal"
BASE_DIR="$(dirname "$(realpath "$0")")/outputs"

# === FUNCTION DEFINITIONS ===
do_export() {
    read -p "Enter source PG ID (e.g., 2.17): " PGID
    [[ -z "$PGID" ]] && { echo "PG ID cannot be empty"; return 1; }
    
    # Source the export script
    source "$(dirname "$0")/export.sh"
}

do_import() {
    read -p "Enter source PG ID (e.g., 2.17): " SRC_PGID
    read -p "Enter destination PG ID (e.g., 2.0): " DST_PGID
    
    [[ -z "$SRC_PGID" ]] && { echo "Source PG ID cannot be empty"; return 1; }
    [[ -z "$DST_PGID" ]] && { echo "Destination PG ID cannot be empty"; return 1; }
    
    # Source the import script
    source "$(dirname "$0")/import.sh"
}

do_delete() {
    if [[ ! -d "$BASE_DIR" ]]; then
        echo "[!] No output directory found at: $BASE_DIR"
        return 1
    fi

    echo "Available PG outputs:"
    ls -1 "$BASE_DIR" 2>/dev/null || { echo "No PG outputs found"; return 1; }
    
    read -p "Enter PG ID to delete (or 'all' for everything): " DEL_PGID
    [[ -z "$DEL_PGID" ]] && { echo "PG ID cannot be empty"; return 1; }
    
    if [[ "$DEL_PGID" == "all" ]]; then
        read -p "Are you sure you want to delete all PG outputs? [y/N] " confirm
        [[ "$confirm" == "y" || "$confirm" == "Y" ]] && rm -rf "${BASE_DIR:?}"/*
    else
        if [[ -e "$BASE_DIR/$DEL_PGID" || -e "$BASE_DIR/$DEL_PGID-list-file.lst" ]]; then
            rm -rf "$BASE_DIR/$DEL_PGID" "$BASE_DIR/$DEL_PGID-list-file.lst"
            echo "[✓] Deleted PG $DEL_PGID outputs"
        else
            echo "[!] No outputs found for PG $DEL_PGID"
            return 1
        fi
    fi
}

# === MAIN MENU ===
while true; do
    echo
    echo "=== Ceph PG Tool ==="
    echo "1) Export PG objects"
    echo "2) Import PG objects"
    echo "3) Delete PG outputs"
    echo "q) Quit"
    echo
    read -p "Select an option: " choice

    case "$choice" in
        1)
            echo "=== Export Mode ==="
            do_export
            ;;
        2)
            echo "=== Import Mode ==="
            do_import
            ;;
        3)
            echo "=== Delete Mode ==="
            do_delete
            ;;
        q|Q)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
done
