#!/usr/bin/env bash
set -euo pipefail

echo "=== Weekly Upstream Sync ==="

# 1. Setup Remotes
git remote add upstream https://github.com/KDE/spectacle.git 2>/dev/null || git remote set-url upstream https://github.com/KDE/spectacle.git
git fetch upstream master
git fetch origin master:master || true

# 2. Sync fork's master with upstream master
echo "Fast-forwarding master to upstream/master..."
git checkout master
git merge --ff-only upstream/master
git push origin master
git checkout main

# 3. Check if there are new commits in upstream/master that are not in main
COMMITS_BEHIND=$(git rev-list --count HEAD..upstream/master)
echo "Commits behind upstream/master: $COMMITS_BEHIND"

if [ "$COMMITS_BEHIND" -eq 0 ]; then
  echo "Already fully up to date with upstream KDE/spectacle master."
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "### Upstream Sync Result" >> "$GITHUB_STEP_SUMMARY"
    echo "Already fully up to date with upstream KDE/spectacle master. No build needed." >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
fi

# 4. Attempt to merge upstream/master into main
echo "Merging $COMMITS_BEHIND commit(s) from upstream/master into main..."
if git merge upstream/master -m "Automated upstream sync: merge KDE/spectacle master"; then
  echo "Merge completed cleanly."
  git push origin main
  git push origin main:feature/smart-eraser || true

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "### Upstream Sync Result" >> "$GITHUB_STEP_SUMMARY"
    echo "Successfully merged $COMMITS_BEHIND new upstream commit(s). The build workflow has been triggered automatically on push." >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
else
  echo "Merge conflict detected!"
  CONFLICTS=$(git diff --name-only --diff-filter=U)
  git merge --abort

  cat > /tmp/conflict_issue.md <<EOF
The scheduled upstream sync encountered merge conflicts with recent commits from KDE/spectacle master.

### Conflicted Files:
\`\`\`
$CONFLICTS
\`\`\`

### Resolution Steps:
1. Fetch latest changes: \`git fetch upstream && git checkout main\`
2. Merge upstream: \`git merge upstream/master\`
3. Resolve conflicts in the files listed above
4. Push to origin: \`git push origin main\`

Once pushed, the automated build workflow will re-verify the build and update the release.
EOF

  EXISTING_ISSUE=$(gh issue list --repo "${GITHUB_REPOSITORY}" --search "Automated upstream sync conflict" --state open --json number --jq '.[0].number' 2>/dev/null || true)
  if [ -z "$EXISTING_ISSUE" ]; then
    gh issue create \
      --repo "${GITHUB_REPOSITORY}" \
      --title "⚠️ Automated upstream sync conflict" \
      --body-file /tmp/conflict_issue.md || true
  else
    gh issue comment "$EXISTING_ISSUE" \
      --repo "${GITHUB_REPOSITORY}" \
      --body-file /tmp/conflict_issue.md || true
  fi

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "### Upstream Sync Result" >> "$GITHUB_STEP_SUMMARY"
    echo "⚠️ Merge conflict encountered on files:" >> "$GITHUB_STEP_SUMMARY"
    echo "\`\`\`" >> "$GITHUB_STEP_SUMMARY"
    echo "$CONFLICTS" >> "$GITHUB_STEP_SUMMARY"
    echo "\`\`\`" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 1
fi
