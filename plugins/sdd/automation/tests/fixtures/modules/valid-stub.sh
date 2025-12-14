#!/usr/bin/env bash
#
# valid-stub.sh - Valid stub module with all required functions
# Used for positive testing of module loading
#

# Required function 1
test_function_one() {
    echo '{"success": true, "message": "Function one executed"}'
}

# Required function 2
test_function_two() {
    echo '{"success": true, "message": "Function two executed"}'
}
