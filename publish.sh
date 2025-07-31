#!/bin/bash

# Resolve Python & Pip executables
PYTHON=$(command -v python || command -v python3)
PIP="$PYTHON -m pip"

if [[ -z "$PYTHON" ]]; then
    echo "Error: Python interpreter not found (python or python3). Please install Python or ensure it's on PATH."
    exit 1
fi

# Function to get the latest version from PyPI
get_latest_version() {
    local package_name="directus-py-sdk"
    local version=""

    # Try PyPI JSON API first
    version=$(curl -s "https://pypi.org/pypi/$package_name/json" | $PYTHON - "$package_name" <<'PY'
import sys, json
try:
    data=json.load(sys.stdin)
    print(data['info']['version'])
except Exception:
    pass
PY
)

    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi

    # Fallback: read from setup.py if network fails
    version=$($PYTHON - <<'PY'
import re, pathlib, sys
try:
    content=pathlib.Path('setup.py').read_text()
    m=re.search(r'version="([^"]+)"', content)
    if m:
        print(m.group(1))
except Exception:
    pass
PY
)
    echo "${version:-0.0.0}"
}

# Function to increment version based on update type
increment_version() {
    local version="$1"
    local update_type="$2"

    if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        version="0.0.0"
    fi

    IFS='.' read -r major minor patch <<< "$version"

    case $update_type in
        1) ((major++)); minor=0; patch=0;;
        2) ((minor++)); patch=0;;
        3) ((patch++)); ;;
    esac

    echo "$major.$minor.$patch"
}

current_version=$(get_latest_version)

echo "Current version: $current_version"

echo "\nWhat type of update is this?"
echo "1) Major version update (Breaking changes)"
echo "2) Minor version update (New features)"
echo "3) Patch version update (Bug fixes)"
read -rp "Enter your choice (1-3): " update_type

if [[ ! $update_type =~ ^[1-3]$ ]]; then
    echo "Invalid choice. Exiting."
    exit 1
fi

new_version=$(increment_version "$current_version" "$update_type")

echo -e "\nCurrent version: $current_version"
echo "New version will be: $new_version"
read -rp "Do you want to proceed with version $new_version? (y/n): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo "Updating version in setup.py..."
$PYTHON - <<PY
import re, pathlib, sys
new_version = "$new_version"
path = pathlib.Path('setup.py')
text = path.read_text()
text = re.sub(r'version="[^"]+"', f'version="{new_version}"', text)
path.write_text(text)
PY

grep -q "version=\"$new_version\"" setup.py || { echo "Failed to update setup.py"; exit 1; }

# --- Git commit & tag ---
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "\nCommitting version bump to git..."
  git add setup.py || { echo "Git add failed"; exit 1; }
  git commit -m "Bump version to $new_version" || echo "Nothing to commit, continuing..."

  # Create annotated tag if it doesn't already exist
  if git rev-parse "v$new_version" >/dev/null 2>&1; then
    echo "Tag v$new_version already exists. Skipping tag creation."
  else
    git tag -a "v$new_version" -m "Release $new_version" || { echo "Git tag failed"; exit 1; }
    git push --follow-tags || git push && git push --tags
  fi
else
  echo "Not a git repository – skipping git commit & tag."
fi

echo "\nBuilding package..."
$PYTHON -m pip install --quiet --upgrade build twine
$PYTHON -m build || { echo "Build failed"; exit 1; }

echo "\nPublishing to PyPI..."
$PYTHON -m twine upload dist/*

echo "\nPackage published successfully! New version $new_version is now available on PyPI."

echo "Cleaning up..."
rm -rf build/ dist/ *.egg-info/

echo "Done!" 