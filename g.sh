#!/usr/bin/env bash
# A simple Git workflow automation script for solo developers
# Environment: Linux/WSL, POSIX shell
# Dependencies: gh (GitHub CLI), npm, ava (test runner)

set -euo pipefail  # fail on errors, undefined vars, and pipelines

# print_usage: show available commands
print_usage() {
  cat <<EOF
Usage: g {start|sync|publish|hotfix} [args]

Commands:
  start <name>    Initialize repo if needed, create feature branch from main + switch
  sync            Update main + rebase current branch onto main
  publish         Run tests, push, auto-PR + auto-merge (or push main)
  hotfix <name>   Create hotfix branch from last tag
EOF
}

# require_clean_branch: ensure no uncommitted changes
require_clean_branch() {
  # Only check if inside a git repo
  if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Error: uncommitted changes. Commit or stash first."
      exit 1
    fi
  fi
}

# get_current_branch: name of active branch
get_current_branch() {
  # Ensure we are in a git repo before trying to get branch name
  if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    git rev-parse --abbrev-ref HEAD
  else
    echo "" # Return empty string if not in a git repo yet
  fi
}

case "${1:-}" in
  start)
    # Check if this is a Git repository, initialize if not
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
      echo "Not a Git repository. Initializing..."
      git init
      # Optional: create an initial commit if you want main to exist right away
      # git commit --allow-empty -m "Initial commit"
      echo "Git repository initialized."
    else
      # If it IS a repo, require clean state before proceeding
      require_clean_branch
    fi

    # Ensure main branch exists and is up-to-date, or create it
    if git show-ref --verify --quiet refs/heads/main; then
      # main exists, switch and pull
      git switch main && git pull --ff-only origin main || echo "Could not pull from remote 'main'. Continuing locally."
    else
      # main does not exist, check if it's the initial empty repo state
      if ! git rev-parse --verify HEAD > /dev/null 2>&1; then
         # Repo is empty, create main and initial commit
         echo "Creating 'main' branch and initial empty commit..."
         git checkout -b main
         git commit --allow-empty -m "Initial commit"
      else
         # Repo not empty but no main branch? This is unusual. Error out.
         echo "Error: 'main' branch does not exist, and repository is not empty. Please check your repository structure."
         exit 1
      fi
    fi

    branch="feat/${2// /-}-$(date +%y%m%d%H%M)"
    git switch -c "$branch"
    echo "Switched to new branch '$branch'"
    ;;

  sync)
    require_clean_branch
    original_branch=$(get_current_branch)
    if [[ -z "$original_branch" ]]; then
      echo "Error: Not in a Git repository or no branch checked out."
      exit 1
    fi

    echo "Fetching remote changes..."
    git fetch origin --prune || echo "Warning: Could not fetch from origin."

    echo "Switching to main and updating..."
    git switch main && git pull --ff-only origin main || echo "Warning: Could not update 'main' from origin. Continuing with local 'main'."

    if [[ "$original_branch" != "main" ]]; then
      echo "Switching back to '$original_branch' and rebasing onto main..."
      git switch "$original_branch"
      git rebase main
    fi
    echo "'$original_branch' is now up-to-date with 'main'."
    ;;

  publish)
    require_clean_branch
    branch=$(get_current_branch)
    if [[ -z "$branch" ]]; then
      echo "Error: Not in a Git repository or no branch checked out."
      exit 1
    fi

    echo "Running tests..."
    # Check which package manager to use based on lock files
    if [ -f "pnpm-lock.yaml" ]; then
      echo "Using pnpm to install dependencies..."
      pnpm install
    elif [ -f "package-lock.json" ]; then
      echo "Using npm to install dependencies..."
      npm ci
    elif [ -f "yarn.lock" ]; then
      echo "Using yarn to install dependencies..."
      yarn install --frozen-lockfile
    else
      echo "Using npm to install dependencies (no lock file found)..."
      npm install
    fi
    
    npx ava

    echo "Pushing '$branch' to origin..."
    git push -u origin HEAD

    if [[ "$branch" == "main" ]]; then
      echo "Main pushed; GitHub Actions deploy should trigger automatically."
      exit 0
    fi

    echo "Creating Pull Request and enabling auto-merge for '$branch'..."
    gh pr create --fill --label automerge --base main || echo "PR may already exist. Attempting to enable auto-merge."
    gh pr merge --squash --auto || echo "Could not enable auto-merge. Check PR status on GitHub."
    ;;

  hotfix)
    require_clean_branch
    tag=$(git describe --tags --abbrev=0)
    if [[ -z "$tag" ]]; then
      echo "Error: No tags found to base hotfix on."
      exit 1
    fi
    branch_name="hotfix/${2// /-}-$(date +%y%m%d%H%M)"
    echo "Creating hotfix branch '$branch_name' from tag '$tag'..."
    git switch -c "$branch_name" "$tag"
    ;;

  *)
    print_usage
    exit 1
    ;;
esac