# =============================================================================
#  stages.sh — Stage registry, dependency resolution, and CLI argument parsing
#
#  Sourced by install.sh and by the test suite. Everything here is definition
#  only; nothing executes until parse_args / resolve_stages are called.
# =============================================================================

# All stages in execution order
ALL_STAGES=("preflight" "repos" "packaging" "config" "services" "extras" "finalize")

# Stage dependencies. Intentionally not readonly so the test suite can inject
# cycles; the resolver guard below fails loudly on any real cycle.
declare -A STAGE_DEPENDENCIES=(
  [preflight]=""
  [repos]="preflight"
  [packaging]="preflight repos"
  [config]="preflight packaging"
  [services]="preflight packaging config"
  [extras]="preflight"
  [finalize]="preflight"
)

declare -A STAGE_WANTED=()
declare -A STAGE_RESOLVING=()

# CLI option defaults (populated by parse_args; exported for helpers/stages)
export DRY_RUN=false
export SELECTIVE_STAGES=""
export FORCE=false
export VERBOSE=false
export ACCEPT_PACKAGE_REMOVALS=false
export TARGET_USER="${TARGET_USER:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Transforms a base Fedora install into a niri + DMS workstation.

Options:
  --dry-run          Print what would happen without executing changes
  --select STAGES   Comma-separated list of stages to run
                     (e.g.: repos,packaging,config)
  --target-user USER Configure this non-root user account
  --accept-package-removals
                     Allow Tophat to remove packages listed as replaced
  --force            Run even if setup marker indicates completion
  --verbose          Show command output inline (don't suppress)
  --help             Show this message

Available stages:
  preflight, repos, packaging, config, services, extras, finalize
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --select)
        if [[ $# -lt 2 || "${2:0:2}" == "--" ]]; then
          echo "Error: --select requires a comma-separated stage list" >&2
          exit 1
        fi
        SELECTIVE_STAGES="$2"
        shift 2
        ;;
      --target-user)
        if [[ $# -lt 2 || "${2:0:2}" == "--" ]]; then
          echo "Error: --target-user requires a username" >&2
          exit 1
        fi
        TARGET_USER="$2"
        shift 2
        ;;
      --accept-package-removals)
        ACCEPT_PACKAGE_REMOVALS=true
        shift
        ;;
      --force)
        FORCE=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --help | -h) usage ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done
}

stage_exists() {
  local candidate="$1"
  local stage

  for stage in "${ALL_STAGES[@]}"; do
    [[ "$candidate" == "$stage" ]] && return 0
  done

  return 1
}

stage_add_with_dependencies() {
  local stage="$1"
  local dep

  if ! stage_exists "$stage"; then
    echo "Error: invalid stage '$stage'" >&2
    echo "Available stages: ${ALL_STAGES[*]}" >&2
    exit 1
  fi

  # Already resolved in this run; its dependencies were processed too
  if [[ -n "${STAGE_WANTED[$stage]:-}" ]]; then
    return 0
  fi

  # Fail loudly if STAGE_DEPENDENCIES ever gains a cycle
  if [[ -n "${STAGE_RESOLVING[$stage]:-}" ]]; then
    echo "Error: circular stage dependency detected at '$stage'" >&2
    exit 1
  fi

  STAGE_RESOLVING[$stage]=1
  for dep in ${STAGE_DEPENDENCIES[$stage]}; do
    stage_add_with_dependencies "$dep"
  done
  unset 'STAGE_RESOLVING[$stage]'

  STAGE_WANTED[$stage]=1
}

# Resolve SELECTIVE_STAGES into STAGES (canonical execution order), pulling in
# dependencies. With no selection, every stage runs.
resolve_stages() {
  local stage

  if [[ -z "$SELECTIVE_STAGES" ]]; then
    STAGES=("${ALL_STAGES[@]}")
    return 0
  fi

  IFS=',' read -ra SELECTED <<<"$SELECTIVE_STAGES"

  local sel
  for sel in "${SELECTED[@]}"; do
    sel="${sel#"${sel%%[![:space:]]*}"}"
    sel="${sel%"${sel##*[![:space:]]}"}"

    if [[ -z "$sel" ]]; then
      echo "Error: --select contains an empty stage name" >&2
      exit 1
    fi

    stage_add_with_dependencies "$sel"
  done

  STAGES=()
  for stage in "${ALL_STAGES[@]}"; do
    [[ -n "${STAGE_WANTED[$stage]:-}" ]] && STAGES+=("$stage")
  done

  echo "Requested stages: ${SELECTED[*]}"
  echo "Execution plan: ${STAGES[*]}"
}
