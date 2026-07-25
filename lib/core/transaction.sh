#!/usr/bin/env bash
: "${RS_LOCK_DIR:=}"
: "${RS_BACKUP_DIR:=}"
: "${RS_LOCK_DEPTH:=0}"
: "${RS_LOCK_HELD_DIR:=}"
rs_lock_acquire(){
  local owner stale
  [[ -n $RS_LOCK_DIR ]] || RS_LOCK_DIR=$(rs_path /run/rs-manager.lock)
  if ((RS_LOCK_DEPTH>0)) && [[ $RS_LOCK_HELD_DIR == "$RS_LOCK_DIR" && -f $RS_LOCK_DIR/pid ]] && [[ $(cat "$RS_LOCK_DIR/pid" 2>/dev/null) == "$$" ]]; then
    RS_LOCK_DEPTH=$((RS_LOCK_DEPTH+1)); return 0
  fi
  mkdir -p "$(dirname "$RS_LOCK_DIR")"
  if ! mkdir "$RS_LOCK_DIR" 2>/dev/null; then
    owner=$(cat "$RS_LOCK_DIR/pid" 2>/dev/null || true)
    if [[ $owner =~ ^[0-9]+$ ]] && ! kill -0 "$owner" 2>/dev/null; then
      stale="$RS_LOCK_DIR.stale.$$.$RANDOM"
      mv "$RS_LOCK_DIR" "$stale" 2>/dev/null || return 1
      rm -rf "$stale"
      mkdir "$RS_LOCK_DIR" 2>/dev/null || return 1
    else
      return 1
    fi
  fi
  printf '%s\n' "$$" > "$RS_LOCK_DIR/pid" || { rmdir "$RS_LOCK_DIR" 2>/dev/null || true; return 1; }
  RS_LOCK_DEPTH=1; RS_LOCK_HELD_DIR=$RS_LOCK_DIR
}
rs_lock_release(){
  [[ -n ${RS_LOCK_DIR:-} && $RS_LOCK_DIR == *.lock && ${RS_LOCK_DEPTH:-0} -gt 0 && $RS_LOCK_HELD_DIR == "$RS_LOCK_DIR" ]] || return 1
  RS_LOCK_DEPTH=$((RS_LOCK_DEPTH-1)); ((RS_LOCK_DEPTH==0)) || return 0
  [[ $(cat "$RS_LOCK_DIR/pid" 2>/dev/null) == "$$" ]] || { RS_LOCK_HELD_DIR=''; return 1; }
  rm -rf "$RS_LOCK_DIR"; RS_LOCK_HELD_DIR=''
}
rs_locked_call(){
  local rc
  rs_lock_acquire || { rs_die 'Another RS Manager operation is running'; return 1; }
  if "$@"; then rc=0; else rc=$?; fi
  rs_lock_release || ((rc!=0)) || rc=1
  return "$rc"
}
rs_backup_create(){ local name=$1; shift; [[ -n $RS_BACKUP_DIR ]] || RS_BACKUP_DIR=$(rs_path /var/lib/rs-manager/backups); mkdir -p "$RS_BACKUP_DIR"; local stamp dir; stamp=$(date +%Y%m%d%H%M%S)-$(rs_random_hex 2); dir="$RS_BACKUP_DIR/$name-$stamp"; mkdir "$dir"; chmod 700 "$dir" 2>/dev/null || true; local file; for file in "$@"; do [[ -e $file ]] && cp -a "$file" "$dir/"; done; printf '%s\n' "$dir"; }
rs_backup_rotate(){ [[ -d $RS_BACKUP_DIR ]] || return 0; local keep=10 count=0 path; while IFS= read -r path; do count=$((count+1)); if ((count>keep)) && [[ $path == "$RS_BACKUP_DIR"/auto-* ]]; then rm -rf "$path"; fi; done < <(ls -1dt "$RS_BACKUP_DIR"/auto-* 2>/dev/null || true); }
rs_atomic_install(){ local candidate=$1 target=$2; mkdir -p "$(dirname "$target")"; local tmp="$target.rs-tmp-$$"; cp "$candidate" "$tmp"; [[ ! -e $target ]] || chmod --reference="$target" "$tmp" 2>/dev/null || true; mv -f "$tmp" "$target"; }
rs_transaction_apply(){
 local candidate=$1 target=$2 validator=${3:-true} post_apply=${4:-true} backup='' rollback='' existed=0 rc=0 rollback_rc=0
 rs_lock_acquire || { rs_die 'Another RS Manager operation is running'; return 1; }
 if ! "$validator" "$candidate"; then rs_lock_release; return 1; fi
 if [[ -e $target ]]; then
   existed=1; rollback=$(mktemp "$(dirname "$target")/.rs-rollback.XXXXXX") || { rs_lock_release; return 1; }
   cp -a "$target" "$rollback" || { rm -f "$rollback"; rs_lock_release; return 1; }
   backup=$(rs_backup_create auto "$target") || { rm -f "$rollback"; rs_lock_release; return 1; }
 fi
 rs_atomic_install "$candidate" "$target" || rc=$?
 if ((rc==0)); then "$post_apply" "$target" || rc=$?; fi
 if ((rc!=0)); then
   if ((existed)); then rs_atomic_install "$rollback" "$target" || rollback_rc=1; else rm -f "$target" || rollback_rc=1; fi
   RS_TRANSACTION_ROLLBACK=1 "$post_apply" "$target" >/dev/null 2>&1 || rollback_rc=1
   if ((rollback_rc!=0)); then
     rs_die "Rollback incomplete for $target; recovery=${rollback:-none}; backup=${backup:-none}"
     rs_lock_release; return 70
   fi
 fi
 rm -f "$rollback"; rs_backup_rotate; rs_lock_release
 ((rc==0)) || return "$rc"
 printf '%s\n' "$backup"
}
rs_transaction_apply_pair(){
 local first_candidate=$1 first_target=$2 second_candidate=$3 second_target=$4 validator=${5:-true} post_apply=${6:-true}
 local first_rollback='' second_rollback='' backup='' first_existed=0 second_existed=0 rc=0 rollback_rc=0
 rs_lock_acquire || { rs_die 'Another RS Manager operation is running'; return 1; }
 if ! "$validator" "$first_candidate"; then rs_lock_release; return 1; fi
 if [[ -e $first_target ]]; then first_existed=1; first_rollback=$(mktemp "$(dirname "$first_target")/.rs-rollback.XXXXXX") && cp -a "$first_target" "$first_rollback" || rc=1; fi
 if ((rc==0)) && [[ -e $second_target ]]; then second_existed=1; second_rollback=$(mktemp "$(dirname "$second_target")/.rs-rollback.XXXXXX") && cp -a "$second_target" "$second_rollback" || rc=1; fi
 if ((rc==0)); then backup=$(rs_backup_create auto "$first_target" "$second_target") || rc=1; fi
 if ((rc!=0)); then rm -f "$first_rollback" "$second_rollback"; rs_lock_release; return 1; fi
 if ((rc==0)); then rs_atomic_install "$first_candidate" "$first_target" || rc=$?; fi
 if ((rc==0)); then rs_atomic_install "$second_candidate" "$second_target" || rc=$?; fi
 if ((rc==0)); then "$post_apply" "$first_target" || rc=$?; fi
 if ((rc!=0)); then
   if ((first_existed)); then rs_atomic_install "$first_rollback" "$first_target" || rollback_rc=1; else rm -f "$first_target" || rollback_rc=1; fi
   if ((second_existed)); then rs_atomic_install "$second_rollback" "$second_target" || rollback_rc=1; else rm -f "$second_target" || rollback_rc=1; fi
   RS_TRANSACTION_ROLLBACK=1 "$post_apply" "$first_target" >/dev/null 2>&1 || rollback_rc=1
   if ((rollback_rc!=0)); then
     rs_die "Rollback incomplete for $first_target and $second_target; recovery=${first_rollback:-none},${second_rollback:-none}; backup=${backup:-none}"
     rs_lock_release; return 70
   fi
 fi
 rm -f "$first_rollback" "$second_rollback"; rs_backup_rotate; rs_lock_release
 ((rc==0))
}
