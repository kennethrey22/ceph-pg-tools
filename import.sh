#!/bin/bash
set -e

PGID=$1
DATA_PATH=$2
JOURNAL_PATH=$3
BACKUP_DIR=$4

echo "[*] Importing objects into PG: $PGID"

find "$BACKUP_DIR" -type f > /tmp/pg-import-list.txt

while IFS= read -r FILE; do
    BASENAME=$(basename "$FILE")

    if [[ "$BASENAME" == *.bytes.dat ]]; then
        OID=$(echo "$BASENAME" | cut -d. -f1-3)
        echo "[*] Restoring bytes for $OID"
        ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
            --pgid "$PGID" "$OID" set-bytes "$FILE"

    elif [[ "$BASENAME" == *.attr.*.dat ]]; then
        OID=$(echo "$BASENAME" | cut -d. -f1-3)
        ATTR=$(echo "$BASENAME" | cut -d. -f5)
        echo "[*] Restoring attr $ATTR for $OID"
        ceph-objectstore-tool --data-path "$DATA_PATH" --journal-path "$JOURNAL_PATH" \
            --pgid "$PGID" "$OID" set-attr "$ATTR" "$FILE"
    fi

done < /tmp/pg-import-list.txt

echo "[✓] Import complete."
