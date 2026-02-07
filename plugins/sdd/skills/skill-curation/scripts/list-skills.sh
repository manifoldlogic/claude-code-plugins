#!/bin/sh
# list-skills.sh - Enumerate repo-local skills under ${SDD_ROOT_DIR}/skills/
#
# Usage:
#   SDD_ROOT_DIR=/path/to/.sdd bash list-skills.sh
#
# Outputs JSON to stdout: {"skills": [...], "count": N}
# Warnings/errors to stderr.
# Always exits 0 to avoid blocking downstream commands.
#
# Output JSON Schema (v1):
# {
#   "skills": [              array (required) - list of discovered skill objects
#     {
#       "name":        string (required) - kebab-case skill name, matches directory name
#       "description": string (required) - one-line description from SKILL.md frontmatter
#       "origin":      string (optional) - ticket ID where skill was created (e.g., "APITEST")
#       "tags":        string (optional) - comma-separated or JSON array from frontmatter
#       "path":        string (required) - absolute path to skill directory (trailing slash)
#     }
#   ],
#   "count": integer (required) - number of skills in array (for convenience)
# }
#
# Example (empty state):
#   {"skills": [], "count": 0}
#
# Example (with skills):
#   {"skills": [{"name": "api-testing-patterns", "description": "REST API testing with bearer auth", "origin": "APITEST", "tags": "[api, testing]", "path": "/app/.sdd/skills/api-testing-patterns/"}], "count": 1}
#
# Schema Stability:
#   - This is schema version 1 (implicit - no version field in output yet)
#   - Breaking changes (field removal, type changes) will increment version
#   - Additive changes (new optional fields) are non-breaking
#   - Consumers should handle missing optional fields gracefully
#   - When modifying output format, update this schema documentation
#
# Consumers: archive.md, plan-ticket.md, skill-curator.md
#
# Dependencies: SDD_ROOT_DIR environment variable must be set.
#
# POSIX-compatible (no bash-only features).

set -e

# --- Helper: output empty result and exit ---
empty_result() {
  printf '{"skills": [], "count": 0}\n'
  exit 0
}

# --- Validate SDD_ROOT_DIR ---
if [ -z "${SDD_ROOT_DIR}" ]; then
  echo "Warning: SDD_ROOT_DIR is not set" >&2
  empty_result
fi

SKILLS_DIR="${SDD_ROOT_DIR}/skills"

# --- Validate skills directory ---
if [ ! -e "${SKILLS_DIR}" ]; then
  echo "Warning: Skills directory does not exist: ${SKILLS_DIR}" >&2
  empty_result
fi

if [ ! -d "${SKILLS_DIR}" ]; then
  echo "Warning: Skills path is not a directory: ${SKILLS_DIR}" >&2
  empty_result
fi

if [ ! -r "${SKILLS_DIR}" ]; then
  echo "Error: Skills directory is not readable: ${SKILLS_DIR}" >&2
  empty_result
fi

# --- Escape a string for JSON output ---
# Handles backslashes, double quotes, and control characters
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g'
}

# --- Extract a frontmatter field value ---
# Arguments: $1 = field name, $2 = frontmatter text
# Outputs the value (trimmed) or empty string
extract_field() {
  _field="$1"
  _frontmatter="$2"
  _value=$(printf '%s\n' "${_frontmatter}" | grep -E "^${_field}:" | head -n 1 | sed "s/^${_field}:[[:space:]]*//" | sed 's/[[:space:]]*$//')
  printf '%s' "${_value}"
}

# --- Parse SKILL.md frontmatter ---
# Arguments: $1 = path to SKILL.md
# Outputs: name|description|origin|tags  (pipe-delimited)
# Returns 1 if frontmatter is invalid or missing required fields
parse_skill_md() {
  _skill_file="$1"

  if [ ! -r "${_skill_file}" ]; then
    echo "Warning: Cannot read file: ${_skill_file}" >&2
    return 1
  fi

  # Check first line is ---
  _first_line=$(head -n 1 "${_skill_file}")
  if [ "${_first_line}" != "---" ]; then
    echo "Warning: Missing frontmatter delimiter in: ${_skill_file}" >&2
    return 1
  fi

  # Extract frontmatter (lines between first --- and second ---)
  _in_frontmatter=0
  _frontmatter=""
  _line_num=0
  _found_end=0
  while IFS= read -r _line || [ -n "${_line}" ]; do
    _line_num=$((_line_num + 1))
    if [ "${_line_num}" -eq 1 ]; then
      _in_frontmatter=1
      continue
    fi
    if [ "${_in_frontmatter}" -eq 1 ] && [ "${_line}" = "---" ]; then
      _found_end=1
      break
    fi
    if [ "${_in_frontmatter}" -eq 1 ]; then
      if [ -n "${_frontmatter}" ]; then
        _frontmatter="${_frontmatter}
${_line}"
      else
        _frontmatter="${_line}"
      fi
    fi
  done < "${_skill_file}"

  if [ "${_found_end}" -eq 0 ]; then
    echo "Warning: Unclosed frontmatter in: ${_skill_file}" >&2
    return 1
  fi

  if [ -z "${_frontmatter}" ]; then
    echo "Warning: Empty frontmatter in: ${_skill_file}" >&2
    return 1
  fi

  # Extract fields
  _name=$(extract_field "name" "${_frontmatter}")
  _description=$(extract_field "description" "${_frontmatter}")
  _origin=$(extract_field "origin" "${_frontmatter}")
  _tags=$(extract_field "tags" "${_frontmatter}")

  # Validate required fields
  if [ -z "${_name}" ]; then
    echo "Warning: Missing required field 'name' in: ${_skill_file}" >&2
    return 1
  fi

  if [ -z "${_description}" ]; then
    echo "Warning: Missing required field 'description' in: ${_skill_file}" >&2
    return 1
  fi

  printf '%s|%s|%s|%s' "${_name}" "${_description}" "${_origin}" "${_tags}"
  return 0
}

# --- Main: enumerate skills ---
skill_count=0
json_entries=""

for entry in "${SKILLS_DIR}"/*; do
  # Handle empty directory (glob returns literal pattern)
  if [ "${entry}" = "${SKILLS_DIR}/*" ]; then
    break
  fi

  # Skip non-directories
  if [ ! -d "${entry}" ]; then
    continue
  fi

  _skill_md="${entry}/SKILL.md"

  # Skip directories without SKILL.md
  if [ ! -f "${_skill_md}" ]; then
    continue
  fi

  # Parse frontmatter
  _parsed=$(parse_skill_md "${_skill_md}") || continue

  # Split parsed result on pipe delimiter
  _name=$(printf '%s' "${_parsed}" | cut -d'|' -f1)
  _description=$(printf '%s' "${_parsed}" | cut -d'|' -f2)
  _origin=$(printf '%s' "${_parsed}" | cut -d'|' -f3)
  _tags=$(printf '%s' "${_parsed}" | cut -d'|' -f4)

  # JSON-escape values
  _name_escaped=$(json_escape "${_name}")
  _description_escaped=$(json_escape "${_description}")
  _origin_escaped=$(json_escape "${_origin}")
  _tags_escaped=$(json_escape "${_tags}")
  _path_escaped=$(json_escape "${entry}/")

  # Build JSON object
  _json_obj="{\"name\": \"${_name_escaped}\", \"description\": \"${_description_escaped}\", \"origin\": \"${_origin_escaped}\", \"tags\": \"${_tags_escaped}\", \"path\": \"${_path_escaped}\"}"

  if [ -n "${json_entries}" ]; then
    json_entries="${json_entries}, ${_json_obj}"
  else
    json_entries="${_json_obj}"
  fi

  skill_count=$((skill_count + 1))
done

# --- Output JSON ---
printf '{"skills": [%s], "count": %d}\n' "${json_entries}" "${skill_count}"
exit 0
