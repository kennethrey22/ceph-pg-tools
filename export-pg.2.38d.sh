#!/bin/bash
set -euo pipefail

# === CONFIGURATION ===
PGID="2.38d"
DATA_PATH="/var/lib/ceph/osd/ceph-47"
JOURNAL_PATH="/var/lib/ceph/osd/ceph-47/journal"
BASE_DIR="$(dirname "$(realpath "$0")")/outputs"
LIST_FILE="$BASE_DIR/$PGID-list-file.lst"
OUTPUT_DIR="$BASE_DIR/$PGID"

# === VALIDATION ===
mkdir -p "$OUTPUT_DIR"
if [[ ! -f "$LIST_FILE" ]]; then
    echo "[!] List file not found: $LIST_FILE"
    echo "[*] Generating list file using ceph-objectstore-tool..."
    if ! ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
        --pgid "$PGID" --op list > "$LIST_FILE" 2> /tmp/ceph_list_file_error.log; then
        echo "[!] Failed to generate list file: $LIST_FILE"
        echo "    Error details:"
        cat /tmp/ceph_list_file_error.log
        exit 1
    fi
    echo "[✓] List file generated: $LIST_FILE"
fi
if [[ ! -r "$LIST_FILE" ]]; then
    echo "[!] List file is not readable: $LIST_FILE"
    exit 1
fi
echo "[*] Exporting PG objects from $PGID"

# === MAIN LOOP ===
while IFS= read -r LINE; do
    # Skip empty lines
    [[ -z "$LINE" ]] && continue

    # Extract object dictionary and OID
    if ! OBJ_DICT=$(echo "$LINE" | jq -c '.[1]' 2>/dev/null); then
        echo "[!] Failed to parse JSON for line: $LINE"
        continue
    fi

    OID=$(echo "$OBJ_DICT" | jq -r '.oid' 2>/dev/null)

    if [[ -z "$OID" || "$OID" == "null" ]]; then
        echo "[!] Skipping invalid or missing OID in line: $LINE"
        continue
    fi

    FILE_PREFIX="$OUTPUT_DIR/$OID"
    echo "[*] Exporting $OID..."

    # === Export bytes ===
    if ! ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
        --pgid "$PGID" "$(echo "$OBJ_DICT")" get-bytes > "${FILE_PREFIX}.bytes.dat" 2>/dev/null; then
        echo "[!] Failed to export bytes for OID: $OID"
        continue
    fi

    # === Get list of attributes ===
    RAW_ATTRS_OUTPUT=$(ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
        --pgid "$PGID" "$(echo "$OBJ_DICT")" list-attrs 2>&1)

    # First try JSON parsing
    if ! echo "$RAW_ATTRS_OUTPUT" | jq empty 2>/dev/null; then
        echo "[!] Non-JSON output detected, processing as raw attributes"
        # Process raw attributes (split by newlines)
        while IFS= read -r ATTR; do
            [[ -z "$ATTR" ]] && continue  # Skip empty lines
            echo "    [+] Exporting raw attr: $ATTR"
            if ! ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
                --pgid "$PGID" "$(echo "$OBJ_DICT")" get-attr "$ATTR" > "${FILE_PREFIX}.attr.${ATTR}.dat" 2>/dev/null; then
                echo "    [!] Failed to export raw attribute: $ATTR for OID: $OID"
            fi
        done <<< "$RAW_ATTRS_OUTPUT"
        continue
    fi

    # Process JSON attributes if parsing succeeded
    if ! ATTRS=$(echo "$RAW_ATTRS_OUTPUT" | jq -r '.[]' 2>/dev/null); then
        echo "[!] Failed to parse attributes for OID: $OID"
        echo "    Raw output: $RAW_ATTRS_OUTPUT"
        continue
    fi

    for ATTR in $ATTRS; do
        echo "    [+] Exporting attr: $ATTR"
        if ! ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
            --pgid "$PGID" "$(echo "$OBJ_DICT")" get-attr "$ATTR" > "${FILE_PREFIX}.attr.${ATTR}.dat" 2>/dev/null; then
            echo "    [!] Failed to export attribute: $ATTR for OID: $OID"
        fi
    done

done < "$LIST_FILE"

echo "[✓] Export completed to $OUTPUT_DIR"
