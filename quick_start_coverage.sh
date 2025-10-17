#!/usr/bin/env bash

# Quick Start Guide for Code Coverage Calculation
# This script provides an interactive menu to help you get started

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

clear

echo "=========================================="
echo "Code Coverage Calculation - Quick Start"
echo "=========================================="
echo ""
echo "Will be counted:"
echo "  • .NET solution files"
echo "  • Java Maven project"
echo "  • Kotlin/Gradle projects"
echo "  • Rust projects"
echo "  • PostgreSQL databases"
echo ""
echo "Git submodules are automatically excluded."
echo ""

# Check prerequisites
echo -e "${BLUE}Checking Prerequisites...${NC}"
echo ""

has_dotnet=0
has_maven=0
has_cargo=0
has_tarpaulin=0

if command -v dotnet &> /dev/null; then
    echo -e "${GREEN}✓${NC} .NET SDK installed ($(dotnet --version))"
    has_dotnet=1
else
    echo -e "${RED}✗${NC} .NET SDK not installed"
fi

if command -v mvn &> /dev/null; then
    echo -e "${GREEN}✓${NC} Maven installed ($(mvn --version | head -1))"
    has_maven=1
else
    echo -e "${YELLOW}○${NC} Maven not installed (Java coverage will be skipped)"
fi

if command -v gradle &> /dev/null; then
    echo -e "${GREEN}✓${NC} Gradle installed ($(gradle -v | sed -n '3p'))"
    has_gradle=1
else
    echo -e "${YELLOW}○${NC} Gradle not installed (Kotlin coverage will be skipped)"
fi

if command -v cargo &> /dev/null; then
    echo -e "${GREEN}✓${NC} Cargo installed ($(cargo --version))"
    has_cargo=1
    
    if command -v cargo-tarpaulin &> /dev/null; then
        echo -e "${GREEN}✓${NC} cargo-tarpaulin installed"
        has_tarpaulin=1
    else
        echo -e "${YELLOW}○${NC} cargo-tarpaulin not installed (Rust coverage will be skipped)"
    fi
else
    echo -e "${RED}✗${NC} Cargo not installed"
fi

echo ""
echo "=========================================="
echo "What would you like to do?"
echo "=========================================="
echo ""
echo "1) Preview projects (see what will be tested)"
echo "2) Run full coverage calculation (2-4 hours)"
echo "3) Install missing tools"
echo "4) Read detailed documentation"
echo "5) Exit"
echo ""

read -p "Enter your choice (1-5): " choice

case $choice in
    1)
        echo ""
        echo -e "${BLUE}Running preview...${NC}"
        echo ""
        ./preview_coverage_projects.sh
        ;;
    2)
        echo ""
        echo -e "${YELLOW}This will run coverage tests on all projects.${NC}"
        echo -e "${YELLOW}Estimated time: 3-6 hours${NC}"
        echo ""
        read -p "Continue? (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo ""
            echo -e "${BLUE}Starting coverage calculation...${NC}"
            echo ""
            ./calculate_comprehensive_coverage.sh
        else
            echo "Cancelled."
        fi
        ;;
    3)
        echo ""
        echo -e "${BLUE}Installation Commands:${NC}"
        echo ""
        if [[ $has_maven -eq 0 ]]; then
            echo "Install Maven:"
            echo "  brew install maven"
            echo ""
        fi
        if [[ $has_cargo -eq 1 ]] && [[ $has_tarpaulin -eq 0 ]]; then
            echo "Install cargo-tarpaulin:"
            echo "  cargo install cargo-tarpaulin"
            echo ""
        fi
        if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
            echo "Install Bash 4+ (optional, for better performance):"
            echo "  brew install bash"
            echo ""
        fi
        echo "After installation, run this script again."
        ;;
    4)
        echo ""
        echo -e "${BLUE}Opening documentation...${NC}"
        echo ""
        if command -v less &> /dev/null; then
            less README.md
        else
            cat README.md
        fi
        ;;
    5)
        echo ""
        echo "Exiting. Run ./quick_start_coverage.sh anytime to return."
        exit 0
        ;;
    *)
        echo ""
        echo -e "${RED}Invalid choice.${NC} Please run the script again."
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Done!${NC}"
echo ""
