#!/usr/bin/env bash
# Imports the project headless, then loads every script, scene and resource in it
# (test/check_project.gd). Fails if Godot exits non-zero or prints an error line in either
# step, because Godot's import exits 0 even when a file fails to import or a script fails to
# parse. CI runs this (.github/workflows/check.yml); it runs the same way locally:
#   test/check_project.sh
# Set GODOT to the Godot binary to use (default: godot on the PATH).
set -uo pipefail

godot="${GODOT:-godot}"
project="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT

# Godot starts each error line with ERROR:, SCRIPT ERROR:, SHADER ERROR: or USER ERROR:.
error_line='^(USER )?((SCRIPT|SHADER) )?ERROR: '
warning_line='^(USER )?WARNING: '

# Prints a GitHub Actions annotation for each error and warning line in Godot's output (with
# colour codes removed), so they show on the run's page. When the next line is "at:" with a
# res:// path, the annotation points at that file and line.
annotate() {
	awk -v step="$1" -v error_line="$error_line" -v warning_line="$warning_line" '
		function flush() {
			if (kind != "") print "::" kind " title=Godot (" step ")" where "::" message
			kind = ""
			where = ""
		}
		$0 ~ error_line || $0 ~ warning_line {
			flush()
			kind = $0 ~ error_line ? "error" : "warning"
			message = $0
			gsub(/%/, "%25", message)
			next
		}
		kind != "" && /^ +at: .*\(res:\/\/[^)]*:[0-9]+\)$/ {
			place = substr($0, index($0, "(res://") + 7)
			place = substr(place, 1, length(place) - 1)
			count = split(place, parts, ":")
			where = ",file=" substr(place, 1, length(place) - length(parts[count]) - 1)
			if (parts[count] + 0 > 0) where = where ",line=" parts[count]
		}
		{ flush() }
		END { flush() }
	'
}

# Runs Godot on the project with the given arguments and prints its output. Returns 1 if
# Godot exits non-zero or prints an error line.
run_godot() {
	local step="$1"
	shift
	local log="$logs/$step.log"
	echo "== $step: $godot --headless --path $project $*"
	"$godot" --headless --path "$project" "$@" 2>&1 | tee "$log"
	local status="${PIPESTATUS[0]}"
	sed -i -E 's/\x1b\[[0-9;]*m//g' "$log"
	local errors warnings
	errors="$(grep -cE "$error_line" "$log")"
	warnings="$(grep -cE "$warning_line" "$log")"
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		annotate "$step" < "$log"
	fi
	echo "== $step: exit code $status, $errors error lines, $warnings warning lines"
	[[ "$status" -eq 0 && "$errors" -eq 0 ]]
}

failed=0
run_godot import --import || failed=1
run_godot load --script res://test/check_project.gd || failed=1
if [[ "$failed" -ne 0 ]]; then
	echo "check_project: FAILED"
	exit 1
fi
echo "check_project: passed"
