# =============================================================================
#  remove_replaced.sh — Remove packages that DMS supersedes
# =============================================================================

log_info "Removing packages that DMS replaces (if present)..."
pkg_remove_from_list "$SETUP_PACKAGES/remove-replaced.packages"
