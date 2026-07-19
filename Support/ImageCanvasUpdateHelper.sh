#!/bin/bash
set -u

if [ "$#" -ne 5 ]; then
  exit 64
fi

current_app="$1"
staged_app="$2"
backup_app="$3"
app_pid="$4"
temporary_root="$5"

current_parent="$(/usr/bin/dirname "$current_app")"
staged_parent="$(/usr/bin/dirname "$staged_app")"
backup_parent="$(/usr/bin/dirname "$backup_app")"
temporary_name="$(/usr/bin/basename "$temporary_root")"

if [[ "${current_app##*.}" != "app" ||
      "$current_parent" != "$staged_parent" ||
      "$current_parent" != "$backup_parent" ||
      "${staged_app##*/}" != .ImageCanvas.update-*.app ||
      "${backup_app##*/}" != .ImageCanvas.backup-*.app ||
      "$temporary_name" != ImageCanvasUpdate-* ||
      ! -d "$current_app" ||
      ! -d "$staged_app" ||
      -e "$backup_app" ]]; then
  exit 65
fi

cleanup_temporary_files() {
  if [ -d "$temporary_root" ]; then
    /bin/rm -rf -- "$temporary_root"
  fi
}

rollback_and_reopen() {
  if [ ! -e "$current_app" ] && [ -d "$backup_app" ]; then
    /bin/mv "$backup_app" "$current_app"
  fi
  if [ -d "$current_app" ]; then
    /usr/bin/open "$current_app" >/dev/null 2>&1
  fi
  if [ -d "$staged_app" ]; then
    /bin/rm -rf -- "$staged_app"
  fi
  cleanup_temporary_files
  exit 1
}

attempts=0
while /bin/kill -0 "$app_pid" >/dev/null 2>&1; do
  /bin/sleep 0.2
  attempts=$((attempts + 1))
  if [ "$attempts" -ge 1500 ]; then
    /bin/rm -rf -- "$staged_app"
    cleanup_temporary_files
    exit 66
  fi
done

if ! /bin/mv "$current_app" "$backup_app"; then
  rollback_and_reopen
fi

if ! /bin/mv "$staged_app" "$current_app"; then
  rollback_and_reopen
fi

if ! /usr/bin/open "$current_app" >/dev/null 2>&1; then
  /bin/rm -rf -- "$current_app"
  rollback_and_reopen
fi

/bin/sleep 1
/bin/rm -rf -- "$backup_app"
cleanup_temporary_files
exit 0
