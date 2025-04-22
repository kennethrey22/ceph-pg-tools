Ceph PG Object Export & Import Scripts
This repository provides two Bash scripts to facilitate object-level export and import operations for Ceph Placement Groups (PGs). These tools are particularly useful for scenarios involving PG recovery, migration, or backup.​

📁 Scripts Overview
export.sh: Exports objects (data and attributes) from a specified source PG to a designated output directory.​
Open Source Stack Exchange

import.sh: Imports previously exported objects into a specified destination PG from the designated input directory.​

🛠 Prerequisites
Ensure the following before using the scripts:

Ceph Environment: A functional Ceph cluster with access to the necessary OSD data and journal paths.​

Tools Installed:

ceph-objectstore-tool

jq (for JSON processing)​
Wikipedia, l'enciclopedia libera

Permissions: Adequate permissions to read from and write to the Ceph OSD directories and journals.​

OSD State: It's recommended to stop the target OSD daemon before performing import operations to prevent data inconsistencies.​

📤 Export Script: export.sh
🔍 Description
The export.sh script exports all objects from a specified source PG, including their data and associated attributes, and saves them into an organized directory structure.​

⚙️ Configuration
Set the following variables within the script:​
MIT Technology Licensing Office

bash
Copy
Edit
PGID="2.17"  # Source PG ID
DATA_PATH="/var/lib/ceph/osd/ceph-0"
JOURNAL_PATH="/var/lib/ceph/osd/ceph-0/journal"
BASE_DIR="$(dirname "$(realpath "$0")")/outputs"
LIST_FILE="$BASE_DIR/$PGID-list-file.lst"
OUTPUT_DIR="$BASE_DIR/$PGID"
🚀 Usage
bash
Copy
Edit
sudo ./export.sh
📁 Output Structure
The exported files will be organized as follows:​

Data Files: <oid>.bytes.dat

Attribute Files: <oid>.attr.<attribute_name>.dat​
Massachusetts Institute of Technology

All files are stored in the directory specified by OUTPUT_DIR.​

📥 Import Script: import.sh
🔍 Description
The import.sh script imports previously exported object data and attributes into a specified destination PG.​

⚙️ Configuration
Set the following variables within the script:​

bash
Copy
Edit
SRC_PGID="2.17"  # Source PG ID (for reference)
DST_PGID="2.0"   # Destination PG ID
DATA_PATH="/var/lib/ceph/osd/ceph-0"
JOURNAL_PATH="/var/lib/ceph/osd/ceph-0/journal"
BASE_DIR="$(dirname "$(realpath "$0")")/outputs"
SRC_DIR="$BASE_DIR/$SRC_PGID"
🚀 Usage
bash
Copy
Edit
sudo ./import.sh
📁 Input Structure
The script expects the input directory (SRC_DIR) to contain files structured as:​

Data Files: <oid>.bytes.dat

Attribute Files: <oid>.attr.<attribute_name>.dat​

These should correspond to the outputs from the export.sh script.​

⚠️ Important Notes
OSD Daemon: Ensure the target OSD daemon is stopped before performing import operations to prevent data corruption.​

Data Consistency: Always verify the integrity and consistency of the data before and after import/export operations.​

Backup: It's recommended to back up existing data before performing import operations.​

🧪 Testing & Validation
After performing export/import operations:​

Verify Object Presence: Use ceph-objectstore-tool to list objects in the target PG and ensure the expected objects are present.​

Check Data Integrity: Compare checksums of the original and imported data files to ensure integrity.​

Monitor Ceph Health: Use ceph health to monitor the overall health of the Ceph cluster.​

📄 License
This project is licensed under the MIT License.​

