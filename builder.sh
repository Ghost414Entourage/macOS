#!/bin/bash

# Ensure a YAML file was passed as an argument
if [ -z "$1" ]; then
  echo "Error: Please specify a YAML schema file."
  echo "Usage: ./builder.sh <path-to-schema.yaml>"
  exit 1
fi

YAML_FILE="$1"

if [ ! -f "$YAML_FILE" ]; then
  echo "Error: File '$YAML_FILE' not found."
  exit 1
fi

# 1. Dynamically extract PayloadType from the YAML file
PAYLOAD_TYPE=$(grep -E "^[[:space:]]*payloadtype:" "$YAML_FILE" | head -n 1 | awk '{print $2}' | tr -d '"' | tr -d "'")
if [ -z "$PAYLOAD_TYPE" ]; then
  PAYLOAD_TYPE="com.apple.applicationaccess"
fi

# 2. Extract profile title or use the filename as default
PROFILE_NAME=$(grep -E "^[[:space:]]*title:" "$YAML_FILE" | head -n 1 | sed 's/.*title:[[:space:]]*//' | tr -d '"' | tr -d "'")
if [ -z "$PROFILE_NAME" ]; then
  PROFILE_NAME=$(basename "$YAML_FILE" .yaml)
fi

PROFILE_ID="com.custom.profile.${PROFILE_NAME// /_}"
PROFILE_UUID=$(uuidgen)
PAYLOAD_UUID=$(uuidgen)
OUTPUT_FILE="${PROFILE_NAME// /_}.mobileconfig"
TEMP_JSON="/tmp/profile_temp.json"

# 3. Extract ALL 'key:' definitions under payloadkeys in the YAML file
# Matches lines like "key: allowAirDrop" or "- key: allowAirDrop"
KEYS=($(grep -E "^[[:space:]]*(-[[:space:]]*)?key:" "$YAML_FILE" | awk '{print $NF}' | tr -d '"' | tr -d "'" | sort -u))

if [ ${#KEYS[@]} -eq 0 ]; then
  echo "Error: No keys found in $YAML_FILE."
  exit 1
fi

# 4. Start building the JSON structure
cat <<EOF > "$TEMP_JSON"
{
  "PayloadIdentifier": "$PROFILE_ID",
  "PayloadUUID": "$PROFILE_UUID",
  "PayloadType": "Configuration",
  "PayloadVersion": 1,
  "PayloadDisplayName": "$PROFILE_NAME",
  "PayloadOrganization": "Custom IT",
  "PayloadScope": "System",
  "PayloadContent": [
    {
      "PayloadType": "$PAYLOAD_TYPE",
      "PayloadIdentifier": "${PROFILE_ID}.payload",
      "PayloadUUID": "$PAYLOAD_UUID",
      "PayloadVersion": 1,
      "PayloadDisplayName": "$PROFILE_NAME Settings"
EOF

echo "=========================================="
echo " Schema: $PROFILE_NAME"
echo " Domain: $PAYLOAD_TYPE"
echo " Found ${#KEYS[@]} key(s) in $YAML_FILE"
echo "=========================================="
echo ""

# 5. Prompt for each key found in the YAML schema
for key in "${KEYS[@]}"; do
  # macOS native GUI popup
  CHOICE=$(osascript -e "button returned of (display dialog \"Setting: $key\n\nChoose value for this key:\" buttons {\"Skip\", \"False\", \"True\"} default button \"False\")" 2>/dev/null)

  # Fallback to terminal input if GUI dialog is dismissed or fails
  if [ -z "$CHOICE" ]; then
    read -p "Set $key (t=True / f=False / s=Skip) [f]: " response
    case "$response" in
      [Yy3Tt]*) CHOICE="True" ;;
      [Ss]*) CHOICE="Skip" ;;
      *) CHOICE="False" ;;
    esac
  fi

  # Skip key if user selected "Skip"
  if [ "$CHOICE" == "Skip" ]; then
    echo " [SKIP] $key"
    continue
  fi

  if [ "$CHOICE" == "True" ]; then
    VAL="true"
  else
    VAL="false"
  fi

  # Append key-value entry to JSON
  echo "      ,\"$key\": $VAL" >> "$TEMP_JSON"
  echo " [SET]  $key = $VAL"
done

# Close JSON tags
cat <<EOF >> "$TEMP_JSON"
    }
  ]
}
EOF

# Convert compiled JSON to Apple XML .mobileconfig via native plutil
plutil -convert xml1 "$TEMP_JSON" -o "$OUTPUT_FILE"
rm -f "$TEMP_JSON"

echo ""
echo "Successfully generated: $OUTPUT_FILE"
