#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
DATA_PATH="/var/lib/ceph/osd/ceph-0"
JOURNAL_PATH="/var/lib/ceph/osd/ceph-0/journal"
BASE_DIR="$(dirname "$(realpath "$0")")/outputs"

# === FUNCTION DEFINITIONS ===
do_export() {
    local PGID=$1
    local LIST_FILE="$BASE_DIR/$PGID-list-file.lst"
    local OUTPUT_DIR="$BASE_DIR/$PGID"

    mkdir -p "$OUTPUT_DIR"
    if [[ ! -f "$LIST_FILE" ]]; then
        echo "[*] Generating list file using ceph-objectstore-tool..."
        if ! ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
            --pgid "$PGID" --op list > "$LIST_FILE" 2> /tmp/ceph_list_file_error.log; then
            echo "[!] Failed to generate list file: $LIST_FILE"
            cat /tmp/ceph_list_file_error.log
            return 1
        fi
        echo "[✓] List file generated: $LIST_FILE"
    fi

    echo "[*] Exporting PG objects from $PGID"

    while IFS= read -r LINE; do
        [[ -z "$LINE" ]] && continue

        if ! OBJ_DICT=$(echo "$LINE" | jq -c '.[1]' 2>/dev/null); then
            echo "[!] Failed to parse JSON for line: $LINE"
            continue
        fi

        OID=$(echo "$OBJ_DICT" | jq -r '.oid' 2>/dev/null)
        [[ -z "$OID" || "$OID" == "null" ]] && continue

        FILE_PREFIX="$OUTPUT_DIR/$OID"
        echo "[*] Exporting $OID..."

        if ! ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
            --pgid "$PGID" "$(echo "$OBJ_DICT")" get-bytes > "${FILE_PREFIX}.bytes.dat" 2>/dev/null; then
            echo "[!] Failed to export bytes for OID: $OID"
            continue
        fi

        RAW_ATTRS_OUTPUT=$(ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
            --pgid "$PGID" "$(echo "$OBJ_DICT")" list-attrs 2>&1)

        if ! echo "$RAW_ATTRS_OUTPUT" | jq empty 2>/dev/null; then
            echo "[!] Non-JSON output detected, processing as raw attributes"
            while IFS= read -r ATTR; do
                [[ -z "$ATTR" ]] && continue
                echo "    [+] Exporting raw attr: $ATTR"
                ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
                    --pgid "$PGID" "$(echo "$OBJ_DICT")" get-attr "$ATTR" > "${FILE_PREFIX}.attr.${ATTR}.dat" 2>/dev/null
            done <<< "$RAW_ATTRS_OUTPUT"
            continue
        fi

        ATTRS=$(echo "$RAW_ATTRS_OUTPUT" | jq -r '.[]' 2>/dev/null)
        for ATTR in $ATTRS; do
            echo "    [+] Exporting attr: $ATTR"
            ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
                --pgid "$PGID" "$(echo "$OBJ_DICT")" get-attr "$ATTR" > "${FILE_PREFIX}.attr.${ATTR}.dat" 2>/dev/null
        done
    done < "$LIST_FILE"

    echo "[✓] Export completed to $OUTPUT_DIR"
}

do_import() {
    local SRC_PGID=$1
    local DST_PGID=$2
    local SRC_DIR="$BASE_DIR/$SRC_PGID"

    [[ ! -d "$SRC_DIR" ]] && { echo "[!] Source directory not found: $SRC_DIR"; return 1; }

    if ! ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
        --pgid "$DST_PGID" --op list >/dev/null 2>&1; then
        echo "[!] Destination PG $DST_PGID is not accessible"
        return 1
    fi

    echo "[*] Importing PG objects from $SRC_DIR to PG $DST_PGID"

    for BYTES_FILE in "$SRC_DIR"/*.bytes.dat; do
        [[ -f "$BYTES_FILE" ]] || continue

        OID=$(basename "$BYTES_FILE" .bytes.dat)
        echo "[*] Importing $OID..."

        OBJ_DICT=$(printf '{"oid":"%s","key":"","snapid":-2,"hash":0,"max":0,"pool":2,"namespace":""}' "$OID")

        if ! ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
            --pgid "$DST_PGID" "$OBJ_DICT" set-bytes < "$BYTES_FILE" 2>/dev/null; then
            echo "[!] Failed to import bytes for OID: $OID"
            continue
        fi

        for ATTR_FILE in "$SRC_DIR/$OID.attr."*.dat; do
            [[ -f "$ATTR_FILE" ]] || continue
            
            ATTR=$(basename "$ATTR_FILE" .dat | sed "s/$OID\.attr\.//")
            echo "    [+] Importing attr: $ATTR"
            
            ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
                --pgid "$DST_PGID" "$OBJ_DICT" set-attr "$ATTR" < "$ATTR_FILE" 2>/dev/null
        done
    done

    echo "[✓] Import completed to PG $DST_PGID"
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

do_list() {
    if [[ ! -d "$BASE_DIR" ]]; then
        echo "[!] No output directory found at: $BASE_DIR"
        return 1
    fi

    echo "=== Exported PGs ==="
    echo "Location: $BASE_DIR"
    echo

    {
        find "$BASE_DIR" -maxdepth 1 -type d -name "[0-9]*.[0-9]*" -printf "%f\n"
        find "$BASE_DIR" -maxdepth 1 -type f -name "*-list-file.lst" -printf "%f\n" | sed 's/-list-file.lst//'
    } | sort -u | while read -r PGID; do
        OBJECTS=$(find "$BASE_DIR/$PGID" -name "*.bytes.dat" 2>/dev/null | wc -l)
        echo "PG $PGID: $OBJECTS objects"
    done
}

do_read() {
    if [[ ! -d "$BASE_DIR" ]]; then
        echo "[!] No output directory found at: $BASE_DIR"
        return 1
    fi

    echo "Available PGs:"
    {
        find "$BASE_DIR" -maxdepth 1 -type d -name "[0-9]*.[0-9]*" -printf "%f\n"
        find "$BASE_DIR" -maxdepth 1 -type f -name "*-list-file.lst" -printf "%f\n" | sed 's/-list-file.lst//'
    } | sort -u || { echo "No PGs found"; return 1; }

    read -p "Enter PG ID to read: " READ_PGID
    [[ -z "$READ_PGID" ]] && { echo "PG ID cannot be empty"; return 1; }

    local PG_DIR="$BASE_DIR/$READ_PGID"
    if [[ ! -d "$PG_DIR" ]]; then
        echo "[!] PG directory not found: $PG_DIR"
        return 1
    fi

    echo
    echo "=== PG $READ_PGID Contents ==="
    echo "Objects:"
    for BYTES_FILE in "$PG_DIR"/*.bytes.dat; do
        [[ -f "$BYTES_FILE" ]] || continue
        OID=$(basename "$BYTES_FILE" .bytes.dat)
        SIZE=$(stat -c%s "$BYTES_FILE")
        echo "- $OID (${SIZE} bytes)"
        
        echo "  Attributes:"
        for ATTR_FILE in "$PG_DIR/$OID.attr."*.dat; do
            [[ -f "$ATTR_FILE" ]] || continue
            ATTR=$(basename "$ATTR_FILE" .dat | sed "s/$OID\.attr\.//")
            ATTR_SIZE=$(stat -c%s "$ATTR_FILE")
            echo "  - $ATTR (${ATTR_SIZE} bytes)"
        done
        echo
    done
}

# === MAIN MENU ===
while true; do
    echo
    echo "=== Ceph PG Tool ==="
    echo "1) Export PG objects"
    echo "2) Import PG objects"
    echo "3) Delete PG outputs"
    echo "4) List exported PGs"
    echo "5) Read PG contents"
    echo "q) Quit"
    echo
    read -p "Select an option: " choice

    case "$choice" in
        1)
            echo "=== Export Mode ==="
            read -p "Enter source PG ID (e.g., 2.17): " PGID
            [[ -z "$PGID" ]] && { echo "PG ID cannot be empty"; continue; }
            do_export "$PGID"
            ;;
        2)
            echo "=== Import Mode ==="
            read -p "Enter source PG ID (e.g., 2.17): " SRC_PGID
            read -p "Enter destination PG ID (e.g., 2.0): " DST_PGID
            [[ -z "$SRC_PGID" ]] && { echo "Source PG ID cannot be empty"; continue; }
            [[ -z "$DST_PGID" ]] && { echo "Destination PG ID cannot be empty"; continue; }
            do_import "$SRC_PGID" "$DST_PGID"
            ;;
        3)
            echo "=== Delete Mode ==="
            do_delete
            ;;
        4)
            echo "=== List Mode ==="
            do_list
            ;;
        5)
            echo "=== Read Mode ==="
            do_read
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
