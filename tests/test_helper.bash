# Shared setup for the fedora-post-install bats smoke tests.
#
# REPO_ROOT is derived from this file's own location — tests/ is a direct
# child of the repo root — so the suite works regardless of the caller's CWD.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
