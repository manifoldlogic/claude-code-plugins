#!/usr/bin/env bash
#
# missing-function.sh - Module missing required function
# Used for negative testing of module interface validation
# This module intentionally omits test_function_two
#

# Has function one but missing function two
test_function_one() {
    echo '{"success": true}'
}
