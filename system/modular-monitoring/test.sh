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

ARGUMENTS:
    MODULE_NAME         Test specific module(s) only

EXAMPLES:
    ./test.sh                           # Test all enabled modules
    ./test.sh --all                     # Test all modules (enabled and disabled)
    ./test.sh thermal usb               # Test only thermal and usb modules
    ./test.sh --verbose --all           # Test all modules with detailed output
    ./test.sh --list                    # Show available modules

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
        # Test only enabled modules
        for enabled_file in "$SCRIPT_DIR/config"/*.enabled; do
            if [[ -L "$enabled_file" && -f "$enabled_file" ]]; then
                local module_name
                module_name=$(basename "$enabled_file" .enabled)
                if [[ -f "$SCRIPT_DIR/modules/$module_name/test.sh" ]]; then
                    modules+=("$module_name")
                fi
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
    
    # Discover modules to test
    local modules_to_test=()
    mapfile -t modules_to_test < <(discover_modules "$test_all_modules" "${specific_modules[@]}")
    
    if [[ ${#modules_to_test[@]} -eq 0 ]]; then
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
    
    # Final summary
    echo ""
    echo -e "${BLUE}📊 FINAL TEST RESULTS${NC}"
    echo "====================="
    echo -e "  ✅ ${GREEN}Passed: $MODULES_PASSED${NC}"
    echo -e "  ❌ ${RED}Failed: $MODULES_FAILED${NC}"
    echo -e "  ⚪ ${YELLOW}Skipped: $MODULES_SKIPPED${NC}"
    echo -e "  📋 ${CYAN}Total: $TOTAL_MODULES${NC}"
    
    # Calculate success rate
    if [[ $TOTAL_MODULES -gt 0 ]]; then
        local success_rate
        success_rate=$(( (MODULES_PASSED * 100) / TOTAL_MODULES ))
        echo -e "  📈 Success Rate: ${success_rate}%"
    fi
    
    echo ""
    
    # Exit code
    if [[ $MODULES_FAILED -eq 0 ]]; then
        echo -e "${GREEN}🎉 All tests passed! System is ready.${NC}"
        exit 0
    else
        echo -e "${YELLOW}⚠️  Some tests failed. Check individual modules for details.${NC}"
        echo ""
        echo -e "${CYAN}💡 Quick fixes:${NC}"
        echo "  • Run individual tests: ./modules/MODULE_NAME/test.sh"
        echo "  • Check dependencies: Install missing tools"
        echo "  • Verify hardware: Some modules need specific hardware"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
