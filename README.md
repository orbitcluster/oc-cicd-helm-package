# Package Helm Chart Action

This GitHub Action packages a Helm chart, handles dynamic versioning based on the branch, and pushes the packaged chart to the GitHub Container Registry (GHCR).

## Description

The action performs the following steps:

1.  Validates `Chart.yaml` existence.
2.  Extracts the chart name and base version from `Chart.yaml`.
3.  Determines the final version:
    - **Main Branch**: Uses the version from `Chart.yaml`.
    - **Other Branches (PRs/Features)**: Appends the branch name and short commit SHA to the version (e.g., `1.2.3-feature-branch-a1b2c3d`).
    - **Override**: If `version-override` is provided, it takes precedence.
4.  Logs into GHCR.
5.  Builds chart dependencies.
6.  Packages the chart.
7.  Pushes the OCI artifact to `ghcr.io/<owner>/<repo>/helm`.

## Inputs

| Input                | Description                                                               | Required | Default  |
| :------------------- | :------------------------------------------------------------------------ | :------- | :------- |
| `github-token`       | GitHub Token for authentication (used to push to GHCR).                   | **Yes**  | N/A      |
| `path`               | Path to the directory containing `Chart.yaml`.                            | Yes      | `.`      |
| `version-override`   | Force a specific version string, bypassing the dynamic logic.             | No       | `""`     |
| `validate_templates` | function as a feature flag to run `helm template --debug` for validation. | No       | `"true"` |

## Outputs

| Output          | Description                                                                                               |
| :-------------- | :-------------------------------------------------------------------------------------------------------- |
| `chart-archive` | The filename of the generated `.tgz` package (e.g., `mychart-1.2.3.tgz`).                                 |
| `image`         | The full OCI image reference with digest (e.g., `oci://ghcr.io/user/repo/helm/mychart:1.2.3@sha256:...`). |
| `package`       | The package path within the OCI registry (e.g., `user/repo/helm/mychart`).                                |
| `version`       | The final semantic version used for the package.                                                          |

## Versioning Behavior

The action enforces a versioning strategy that supports Continuous Deployment:

- **Release (Branch: `main`)**:
  - Version: `X.Y.Z` (from `Chart.yaml`)
  - The `Chart.yaml` version is respected as the source of truth for releases.

- **Pre-Release (Other Branches)**:
  - Version: `X.Y.Z-<BRANCH_NAME>-<SHORT_SHA>`
  - Example: If `Chart.yaml` is `1.0.0` and branch is `feat/new-ui`, version becomes `1.0.0-feat-new-ui-a1b2c3d`.
  - Safe for testing; does not conflict with release versions.

- **Override**:
  - If `version-override` is set (e.g., `1.0.1-rc.1`), this exact string is used.

## Example Usage

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  package-helm:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Package and Push Helm Chart
        uses: ./
        id: helm-package
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          path: ./charts/my-chart
          # validate_templates: "false" # Optional: disable validation

      - name: Print Output
        run: |
          echo "Pushed version: ${{ steps.helm-package.outputs.version }}"
          echo "Image ref: ${{ steps.helm-package.outputs.image }}"
```
