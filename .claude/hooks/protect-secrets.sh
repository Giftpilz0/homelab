#!/usr/bin/env bash
# PreToolUse hook: block shell commands that would expose secrets.
# Read/Edit access to secret files is denied in settings.json; this covers
# Bash, where e.g. `cat`, `sops -d` or `tofu show` could print them.
set -euo pipefail

input=$(cat)
command=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")

block() {
    echo "Blocked: $1. Ask the user to run it themselves with '! <command>'." >&2
    exit 2
}

readers='(cat|less|more|head|tail|bat|grep|rg|sed|awk|cut|sort|strings|xxd|od|base64|cp|mv|scp|rsync|python3?|jq|yq|diff|git (show|diff|log -p))'
secret_files='(\.sops\.ya?ml|secrets\.ya?ml|\.tfstate|\.key\b|\.env\b)'

patterns=(
    "\b${readers}\b[^|;&]*${secret_files}"
    '(^|[;&|(]|\$\(|\bexec|\benv)\s*sops\b'
    '\btofu\s+(show|output|state|console)'
    # running the state decrypt script (mentioning it, e.g. in git mv, is fine)
    '(^|[;&|(]|\$\(|\b(bash|sh|exec|source)\b)\s*[^ ;&|]*state-utils\.sh'
    '\bgpg\b.*(--decrypt|-d\b|--export-secret)'
    '\bansible-inventory\b'
    'ANSIBLE_SOPS|SOPS_AGE_KEY'
)

for pattern in "${patterns[@]}"; do
    if grep -qE "$pattern" <<<"$command"; then
        block "command may expose secrets (matched '$pattern')"
    fi
done

# Recursive/bulk reads that reach tofu/ (plain state while decrypted, .terraform/), e.g. `grep -r x .`
# from the repo root. Paths are resolved against the cwd, following `cd` within the command.
python3 -I - "$command" "${cwd:-$PWD}" "${CLAUDE_PROJECT_DIR:-$PWD}" <<'EOF' || block "recursive read reaching tofu/ (plain state). Search tracked files with 'git grep' or name the files explicitly"
import os, re, shlex, sys

command, cwd, root = sys.argv[1:4]
protected = os.path.realpath(os.path.join(root, "tofu"))

def reaches(path):
    p = os.path.realpath(path)
    return p == protected or protected.startswith(p + os.sep) or p.startswith(protected + os.sep)

def recursive(words):
    name = os.path.basename(words[0])
    flags = [w for w in words[1:] if w.startswith("-")]
    if name in ("rg", "ag", "ack", "tar", "zip", "rsync", "xargs"):
        return True
    if name in ("grep", "egrep", "fgrep", "ugrep"):
        return any(re.match(r"^-[a-zA-Z]*[rR]", f) or f in ("--recursive", "--dereference-recursive")
                   or f.startswith("--directories=recurse") for f in flags)
    if name in ("cp", "scp"):
        return any(re.match(r"^-[a-zA-Z]*[rRa]", f) or f in ("--recursive", "--archive") for f in flags)
    if name == "find":
        return any(w in ("-exec", "-execdir", "-ok", "-okdir", "-fprint") for w in words)
    if name == "git" and len(words) > 1 and words[1] == "grep":
        return "--untracked" in words or "--no-index" in words
    return False

try:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    tokens = list(lexer)
except ValueError:
    sys.exit(0)  # unparsable: leave it to the patterns above

segments, current = [], []
for t in tokens:
    if t and set(t) <= set(";&|()"):
        segments.append(current)
        current = []
    else:
        current.append(t)
segments.append(current)

for words in segments:
    words = [os.path.expanduser(os.path.expandvars(w)) for w in words]
    while words and re.match(r"^\w+=", words[0]):
        words = words[1:]  # VAR=value prefix
    if not words:
        continue
    if words[0] == "cd":
        cwd = os.path.join(cwd, words[1]) if len(words) > 1 else os.path.expanduser("~")
        continue
    if not recursive(words):
        continue
    name = os.path.basename(words[0])
    if name == "xargs":
        # Paths arrive via the pipe: check every argument of the whole command
        paths = [w for w in tokens if not w.startswith("-")] + ["."]
    else:
        args = words[2:] if name == "git" else words[1:]
        paths = [w for w in args if not w.startswith("-")]
        searches = name in ("grep", "egrep", "fgrep", "ugrep", "rg", "ag", "ack", "git")
        if searches and not any(w in ("-e", "-f") or w.startswith(("--regexp", "--file")) for w in args):
            paths = paths[1:]  # first positional is the pattern
        paths = paths or ["."]
    for w in paths:
        w = re.split(r"[*?\[]", w)[0] or "."  # glob: check its fixed prefix
        if reaches(os.path.join(cwd, w)):
            sys.exit(1)
EOF
