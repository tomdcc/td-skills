#!/usr/bin/env bash
# Reconcile the JDK<major> exports in ~/.zshenv with what asdf actually has installed.
#
# gradle.properties in the Develocity monorepo sets
#   org.gradle.java.installations.auto-detect=false
#   org.gradle.java.installations.fromEnv=JDK7,JDK8,JDK11,JDK17,JDK21,JDK25
# so a build finds toolchains only through these variables. A stale path fails at
# configuration time with "Cannot find a Java installation ... matching {languageVersion=N}".
set -euo pipefail

ZSHENV="${ZSHENV:-$HOME/.zshenv}"
INSTALLS="${ASDF_JAVA_INSTALLS:-$HOME/.asdf/installs/java}"
VENDOR="${JDK_VENDOR_PREFIX:-liberica}"
# Only these get flagged when installed but unexported. A non-LTS release is nobody's
# toolchain target for long, so noticing one is installed is noise rather than drift.
LTS_MAJORS="${JDK_LTS_MAJORS:-8 11 17 21 25}"
MODE="apply"

usage() { echo "usage: ${0##*/} [--check|--apply]"; exit 2; }
case "${1-}" in
  --check) MODE="check" ;;
  --apply|"") MODE="apply" ;;
  -h|--help) usage ;;
  *) usage ;;
esac

[ -d "$INSTALLS" ] || { echo "no asdf java installs at $INSTALLS" >&2; exit 1; }
[ -f "$ZSHENV" ] || { echo "no $ZSHENV" >&2; exit 1; }

# Newest install per major version. "liberica-8u342+7" -> 8, "liberica-11.0.16+8" -> 11.
declare -a MAJORS=() PATHS=()
while IFS=$'\t' read -r major dir; do
  MAJORS+=("$major"); PATHS+=("$INSTALLS/$dir")
done < <(
  for d in "$INSTALLS/$VENDOR"-*; do
    [ -x "$d/bin/java" ] || continue
    name="${d##*/}"; rest="${name#"$VENDOR"-}"
    major="${rest%%[!0-9]*}"
    [ -n "$major" ] && printf '%s\t%s\n' "$major" "$name"
  done | sort -t$'\t' -k1,1n -k2,2V | awk -F'\t' '{best[$1]=$2} END {for (m in best) print m "\t" best[m]}' | sort -n
)

[ "${#MAJORS[@]}" -gt 0 ] || { echo "no $VENDOR installs with a bin/java under $INSTALLS" >&2; exit 1; }

drift=0
declare -a uncovered=()
for i in "${!MAJORS[@]}"; do
  major="${MAJORS[$i]}"; want="${PATHS[$i]}"
  have="$(sed -n "s|^export JDK${major}=||p" "$ZSHENV" | tail -1)"
  have="${have/#\$HOME/$HOME}"
  if [ -z "$have" ]; then
    # Installed but never exported. Only a problem if a build wants that major, and
    # gradle.properties names the ones that matter, so report without forcing a change.
    case " $LTS_MAJORS " in *" $major "*) uncovered+=("JDK${major} (${want##*/})") ;; esac
  elif [ "$have" != "$want" ]; then
    echo "stale    JDK${major}: ${have/#$HOME/\$HOME} -> ${want/#$HOME/\$HOME}"; drift=1
  fi
done

# Exports naming a major that no longer has an install at all.
while read -r major; do
  found=0
  for m in "${MAJORS[@]}"; do [ "$m" = "$major" ] && found=1; done
  [ "$found" = 0 ] && { echo "orphan   JDK${major} is exported but nothing is installed for it"; drift=1; }
done < <(sed -n 's|^export JDK\([0-9][0-9]*\)=.*|\1|p' "$ZSHENV" | sort -un)

if [ "${#uncovered[@]}" -gt 0 ]; then
  echo "not exported (add by hand if a build needs one): ${uncovered[*]}"
fi

if [ "$drift" = 0 ]; then echo "exports are up to date"; exit 0; fi
[ "$MODE" = "check" ] && exit 1

backup="$ZSHENV.bak.$(date +%Y%m%d%H%M%S)"
cp "$ZSHENV" "$backup"

tmp="$(mktemp)"
cp "$ZSHENV" "$tmp"
for i in "${!MAJORS[@]}"; do
  major="${MAJORS[$i]}"; want="${PATHS[$i]/#$HOME/\$HOME}"
  grep -q "^export JDK${major}=" "$tmp" || continue
  if true; then
    awk -v m="$major" -v v="$want" '
      $0 ~ "^export JDK" m "=" { print "export JDK" m "=" v; next } { print }
    ' "$tmp" > "$tmp.new" && mv "$tmp.new" "$tmp"
  else
    last="$(grep -n '^export JDK[0-9]' "$tmp" | tail -1 | cut -d: -f1 || true)"
    if [ -n "$last" ]; then
      awk -v n="$last" -v line="export JDK${major}=${want}" 'NR==n {print; print line; next} {print}' "$tmp" > "$tmp.new" && mv "$tmp.new" "$tmp"
    else
      printf '\nexport JDK%s=%s\n' "$major" "$want" >> "$tmp"
    fi
  fi
done

mv "$tmp" "$ZSHENV"
echo "updated $ZSHENV (backup: $backup)"
echo "existing shells keep the old values; open a new one to pick these up"
