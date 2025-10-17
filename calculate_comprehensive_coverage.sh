#!/usr/bin/env bash

# Comprehensive Code Coverage Calculator for Multi-Language Project
# Calculates coverage for .NET, Java, Kotlin/Gradle, Rust, PostgreSQL, and Web (Nx/Node)
# Excludes git submodules to prevent duplicate counting

# Requires bash 4+ for associative arrays
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "This script requires bash 4 or higher."
    echo "On macOS, install with: brew install bash"
    echo "Or run with: /usr/local/bin/bash $0"
    USE_SIMPLE_MODE=1
else
    USE_SIMPLE_MODE=0
fi

set -e

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COVERAGE_OUTPUT_DIR="$WORKSPACE_ROOT/coverage-results-complete"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SUMMARY_FILE="$COVERAGE_OUTPUT_DIR/coverage-summary-$TIMESTAMP.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create output directory
mkdir -p "$COVERAGE_OUTPUT_DIR"

echo "=========================================="
echo "Comprehensive Code Coverage Calculator"
echo "=========================================="
echo "Workspace: $WORKSPACE_ROOT"
echo "Output: $COVERAGE_OUTPUT_DIR"
echo ""

# Function to check if a path is in a git submodule
is_submodule() {
    local path="$1"
    local current_dir=""
    
    # If path is a directory, start checking at the directory itself; otherwise start at its parent
    if [[ -d "$path" ]]; then
        current_dir="$path"
    else
        current_dir="$(dirname "$path")"
    fi
    
    # Walk up the directory tree until workspace root
    while [[ "$current_dir" != "$WORKSPACE_ROOT" && "$current_dir" != "/" && -n "$current_dir" ]]; do
        # Submodule roots typically have a .git file (not directory)
        if [[ -f "$current_dir/.git" ]]; then
            return 0  # It's a submodule
        fi
        current_dir="${current_dir%/*}"
        [[ -z "$current_dir" ]] && current_dir="/"
    done
    
    return 1  # Not inside a submodule
}

# Function to find the git repository root for a given path (with caching)
find_git_root() {
    local path="$1"
    
    # Check cache first (use the path itself as cache key)
    if [[ "$USE_SIMPLE_MODE" -eq 0 ]]; then
        if [[ -n "${git_root_cache[$path]}" ]]; then
            echo "${git_root_cache[$path]}"
            return 0
        fi
    fi
    
    local search_dir="$path"
    local iterations=0
    local max_iterations=20  # Safety limit to prevent infinite loops
    
    # Check the path itself and then walk up
    while [[ "$search_dir" != "/" ]] && [[ "$search_dir" != "." ]] && [[ $iterations -lt $max_iterations ]]; do
        if [[ -d "$search_dir/.git" ]] || [[ -f "$search_dir/.git" ]]; then
            # Cache the result
            if [[ "$USE_SIMPLE_MODE" -eq 0 ]]; then
                git_root_cache["$path"]="$search_dir"
            fi
            echo "$search_dir"
            return 0
        fi
        # Use parameter expansion instead of dirname command
        search_dir="${search_dir%/*}"
        [[ -z "$search_dir" ]] && search_dir="/"
        iterations=$((iterations + 1))
    done
    
    # Cache negative result
    if [[ "$USE_SIMPLE_MODE" -eq 0 ]]; then
        git_root_cache["$path"]=""
    fi
    echo ""
    return 1
}

# Initialize counters
declare -A tech_projects
declare -A tech_covered_lines
declare -A tech_total_lines
declare -A tech_coverage_percentage

tech_projects["dotnet"]=0
tech_projects["java"]=0
tech_projects["kotlin"]=0
tech_projects["rust"]=0
tech_projects["postgresql"]=0
tech_projects["web"]=0

tech_covered_lines["dotnet"]=0
tech_covered_lines["java"]=0
tech_covered_lines["kotlin"]=0
tech_covered_lines["rust"]=0
tech_covered_lines["postgresql"]=0
tech_covered_lines["web"]=0

tech_total_lines["dotnet"]=0
tech_total_lines["java"]=0
tech_total_lines["kotlin"]=0
tech_total_lines["rust"]=0
tech_total_lines["postgresql"]=0
tech_total_lines["web"]=0

# Initialize tracking for processed git roots
if [[ "$USE_SIMPLE_MODE" -eq 0 ]]; then
    declare -A processed_git_roots
    declare -A git_root_cache
fi

# Simple mode fallback for older bash
if [[ "$USE_SIMPLE_MODE" -eq 1 ]]; then
    PROCESSED_FILE=$(mktemp)
    GIT_ROOT_CACHE_FILE=$(mktemp)
    trap "rm -f $PROCESSED_FILE $GIT_ROOT_CACHE_FILE" EXIT
fi

check_if_processed() {
    local key="$1"
    if [[ "$USE_SIMPLE_MODE" -eq 1 ]]; then
        grep -q "^$key$" "$PROCESSED_FILE" 2>/dev/null && return 0 || return 1
    else
        [[ -n "${processed_git_roots[$key]}" ]] && return 0 || return 1
    fi
}

mark_as_processed() {
    local key="$1"
    if [[ "$USE_SIMPLE_MODE" -eq 1 ]]; then
        echo "$key" >> "$PROCESSED_FILE"
    else
        processed_git_roots["$key"]=1
    fi
}

echo -e "${BLUE}Step 1: Discovering projects (excluding submodules)...${NC}"
echo ""

# Find all .NET solution files (excluding submodules and .git directories)
echo -e "${YELLOW}Discovering .NET projects...${NC}"
dotnet_solutions=()
while IFS= read -r -d '' sln_file; do
    # Skip if in .git directory (extra safety check)
    [[ "$sln_file" == *"/.git/"* ]] && continue
    
    # Exclude git submodules (parent chain contains .git file)
    if is_submodule "$sln_file"; then
        continue
    fi
    
    # Add the project directly (each project is in its own git repo)
    dotnet_solutions+=("$sln_file")
    # Use simple string substitution instead of realpath for speed
    rel_path="${sln_file#$WORKSPACE_ROOT/}"
    echo "  ✓ Found: $rel_path"
done < <(find "$WORKSPACE_ROOT" -name "*.sln" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

echo "Total .NET solutions found: ${#dotnet_solutions[@]}"
echo ""

# Find all Java Maven projects (excluding submodules and .git directories)
echo -e "${YELLOW}Discovering Java projects...${NC}"
java_projects=()
while IFS= read -r -d '' pom_file; do
    # Skip if in .git directory (extra safety check)
    [[ "$pom_file" == *"/.git/"* ]] && continue
    
    # Exclude git submodules (parent chain contains .git file)
    if is_submodule "$pom_file"; then
        continue
    fi
    
    # Add the project directly (each project is in its own git repo)
    java_projects+=("$pom_file")
    # Use simple string substitution instead of realpath for speed
    rel_path="${pom_file#$WORKSPACE_ROOT/}"
    echo "  ✓ Found: $rel_path"
done < <(find "$WORKSPACE_ROOT" -name "pom.xml" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

echo "Total Java projects found: ${#java_projects[@]}"
echo ""

# Find all Kotlin/Gradle projects (excluding submodules and .git directories)
echo -e "${YELLOW}Discovering Kotlin/Gradle projects...${NC}"
kotlin_projects=()
while IFS= read -r -d '' gradle_file; do
    # Skip if in .git directory (extra safety check)
    [[ "$gradle_file" == *"/.git/"* ]] && continue
    
    # Exclude git submodules (parent chain contains .git file)
    if is_submodule "$gradle_file"; then
        continue
    fi
    
    # Add the project directly (each project is in its own git repo)
    kotlin_projects+=("$gradle_file")
    # Use simple string substitution instead of realpath for speed
    rel_path="${gradle_file#$WORKSPACE_ROOT/}"
    echo "  ✓ Found: $rel_path"
done < <(find "$WORKSPACE_ROOT" -name "settings.gradle.kts" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

echo "Total Kotlin/Gradle projects found: ${#kotlin_projects[@]}"
echo ""

# Find all Rust projects (excluding submodules and .git directories)
echo -e "${YELLOW}Discovering Rust projects...${NC}"
rust_projects=()
while IFS= read -r -d '' cargo_file; do
    # Skip if in .git directory (extra safety check)
    [[ "$cargo_file" == *"/.git/"* ]] && continue
    
    # Exclude git submodules (parent chain contains .git file)
    if is_submodule "$cargo_file"; then
        continue
    fi
    
    # Only count workspace root Cargo.toml files
    if grep -q "\[workspace\]" "$cargo_file" 2>/dev/null || ! grep -q "workspace = " "$cargo_file" 2>/dev/null; then
        # Add the project directly (each project is in its own git repo)
        rust_projects+=("$cargo_file")
        # Use simple string substitution instead of realpath for speed
        rel_path="${cargo_file#$WORKSPACE_ROOT/}"
        echo "  ✓ Found: $rel_path"
    fi
done < <(find "$WORKSPACE_ROOT" -name "Cargo.toml" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

echo "Total Rust projects found: ${#rust_projects[@]}"
echo ""

# Find PostgreSQL database directories (excluding submodules and .git directories)
echo -e "${YELLOW}Discovering PostgreSQL projects...${NC}"
postgres_projects=()
db_count=0

# Use a more efficient approach: collect all first, then process  
# Note: Using while read loop is more reliable than mapfile for null-delimited input
db_dirs=()
while IFS= read -r -d '' db_dir; do
    db_dirs+=("$db_dir")
done < <(find "$WORKSPACE_ROOT" -type d \( -name "*.database" -o -name "*-database" \) ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

total_dbs=${#db_dirs[@]}
echo "  Found $total_dbs database directories to check..."

# Use C-style for loop to iterate through database directories
for ((i=0; i<total_dbs; i++)); do
    db_dir="${db_dirs[i]}"
    
    # Skip .git directories (extra safety)
    [[ "$db_dir" == *"/.git/"* ]] || [[ "$db_dir" == *"/.git" ]] && continue
    
    # Exclude git submodules (parent chain contains .git file)
    if is_submodule "$db_dir"; then
        continue
    fi
    
    db_count=$((db_count + 1))
    
    # Add the project directly (each project is in its own git repo)
    postgres_projects+=("$db_dir")
    # Use simple string substitution instead of realpath for speed
    rel_path="${db_dir#$WORKSPACE_ROOT/}"
    echo "  ✓ Found: $rel_path"
done

echo "Total PostgreSQL projects found: ${#postgres_projects[@]} (scanned $db_count directories)"
echo ""

# Find Web (Nx/Node) projects (excluding submodules and .git directories)
echo -e "${YELLOW}Discovering Web (Nx/Node) projects...${NC}"
web_nx_projects=()
web_node_projects=()

# Helper: check if a directory is inside an Nx workspace (has nx.json in its parent chain)
is_in_nx_workspace() {
    local path="$1"
    local current_dir=""

    if [[ -d "$path" ]]; then
        current_dir="$path"
    else
        current_dir="$(dirname "$path")"
    fi

    while [[ "$current_dir" != "$WORKSPACE_ROOT" && "$current_dir" != "/" && -n "$current_dir" ]]; do
        if [[ -f "$current_dir/nx.json" ]]; then
            return 0
        fi
        current_dir="${current_dir%/*}"
        [[ -z "$current_dir" ]] && current_dir="/"
    done
    return 1
}

# Discover Nx workspaces (treat each nx.json as a single project)
while IFS= read -r -d '' nx_file; do
    [[ "$nx_file" == *"/.git/"* ]] && continue
    if is_submodule "$nx_file"; then
        continue
    fi
    nx_dir="${nx_file%/*}"
    web_nx_projects+=("$nx_dir")
    rel_path="${nx_dir#$WORKSPACE_ROOT/}"
    echo "  ✓ Nx workspace: $rel_path"
done < <(find "$WORKSPACE_ROOT" -name "nx.json" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

# Discover standalone Node projects (package.json) that are NOT under an Nx workspace
while IFS= read -r -d '' pkg_file; do
    [[ "$pkg_file" == *"/.git/"* ]] && continue
    # Skip packages within node_modules
    [[ "$pkg_file" == *"/node_modules/"* ]] && continue
    # Skip packages that are part of Nx workspaces
    if is_in_nx_workspace "$pkg_file"; then
        continue
    fi
    if is_submodule "$pkg_file"; then
        continue
    fi
    pkg_dir="${pkg_file%/*}"
    # Heuristic: include only if it has a test script
    if grep -q '"test"' "$pkg_file" 2>/dev/null || grep -q '"test:cov"' "$pkg_file" 2>/dev/null; then
        web_node_projects+=("$pkg_dir")
        rel_path="${pkg_dir#$WORKSPACE_ROOT/}"
        echo "  ✓ Node project: $rel_path"
    fi
done < <(find "$WORKSPACE_ROOT" -name "package.json" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

echo "Total Web Nx workspaces found: ${#web_nx_projects[@]}"
echo "Total standalone Node projects found: ${#web_node_projects[@]}"
echo ""

echo "=========================================="
echo -e "${BLUE}Step 2: Calculating Coverage${NC}"
echo "=========================================="
echo ""
echo "Summary of discovered projects:"
echo "  .NET solutions: ${#dotnet_solutions[@]}"
echo "  Java projects: ${#java_projects[@]}"
echo "  Kotlin/Gradle projects: ${#kotlin_projects[@]}"
echo "  Rust projects: ${#rust_projects[@]}"
echo "  PostgreSQL databases: ${#postgres_projects[@]}"
echo "  Web Nx workspaces: ${#web_nx_projects[@]}"
echo "  Web Node projects: ${#web_node_projects[@]}"
echo ""

# Function to kill process tree
kill_process_tree() {
    local pid=$1
    local signal=${2:-TERM}
    
    # Get all child PIDs recursively
    local children=$(pgrep -P $pid 2>/dev/null)
    
    # Kill children first
    for child in $children; do
        kill_process_tree $child $signal
    done
    
    # Kill the parent
    kill -$signal $pid 2>/dev/null
}

# Function to calculate .NET coverage
calculate_dotnet_coverage() {
    # Disable exit on error for this function
    set +e

    local sln_file="$1"
    local sln_dir="${sln_file%/*}"
    [[ -z "$sln_dir" ]] && sln_dir="."
    local sln_name="$(basename "$sln_file" .sln)"
    local sln_basename="$(basename "$sln_file")"

    echo -e "${GREEN}Processing .NET solution: $sln_name${NC}"
    echo "  Location: $sln_dir"

    # Check if dotnet is available
    if ! command -v dotnet >/dev/null 2>&1; then
        echo -e "  ${YELLOW}Warning: dotnet CLI not found. Skipping.${NC}"
        echo ""
        return 1
    fi

    cd "$sln_dir" || {
        echo -e "  ${RED}Error: Cannot change to directory $sln_dir${NC}"
        echo ""
        set -e
        return 1
    }

    echo "  Restoring dependencies..."
    dotnet restore "$sln_basename" >/dev/null 2>&1
    local restore_exit=$?
    if [[ $restore_exit -ne 0 ]]; then
        echo -e "  ${RED}Error: Restore failed (exit code: $restore_exit)${NC}"
        cd "$WORKSPACE_ROOT"
        echo ""
        set -e
        return 1
    fi

    echo "  Running tests with coverage..."
    dotnet test "$sln_basename" --collect:"XPlat Code Coverage" --results-directory:"$COVERAGE_OUTPUT_DIR/dotnet/$sln_name" --verbosity:quiet >/dev/null 2>&1
    local test_exit=$?
    if [[ $test_exit -ne 0 ]]; then
        echo -e "  ${YELLOW}Warning: Tests failed or no tests found (exit code: $test_exit)${NC}"
    fi

    # Find and parse coverage files
    local coverage_files=()
    while IFS= read -r -d '' f; do coverage_files+=("$f"); done < <(find "$COVERAGE_OUTPUT_DIR/dotnet/$sln_name" -name "coverage.cobertura.xml" -print0 2>/dev/null)

    if [[ ${#coverage_files[@]} -gt 0 ]]; then
        echo "  Found ${#coverage_files[@]} coverage file(s)"
        for coverage_file in "${coverage_files[@]}"; do
            if [[ -f "$coverage_file" ]]; then
                if command -v xmllint >/dev/null 2>&1; then
                    covered=$(xmllint --xpath "string(//coverage/@lines-covered)" "$coverage_file" 2>/dev/null || echo "0")
                    total=$(xmllint --xpath "string(//coverage/@lines-valid)" "$coverage_file" 2>/dev/null || echo "0")
                else
                    covered=$(grep -oE 'lines-covered="[0-9]+"' "$coverage_file" 2>/dev/null | head -1 | sed -E 's/.*="([0-9]+)"/\1/')
                    total=$(grep -oE 'lines-valid="[0-9]+"' "$coverage_file" 2>/dev/null | head -1 | sed -E 's/.*="([0-9]+)"/\1/')
                fi

                covered=${covered:-0}
                total=${total:-0}

                if [[ "$total" -gt 0 ]]; then
                    tech_covered_lines["dotnet"]=$((tech_covered_lines["dotnet"] + covered))
                    tech_total_lines["dotnet"]=$((tech_total_lines["dotnet"] + total))
                    tech_projects["dotnet"]=$((tech_projects["dotnet"] + 1))
                    local percentage=$(awk "BEGIN {printf \"%.2f\", ($covered/$total)*100}")
                    echo "  Coverage: $percentage% ($covered/$total lines)"
                else
                    echo -e "  ${YELLOW}Warning: No valid coverage data in file${NC}"
                fi
            fi
        done
    else
        echo -e "  ${YELLOW}Warning: No coverage data generated${NC}"
    fi

    cd "$WORKSPACE_ROOT"
    set -e
    echo ""
}

# Function to calculate Java coverage
calculate_java_coverage() {
    local pom_file="$1"
    local project_dir="$(dirname "$pom_file")"
    local project_name="$(basename "$project_dir")"
    
    echo -e "${GREEN}Processing Java project: $project_name${NC}"
    echo "  Location: $project_dir"
    
    cd "$project_dir" || {
        echo -e "  ${RED}Error: Cannot change to directory $project_dir${NC}"
        cd "$WORKSPACE_ROOT"
        echo ""
        return 1
    }
    
    # Check if mvn is available
    if ! command -v mvn &> /dev/null; then
        echo -e "  ${YELLOW}Warning: Maven not found. Skipping.${NC}"
        cd "$WORKSPACE_ROOT"
        echo ""
        return 1
    fi
    
    # Try to run tests with JaCoCo
    echo "  Running tests with coverage..."
    if mvn clean test jacoco:report -DskipTests=false >/dev/null 2>&1; then
        
        # Find JaCoCo XML report
        jacoco_report="$project_dir/target/site/jacoco/jacoco.xml"
        
        if [[ -f "$jacoco_report" ]]; then
            echo "  Found coverage report"
            # Parse JaCoCo XML
            if command -v xmllint &> /dev/null; then
                covered=$(xmllint --xpath "sum(//counter[@type='LINE']/@covered)" "$jacoco_report" 2>/dev/null || echo "0")
                missed=$(xmllint --xpath "sum(//counter[@type='LINE']/@missed)" "$jacoco_report" 2>/dev/null || echo "0")
            else
                # Fallback parsing without xmllint
                covered=$(grep -oP 'type="LINE".*?covered="\K[^"]+' "$jacoco_report" 2>/dev/null | awk '{s+=$1} END {print s}' || echo "0")
                missed=$(grep -oP 'type="LINE".*?missed="\K[^"]+' "$jacoco_report" 2>/dev/null | awk '{s+=$1} END {print s}' || echo "0")
            fi
            
            covered=${covered:-0}
            missed=${missed:-0}
            total=$((covered + missed))
            
            if [[ "$total" -gt 0 ]]; then
                tech_covered_lines["java"]=$((tech_covered_lines["java"] + covered))
                tech_total_lines["java"]=$((tech_total_lines["java"] + total))
                tech_projects["java"]=$((tech_projects["java"] + 1))
                
                local percentage=$(awk "BEGIN {printf \"%.2f\", ($covered/$total)*100}")
                echo "  Coverage: $percentage% ($covered/$total lines)"
                
                # Copy report
                cp "$jacoco_report" "$COVERAGE_OUTPUT_DIR/java_${project_name}_jacoco.xml" 2>/dev/null
            else
                echo -e "  ${YELLOW}Warning: Coverage report is empty${NC}"
            fi
        else
            echo -e "  ${YELLOW}Warning: No JaCoCo report generated${NC}"
        fi
    else
        echo -e "  ${RED}Error: Tests failed or no tests found${NC}"
    fi
    
    cd "$WORKSPACE_ROOT"
    echo ""
}

# Function to calculate Kotlin/Gradle coverage
calculate_kotlin_coverage() {
    local gradle_file="$1"
    local project_dir="$(dirname "$gradle_file")"
    local project_name="$(basename "$project_dir")"
    
    echo -e "${GREEN}Processing Kotlin/Gradle project: $project_name${NC}"
    echo "  Location: $project_dir"
    
    cd "$project_dir" || {
        echo -e "  ${RED}Error: Cannot change to directory $project_dir${NC}"
        cd "$WORKSPACE_ROOT"
        echo ""
        return 1
    }
    
    # Check if gradlew exists
    if [[ -f "./gradlew" ]]; then
        gradle_cmd="./gradlew"
    elif command -v gradle &> /dev/null; then
        gradle_cmd="gradle"
    else
        echo -e "  ${RED}Error: Gradle not found${NC}"
        cd "$WORKSPACE_ROOT"
        echo ""
        return 1
    fi
    
    # Try to run tests with JaCoCo
    echo "  Running tests with coverage..."
    if $gradle_cmd clean test jacocoTestReport >/dev/null 2>&1; then
        
        # Find JaCoCo XML reports (may be in multiple modules)
        jacoco_reports=($(find "$project_dir" -path "*/build/reports/jacoco/test/jacocoTestReport.xml" 2>/dev/null))
        
        if [[ ${#jacoco_reports[@]} -gt 0 ]]; then
            echo "  Found ${#jacoco_reports[@]} coverage report(s)"
            local total_covered=0
            local total_lines=0
            
            # Parse each JaCoCo XML report
            for jacoco_report in "${jacoco_reports[@]}"; do
                if [[ -f "$jacoco_report" ]]; then
                    if command -v xmllint &> /dev/null; then
                        covered=$(xmllint --xpath "sum(//counter[@type='LINE']/@covered)" "$jacoco_report" 2>/dev/null || echo "0")
                        missed=$(xmllint --xpath "sum(//counter[@type='LINE']/@missed)" "$jacoco_report" 2>/dev/null || echo "0")
                    else
                        covered=$(grep -oP 'type="LINE".*?covered="\K[^"]+' "$jacoco_report" 2>/dev/null | awk '{s+=$1} END {print s}' || echo "0")
                        missed=$(grep -oP 'type="LINE".*?missed="\K[^"]+' "$jacoco_report" 2>/dev/null | awk '{s+=$1} END {print s}' || echo "0")
                    fi
                    
                    covered=${covered:-0}
                    missed=${missed:-0}
                    
                    total_covered=$((total_covered + covered))
                    total_lines=$((total_lines + covered + missed))
                    
                    # Copy report with module name
                    module_name=$(echo "$jacoco_report" | sed "s|$project_dir/||" | sed 's|/build/reports.*||' | tr '/' '_')
                    cp "$jacoco_report" "$COVERAGE_OUTPUT_DIR/kotlin_${project_name}_${module_name}_jacoco.xml" 2>/dev/null
                fi
            done
            
            if [[ "$total_lines" -gt 0 ]]; then
                tech_covered_lines["kotlin"]=$((tech_covered_lines["kotlin"] + total_covered))
                tech_total_lines["kotlin"]=$((tech_total_lines["kotlin"] + total_lines))
                tech_projects["kotlin"]=$((tech_projects["kotlin"] + 1))
                
                local percentage=$(awk "BEGIN {printf \"%.2f\", ($total_covered/$total_lines)*100}")
                echo "  Coverage: $percentage% ($total_covered/$total_lines lines)"
                echo "  Modules processed: ${#jacoco_reports[@]}"
            else
                echo -e "  ${YELLOW}Warning: Coverage reports are empty${NC}"
            fi
        else
            echo -e "  ${YELLOW}Warning: No JaCoCo reports generated${NC}"
            echo "  Note: Ensure build.gradle.kts includes jacoco plugin"
        fi
    else
        echo -e "  ${RED}Error: Tests failed or no tests found${NC}"
    fi
    
    cd "$WORKSPACE_ROOT"
    echo ""
}

# Function to calculate Rust coverage
calculate_rust_coverage() {
    local cargo_file="$1"
    local project_dir="$(dirname "$cargo_file")"
    local project_name="$(basename "$project_dir")"
    
    echo -e "${GREEN}Processing Rust project: $project_name${NC}"
    echo "  Location: $project_dir"
    
    cd "$project_dir" || {
        echo -e "  ${RED}Error: Cannot change to directory $project_dir${NC}"
        cd "$WORKSPACE_ROOT"
        echo ""
        return 1
    }
    
    # Check if cargo-tarpaulin is available
    if command -v cargo-tarpaulin &> /dev/null; then
        echo "  Running tests with coverage..."
        if cargo tarpaulin --out Xml --output-dir "$COVERAGE_OUTPUT_DIR/rust/$project_name" >/dev/null 2>&1; then
            
            coverage_file="$COVERAGE_OUTPUT_DIR/rust/$project_name/cobertura.xml"
            
            if [[ -f "$coverage_file" ]]; then
                echo "  Found coverage report"
                if command -v xmllint &> /dev/null; then
                    covered=$(xmllint --xpath "string(//coverage/@lines-covered)" "$coverage_file" 2>/dev/null || echo "0")
                    total=$(xmllint --xpath "string(//coverage/@lines-valid)" "$coverage_file" 2>/dev/null || echo "0")
                else
                    covered=$(grep -oP 'lines-covered="\K[^"]+' "$coverage_file" 2>/dev/null | head -1 || echo "0")
                    total=$(grep -oP 'lines-valid="\K[^"]+' "$coverage_file" 2>/dev/null | head -1 || echo "0")
                fi
                
                covered=${covered:-0}
                total=${total:-0}
                
                if [[ "$total" -gt 0 ]]; then
                    tech_covered_lines["rust"]=$((tech_covered_lines["rust"] + covered))
                    tech_total_lines["rust"]=$((tech_total_lines["rust"] + total))
                    tech_projects["rust"]=$((tech_projects["rust"] + 1))
                    
                    local percentage=$(awk "BEGIN {printf \"%.2f\", ($covered/$total)*100}")
                    echo "  Coverage: $percentage% ($covered/$total lines)"
                else
                    echo -e "  ${YELLOW}Warning: Coverage report is empty${NC}"
                fi
            else
                echo -e "  ${YELLOW}Warning: No coverage file generated${NC}"
            fi
        else
            echo -e "  ${RED}Error: Coverage calculation failed${NC}"
        fi
    else
        echo -e "  ${YELLOW}Warning: cargo-tarpaulin not installed. Skipping Rust coverage.${NC}"
        echo "  Install with: cargo install cargo-tarpaulin"
    fi
    
    cd "$WORKSPACE_ROOT"
    echo ""
}

# Function to calculate PostgreSQL coverage (basic analysis)
calculate_postgresql_coverage() {
    local db_dir="$1"
    local db_name="$(basename "$db_dir")"
    
    echo -e "${GREEN}Processing PostgreSQL database: $db_name${NC}"
    
    # Collect routine files (create function/procedure) under scheme or *.scheme directories
    local routine_files=()
    while IFS= read -r f; do
        if grep -qiE "\\bCREATE\\s+(OR\\s+REPLACE\\s+)?(FUNCTION|PROCEDURE)\\b" "$f" 2>/dev/null; then
            routine_files+=("$f")
        fi
    done < <(find "$db_dir" -type f -name "*.sql" \( -path "*/scheme/routines/*" -o -path "*/*.scheme/routines/*" \) 2>/dev/null)
    
    local routine_count=${#routine_files[@]}
    if [[ $routine_count -eq 0 ]]; then
        echo -e "  ${YELLOW}No SQL functions/procedures found${NC}"
        echo ""
        return 0
    fi
    
    tech_projects["postgresql"]=$((tech_projects["postgresql"] + 1))
    
    # Sum total lines across routine files
    local total_lines=0
    for rf in "${routine_files[@]}"; do
        if [[ -f "$rf" ]]; then
            local l
            l=$(wc -l < "$rf" 2>/dev/null || echo 0)
            total_lines=$((total_lines + l))
        fi
    done
    tech_total_lines["postgresql"]=$((tech_total_lines["postgresql"] + total_lines))
    
    # Count test files: under scheme/tests or *.scheme/tests, plus any *test*.sql/*spec*.sql within these trees
    local test_count
    test_count=$(find "$db_dir" -type f -name "*.sql" \( -path "*/scheme/tests/*" -o -path "*/*.scheme/tests/*" -o \( \( -path "*/scheme/*" -o -path "*/*.scheme/*" \) -a \( -iname "*test*.sql" -o -iname "*spec*.sql" \) \) \) 2>/dev/null | wc -l | tr -d ' ')
    
    echo "  Routine files: $routine_count"
    echo "  Test files: $test_count"
    
    local covered_lines=0
    if [[ "$test_count" -gt 0 ]]; then
        # Pre-build a null-delimited list of test files for xargs -0, to be portable on macOS
        for rf in "${routine_files[@]}"; do
            # Extract routine names from the file
            local names=()
            while IFS= read -r line; do
                # line example: CREATE FUNCTION schema.name
                local n
                n=$(echo "$line" | awk '{print tolower($NF)}' | sed -E 's/[;\r\n]//g; s/\(.*$//')
                [[ -n "$n" ]] && names+=("$n")
            done < <(grep -oiE "\\bCREATE\\s+(OR\\s+REPLACE\\s+)?(FUNCTION|PROCEDURE)\\s+[a-zA-Z0-9_\\.]+" "$rf" 2>/dev/null | sort -u)
            
            local file_is_covered=0
            for n in "${names[@]}"; do
                [[ -z "$n" ]] && continue
                local bare_name="${n##*.}"
                # Escape regex metacharacters for safe grep -E
                local esc_n esc_bare
                esc_n=$(echo "$n" | sed -E 's/[][^$.|?*+(){}\\]/\\&/g')
                esc_bare=$(echo "$bare_name" | sed -E 's/[][^$.|?*+(){}\\]/\\&/g')
                # Search test files directly with find -> xargs -0 grep
                if find "$db_dir" -type f -name "*.sql" \( -path "*/scheme/tests/*" -o -path "*/*.scheme/tests/*" -o \( \( -path "*/scheme/*" -o -path "*/*.scheme/*" \) -a \( -iname "*test*.sql" -o -iname "*spec*.sql" \) \) \) -print0 2>/dev/null \
                    | xargs -0 grep -qiE "\\b${esc_n}\\b|\\b${esc_bare}\\b" 2>/dev/null; then
                    file_is_covered=1
                    break
                fi
            done
            if [[ $file_is_covered -eq 1 ]]; then
                local l
                l=$(wc -l < "$rf" 2>/dev/null || echo 0)
                covered_lines=$((covered_lines + l))
            fi
        done
        
        if [[ $covered_lines -gt $total_lines ]]; then
            covered_lines=$total_lines
        fi
        
        # Fallback: if no direct matches but tests exist, estimate coverage using assertion density
        if [[ $covered_lines -eq 0 ]]; then
            # Count assertion calls in tests
            local assertion_count
            assertion_count=$(find "$db_dir" -type f -name "*.sql" \( -path "*/scheme/tests/*" -o -path "*/*.scheme/tests/*" -o \( \( -path "*/scheme/*" -o -path "*/*.scheme/*" \) -a \( -iname "*test*.sql" -o -iname "*spec*.sql" \) \) \) -print0 2>/dev/null \
                | xargs -0 grep -oiE "\\b(assert_|test_utils\\.assert_)\\w+" 2>/dev/null | wc -l | tr -d ' ')
            if [[ -n "$assertion_count" ]] && [[ "$assertion_count" -gt 0 ]] && [[ $routine_count -gt 0 ]]; then
                # Assume roughly 4 assertions per routine on average
                local est_routines=$(( assertion_count / 4 ))
                if [[ $est_routines -lt 1 ]]; then est_routines=1; fi
                if [[ $est_routines -gt $routine_count ]]; then est_routines=$routine_count; fi
                # Average lines per routine
                local avg_lines=0
                if [[ $routine_count -gt 0 ]]; then
                    avg_lines=$(( total_lines / routine_count ))
                fi
                covered_lines=$(( est_routines * avg_lines ))
                if [[ $covered_lines -gt $total_lines ]]; then covered_lines=$total_lines; fi
                echo -e "  ${YELLOW}Fallback coverage applied from assertions: ${assertion_count} asserts across ~${est_routines} routines${NC}"
            fi
        fi
        
        tech_covered_lines["postgresql"]=$((tech_covered_lines["postgresql"] + covered_lines))
        local percentage="0.00"
        if [[ $total_lines -gt 0 ]]; then
            percentage=$(awk "BEGIN {printf \"%.2f\", ($covered_lines/$total_lines)*100}")
        fi
        echo "  Estimated coverage: $percentage% ($covered_lines/$total_lines lines)"
    else
        echo -e "  ${YELLOW}No tests detected - assuming 0% coverage${NC}"
    fi
    
    echo ""
}

# Function to parse and accumulate coverage from lcov.info files
accumulate_lcov_coverage() {
    local base_dir="$1"
    local total=0
    local covered=0
    # Find all lcov.info files and parse DA: lines
    while IFS= read -r -d '' lcov; do
        # Use awk to count lines and covered lines
        read -r c t < <(awk -F',' '/^DA:/ {total++; if ($2+0>0) covered++} END {print covered, total}' "$lcov")
        covered=$((covered + c))
        total=$((total + t))
    done < <(find "$base_dir" -type f -name "lcov.info" -path "*/coverage/*" -print0 2>/dev/null)
    echo "$covered $total"
}

# Function to calculate Web coverage for Nx and Node projects
calculate_web_coverage() {
    local project_dir="$1"
    local kind="$2" # nx or node

    local project_name
    project_name="$(basename "$project_dir")"
    echo -e "${GREEN}Processing Web project ($kind): $project_name${NC}"
    echo "  Location: $project_dir"

    cd "$project_dir" || {
        echo -e "  ${RED}Error: Cannot change to directory $project_dir${NC}"
        cd "$WORKSPACE_ROOT"
        echo ""
        return 1
    }

    # Check Node & npm
    if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
        echo -e "  ${YELLOW}Warning: Node.js and/or npm not found. Skipping.${NC}"
        cd "$WORKSPACE_ROOT"
        echo ""
        return 1
    fi

    # Install dependencies (prefer CI if lockfile exists)
    local install_cmd
    if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
        install_cmd="npm ci"
    else
        install_cmd="npm install"
    fi

    echo "  Installing dependencies (this may take a while)..."
    if ! $install_cmd >/dev/null 2>&1; then
        echo -e "  ${YELLOW}Warning: npm install failed; attempting to proceed to tests${NC}"
    fi

    # Run tests with coverage
    if [[ "$kind" == "nx" ]]; then
        echo "  Running Nx tests with coverage (configuration=ci)..."
        if npx --yes nx run-many -t test --configuration=ci >/dev/null 2>&1; then
            :
        else
            echo -e "  ${YELLOW}Warning: Nx tests failed or no tests found${NC}"
        fi
    else
        # standalone node project
        if npm run -s test:cov >/dev/null 2>&1; then
            :
        else
            echo "  Running npm test with coverage flags..."
            npm test -- --coverage --watchAll=false >/dev/null 2>&1 || true
        fi
    fi

    # Accumulate coverage from lcov.info files
    read -r covered total < <(accumulate_lcov_coverage "$project_dir")
    covered=${covered:-0}
    total=${total:-0}

    if [[ "$total" -gt 0 ]]; then
        tech_covered_lines["web"]=$((tech_covered_lines["web"] + covered))
        tech_total_lines["web"]=$((tech_total_lines["web"] + total))
        tech_projects["web"]=$((tech_projects["web"] + 1))
        local percentage
        percentage=$(awk "BEGIN {printf \"%.2f\", ($covered/$total)*100}")
        echo "  Coverage: $percentage% ($covered/$total lines)"
    else
        echo -e "  ${YELLOW}Warning: No coverage data found (lcov.info missing)${NC}"
    fi

    cd "$WORKSPACE_ROOT"
    echo ""
}

# Process all .NET solutions
echo -e "${BLUE}=== Processing .NET Solutions (${#dotnet_solutions[@]} found) ===${NC}"
echo ""
if [[ ${#dotnet_solutions[@]} -gt 0 ]]; then
    mkdir -p "$COVERAGE_OUTPUT_DIR/dotnet"
    
    for sln in "${dotnet_solutions[@]}"; do
        calculate_dotnet_coverage "$sln"
    done
else
    echo -e "  ${YELLOW}No .NET solutions to process${NC}"
    echo ""
fi

# Process all Java projects
echo -e "${BLUE}=== Processing Java Projects (${#java_projects[@]} found) ===${NC}"
echo ""
if [[ ${#java_projects[@]} -gt 0 ]]; then
    mkdir -p "$COVERAGE_OUTPUT_DIR/java"

    for pom in "${java_projects[@]}"; do
        calculate_java_coverage "$pom"
    done
else
    echo -e "  ${YELLOW}No Java projects to process${NC}"
    echo ""
fi

# Process all Kotlin/Gradle projects
echo -e "${BLUE}=== Processing Kotlin/Gradle Projects (${#kotlin_projects[@]} found) ===${NC}"
echo ""
if [[ ${#kotlin_projects[@]} -gt 0 ]]; then
    mkdir -p "$COVERAGE_OUTPUT_DIR/kotlin"

    for gradle in "${kotlin_projects[@]}"; do
        calculate_kotlin_coverage "$gradle"
    done
else
    echo -e "  ${YELLOW}No Kotlin/Gradle projects to process${NC}"
    echo ""
fi

# Process all Rust projects
echo -e "${BLUE}=== Processing Rust Projects (${#rust_projects[@]} found) ===${NC}"
echo ""
if [[ ${#rust_projects[@]} -gt 0 ]]; then
    mkdir -p "$COVERAGE_OUTPUT_DIR/rust"

    for cargo in "${rust_projects[@]}"; do
        calculate_rust_coverage "$cargo"
    done
else
    echo -e "  ${YELLOW}No Rust projects to process${NC}"
    echo ""
fi

# Process all PostgreSQL projects
echo -e "${BLUE}=== Processing PostgreSQL Databases (${#postgres_projects[@]} found) ===${NC}"
echo ""
if [[ ${#postgres_projects[@]} -gt 0 ]]; then
    for db_dir in "${postgres_projects[@]}"; do
        calculate_postgresql_coverage "$db_dir"
    done
else
    echo -e "  ${YELLOW}No PostgreSQL projects to process${NC}"
    echo ""
fi

# Process all Web (Nx/Node) projects
echo -e "${BLUE}=== Processing Web Projects (Nx: ${#web_nx_projects[@]}, Node: ${#web_node_projects[@]}) ===${NC}"
echo ""
if [[ ${#web_nx_projects[@]} -gt 0 || ${#web_node_projects[@]} -gt 0 ]]; then
    for nx_dir in "${web_nx_projects[@]}"; do
        calculate_web_coverage "$nx_dir" "nx"
    done
    for node_dir in "${web_node_projects[@]}"; do
        calculate_web_coverage "$node_dir" "node"
    done
else
    echo -e "  ${YELLOW}No Web projects to process${NC}"
    echo ""
fi

echo "=========================================="
echo -e "${BLUE}Step 3: Generating Summary Report${NC}"
echo "=========================================="
echo ""

# Calculate overall percentages
for tech in dotnet java kotlin rust postgresql; do
    if [[ ${tech_total_lines[$tech]} -gt 0 ]]; then
        tech_coverage_percentage[$tech]=$(awk "BEGIN {printf \"%.2f\", (${tech_covered_lines[$tech]}/${tech_total_lines[$tech]})*100}")
    else
        tech_coverage_percentage[$tech]="0.00"
    fi
done

# Calculate web coverage percentage
if [[ ${tech_total_lines[web]} -gt 0 ]]; then
    tech_coverage_percentage[web]=$(awk "BEGIN {printf \"%.2f\", (${tech_covered_lines[web]}/${tech_total_lines[web]})*100}")
else
    tech_coverage_percentage[web]="0.00"
fi

# Generate summary file
{
    echo "=========================================="
    echo "COMPREHENSIVE CODE COVERAGE REPORT"
    echo "=========================================="
    echo "Generated: $(date)"
    echo "Workspace: $WORKSPACE_ROOT"
    echo ""
    echo "NOTE: This report excludes git submodules to prevent duplicate counting"
    echo ""
    echo "=========================================="
    echo "COVERAGE BY TECHNOLOGY"
    echo "=========================================="
    echo ""
    
    echo ".NET Projects:"
    echo "  Projects Analyzed: ${tech_projects[dotnet]}"
    echo "  Lines Covered: ${tech_covered_lines[dotnet]}"
    echo "  Total Lines: ${tech_total_lines[dotnet]}"
    echo "  Coverage: ${tech_coverage_percentage[dotnet]}%"
    echo ""
    
    echo "Java Projects:"
    echo "  Projects Analyzed: ${tech_projects[java]}"
    echo "  Lines Covered: ${tech_covered_lines[java]}"
    echo "  Total Lines: ${tech_total_lines[java]}"
    echo "  Coverage: ${tech_coverage_percentage[java]}%"
    echo ""
    
    echo "Kotlin/Gradle Projects:"
    echo "  Projects Analyzed: ${tech_projects[kotlin]}"
    echo "  Lines Covered: ${tech_covered_lines[kotlin]}"
    echo "  Total Lines: ${tech_total_lines[kotlin]}"
    echo "  Coverage: ${tech_coverage_percentage[kotlin]}%"
    echo ""
    
    echo "Rust Projects:"
    echo "  Projects Analyzed: ${tech_projects[rust]}"
    echo "  Lines Covered: ${tech_covered_lines[rust]}"
    echo "  Total Lines: ${tech_total_lines[rust]}"
    echo "  Coverage: ${tech_coverage_percentage[rust]}%"
    echo ""
    
    echo "PostgreSQL Databases:"
    echo "  Projects Analyzed: ${tech_projects[postgresql]}"
    echo "  Lines Covered: ${tech_covered_lines[postgresql]}"
    echo "  Total Lines: ${tech_total_lines[postgresql]}"
    echo "  Coverage: ${tech_coverage_percentage[postgresql]}%"
    echo ""

    echo "Web Projects (Nx/Node):"
    echo "  Projects Analyzed: ${tech_projects[web]}"
    echo "  Lines Covered: ${tech_covered_lines[web]}"
    echo "  Total Lines: ${tech_total_lines[web]}"
    echo "  Coverage: ${tech_coverage_percentage[web]}%"
    echo ""
    
    # Calculate overall statistics
    total_projects=$((tech_projects[dotnet] + tech_projects[java] + tech_projects[kotlin] + tech_projects[rust] + tech_projects[postgresql] + tech_projects[web]))
    total_covered=$((tech_covered_lines[dotnet] + tech_covered_lines[java] + tech_covered_lines[kotlin] + tech_covered_lines[rust] + tech_covered_lines[postgresql] + tech_covered_lines[web]))
    total_lines=$((tech_total_lines[dotnet] + tech_total_lines[java] + tech_total_lines[kotlin] + tech_total_lines[rust] + tech_total_lines[postgresql] + tech_total_lines[web]))
    
    if [[ $total_lines -gt 0 ]]; then
        overall_coverage=$(awk "BEGIN {printf \"%.2f\", ($total_covered/$total_lines)*100}")
    else
        overall_coverage="0.00"
    fi
    
    echo "=========================================="
    echo "OVERALL STATISTICS"
    echo "=========================================="
    echo "  Total Projects: $total_projects"
    echo "  Total Lines Covered: $total_covered"
    echo "  Total Lines: $total_lines"
    echo "  Overall Coverage: $overall_coverage%"
    echo ""
    echo "=========================================="
    
} | tee "$SUMMARY_FILE"

# Display summary to console
cat "$SUMMARY_FILE"

echo ""
echo -e "${GREEN}Coverage calculation complete!${NC}"
echo "Summary saved to: $SUMMARY_FILE"
echo "Detailed results in: $COVERAGE_OUTPUT_DIR"
echo ""
# Exit with success