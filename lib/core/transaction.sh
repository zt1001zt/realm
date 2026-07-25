#!/usr/bin/env bash
: "${RS_LOCK_DIR:=/run/rs-manager.lock}"
: "${RS_BACKUP_DIR:=/var/lib/rs-manager/backups}"
rs_lock_acquire(){ mkdir -p "$(dirname "$RS_LOCK_DIR")"; if mkdir "$RS_LOCK_DIR" 2>/dev/null; then printf '%s\n' "$$" > "$RS_LOCK_DIR/pid"; return 0; fi; return 1; }
rs_lock_release(){ [[ -n ${RS_LOCK_DIR:-} && $RS_LOCK_DIR == *.lock ]] || return 1; rm -rf "$RS_LOCK_DIR"; }
rs_backup_create(){ local name=$1; shift; mkdir -p "$RS_BACKUP_DIR"; local stamp dir; stamp=$(date +%Y%m%d%H%M%S)-$(rs_random_hex 2); dir="$RS_BACKUP_DIR/$name-$stamp"; mkdir "$dir"; chmod 700 "$dir" 2>/dev/null || true; local file; for file in "$@"; do [[ -e $file ]] && cp -a "$file" "$dir/"; done; printf '%s\n' "$dir"; }
rs_backup_rotate(){ [[ -d $RS_BACKUP_DIR ]] || return 0; local keep=${1:-10} count=0 path; while IFS= read -r path; do count=$((count+1)); if ((count>keep)) && [[ $path == "$RS_BACKUP_DIR"/auto-* ]]; then rm -rf "$path"; fi; done < <(ls -1dt "$RS_BACKUP_DIR"/auto-* 2>/dev/null || true); }
rs_atomic_install(){ local candidate=$1 target=$2; mkdir -p "$(dirname "$target")"; local tmp="$target.rs-tmp-$$"; cp "$candidate" "$tmp"; [[ ! -e $target ]] || chmod --reference="$target" "$tmp" 2>/dev/null || true; mv -f "$tmp" "$target"; }
rs_transaction_apply(){ local candidate=$1 target=$2 validator=${3:-true}; local backup=''; [[ ! -e $target ]] || backup=$(rs_backup_create auto "$target"); "$validator" "$candidate" || return 1; rs_atomic_install "$candidate" "$target" || return 1; printf '%s\n' "$backup"; }
