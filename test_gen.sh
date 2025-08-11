#!/bin/bash
#
# Test script for the BTS Raspberry Pi Project Generator
# Author: Joshua D. Boyd
#
# Tests the gen.sh script to ensure it properly generates projects
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TEST_DIR="/tmp/bts-rpi-test-$$"
TEST_PROJECT="sensor-monitor"

echo -e "${BLUE}Testing BTS Raspberry Pi Project Generator${NC}"
echo ""

# Test 1: Basic generation
echo -e "${YELLOW}Test 1: Basic project generation${NC}"
./gen.sh "$TEST_DIR" "$TEST_PROJECT"

if [ -d "$TEST_DIR" ]; then
    echo -e "${GREEN}✓ Project directory created${NC}"
else
    echo -e "${RED}✗ Project directory not created${NC}"
    exit 1
fi

# Test 2: Check file renames
echo -e "${YELLOW}Test 2: File renames and copies${NC}"

expected_files=(
    "files/$TEST_PROJECT.py"
    "files/$TEST_PROJECT.service" 
    "files/$TEST_PROJECT-update.sh"
    "build.sh"
    "build-container.sh"
    "Containerfile"
    "deploy-update.sh"
)

for file in "${expected_files[@]}"; do
    if [ -f "$TEST_DIR/$file" ]; then
        echo -e "${GREEN}✓ $file exists${NC}"
    else
        echo -e "${RED}✗ $file missing${NC}"
        exit 1
    fi
done

# Test 3: Check content updates
echo -e "${YELLOW}Test 3: Content updates${NC}"

# Check if references were updated in the service file
if grep -q "ExecStart=.*$TEST_PROJECT.py" "$TEST_DIR/files/$TEST_PROJECT.service"; then
    echo -e "${GREEN}✓ Service file updated correctly${NC}"
else
    echo -e "${RED}✗ Service file not updated correctly${NC}"
    exit 1
fi

# Check if the Packer template was updated
if grep -q "$TEST_PROJECT.service" "$TEST_DIR/raspberry-pi.pkr.hcl"; then
    echo -e "${GREEN}✓ Packer template updated correctly${NC}"
else
    echo -e "${RED}✗ Packer template not updated correctly${NC}"
    exit 1
fi

# Check if README was updated
if grep -q "# $TEST_PROJECT" "$TEST_DIR/README.md"; then
    echo -e "${GREEN}✓ README title updated correctly${NC}"
else
    echo -e "${RED}✗ README title not updated correctly${NC}"
    exit 1
fi

# Test 4: Check permissions
echo -e "${YELLOW}Test 4: File permissions${NC}"

executable_files=(
    "build.sh"
    "build-container.sh"
    "deploy-update.sh"
    "files/$TEST_PROJECT.py"
    "files/$TEST_PROJECT-update.sh"
)

for file in "${executable_files[@]}"; do
    if [ -x "$TEST_DIR/$file" ]; then
        echo -e "${GREEN}✓ $file is executable${NC}"
    else
        echo -e "${RED}✗ $file is not executable${NC}"
        exit 1
    fi
done

# Test 5: Check .gitignore creation
echo -e "${YELLOW}Test 5: .gitignore creation${NC}"
if [ -f "$TEST_DIR/.gitignore" ]; then
    echo -e "${GREEN}✓ .gitignore created${NC}"
else
    echo -e "${RED}✗ .gitignore not created${NC}"
    exit 1
fi

# Cleanup
echo -e "${YELLOW}Cleaning up test files...${NC}"
rm -rf "$TEST_DIR"

echo ""
echo -e "${GREEN}All tests passed! Generator is working correctly.${NC}"
echo ""
echo -e "${BLUE}You can now use gen.sh to create new projects:${NC}"
echo "  ./gen.sh ../my-project my-app-name"
