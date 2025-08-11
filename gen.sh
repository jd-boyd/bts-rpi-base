#!/bin/bash
#
# BTS Raspberry Pi Project Generator
# Author: Joshua D. Boyd
#
# Generates a new Raspberry Pi project from the bts-rpi-base template
# with customized application names and references.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory (where bts-rpi-base template is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR"

usage() {
    echo "Usage: $0 <target-dir> <target-name>"
    echo ""
    echo "Arguments:"
    echo "  target-dir    Directory where the new project will be created"
    echo "  target-name   Name for the application (used for service, files, etc.)"
    echo ""
    echo "Examples:"
    echo "  $0 ../my-sensor-project sensor-monitor"
    echo "  $0 /home/user/projects/iot-logger data-logger"
    echo "  $0 ./weather-station weather"
    echo ""
    echo "This will:"
    echo "  - Copy all template files to target-dir"
    echo "  - Rename app.py to target-name.py"
    echo "  - Rename app.service to target-name.service"
    echo "  - Update all references in files to use target-name"
    echo "  - Create a ready-to-build project"
    exit 1
}

# Validate arguments
if [ $# -ne 2 ]; then
    echo -e "${RED}Error: Wrong number of arguments${NC}"
    usage
fi

TARGET_DIR="$1"
TARGET_NAME="$2"

# Validate target name (should be suitable for systemd service names)
if [[ ! "$TARGET_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
    echo -e "${RED}Error: Target name must start with alphanumeric character and contain only letters, numbers, hyphens, and underscores${NC}"
    exit 1
fi

# Check if target directory already exists
if [ -d "$TARGET_DIR" ]; then
    echo -e "${RED}Error: Target directory already exists: $TARGET_DIR${NC}"
    exit 1
fi

# Validate template directory
if [ ! -f "$TEMPLATE_DIR/raspberry-pi.pkr.hcl" ]; then
    echo -e "${RED}Error: Template files not found in $TEMPLATE_DIR${NC}"
    echo "Make sure you're running this script from the bts-rpi-base directory"
    exit 1
fi

# Check if files are in files/ subdirectory or root
if [ -f "$TEMPLATE_DIR/files/app.py" ]; then
    FILES_DIR="files"
    echo "Using files/ subdirectory structure"
elif [ -f "$TEMPLATE_DIR/app.py" ]; then
    FILES_DIR=""
    echo "Using root directory structure"
else
    echo -e "${RED}Error: Cannot find app.py in template${NC}"
    exit 1
fi

echo -e "${BLUE}BTS Raspberry Pi Project Generator${NC}"
echo -e "${BLUE}Author: Joshua D. Boyd${NC}"
echo ""
echo "Creating new project:"
echo "  Template: $TEMPLATE_DIR"
echo "  Target:   $TARGET_DIR"
echo "  App Name: $TARGET_NAME"
echo ""

# Create target directory
echo -e "${YELLOW}Creating project directory...${NC}"
mkdir -p "$TARGET_DIR"

# Copy all files except .git
echo -e "${YELLOW}Copying template files...${NC}"
rsync -av \
    --exclude='.git' \
    --exclude='.gitignore' \
    --exclude='*.img' \
    --exclude='*.img.gz' \
    --exclude='output/' \
    --exclude='packer.log' \
    "$TEMPLATE_DIR/" "$TARGET_DIR/"

# Create files directory if it doesn't exist and files are in root
if [ -z "$FILES_DIR" ]; then
    echo -e "${YELLOW}Creating files/ directory and moving template files...${NC}"
    mkdir -p "$TARGET_DIR/files"

    # Move template files to files/ directory
    [ -f "$TARGET_DIR/app.py" ] && mv "$TARGET_DIR/app.py" "$TARGET_DIR/files/"
    [ -f "$TARGET_DIR/app.service" ] && mv "$TARGET_DIR/app.service" "$TARGET_DIR/files/"
    [ -f "$TARGET_DIR/requirements.txt" ] && mv "$TARGET_DIR/requirements.txt" "$TARGET_DIR/files/"
    [ -f "$TARGET_DIR/app-update.sh" ] && mv "$TARGET_DIR/app-update.sh" "$TARGET_DIR/files/"

    # Update FILES_DIR for subsequent operations
    FILES_DIR="files"
fi

# File renaming operations
echo -e "${YELLOW}Renaming files...${NC}"

# Rename the main application file
if [ -f "$TARGET_DIR/$FILES_DIR/app.py" ]; then
    mv "$TARGET_DIR/$FILES_DIR/app.py" "$TARGET_DIR/$FILES_DIR/$TARGET_NAME.py"
    echo "  app.py -> $TARGET_NAME.py"
fi

# Rename the systemd service file
if [ -f "$TARGET_DIR/$FILES_DIR/app.service" ]; then
    mv "$TARGET_DIR/$FILES_DIR/app.service" "$TARGET_DIR/$FILES_DIR/$TARGET_NAME.service"
    echo "  app.service -> $TARGET_NAME.service"
fi

# Rename the update script (keep generic name but update contents)
if [ -f "$TARGET_DIR/$FILES_DIR/app-update.sh" ]; then
    mv "$TARGET_DIR/$FILES_DIR/app-update.sh" "$TARGET_DIR/$FILES_DIR/$TARGET_NAME-update.sh"
    echo "  app-update.sh -> $TARGET_NAME-update.sh"
fi

# Update file contents
echo -e "${YELLOW}Updating file references...${NC}"

# List of files to update
declare -a FILES_TO_UPDATE=(
    "$TARGET_DIR/raspberry-pi.pkr.hcl"
    "$TARGET_DIR/$FILES_DIR/$TARGET_NAME.py"
    "$TARGET_DIR/$FILES_DIR/$TARGET_NAME.service"
    "$TARGET_DIR/$FILES_DIR/$TARGET_NAME-update.sh"
    "$TARGET_DIR/build.sh"
    "$TARGET_DIR/build-container.sh"
    "$TARGET_DIR/deploy-update.sh"
    "$TARGET_DIR/README.md"
)

# Update references in files
for file in "${FILES_TO_UPDATE[@]}"; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "  Updating $filename..."

        # Create temporary file for sed operations
        temp_file=$(mktemp)

        # Replace various app-related references
        sed \
            -e "s/app/$TARGET_NAME/g" \
            -e "s/app\.py/$TARGET_NAME.py/g" \
            -e "s/app-update/$TARGET_NAME-update/g" \
            -e "s/App/$(echo $TARGET_NAME | sed 's/-/_/g' | awk '{print toupper(substr($0,1,1)) substr($0,2)}')/g" \
            -e "s/\/opt\/app\.py/\/opt\/app\/$TARGET_NAME.py/g" \
            -e "s/files\/app\.py/files\/$TARGET_NAME.py/g" \
            -e "s/files\/app\.service/files\/$TARGET_NAME.service/g" \
            -e "s/files\/app-update\.sh/files\/$TARGET_NAME-update.sh/g" \
            "$file" > "$temp_file"

        # Replace the original file
        mv "$temp_file" "$file"
    fi
done

# Update specific configurations
echo -e "${YELLOW}Updating project configuration...${NC}"

# Update the Packer template with the new service name
if [ -f "$TARGET_DIR/raspberry-pi.pkr.hcl" ]; then
    # Update the service file reference in Packer template
    sed -i "s/app\.service/$TARGET_NAME.service/g" "$TARGET_DIR/raspberry-pi.pkr.hcl"
    # Update the update script reference
    sed -i "s/app-update\.sh/$TARGET_NAME-update.sh/g" "$TARGET_DIR/raspberry-pi.pkr.hcl"
fi

# Update systemd service file paths
if [ -f "$TARGET_DIR/files/$TARGET_NAME.service" ]; then
    # Update the ExecStart path
    sed -i "s/\/opt\/app\/app\.py/\/opt\/app\/$TARGET_NAME.py/g" "$TARGET_DIR/files/$TARGET_NAME.service"
fi

# Update the update script service name references
if [ -f "$TARGET_DIR/files/$TARGET_NAME-update.sh" ]; then
    sed -i "s/SERVICE_NAME=\"app\"/SERVICE_NAME=\"$TARGET_NAME\"/g" "$TARGET_DIR/files/$TARGET_NAME-update.sh"
fi

# Update deployment script
if [ -f "$TARGET_DIR/deploy-update.sh" ]; then
    sed -i "s/app-update/$TARGET_NAME-update/g" "$TARGET_DIR/deploy-update.sh"
fi

# Update build script project name
if [ -f "$TARGET_DIR/build.sh" ]; then
    sed -i "s/PROJECT_NAME=\"raspberry-pi-custom\"/PROJECT_NAME=\"$TARGET_NAME\"/g" "$TARGET_DIR/build.sh"
fi

# Update container build script project name
if [ -f "$TARGET_DIR/build-container.sh" ]; then
    sed -i "s/PROJECT_NAME=\"raspberry-pi-custom\"/PROJECT_NAME=\"$TARGET_NAME\"/g" "$TARGET_DIR/build-container.sh"
fi

# Update README title and references
if [ -f "$TARGET_DIR/README.md" ]; then
    # Update the title
    sed -i "1s/.*/# $TARGET_NAME/" "$TARGET_DIR/README.md"
    # Update service status commands
    sed -i "s/systemctl status app/systemctl status $TARGET_NAME/g" "$TARGET_DIR/README.md"
    sed -i "s/journalctl -u app/journalctl -u $TARGET_NAME/g" "$TARGET_DIR/README.md"
fi

# Make scripts executable
echo -e "${YELLOW}Setting permissions...${NC}"
chmod +x "$TARGET_DIR/build.sh"
chmod +x "$TARGET_DIR/build-container.sh"
chmod +x "$TARGET_DIR/deploy-update.sh"
chmod +x "$TARGET_DIR/gen.sh" 2>/dev/null || true
chmod +x "$TARGET_DIR/$FILES_DIR/$TARGET_NAME.py"
chmod +x "$TARGET_DIR/$FILES_DIR/$TARGET_NAME-update.sh"

# Create .gitignore for the new project
echo -e "${YELLOW}Creating .gitignore...${NC}"
cat > "$TARGET_DIR/.gitignore" << 'EOF'
# Build artifacts
*.img
*.img.gz
output/

# Temporary files
*~
*.tmp
.DS_Store

# Python
__pycache__/
*.pyc
*.pyo
*.egg-info/
.venv/
venv/

# IDE
.vscode/
.idea/
*.swp
*.swo

# Logs
*.log
EOF

# Generate a basic project-specific README section
echo -e "${YELLOW}Updating README with project specifics...${NC}"
cat >> "$TARGET_DIR/README.md" << EOF

## Project: $TARGET_NAME

This project was generated from the bts-rpi-base template.

### Quick Start

1. Customize your application in \`files/$TARGET_NAME.py\`
2. Update dependencies in \`files/requirements.txt\`
3. Build the image: \`./build.sh\`
4. Deploy updates: \`./deploy-update.sh\`

### Service Management

\`\`\`bash
# Check service status
sudo systemctl status $TARGET_NAME

# View logs
sudo journalctl -u $TARGET_NAME -f

# Manual service control
sudo systemctl start $TARGET_NAME
sudo systemctl stop $TARGET_NAME
sudo systemctl restart $TARGET_NAME
\`\`\`

### Application Updates

\`\`\`bash
# Update application
sudo $TARGET_NAME-update install /path/to/new/version

# Check update status
sudo $TARGET_NAME-update status

# Rollback if needed
sudo $TARGET_NAME-update restore /var/backups/app/backup-YYYYMMDD-HHMMSS
\`\`\`
EOF

echo ""
echo -e "${GREEN}Project generated successfully!${NC}"
echo ""
echo -e "${BLUE}Project Details:${NC}"
echo "  Location: $TARGET_DIR"
echo "  Application: $TARGET_NAME"
echo "  Service: $TARGET_NAME.service"
echo "  Update Script: $TARGET_NAME-update"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. cd $TARGET_DIR"
echo "2. Edit files/$TARGET_NAME.py for your application logic"
echo "3. Update files/requirements.txt with your dependencies"
echo "4. Choose build method:"
echo "   - Native: ./build.sh"
echo "   - Container: ./build-container.sh build-image && ./build-container.sh build-rpi"
echo ""
echo -e "${GREEN}Happy building!${NC}"
