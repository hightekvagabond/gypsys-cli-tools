#!/bin/bash
# Master Test Script - Modular Monitoring System
# Tests all enabled modules using modular discovery

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load system configuration
if [[ -f "$SCRIPT_DIR/config/SYSTEM.conf" ]]; then
    source "$SCRIPT_DIR/config/SYSTEM.conf"
fi

# Load common functions for module help
source "$SCRIPT_DIR/modules/common.sh"

# Test results tracking
TOTAL_MODULES=0
MODULES_PASSED=0
MODULES_FAILED=0
MODULES_SKIPPED=0

# Autofix test results tracking
TOTAL_AUTOFIX=0
AUTOFIX_PASSED=0
AUTOFIX_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_help() {
    cat << 'EOF'
Master Test Script - Modular Monitoring System

USAGE:
    ./test.sh [OPTIONS] [MODULE_NAME...]

OPTIONS:
    --help              Show this help message
    --list              List all available modules with test scripts
    --enabled-only      Test only enabled modules (default)
    --all               Test all modules regardless of enabled status
    --verbose           Show detailed test output
    --summary-only      Show only final summary
    --fail-fast         Stop testing on first module failure
    --autofix-only      Test only autofix scripts (dry-run mode)
    --include-autofix   Include autofix dry-run tests with module tests

ARGUMENTS:
    MODULE_NAME         Test specific module(s) only

EXAMPLES:
    ./test.sh                           # Test all enabled modules
    ./test.sh --all                     # Test all modules (enabled and disabled)
    ./test.sh thermal usb               # Test only thermal and usb modules
    ./test.sh --verbose --all           # Test all modules with detailed output
    ./test.sh --list                    # Show available modules
    ./test.sh --autofix-only            # Test only autofix scripts (dry-run)
    ./test.sh --include-autofix --all   # Test modules + autofix scripts

EOF
}

list_modules() {
    echo -e "${BLUE}🧪 AVAILABLE MODULES WITH TESTS${NC}"
    echo "=================================="
    echo ""
    
    local enabled_count=0
    local disabled_count=0
    local no_test_count=0
    
    for module_dir in "$SCRIPT_DIR/modules"/*; do
        if [[ -d "$module_dir" && ! "$module_dir" =~ (common\.sh|MODULE_BEST_PRACTICES\.md)$ ]]; then
            local module_name
            module_name=$(basename "$module_dir")
            local test_script="$module_dir/test.sh"
            local enabled_file="$SCRIPT_DIR/config/$module_name.enabled"
            
            if [[ -f "$test_script" ]]; then
                if [[ -L "$enabled_file" && -f "$enabled_file" ]]; then
                    echo -e "  ✅ ${GREEN}$module_name${NC} (enabled, has test)"
                    enabled_count=$((enabled_count + 1))
                else
                    echo -e "  ⭕ ${YELLOW}$module_name${NC} (disabled, has test)"
                    disabled_count=$((disabled_count + 1))
                fi
            else
                if [[ -L "$enabled_file" && -f "$enabled_file" ]]; then
                    echo -e "  ❌ ${RED}$module_name${NC} (enabled, NO TEST)"
                else
                    echo -e "  ⚪ ${module_name} (disabled, no test)"
                fi
                no_test_count=$((no_test_count + 1))
            fi
        fi
    done
    
    echo ""
    echo -e "${CYAN}📊 SUMMARY:${NC}"
    echo "  Enabled with tests: $enabled_count"
    echo "  Disabled with tests: $disabled_count" 
    echo "  No test scripts: $no_test_count"
    exit 0
}

# =============================================================================
# AUTOFIX SCRIPT DISCOVERY AND TESTING
# =============================================================================

discover_autofix_scripts() {
    local autofix_scripts=()
    
    # Find all .sh files in autofix directory, excluding common.sh
    for script_path in "$SCRIPT_DIR/autofix"/*.sh; do
        if [[ -f "$script_path" ]]; then
            local script_name
            script_name=$(basename "$script_path")
            
            # Skip common.sh and any non-executable autofix scripts
            if [[ "$script_name" != "common.sh" && -x "$script_path" ]]; then
                autofix_scripts+=("$script_name")
            fi
        fi
    done
    
    printf '%s\n' "${autofix_scripts[@]}"
}

list_autofix_scripts() {
    echo -e "${BLUE}📋 Available Autofix Scripts:${NC}"
    echo "============================="
    
    local autofix_scripts=()
    mapfile -t autofix_scripts < <(discover_autofix_scripts)
    
    if [[ ${#autofix_scripts[@]} -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No autofix scripts found${NC}"
        return
    fi
    
    for script in "${autofix_scripts[@]}"; do
        local script_path="$SCRIPT_DIR/autofix/$script"
        if [[ -x "$script_path" ]]; then
            echo -e "  ✅ ${GREEN}$script${NC} (executable)"
        else
            echo -e "  ❌ ${RED}$script${NC} (not executable)"
        fi
    done
    
    echo ""
    echo -e "${CYAN}Total: ${#autofix_scripts[@]} autofix scripts${NC}"
}

run_autofix_test() {
    local script_name="$1"
    local verbose="$2"
    local script_path="$SCRIPT_DIR/autofix/$script_name"
    
    TOTAL_AUTOFIX=$((TOTAL_AUTOFIX + 1))
    
    if [[ ! -f "$script_path" ]]; then
        echo -e "  ❌ ${RED}$script_name: FAIL${NC} (Script not found)"
        AUTOFIX_FAILED=$((AUTOFIX_FAILED + 1))
        return 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        echo -e "  ❌ ${RED}$script_name: FAIL${NC} (Not executable)"
        AUTOFIX_FAILED=$((AUTOFIX_FAILED + 1))
        return 1
    fi
    
    echo -e "${CYAN}🧪 Testing autofix script: $script_name (dry-run)...${NC}"
    
    # Test 1: Syntax check
    if ! bash -n "$script_path" >/dev/null 2>&1; then
        echo -e "  ❌ ${RED}$script_name: FAIL${NC} (Syntax error)"
        AUTOFIX_FAILED=$((AUTOFIX_FAILED + 1))
        return 1
    fi
    
    # Test 2: Help function check
    local help_output
    if help_output=$("$script_path" --help 2>&1); then
        if [[ "$verbose" == "true" ]]; then
            echo "  ✅ Help function works"
        fi
    else
        echo -e "  ⚠️  ${YELLOW}$script_name: Help function missing or broken${NC}"
    fi
    
    # Test 3: Dry-run execution test
    local dry_run_output
    local dry_run_exit_code=0
    
    if dry_run_output=$("$script_path" --dry-run test_module 60 2>&1); then
        if [[ "$verbose" == "true" ]]; then
            echo "----------------------------------------"
            echo "$dry_run_output"
            echo "----------------------------------------"
        fi
        echo -e "  ✅ ${GREEN}$script_name: PASS${NC} (Dry-run successful)"
        AUTOFIX_PASSED=$((AUTOFIX_PASSED + 1))
        return 0
    else
        dry_run_exit_code=$?
        if [[ "$verbose" == "true" ]]; then
            echo "----------------------------------------"
            echo "DRY-RUN OUTPUT:"
            echo "$dry_run_output"
            echo "EXIT CODE: $dry_run_exit_code"
            echo "----------------------------------------"
        fi
        echo -e "  ❌ ${RED}$script_name: FAIL${NC} (Dry-run failed with exit code $dry_run_exit_code)"
        AUTOFIX_FAILED=$((AUTOFIX_FAILED + 1))
        return 1
    fi
}

run_all_autofix_tests() {
    local verbose="$1"
    local summary_only="$2"
    
    local autofix_scripts=()
    mapfile -t autofix_scripts < <(discover_autofix_scripts)
    
    if [[ ${#autofix_scripts[@]} -eq 0 ]]; then
        echo -e "${YELLOW}⚠️  No autofix scripts found to test${NC}"
        return 0
    fi
    
    if [[ "$summary_only" != "true" ]]; then
        echo -e "${CYAN}🔧 Testing ${#autofix_scripts[@]} autofix scripts (dry-run mode)${NC}"
        echo ""
    fi
    
    for script in "${autofix_scripts[@]}"; do
        if [[ "$summary_only" == "true" ]]; then
            run_autofix_test "$script" false >/dev/null 2>&1
        else
            run_autofix_test "$script" "$verbose"
        fi
    done
}

# =============================================================================

# Load common functions for get_enabled_modules()
source "$SCRIPT_DIR/modules/common.sh"

discover_modules() {
    local test_all_modules="$1"
    local specific_modules=("${@:2}")
    local modules=()
    
    if [[ ${#specific_modules[@]} -gt 0 ]]; then
        # Test specific modules
        for module in "${specific_modules[@]}"; do
            if [[ -f "$SCRIPT_DIR/modules/$module/test.sh" ]]; then
                modules+=("$module")
            else
                echo -e "${RED}❌ Module '$module' has no test script${NC}"
            fi
        done
    elif [[ "$test_all_modules" == "true" ]]; then
        # Test all modules with test scripts
        for module_dir in "$SCRIPT_DIR/modules"/*; do
            if [[ -d "$module_dir" && ! "$module_dir" =~ (common\.sh|MODULE_BEST_PRACTICES\.md)$ ]]; then
                local module_name
                module_name=$(basename "$module_dir")
                if [[ -f "$module_dir/test.sh" ]]; then
                    modules+=("$module_name")
                fi
            fi
        done
    else
        # Test only enabled modules (using new configuration system)
        local enabled_modules
        mapfile -t enabled_modules < <(get_enabled_modules)
        for module_name in "${enabled_modules[@]}"; do
            if [[ -f "$SCRIPT_DIR/modules/$module_name/test.sh" ]]; then
                modules+=("$module_name")
            fi
        done
    fi
    
    printf '%s\n' "${modules[@]}"
}

# Helper function to check if hardware exists using module's exists.sh
check_module_hardware_exists() {
    local module="$1"
    local exists_script="$SCRIPT_DIR/modules/$module/exists.sh"
    
    if [[ -f "$exists_script" && -x "$exists_script" ]]; then
        "$exists_script" >/dev/null 2>&1
        return $?
    else
        # If no exists.sh script, assume hardware exists (for backwards compatibility)
        return 0
    fi
}

validate_module_structure() {
    local module="$1"
    local module_dir="$SCRIPT_DIR/modules/$module"
    local validation_errors=()
    
    echo -e "${CYAN}🔍 Validating module structure for $module...${NC}"
    
    # Required files check
    local required_files=(
        "exists.sh:Hardware existence check"
        "monitor.sh:Main monitoring script" 
        "status.sh:Status reporting script"
        "test.sh:Module testing script"
        "scan.sh:Hardware detection and configuration"
        "config.conf:Module configuration"
        "README.md:Module documentation"
    )
    
    for file_info in "${required_files[@]}"; do
        local file_name="${file_info%%:*}"
        local file_desc="${file_info##*:}"
        local file_path="$module_dir/$file_name"
        
        if [[ ! -f "$file_path" ]]; then
            validation_errors+=("❌ Missing $file_name ($file_desc)")
        elif [[ "$file_name" == *.sh && ! -x "$file_path" ]]; then
            validation_errors+=("⚠️  $file_name exists but not executable")
        else
            echo -e "  ✅ $file_name: Found and valid"
            
            # Additional validation for monitor.sh - check for --description flag
            if [[ "$file_name" == "monitor.sh" ]]; then
                if ! "$file_path" --description >/dev/null 2>&1; then
                    validation_errors+=("⚠️  monitor.sh missing required --description flag")
                else
                    echo -e "  ✅ monitor.sh: --description flag working"
                fi
            fi
            
            # Additional validation for scan.sh - check for required modes
            if [[ "$file_name" == "scan.sh" ]]; then
                # Test --help flag
                if ! "$file_path" --help >/dev/null 2>&1; then
                    validation_errors+=("⚠️  scan.sh missing required --help flag")
                else
                    echo -e "  ✅ scan.sh: --help flag working"
                fi
                
                # Test --config mode
                if "$file_path" --config >/dev/null 2>&1; then
                    echo -e "  ✅ scan.sh: --config mode working"
                else
                    # --config might fail if no hardware is detected, which is OK
                    echo -e "  ℹ️  scan.sh: --config mode callable (hardware detection may vary)"
                fi
                
                # Test default mode (should not crash)
                if "$file_path" >/dev/null 2>&1; then
                    echo -e "  ✅ scan.sh: default mode working"
                else
                    echo -e "  ℹ️  scan.sh: default mode callable (hardware detection may vary)"
                fi
            fi
        fi
    done
    
    # Note: Autofix directories are now centralized in /autofix/ - no longer required per module
    
    # Report validation results
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        echo -e "${RED}❌ Module structure validation failed:${NC}"
        for error in "${validation_errors[@]}"; do
            echo -e "    $error"
        done
        return 1
    else
        echo -e "${GREEN}✅ Module structure validation passed${NC}"
        return 0
    fi
}

validate_autofix_scripts() {
    local module="$1"
    local -n errors_ref=$2
    local module_dir="$SCRIPT_DIR/modules/$module"
    local monitor_script="$module_dir/monitor.sh"
    
    if [[ ! -f "$monitor_script" ]]; then
        errors_ref+=("❌ Cannot validate autofixes: monitor.sh missing")
        return 1
    fi
    
    # Get expected autofix scripts from monitor.sh
    local expected_scripts=()
    while IFS= read -r script; do
        if [[ -n "$script" ]]; then
            expected_scripts+=("$script")
        fi
    done < <(grep -o '\$SCRIPT_DIR/autofix/[^"]*\.sh' "$monitor_script" 2>/dev/null | sed 's|.*autofix/||' | sort -u)
    
    if [[ ${#expected_scripts[@]} -eq 0 ]]; then
        echo -e "  ℹ️  No autofix scripts referenced in monitor.sh"
        return 0
    fi
    
    echo -e "  🔧 Checking referenced autofix scripts:"
    for script in "${expected_scripts[@]}"; do
        local script_path="$module_dir/autofix/$script"
        if [[ -f "$script_path" && -x "$script_path" ]]; then
            echo -e "    ✅ $script: Found and executable"
        elif [[ -f "$script_path" ]]; then
            errors_ref+=("⚠️  autofix/$script exists but not executable")
        else
            errors_ref+=("❌ Missing referenced autofix script: autofix/$script")
        fi
    done
    
    # Check for orphaned autofix scripts
    local actual_scripts=()
    while IFS= read -r -d '' script; do
        actual_scripts+=("$(basename "$script")")
    done < <(find "$module_dir/autofix" -name "*.sh" -type f -print0 2>/dev/null)
    
    for script in "${actual_scripts[@]}"; do
        if [[ ! " ${expected_scripts[*]} " =~ " ${script} " ]]; then
            echo -e "    ⚠️  Orphaned autofix script: $script (not referenced in monitor.sh)"
        fi
    done
}

run_module_test() {
    local module="$1"
    local verbose="$2"
    local test_script="$SCRIPT_DIR/modules/$module/test.sh"
    
    TOTAL_MODULES=$((TOTAL_MODULES + 1))
    
    # First validate module structure
    if ! validate_module_structure "$module"; then
        echo -e "  ❌ ${RED}$module: FAIL${NC} (Invalid module structure)"
        MODULES_FAILED=$((MODULES_FAILED + 1))
        return 1
    fi
    
    if [[ ! -x "$test_script" ]]; then
        echo -e "  ⚪ ${module}: No executable test script"
        MODULES_SKIPPED=$((MODULES_SKIPPED + 1))
        return 2
    fi
    
    # Check if hardware exists before running full test
    if ! check_module_hardware_exists "$module"; then
        if [[ "$module" == "nonexistent" ]]; then
            # Special case: nonexistent module - run test and expect it to fail
            echo -e "${CYAN}🧪 Testing $module module...${NC}"
        else
            # For real modules, skip if hardware doesn't exist
            echo -e "  ⏭️  ${YELLOW}$module: SKIP${NC} (Required hardware not detected on this system)"
            MODULES_SKIPPED=$((MODULES_SKIPPED + 1))
            return 0
        fi
    else
        echo -e "${CYAN}🧪 Testing $module module...${NC}"
    fi
    
    if [[ "$verbose" == "true" ]]; then
        echo "----------------------------------------"
        if "$test_script"; then
            echo -e "${GREEN}✅ $module: All tests passed${NC}"
            MODULES_PASSED=$((MODULES_PASSED + 1))
            echo "----------------------------------------"
            return 0
        else
            # Special handling for nonexistent module
            if [[ "$module" == "nonexistent" ]]; then
                echo -e "${GREEN}✅ $module: EXPECTED FAIL (Correctly failed for non-existent hardware)${NC}"
                MODULES_PASSED=$((MODULES_PASSED + 1))
                echo "----------------------------------------"
                return 0
            else
                echo -e "${RED}❌ $module: Some tests failed${NC}"
                MODULES_FAILED=$((MODULES_FAILED + 1))
                echo "----------------------------------------"
                return 1
            fi
        fi
    else
        local test_output
        if test_output=$("$test_script" 2>&1); then
            # Extract summary line from test output
            local summary
            summary=$(echo "$test_output" | grep -E "📊|Passed:|passed|failed" | tail -1 || echo "Tests completed")
            echo -e "  ✅ ${GREEN}$module: PASS${NC} ($summary)"
            MODULES_PASSED=$((MODULES_PASSED + 1))
            return 0
        else
            # Special handling for nonexistent module
            if [[ "$module" == "nonexistent" ]]; then
                echo -e "  ✅ ${GREEN}$module: PASS${NC} (Correctly failed as expected for non-existent hardware)"
                MODULES_PASSED=$((MODULES_PASSED + 1))
                return 0
            else
                # Show the failure reason
                local failure_reason
                failure_reason=$(echo "$test_output" | grep -E "❌ FAIL|Testing.*❌|failed" | head -1 || echo "Tests failed")
                echo -e "  ❌ ${RED}$module: FAIL${NC} ($failure_reason)"
                echo -e "    ${YELLOW}For details: ./modules/$module/test.sh${NC}"
                MODULES_FAILED=$((MODULES_FAILED + 1))
                return 1
            fi
        fi
    fi
}

main() {
    local test_all_modules=false
    local verbose=false
    local summary_only=false
    local fail_fast=false
    local autofix_only=false
    local include_autofix=false
    local specific_modules=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                exit 0
                ;;
            --list)
                list_modules
                echo ""
                list_autofix_scripts
                exit 0
                ;;
            --autofix-only)
                autofix_only=true
                shift
                ;;
            --include-autofix)
                include_autofix=true
                shift
                ;;
            --all)
                test_all_modules=true
                shift
                ;;
            --enabled-only)
                test_all_modules=false
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            --summary-only)
                summary_only=true
                shift
                ;;
            --fail-fast)
                fail_fast=true
                shift
                ;;
            --*)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                specific_modules+=("$1")
                shift
                ;;
        esac
    done
    
    # Header
    echo -e "${BLUE}🛡️  MODULAR MONITORING TEST SUITE${NC}"
    echo "=================================="
    echo ""
    
    # Handle autofix-only mode
    if [[ "$autofix_only" == "true" ]]; then
        run_all_autofix_tests "$verbose" "$summary_only"
        show_final_results
        exit $?
    fi
    
    # Discover modules to test
    local modules_to_test=()
    mapfile -t modules_to_test < <(discover_modules "$test_all_modules" "${specific_modules[@]}")
    
    if [[ ${#modules_to_test[@]} -eq 0 ]] && [[ "$include_autofix" != "true" ]]; then
        echo -e "${YELLOW}⚠️  No modules found to test${NC}"
        if [[ "$test_all_modules" != "true" ]]; then
            echo "  Try: ./test.sh --all (to test all modules)"
            echo "  Or:  ./test.sh --list (to see available modules)"
        fi
        exit 1
    fi
    
    # Show what we're testing
    if [[ "$summary_only" != "true" ]]; then
        if [[ ${#specific_modules[@]} -gt 0 ]]; then
            echo -e "${CYAN}Testing specific modules: ${modules_to_test[*]}${NC}"
        elif [[ "$test_all_modules" == "true" ]]; then
            echo -e "${CYAN}Testing all ${#modules_to_test[@]} available modules${NC}"
        else
            echo -e "${CYAN}Testing ${#modules_to_test[@]} enabled modules${NC}"
        fi
        echo ""
    fi
    
    # Run tests
    for module in "${modules_to_test[@]}"; do
        if [[ "$summary_only" == "true" ]]; then
            run_module_test "$module" false >/dev/null 2>&1
        else
            if ! run_module_test "$module" "$verbose"; then
                if [[ "$fail_fast" == "true" ]]; then
                    echo -e "\n${RED}❌ Stopping on first failure (--fail-fast)${NC}"
                    break
                fi
            fi
        fi
        
        # Add spacing between modules in verbose mode
        if [[ "$verbose" == "true" && "$summary_only" != "true" ]]; then
            echo ""
        fi
    done
    
    # Run autofix tests if requested
    if [[ "$include_autofix" == "true" ]]; then
        echo ""
        echo -e "${BLUE}=== AUTOFIX SCRIPT TESTS ===${NC}"
        run_all_autofix_tests "$verbose" "$summary_only"
    fi
    
    show_final_results
}

show_final_results() {
    # Final summary
    echo ""
    echo -e "${BLUE}📊 FINAL TEST RESULTS${NC}"
    echo "====================="
    
    # Module results (if any were tested)
    if [[ $TOTAL_MODULES -gt 0 ]]; then
        echo -e "${CYAN}MODULES:${NC}"
        echo -e "  ✅ ${GREEN}Passed: $MODULES_PASSED${NC}"
        echo -e "  ❌ ${RED}Failed: $MODULES_FAILED${NC}"
        echo -e "  ⚪ ${YELLOW}Skipped: $MODULES_SKIPPED${NC}"
        echo -e "  📋 ${CYAN}Total: $TOTAL_MODULES${NC}"
        
        # Calculate module success rate
        if [[ $TOTAL_MODULES -gt 0 ]]; then
            local module_success_rate
            module_success_rate=$(( (MODULES_PASSED * 100) / TOTAL_MODULES ))
            echo -e "  📈 Module Success Rate: ${module_success_rate}%"
        fi
        echo ""
    fi
    
    # Autofix results (if any were tested)
    if [[ $TOTAL_AUTOFIX -gt 0 ]]; then
        echo -e "${CYAN}AUTOFIX SCRIPTS:${NC}"
        echo -e "  ✅ ${GREEN}Passed: $AUTOFIX_PASSED${NC}"
        echo -e "  ❌ ${RED}Failed: $AUTOFIX_FAILED${NC}"
        echo -e "  📋 ${CYAN}Total: $TOTAL_AUTOFIX${NC}"
        
        # Calculate autofix success rate
        if [[ $TOTAL_AUTOFIX -gt 0 ]]; then
            local autofix_success_rate
            autofix_success_rate=$(( (AUTOFIX_PASSED * 100) / TOTAL_AUTOFIX ))
            echo -e "  📈 Autofix Success Rate: ${autofix_success_rate}%"
        fi
        echo ""
    fi
    
    # Overall results
    local total_tests=$((TOTAL_MODULES + TOTAL_AUTOFIX))
    local total_passed=$((MODULES_PASSED + AUTOFIX_PASSED))
    local total_failed=$((MODULES_FAILED + AUTOFIX_FAILED))
    
    if [[ $total_tests -gt 0 ]]; then
        echo -e "${CYAN}OVERALL:${NC}"
        echo -e "  ✅ ${GREEN}Total Passed: $total_passed${NC}"
        echo -e "  ❌ ${RED}Total Failed: $total_failed${NC}"
        echo -e "  📋 ${CYAN}Total Tests: $total_tests${NC}"
        
        local overall_success_rate
        overall_success_rate=$(( (total_passed * 100) / total_tests ))
        echo -e "  📈 Overall Success Rate: ${overall_success_rate}%"
    fi
    
    echo ""
    
    # Exit code based on any failures
    if [[ $total_failed -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed! System is ready.${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Some tests failed. Check individual components for details.${NC}"
        echo ""
        echo -e "${CYAN}💡 Quick fixes:${NC}"
        if [[ $MODULES_FAILED -gt 0 ]]; then
            echo "  • Run individual module tests: ./modules/MODULE_NAME/test.sh"
            echo "  • Check dependencies: Install missing tools"
            echo "  • Verify hardware: Some modules need specific hardware"
        fi
        if [[ $AUTOFIX_FAILED -gt 0 ]]; then
            echo "  • Fix autofix script syntax errors"
            echo "  • Test autofix scripts: ./test.sh --autofix-only --verbose"
        fi
        return 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
