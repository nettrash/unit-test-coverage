#!/usr/bin/env bash

# Preview what projects will be tested (excluding submodules)
# This script shows what the coverage calculator will process

# Requires bash 4+ for associative arrays
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "This script requires bash 4 or higher."
    echo "On macOS, install with: brew install bash"
    echo "Or run with: /usr/local/bin/bash $0"
    # Fallback: use a different approach
    USE_SIMPLE_MODE=1
else
    USE_SIMPLE_MODE=0
fi

set -e

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Coverage Projects Preview"
echo "=========================================="
echo "Workspace: $WORKSPACE_ROOT"
echo ""

# Function to check if a path is in a git submodule
is_submodule() {
    local path="$1"
    local current_dir=""
    
    # If path is a directory, start at the directory; otherwise start at its parent
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
    
    return 1
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

# Initialize tracking for processed git roots
if [[ "$USE_SIMPLE_MODE" -eq 0 ]]; then
    declare -A processed_git_roots
    declare -A git_root_cache
fi

# Simple mode fallback for older bash
if [[ "$USE_SIMPLE_MODE" -eq 1 ]]; then
    PROCESSED_FILE=$(mktemp)
    trap "rm -f $PROCESSED_FILE" EXIT
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

echo -e "${BLUE}=== .NET Projects (*.sln) ===${NC}"
dotnet_count=0
while IFS= read -r -d '' sln_file; do
    # Skip if in .git directory (extra safety check)
    [[ "$sln_file" == *"/.git/"* ]] && continue
    
    # Exclude git submodules using helper (checks parent chain for .git file)
    if is_submodule "$sln_file"; then
        continue
    fi
    
    git_root=$(find_git_root "$sln_file")
    if [[ -n "$git_root" ]] && ! check_if_processed "dotnet:$git_root"; then
        mark_as_processed "dotnet:$git_root"
        # Use simple string substitution instead of realpath for speed
        relative_path="${sln_file#$WORKSPACE_ROOT/}"
        echo -e "${GREEN}✓${NC} $relative_path"
        dotnet_count=$((dotnet_count + 1))
    fi
done < <(find "$WORKSPACE_ROOT" -name "*.sln" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)
echo "Total: $dotnet_count projects"
echo ""

echo -e "${BLUE}=== Java Projects (pom.xml) ===${NC}"
java_count=0
while IFS= read -r -d '' pom_file; do
    # Skip if in .git directory (extra safety check)
    [[ "$pom_file" == *"/.git/"* ]] && continue
    
    # Exclude git submodules using helper (checks parent chain for .git file)
    if is_submodule "$pom_file"; then
        continue
    fi
    
    git_root=$(find_git_root "$pom_file")
    if [[ -n "$git_root" ]] && ! check_if_processed "java:$git_root"; then
        mark_as_processed "java:$git_root"
        # Use simple string substitution instead of realpath for speed
        relative_path="${pom_file#$WORKSPACE_ROOT/}"
        echo -e "${GREEN}✓${NC} $relative_path"
        java_count=$((java_count + 1))
    fi
done < <(find "$WORKSPACE_ROOT" -name "pom.xml" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

if command -v mvn &> /dev/null; then
    echo -e "${GREEN}Maven is installed${NC}"
else
    echo -e "${YELLOW}Warning: Maven is not installed - Java coverage will be skipped${NC}"
fi
echo "Total: $java_count projects"
echo ""

echo -e "${BLUE}=== Kotlin/Gradle Projects (settings.gradle.kts) ===${NC}"
kotlin_count=0
while IFS= read -r -d '' gradle_file; do
    # Skip if in .git directory (extra safety check)
    [[ "$gradle_file" == *"/.git/"* ]] && continue
    
    # Exclude git submodules using helper (checks parent chain for .git file)
    if is_submodule "$gradle_file"; then
        continue
    fi
    
    git_root=$(find_git_root "$gradle_file")
    if [[ -n "$git_root" ]] && ! check_if_processed "kotlin:$git_root"; then
        mark_as_processed "kotlin:$git_root"
        # Use simple string substitution instead of realpath for speed
        relative_path="${gradle_file#$WORKSPACE_ROOT/}"
        echo -e "${GREEN}✓${NC} $relative_path"
        kotlin_count=$((kotlin_count + 1))
    fi
done < <(find "$WORKSPACE_ROOT" -name "settings.gradle.kts" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

if command -v gradle &> /dev/null; then
    echo -e "${GREEN}Gradle is installed${NC}"
else
    echo -e "${YELLOW}Warning: Gradle not installed - Kotlin coverage will be skipped${NC}"
    echo "Most projects have ./gradlew wrapper, so this may still work"
fi
echo "Total: $kotlin_count projects"
echo ""

echo -e "${BLUE}=== Rust Projects (Cargo.toml) ===${NC}"
rust_count=0
while IFS= read -r -d '' cargo_file; do
    # Skip if in .git directory (extra safety check)
    [[ "$cargo_file" == *"/.git/"* ]] && continue
    
    # Exclude git submodules using helper (checks parent chain for .git file)
    if is_submodule "$cargo_file"; then
        continue
    fi
    
    if grep -q "\[workspace\]" "$cargo_file" 2>/dev/null || ! grep -q "workspace = " "$cargo_file" 2>/dev/null; then
        git_root=$(find_git_root "$cargo_file")
        if [[ -n "$git_root" ]] && ! check_if_processed "rust:$git_root"; then
            mark_as_processed "rust:$git_root"
            # Use simple string substitution instead of realpath for speed
            relative_path="${cargo_file#$WORKSPACE_ROOT/}"
            echo -e "${GREEN}✓${NC} $relative_path"
            rust_count=$((rust_count + 1))
        fi
    fi
done < <(find "$WORKSPACE_ROOT" -name "Cargo.toml" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

if command -v cargo &> /dev/null; then
    echo -e "${GREEN}Cargo is installed${NC}"
    if command -v cargo-tarpaulin &> /dev/null; then
        echo -e "${GREEN}cargo-tarpaulin is installed${NC}"
    else
        echo -e "${YELLOW}Warning: cargo-tarpaulin not installed - Rust coverage will be skipped${NC}"
        echo "Install with: cargo install cargo-tarpaulin"
    fi
else
    echo -e "${YELLOW}Warning: Cargo is not installed - Rust coverage will be skipped${NC}"
fi
echo "Total: $rust_count projects"
echo ""

echo -e "${BLUE}=== PostgreSQL Databases (*.database directories) ===${NC}"
postgres_count=0
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
    
    # Exclude git submodules using helper (checks parent chain for .git file)
    if is_submodule "$db_dir"; then
        continue
    fi
    
    db_count=$((db_count + 1))
    
    git_root=$(find_git_root "$db_dir")
    if [[ -n "$git_root" ]] && ! check_if_processed "postgresql:$git_root"; then
        postgres_count=$((postgres_count + 1))
        mark_as_processed "postgresql:$git_root"
        # Use simple string substitution instead of realpath for speed
        rel_path="${db_dir#$WORKSPACE_ROOT/}"
        echo "  ✓ Found: $rel_path"
    fi
done

echo "Total PostgreSQL projects found: $postgres_count (scanned $db_count directories)"
echo ""

echo -e "${BLUE}=== Web Projects (Nx/Node) ===${NC}"
web_nx_count=0
web_node_count=0

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

# Nx workspaces
while IFS= read -r -d '' nx_file; do
    [[ "$nx_file" == *"/.git/"* ]] && continue
    if is_submodule "$nx_file"; then
        continue
    fi
    nx_dir="${nx_file%/*}"
    rel_path="${nx_dir#$WORKSPACE_ROOT/}"
    echo -e "${GREEN}✓${NC} Nx: $rel_path"
    web_nx_count=$((web_nx_count + 1))
done < <(find "$WORKSPACE_ROOT" -name "nx.json" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

# Standalone Node projects (with test script) that are not part of an Nx workspace
while IFS= read -r -d '' pkg_file; do
    [[ "$pkg_file" == *"/.git/"* ]] && continue
    [[ "$pkg_file" == *"/node_modules/"* ]] && continue
    if is_in_nx_workspace "$pkg_file"; then
        continue
    fi
    if is_submodule "$pkg_file"; then
        continue
    fi
    if grep -q '"test"' "$pkg_file" 2>/dev/null || grep -q '"test:cov"' "$pkg_file" 2>/dev/null; then
        pkg_dir="${pkg_file%/*}"
        rel_path="${pkg_dir#$WORKSPACE_ROOT/}"
        echo -e "${GREEN}✓${NC} Node: $rel_path"
        web_node_count=$((web_node_count + 1))
    fi
done < <(find "$WORKSPACE_ROOT" -name "package.json" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/target/*" ! -path "*/build/*" -print0 2>/dev/null)

echo "Total Web Nx workspaces: $web_nx_count"
echo "Total Web Node projects: $web_node_count"
echo ""
