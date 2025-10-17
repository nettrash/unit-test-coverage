# Unit Test Coverage Toolkit

Calculate and aggregate unit-test code coverage across a mixed-language monorepo, while automatically excluding git submodules to avoid double counting. Outputs a per-technology breakdown and an overall coverage summary.

## What this covers

Out of the box, the scripts detect and measure coverage for:

- .NET solutions (`*.sln`) via `dotnet test` with XPlat Code Coverage
- Java (Maven) projects (`pom.xml`) via JaCoCo
- Kotlin (Gradle) projects (`settings.gradle.kts`) via JaCoCo
- Rust projects (`Cargo.toml`) via `cargo-tarpaulin`
- PostgreSQL “database” directories (`*.database` or `*-database`), using a heuristic
- Web projects:
  - Nx workspaces (`nx.json`): `npx nx run-many -t test --configuration=ci`
  - Standalone Node projects (`package.json` with a test script): Jest/Istanbul lcov parsing

Git submodules are automatically excluded by scanning parent chains for a `.git` file.

## How it works (high level)

1. Scans the workspace from the script location and discovers projects by well-known markers.
2. Skips anything inside git submodules and common build output folders (`node_modules`, `target`, `build`).
3. Runs language-appropriate test commands to generate coverage reports.
4. Parses Cobertura/XML/LCOV outputs (or estimates for PostgreSQL) and aggregates covered/total lines by technology.
5. Writes a timestamped summary and stores detailed artifacts under `coverage-results-complete/`.

## Prerequisites

You can run the toolkit even if some tools are missing—those technologies will be skipped with a warning. For full coverage:

- Bash 4+ (recommended for performance)
  - macOS typically ships with Bash 3.x. Either install a newer Bash or the scripts will fall back to a simpler mode.
  - Install on macOS (Homebrew): `brew install bash`
- .NET SDK: `dotnet` CLI available in `PATH`
- Java + Maven: `mvn`
- Gradle (or project `./gradlew` wrappers)
- Rust: `cargo` and `cargo-tarpaulin` (install via `cargo install cargo-tarpaulin`)
- Node.js and `npm` (and `npx` for Nx workspaces)
- Optional utilities for faster/more precise parsing:
  - `xmllint` (libxml2) for XML coverage parsing
  - `less` for viewing docs via the quick start script

## Quick start

Run the interactive helper. It can preview what will be tested, kick off the full run, or show install hints.

```bash
./quick_start_coverage.sh
```

Approximate runtime for a large monorepo can be several hours, depending on project count and dependency installs.

## Preview what will be tested

See all detected projects without running tests:

```bash
./preview_coverage_projects.sh
```

## Run the full coverage calculation

This discovers projects, runs tests with coverage, aggregates results, and writes a summary and artifacts.

```bash
./calculate_comprehensive_coverage.sh
```

### Outputs

- `coverage-results-complete/` directory with per-technology artifacts
  - .NET: Cobertura XML under `coverage-results-complete/dotnet/<solution>/.../coverage.cobertura.xml`
  - Java: JaCoCo XML at `target/site/jacoco/jacoco.xml` (copied to `coverage-results-complete/java_<project>_jacoco.xml`)
  - Kotlin/Gradle: module JaCoCo XML copied to `coverage-results-complete/kotlin_<project>_<module>_jacoco.xml`
  - Rust: Cobertura XML from `cargo tarpaulin` under `coverage-results-complete/rust/<project>/cobertura.xml`
  - Web (Nx/Node): LCOV files discovered under `**/coverage/**/lcov.info` are parsed and aggregated
- Summary text file: `coverage-results-complete/coverage-summary-YYYYMMDD_HHMMSS.txt`
  - Contains per-technology counts of projects, covered lines, total lines, and percentage, plus overall coverage

## Technology-specific details

- .NET
  - Command: `dotnet test --collect:"XPlat Code Coverage"`
  - Output: Cobertura XML parsed for lines-covered/lines-valid

- Java (Maven)
  - Command: `mvn clean test jacoco:report`
  - Output: parses `target/site/jacoco/jacoco.xml` for LINE counters (covered/missed)

- Kotlin/Gradle
  - Command: `gradle|./gradlew clean test jacocoTestReport`
  - Output: parses `*/build/reports/jacoco/test/jacocoTestReport.xml` across modules

- Rust
  - Command: `cargo tarpaulin --out Xml`
  - Output: Cobertura XML (`cobertura.xml`)

- PostgreSQL
  - Discovers directories ending with `.database` or `-database`
  - Counts routine SQL files under `scheme/routines` or `*.scheme/routines`
  - Marks a routine “covered” if its function/procedure name appears in test SQL files under `scheme/tests`, `*.scheme/tests`, or in files named like `*test*.sql`/`*spec*.sql` inside those trees
  - If names don’t match but assertions are present, it estimates coverage using assertion density (assumes ~4 assertions per routine)
  - This is heuristic/approximate coverage intended for directional insight

- Web (Nx/Node)
  - Nx workspaces: `npx nx run-many -t test --configuration=ci`
  - Standalone Node: tries `npm run test:cov`, falls back to `npm test -- --coverage --watchAll=false`
  - Coverage is aggregated from LCOV files found under `coverage/`

## CI usage (example: GitHub Actions)

Note: end-to-end coverage across many projects can be time-consuming. Consider caching and/or running on a schedule.

```yaml
name: Coverage
on:
  workflow_dispatch: {}
  schedule:
    - cron: '0 3 * * 0' # weekly

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: 'lts/*'
      - name: Set up Java
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '21'
      - name: Set up .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '8.0.x'
      - name: Install Rust (for tarpaulin)
        uses: dtolnay/rust-toolchain@stable
      - name: Install cargo-tarpaulin
        run: cargo install cargo-tarpaulin
      - name: Make scripts executable
        run: |
          chmod +x quick_start_coverage.sh preview_coverage_projects.sh calculate_comprehensive_coverage.sh
      - name: Run coverage
        run: ./calculate_comprehensive_coverage.sh
      - name: Upload summary
        uses: actions/upload-artifact@v4
        with:
          name: coverage-results-complete
          path: coverage-results-complete
```

## Troubleshooting

- Permission denied
	- Ensure scripts are executable: `chmod +x quick_start_coverage.sh preview_coverage_projects.sh calculate_comprehensive_coverage.sh`
- Missing tools
	- The quick start script can show install hints; missing tools just skip that technology
- macOS Bash 3.x
	- Either install Bash 4+ (`brew install bash`) or run explicitly via the new bash path (e.g., `/usr/local/bin/bash ./calculate_comprehensive_coverage.sh`)
- Nx not found
	- Ensure Nx is installed as a dev dependency or available via `npx`
- Long runtimes
	- Use the preview first; run languages individually by temporarily removing others if needed; rely on CI caches

## License

This project is licensed under the terms of the LICENSE file in this repository.

