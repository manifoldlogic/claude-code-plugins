#!/usr/bin/env bash
#
# syntax-error.sh - Module with bash syntax error
# Used for negative testing of module loading
#

# This has a syntax error - missing closing brace
test_function_one() {
    echo '{"success": true}'

# Missing closing brace for function
