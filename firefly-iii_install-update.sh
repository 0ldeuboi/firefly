#!/bin/bash

# This script installs or updates Firefly III and the Firefly Importer on Ubuntu 20.04 or higher.
# Please run this script as root or using sudo.

# Environment Variables for Non-Interactive Mode:
#   - NON_INTERACTIVE=true : Run the script in non-interactive mode.
#   - HAS_DOMAIN=true|false : Set to "true" if you have a domain name, "false" or leave unset if not.
#   - DOMAIN_NAME : Your domain name (e.g., example.com). Required if HAS_DOMAIN=true.
#   - EMAIL_ADDRESS : Your email address for SSL certificate registration. Required if HAS_DOMAIN=true.
#   - DB_NAME : (Optional) Database name. Default is a randomly generated name.
#   - DB_USER : (Optional) Database username. Default is a randomly generated name.
#   - DB_PASS : (Optional) Database password. Default is a randomly generated password.
#   - GITHUB_TOKEN : (Optional) Your GitHub API token to avoid rate limiting.

# Enable debug logging with DEBUG=true ./script.sh
DEBUG="${DEBUG:-false}"

#####################################################################################################################################################
#
#   1. Core Utility Functions
#
#####################################################################################################################################################

# Define colors and formatting
COLOR_RESET="\033[0m"
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

# Define a variable for clearing the line
CLEAR_LINE="\r\033[K"

# 1.1 Function to log messages with consistent formatting
# Parameters:
#   level: Log level (INFO, SUCCESS, WARNING, ERROR)
#   message: The message to log
# Returns:
#   0 always
_1_1_log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    local function_name="${FUNCNAME[2]:-main}"
    local line_number="${BASH_LINENO[1]:-unknown}"
    local context="[$function_name:$line_number]"

    # Determine color based on level
    local color=""
    case "$level" in
    "INFO") color="$COLOR_BLUE" ;;
    "SUCCESS") color="$COLOR_GREEN" ;;
    "WARNING") color="$COLOR_YELLOW" ;;
    "ERROR") color="$COLOR_RED" ;;
    *) color="$COLOR_RESET" ;;
    esac

    # Only print to stderr if not in non-interactive mode or if it's not an error
    if [ "$NON_INTERACTIVE" = false ] || [ "$level" != "ERROR" ]; then
        echo -e "${color}[${level}]${COLOR_RESET} $message" >&2
    fi

    # Always log to file with timestamp and context
    echo "$timestamp [$level] $context $message" >>"$LOG_FILE"

    return 0
}

# 1.2 Enhanced info function
# Parameters:
#   Any number of arguments: The message to log
_1_2_info() {
    _1_1_log_message "INFO" "$*"
}

# 1.3 Enhanced success function
# Parameters:
#   Any number of arguments: The message to log
1_3_success() {
    _1_1_log_message "SUCCESS" "$*"
}

# 1.4 Enhanced warning function
# Parameters:
#   Any number of arguments: The message to log
1_4_warning() {
    _1_1_log_message "WARNING" "$*"
}

# 1.5 Enhanced error function
# Parameters:
#   Any number of arguments: The error message to log
_1_5_error() {
    _1_1_log_message "ERROR" "$*"
}

# 1.6 Function to prompt user for input
# Parameters:
#   Any number of arguments: The prompt message
prompt() {
    echo -ne "${COLOR_CYAN}$*${COLOR_RESET}"
}

# 1.7 Function to log critical errors and exit the script
# Parameters:
#   message: The critical error message
#   exit_code: Exit code (default: 1)
# Returns:
#   Does not return - exits the script
critical_error() {
    local message="$1"
    local exit_code="${2:-1}"

    TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
    local function_name="${FUNCNAME[1]:-main}"
    local line_number="${BASH_LINENO[0]:-unknown}"

    echo -e "${COLOR_RED}[CRITICAL ERROR]${COLOR_RESET} $message" >&2
    echo "$TIMESTAMP [CRITICAL] [$function_name:$line_number] $message" >>"$LOG_FILE"

    # Cleanup before exiting
    cleanup

    echo -e "\n${COLOR_RED}The script encountered a critical error and must exit.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Check the log for details: $LOG_FILE${COLOR_RESET}\n"

    exit "$exit_code"
}

# 1.8 Function to log debug messages (only appears in log file)
# Parameters:
#   Any number of arguments: The debug message to log
debug() {
    # Only log if DEBUG mode is enabled
    if [ "${DEBUG:-false}" = true ]; then
        TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
        local function_name="${FUNCNAME[1]:-main}"
        local line_number="${BASH_LINENO[0]:-unknown}"
        echo "$TIMESTAMP [DEBUG] [$function_name:$line_number] $*" >>"$LOG_FILE"
    fi
}

# 1.9 Function to check command result and handle errors
# Parameters:
#   result: Command result code
#   error_message: Message to display on error
#   fatal: Whether error is fatal (default: false)
# Returns:
#   0 if result is 0, 1 otherwise
check_error() {
    local result="$1"
    local error_message="$2"
    local fatal="${3:-false}"

    if [ "$result" -ne 0 ]; then
        if [ "$fatal" = true ]; then
            critical_error "$error_message (Error code: $result)"
        else
            error "$error_message (Error code: $result)"
            return 1
        fi
    fi
    return 0
}

#####################################################################################################################################################
#
#   2. System Management Functions
#
#####################################################################################################################################################

# 2.1 Detect OS once and store in a global variable
detect_os() {
    if command -v apt-get &>/dev/null; then
        os_type="debian"
    elif command -v yum &>/dev/null || command -v dnf &>/dev/null; then
        os_type="rhel"
    elif command -v apk &>/dev/null; then
        os_type="alpine"
    else
        error "Unsupported OS. Cannot determine package manager."
        exit 1
    fi
}

# 2.2 Function to handle package operations across different distributions
# Parameters:
#   operation: Operation to perform (install, update, remove)
#   packages: Space-separated list of packages
# Returns:
#   0 if successful, 1 if failed
package_manager() {
    debug "Starting package_manager function with operation: $1, packages: $2"
    local operation="$1"
    local packages="$2"
    local cmd=""
    local result=1
    local description="Package Management"

    # Determine package manager command based on detected OS
    case "$os_type" in
    "debian")
        case "$operation" in
        install)
            cmd="apt-get install -y $packages"
            description="Installing packages"
            ;;
        update)
            cmd="apt-get update"
            description="Updating package lists"
            ;;
        upgrade)
            cmd="apt-get upgrade -y"
            description="Upgrading packages"
            ;;
        remove)
            cmd="apt-get remove -y $packages"
            description="Removing packages"
            ;;
        purge)
            cmd="apt-get purge -y $packages"
            description="Purging packages"
            ;;
        autoremove)
            cmd="apt-get autoremove -y"
            description="Auto-removing unused packages"
            ;;
        *)
            error "Unknown operation: $operation"
            return 1
            ;;
        esac
        ;;

    "rhel")
        case "$operation" in
        install)
            cmd="yum install -y $packages"
            # Check if dnf is available (newer RHEL/CentOS/Fedora)
            if command -v dnf &>/dev/null; then
                cmd="dnf install -y $packages"
            fi
            description="Installing packages"
            ;;
        update)
            cmd="yum check-update"
            if command -v dnf &>/dev/null; then
                cmd="dnf check-update"
            fi
            description="Updating package lists"
            ;;
        upgrade)
            cmd="yum update -y"
            if command -v dnf &>/dev/null; then
                cmd="dnf update -y"
            fi
            description="Upgrading packages"
            ;;
        remove)
            cmd="yum remove -y $packages"
            if command -v dnf &>/dev/null; then
                cmd="dnf remove -y $packages"
            fi
            description="Removing packages"
            ;;
        purge)
            # yum/dnf doesn't distinguish between remove and purge
            cmd="yum remove -y $packages"
            if command -v dnf &>/dev/null; then
                cmd="dnf remove -y $packages"
            fi
            description="Purging packages"
            ;;
        autoremove)
            cmd="yum autoremove -y"
            if command -v dnf &>/dev/null; then
                cmd="dnf autoremove -y"
            fi
            description="Auto-removing unused packages"
            ;;
        *)
            error "Unknown operation: $operation"
            return 1
            ;;
        esac
        ;;

    "alpine")
        case "$operation" in
        install)
            cmd="apk add $packages"
            description="Installing packages"
            ;;
        update)
            cmd="apk update"
            description="Updating package lists"
            ;;
        upgrade)
            cmd="apk upgrade"
            description="Upgrading packages"
            ;;
        remove)
            cmd="apk del $packages"
            description="Removing packages"
            ;;
        purge)
            # apk doesn't distinguish between remove and purge
            cmd="apk del $packages"
            description="Purging packages"
            ;;
        autoremove)
            # apk doesn't have autoremove
            cmd="true" # No-op command
            description="Auto-removing unused packages"
            ;;
        *)
            error "Unknown operation: $operation"
            return 1
            ;;
        esac
        ;;

    *)
        error "Unsupported OS type: $os_type"
        return 1
        ;;
    esac

    # Execute the command with progress tracking
    _1_2_info "Executing: $cmd"

    local temp_output=$(mktemp)
    show_progress "$description" 5 100 "Starting..."

    # Run the command and capture output
    eval "$cmd" > >(tee -a "$LOG_FILE" >"$temp_output") 2>&1 &
    local cmd_pid=$!
    local progress=10
    local last_update=""
    local start_time=$(date +%s)

    # Monitor command execution
    while kill -0 $cmd_pid 2>/dev/null; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        progress=$((10 + (elapsed * 85 / 30))) # Scale progress over 30 seconds
        [ "$progress" -gt 95 ] && progress=95  # Cap progress at 95%

        # Extract status from command output
        local status=""
        if [ -f "$temp_output" ]; then
            status=$(tail -n1 "$temp_output" | grep -v "^$" | tr -d '\r' | cut -c 1-40)
            [ ${#status} -eq 40 ] && status="${status}..."
            [ -z "$status" ] && status="Processing..."
        fi

        # Update progress display
        if [ "$status" != "$last_update" ] || [ $((current_time % 2)) -eq 0 ]; then
            show_progress "$description" "$progress" 100 "$status"
            last_update="$status"
        fi

        sleep 0.5
    done

    # Get command exit code and finalize progress
    wait $cmd_pid
    local exit_code=$?

    show_progress "$description" 100 100 "Complete" "true"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [CMD] Completed: $cmd (Exit code: $exit_code)" >>"$LOG_FILE"

    # Check for non-zero exit code and handle update operation specially
    if [ $exit_code -ne 0 ]; then
        # Check-update returns 100 when updates are available in yum/dnf
        if [ "$operation" = "update" ] && [ "$os_type" = "rhel" ] && [ $exit_code -eq 100 ]; then
            1_3_success "Package list updated successfully. Updates are available."
            exit_code=0
        else
            # Log specific error information from the output
            local error_info=$(grep -i "error\|fail\|warning" "$temp_output" | head -n 3)
            if [ -n "$error_info" ]; then
                error "Package operation failed with errors: $error_info"
            else
                error "Package operation failed with exit code $exit_code."
            fi
        fi
    else
        1_3_success "Package operation completed successfully."
    fi

    # Clean up
    rm -f "$temp_output"

    return $exit_code
}

# 2.3 Function to detect system information with improved compatibility
detect_system_info() {
    debug "Starting detect_system_info function"

    # Detect OS type and version
    if [ -f /etc/os-release ]; then
        # Modern Linux distributions have this file
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        OS_ID="$ID"
        OS_ID_LIKE="$ID_LIKE"
    elif [ -f /etc/lsb-release ]; then
        # Older Ubuntu/Debian systems
        . /etc/lsb-release
        OS_NAME="$DISTRIB_ID"
        OS_VERSION="$DISTRIB_RELEASE"
        OS_ID="$(echo $DISTRIB_ID | tr '[:upper:]' '[:lower:]')"
        OS_ID_LIKE="debian"
    elif [ -f /etc/redhat-release ]; then
        # RHEL-based systems
        OS_NAME=$(cat /etc/redhat-release)
        OS_VERSION=$(grep -o '[0-9\.]*' /etc/redhat-release | head -n1)
        OS_ID="rhel"
        OS_ID_LIKE="fedora"
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux
        OS_NAME="Alpine Linux"
        OS_VERSION=$(grep -o '[0-9\.]*' /etc/alpine-release | head -n1)
        OS_ID="alpine"
        OS_ID_LIKE=""
    else
        # Fallback for unknown distributions
        OS_NAME="Unknown"
        OS_VERSION="Unknown"
        OS_ID="unknown"
        OS_ID_LIKE=""
        _1_4_warning "Could not determine OS distribution. Some features may not work correctly."
    fi

    # Detect package management system
    if command -v apt-get >/dev/null 2>&1; then
        os_type="debian"
    elif command -v dnf >/dev/null 2>&1; then
        os_type="rhel"
    elif command -v yum >/dev/null 2>&1; then
        os_type="rhel"
    elif command -v apk >/dev/null 2>&1; then
        os_type="alpine"
    else
        error "Unsupported OS. This script requires apt, dnf, yum, or apk."
        exit 1
    fi

    # Detect system architecture
    if command -v uname >/dev/null 2>&1; then
        ARCH=$(uname -m)
    else
        ARCH="unknown"
        _1_4_warning "Could not determine system architecture."
    fi

    # Detect init system
    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif [ -f /sbin/openrc-run ] || [ -d /etc/init.d ]; then
        INIT_SYSTEM="openrc"
    elif [ -f /sbin/init ] && /sbin/init --version 2>&1 | grep -q upstart; then
        INIT_SYSTEM="upstart"
    elif [ -x /etc/init.d/cron ] && [ ! -h /etc/init.d/cron ]; then
        INIT_SYSTEM="sysv"
    else
        INIT_SYSTEM="unknown"
        _1_4_warning "Could not determine init system. Using generic commands."
    fi

    # Export all detected variables
    export OS_NAME OS_VERSION OS_ID OS_ID_LIKE ARCH INIT_SYSTEM os_type

    _1_2_info "System detection complete: $OS_NAME $OS_VERSION ($ARCH), Package manager: $os_type, Init system: $INIT_SYSTEM"

    return 0
}

# 2.4 Function to add PHP repository with cross-distribution support
# Parameters:
#   None - Uses global OS_* variables
# Returns:
#   0 if repository added successfully, 1 if failed
_2_4_add_php_repository() {
    debug "Starting add_php_repository function"

    case "$os_type" in
    "debian")
        _1_2_info "Adding PHP repository for Debian-based system..."

        # Check if this is Ubuntu, Debian, or other
        if [ "$OS_ID" = "ubuntu" ]; then
            # For Ubuntu
            if ! grep -q "^deb.*ppa:ondrej/php" /etc/apt/sources.list.d/*.list 2>/dev/null; then
                _1_2_info "Adding Ondrej PHP PPA for Ubuntu..."
                apt-get update
                apt-get install -y software-properties-common
                add-apt-repository -y ppa:ondrej/php
                apt-get update
            else
                _1_2_info "Ondrej PHP PPA already added."
            fi
        elif [ "$OS_ID" = "debian" ]; then
            # For Debian
            if ! grep -q "packages.sury.org/php" /etc/apt/sources.list.d/*.list 2>/dev/null; then
                _1_2_info "Adding Sury PHP repository for Debian..."
                apt-get update
                apt-get install -y apt-transport-https lsb-release ca-certificates curl
                curl -sSLo /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
                sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
                apt-get update
            else
                _1_2_info "Sury PHP repository already added."
            fi
        elif [[ "$OS_ID_LIKE" == *"debian"* ]]; then
            # For Debian-like systems
            _1_4_warning "Using default PHP packages from distribution repositories."
            # No additional repositories added, use distribution default
        else
            _1_4_warning "Unknown Debian-based distribution. Using default PHP packages."
        fi
        ;;

    "rhel")
        _1_2_info "Adding PHP repository for RHEL-based system..."

        # Check if EPEL is installed
        if ! rpm -q epel-release &>/dev/null; then
            _1_2_info "Installing EPEL repository..."
            if [ "$OS_VERSION" = "7" ]; then
                yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
            elif [ "${OS_VERSION%%.*}" = "8" ]; then
                dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
            elif [ "${OS_VERSION%%.*}" = "9" ]; then
                dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
            else
                _1_4_warning "Unsupported RHEL version: $OS_VERSION. Using default repositories."
            fi
        else
            _1_2_info "EPEL repository already installed."
        fi

        # Check if Remi repo is installed
        if ! rpm -q remi-release &>/dev/null; then
            _1_2_info "Installing Remi repository..."
            if [ "$OS_VERSION" = "7" ]; then
                yum install -y https://rpms.remirepo.net/enterprise/remi-release-7.rpm
            elif [ "${OS_VERSION%%.*}" = "8" ]; then
                dnf install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm
            elif [ "${OS_VERSION%%.*}" = "9" ]; then
                dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm
            else
                _1_4_warning "Unsupported RHEL version: $OS_VERSION. Using default repositories."
            fi
        else
            _1_2_info "Remi repository already installed."
        fi
        ;;

    "alpine")
        _1_2_info "Alpine Linux detected. Using built-in package repositories for PHP."
        # No additional repositories needed for Alpine
        ;;

    *)
        error "Unsupported OS type: $os_type. Cannot add PHP repository."
        return 1
        ;;
    esac

    1_3_success "PHP repository configuration completed."
    return 0
}

#####################################################################################################################################################
#
#   3. PHP Management Functions
#
#####################################################################################################################################################

# Function to detect installed PHP version
# Parameters:
#   None
# Returns:
#   Detected PHP version (e.g., "8.1"), or empty string if not found
detect_php_version() {
    debug "Starting detect_php_version"
    local php_version=""

    # Method 1: Check via PHP command line if available
    if command -v php &>/dev/null; then
        php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
        if [ -n "$php_version" ]; then
            debug "Detected PHP version via php command: $php_version"
            echo "$php_version"
            return 0
        fi
    fi

    # Method 2: Check via package manager
    case "$os_type" in
    "debian")
        # Look for installed PHP packages
        local php_pkg=$(dpkg -l | grep -E '^ii +php[0-9]+\.[0-9]+-common' | head -n1 | awk '{print $2}')
        if [ -n "$php_pkg" ]; then
            php_version=$(echo "$php_pkg" | grep -oP 'php\K[0-9]+\.[0-9]+')
            if [ -n "$php_version" ]; then
                debug "Detected PHP version from Debian package: $php_version"
                echo "$php_version"
                return 0
            fi
        fi
        ;;

    "rhel")
        # For RHEL/CentOS
        if command -v dnf &>/dev/null; then
            php_version=$(dnf list installed php-cli 2>/dev/null | grep php-cli | awk '{print $2}' | cut -d':' -f2 | cut -d'.' -f1-2)
        else
            php_version=$(yum list installed php-cli 2>/dev/null | grep php-cli | awk '{print $2}' | cut -d':' -f2 | cut -d'.' -f1-2)
        fi

        if [ -n "$php_version" ]; then
            debug "Detected PHP version from RHEL package: $php_version"
            echo "$php_version"
            return 0
        fi
        ;;

    "alpine")
        # For Alpine Linux
        local php_pkg=$(apk _1_2_info | grep -oP 'php[0-9]+-common' | head -n1)
        if [ -n "$php_pkg" ]; then
            # Format Alpine PHP version (e.g., php81-common → 8.1)
            php_version=$(echo "$php_pkg" | grep -oP 'php\K[0-9]+' | sed 's/\(.\)\(.\)/\1.\2/')
            if [ -n "$php_version" ]; then
                debug "Detected PHP version from Alpine package: $php_version"
                echo "$php_version"
                return 0
            fi
        fi
        ;;
    esac

    # If no PHP version detected
    debug "No PHP version detected"
    echo ""
    return 1
}

# Function to get available PHP versions from package manager
# Parameters:
#   None
# Returns:
#   List of available PHP versions (one per line), or empty if none found
get_available_php_versions() {
    debug "Starting get_available_php_versions"
    local temp_file=$(mktemp)

    case "$os_type" in
    "debian")
        _2_4_add_php_repository
        package_manager update "" # Ensure package lists are refreshed
        apt-cache madison php | awk '{print $3}' | grep -oP '^\d+\.\d+' | sort -V | uniq >"$temp_file"
        ;;

    "rhel")
        _2_4_add_php_repository
        package_manager update "" # Refresh repository cache
        if command -v dnf &>/dev/null; then
            dnf module reset php -y
            dnf module enable remi-php:latest -y
            dnf module list php --available | grep -oP 'php:remi-\K\d+\.\d+' | sort -V >"$temp_file"
        else
            yum list available | grep -oP 'php\d\d-php-common' | grep -oP '\d\d' | sed 's/\(..\)/\1./' | sort -V >"$temp_file"
        fi
        ;;

    "alpine")
        package_manager update "" # Refresh package lists for Alpine
        apk list | grep -oP 'php\d\d-common' | grep -oP 'php\K\d\d' | sed 's/\(..\)/\1./' | sort -V | uniq >"$temp_file"
        ;;

    *)
        error "Unsupported OS for PHP version detection: $os_type"
        rm -f "$temp_file"
        return 1
        ;;
    esac

    cat "$temp_file"
    rm -f "$temp_file"
    return 0
}

# Function to validate user input with enhanced error messages and comprehensive type checking
#
# Parameters:
#   input_value: The value to validate
#   input_type: Type of validation to perform (see supported types below)
#   error_msg: Custom error message to display if validation fails (optional)
#   show_errors: Set to "true" to display error messages (default: false)
#
# Supported validation types:
#   "email" - Email address validation
#   "domain" - Domain name validation
#   "hostname" - Hostname validation (may include domain or IP)
#   "ip" - IP address validation
#   "number" - Integer number validation
#   "port" - TCP/UDP port number validation (1-65535)
#   "decimal" - Decimal number validation
#   "path" - File path validation
#   "directory" - Existing directory validation
#   "file" - Existing file validation
#   "password" - Password strength validation
#   "username" - Username format validation
#   "date" - Date format validation (YYYY-MM-DD)
#   "time" - Time format validation (HH:MM:SS)
#   "yes_no" - Yes/No input validation (Y/y/N/n)
#   "alphanumeric" - Letters and numbers only
#   "db_identifier" - Database identifier validation (letters, numbers, underscore)
#
# Returns:
#   0 if validation passes, 1 if it fails
validate_input() {
    local input_value="$1"
    local input_type="$2"
    local error_msg="$3"
    local show_errors="${4:-false}" # Default to NOT showing errors

    # Initialize result as failure
    local result=1
    local default_error=""

    # Handle empty input - we'll allow empty input for certain types
    if [ -z "$input_value" ]; then
        case "$input_type" in
        # These types can be empty in some contexts
        "path" | "directory" | "file" | "url" | "date" | "time")
            result=0
            ;;
        # All other types require non-empty input
        *)
            default_error="Input cannot be empty"
            result=1
            ;;
        esac
    else
        # Validation based on input type
        case "$input_type" in
        "email")
            # RFC 5322 compliant email regex, simplified for bash
            if [[ "$input_value" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ &&
                ! "$input_value" =~ \.\. &&
                ! "$input_value" =~ ^[^@]+@\. &&
                ! "$input_value" =~ @[^.]*$ ]]; then
                result=0
            else
                default_error="Invalid email format: $input_value"
            fi
            ;;

        "domain")
            # Domain name validation (strict format)
            if [[ "$input_value" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
                result=0
            else
                default_error="Invalid domain format: $input_value"
            fi
            ;;

        "hostname")
            # Hostname validation (domain or IP)
            if [[ "$input_value" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] ||
                [[ "$input_value" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                result=0
            else
                default_error="Invalid hostname format: $input_value"
            fi
            ;;

        "ip")
            # Basic IPv4 validation
            if [[ "$input_value" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                # Check each octet is in valid range (0-255)
                local valid=true
                local IFS='.'
                for octet in $input_value; do
                    if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
                        valid=false
                        break
                    fi
                done

                if [ "$valid" = true ]; then
                    result=0
                else
                    default_error="Invalid IP address (octet out of range 0-255): $input_value"
                fi
            else
                default_error="Invalid IP address format: $input_value"
            fi
            ;;

        "number")
            # Integer validation
            if [[ "$input_value" =~ ^[0-9]+$ ]]; then
                result=0
            else
                default_error="Not a valid number: $input_value"
            fi
            ;;

        "port")
            # TCP/UDP port validation (1-65535)
            if [[ "$input_value" =~ ^[0-9]+$ ]] && [ "$input_value" -ge 1 ] && [ "$input_value" -le 65535 ]; then
                result=0
            else
                default_error="Invalid port number (must be 1-65535): $input_value"
            fi
            ;;

        "decimal")
            # Decimal number validation
            if [[ "$input_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                result=0
            else
                default_error="Not a valid decimal number: $input_value"
            fi
            ;;

        "path")
            # Basic path format validation
            if [[ "$input_value" =~ ^[a-zA-Z0-9_/.-]+$ ]]; then
                result=0
            else
                default_error="Invalid path format: $input_value"
            fi
            ;;

        "directory")
            # Existing directory validation
            if [ -d "$input_value" ]; then
                result=0
            else
                default_error="Directory does not exist: $input_value"
            fi
            ;;

        "file")
            # Existing file validation
            if [ -f "$input_value" ]; then
                result=0
            else
                default_error="File does not exist: $input_value"
            fi
            ;;

        "password")
            # Password strength validation (min 8 chars, at least 1 letter, 1 number, 1 special char)
            if [ ${#input_value} -ge 8 ] &&
                [[ "$input_value" =~ [a-zA-Z] ]] &&
                [[ "$input_value" =~ [0-9] ]] &&
                [[ "$input_value" =~ [^a-zA-Z0-9] ]]; then
                result=0
            else
                default_error="Password too weak (need 8+ chars with letters, numbers, and special chars)"
            fi
            ;;

        "username")
            # Username format validation (letters, numbers, underscore, hyphen)
            if [[ "$input_value" =~ ^[a-zA-Z0-9_-]{3,32}$ ]]; then
                result=0
            else
                default_error="Invalid username format: $input_value (use 3-32 chars: letters, numbers, _ or -)"
            fi
            ;;

        "date")
            # Date format validation (YYYY-MM-DD)
            if [[ "$input_value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
                # Extract components
                local year=$(echo "$input_value" | cut -d'-' -f1)
                local month=$(echo "$input_value" | cut -d'-' -f2)
                local day=$(echo "$input_value" | cut -d'-' -f3)

                # Validate month and day ranges
                if [ "$month" -ge 1 ] && [ "$month" -le 12 ] && [ "$day" -ge 1 ] && [ "$day" -le 31 ]; then
                    result=0
                else
                    default_error="Invalid date values in: $input_value"
                fi
            else
                default_error="Invalid date format (use YYYY-MM-DD): $input_value"
            fi
            ;;

        "time")
            # Time format validation (HH:MM:SS)
            if [[ "$input_value" =~ ^[0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]]; then
                # Extract components
                local hour=$(echo "$input_value" | cut -d':' -f1)
                local minute=$(echo "$input_value" | cut -d':' -f2)
                local second="00"
                if [[ "$input_value" == *:*:* ]]; then
                    second=$(echo "$input_value" | cut -d':' -f3)
                fi

                # Validate ranges
                if [ "$hour" -ge 0 ] && [ "$hour" -le 23 ] &&
                    [ "$minute" -ge 0 ] && [ "$minute" -le 59 ] &&
                    [ "$second" -ge 0 ] && [ "$second" -le 59 ]; then
                    result=0
                else
                    default_error="Invalid time values in: $input_value"
                fi
            else
                default_error="Invalid time format (use HH:MM:SS or HH:MM): $input_value"
            fi
            ;;

        "yes_no")
            # Yes/No validation
            if [[ "$input_value" =~ ^[YyNn]$ ]]; then
                result=0
            else
                default_error="Please enter 'y/Y' for Yes or 'n/N' for No."
            fi
            ;;

        "alphanumeric")
            # Letters and numbers only
            if [[ "$input_value" =~ ^[a-zA-Z0-9]+$ ]]; then
                result=0
            else
                default_error="Only letters and numbers allowed: $input_value"
            fi
            ;;

        "db_identifier")
            # Database identifier validation (letters, numbers, underscore)
            if [[ "$input_value" =~ ^[a-zA-Z0-9_]+$ ]]; then
                result=0
            else
                default_error="Invalid database identifier: $input_value (use letters, numbers, underscore)"
            fi
            ;;

        *)
            default_error="Unknown validation type: $input_type"
            result=1
            ;;
        esac
    fi

    # Output error message ONLY if validation failed AND show_errors is set to true
    if [ "$result" -ne 0 ] && [ "$show_errors" = "true" ]; then
        if [ -n "$error_msg" ]; then
            error "$error_msg"
        elif [ -n "$default_error" ]; then
            error "$default_error"
        fi
    fi

    return $result
}

# Function to display a progress indicator for long-running operations
# Parameters:
#   operation_name: Name of the operation in progress
#   current_step: Current step number
#   total_steps: Total number of steps
#   operation_status: Status message to display (optional)
#   persist: Whether to keep the last status line (optional)
# Enhanced progress indicator for better visual feedback
show_progress() {
    local operation_name="$1"
    local current_step="$2"
    local total_steps="$3"
    local operation_status="${4:-in progress}"
    local persist="${5:-false}"
    local indent="${6:-0}"

    # Skip progress updates in non-interactive mode
    if [ "$NON_INTERACTIVE" = true ]; then
        if [ "$persist" = true ] || [ "$current_step" -eq "$total_steps" ]; then
            _1_2_info "$operation_name: $operation_status (Complete)"
        fi
        return 0
    fi

    # Calculate percentage with boundary checking
    local percentage=0
    if [ "$total_steps" -gt 0 ]; then
        percentage=$((current_step * 100 / total_steps))
        # Ensure percentage doesn't exceed 100
        [ "$percentage" -gt 100 ] && percentage=100
    fi

    # Calculate the number of bars to display (out of 20)
    local bars=$((percentage / 5))
    local spaces=$((20 - bars))

    # Create the progress bar with color gradients
    local progress_bar="["

    # Choose colors based on progress
    local bar_color="$COLOR_GREEN"
    if [ "$percentage" -lt 33 ]; then
        bar_color="$COLOR_BLUE"
    elif [ "$percentage" -lt 66 ]; then
        bar_color="$COLOR_CYAN"
    fi

    # Add the filled portion
    for ((i = 0; i < bars; i++)); do
        progress_bar+="${bar_color}#${COLOR_RESET}"
    done

    # Add the empty portion
    for ((i = 0; i < spaces; i++)); do
        progress_bar+="."
    done

    progress_bar+="]"

    # Format the percentage with leading space for single digits
    local percentage_display=" $percentage"
    [ "$percentage" -ge 10 ] && percentage_display="$percentage"

    # Create indentation based on nesting level
    local indentation=""
    for ((i = 0; i < indent; i++)); do
        indentation+="  "
    done

    # Create spinner animation
    local spinner_chars=("|" "/" "-" "\\")
    local spinner_index=$(((current_step / 2) % ${#spinner_chars[@]}))
    local spinner="${spinner_chars[$spinner_index]}"

    # Only show spinner if not at 100%
    [ "$percentage" -eq 100 ] && spinner=" "

    # Use the CLEAR_LINE variable
    echo -ne "${CLEAR_LINE}${indentation}${COLOR_CYAN}${operation_name}${COLOR_RESET}: ${progress_bar} ${percentage_display}% ${spinner} ${operation_status}"

    # If we're at 100% or persist is requested, add a newline
    if [ "$percentage" -eq 100 ] || [ "$persist" = "true" ]; then
        echo ""
    fi
}

# Function to display a hierarchical progress tree
# This allows for more detailed progress reporting with sub-tasks
start_progress_group() {
    local group_name="$1"
    local indent="${2:-0}"

    # Skip in non-interactive mode
    if [ "$NON_INTERACTIVE" = true ]; then
        return 0
    fi

    # Add indentation
    local indentation=""
    for ((i = 0; i < indent; i++)); do
        indentation+="  "
    done

    echo -e "${indentation}${COLOR_CYAN}${group_name}${COLOR_RESET}:"

    # Return success
    return 0
}

# Function to create a time-based progress indicator for long-running commands
# Function to monitor a command with pulsing progress indicator for long-running commands
monitor_command_with_pulse() {
    local operation_name="$1"
    local command="$2"
    local indent="${3:-0}"
    local timeout="${4:-300}" # Default timeout: 5 minutes

    debug "Starting monitor_command_with_pulse for: $command"

    # Use the unified function with pulse mode
    execute_with_progress "$operation_name" "$command" "pulse=true" "timeout=$timeout" "indent=$indent"
    return $?
}

# Function to estimate total files in a directory with smart sampling
estimate_file_count() {
    local directory="$1"

    # For small directories, just count directly
    local quick_estimate=$(find "$directory" -type f -maxdepth 1 | wc -l)
    if [ "$quick_estimate" -lt 100 ]; then
        find "$directory" -type f | wc -l
        return 0
    fi

    # For larger directories, use sampling
    local sample_count=0
    local dir_count=$(find "$directory" -type d | wc -l)

    # Sample up to 5 subdirectories
    local sample_dirs=$(find "$directory" -type d | sort -R | head -n 5)
    for dir in $sample_dirs; do
        sample_count=$((sample_count + $(find "$dir" -type f | wc -l)))
    done

    # Calculate average files per directory
    local avg_files_per_dir=0
    if [ "$dir_count" -gt 0 ] && [ ${#sample_dirs[@]} -gt 0 ]; then
        avg_files_per_dir=$((sample_count / ${#sample_dirs[@]}))
    fi

    # Estimate total (with min of actual quick count)
    local estimate=$((dir_count * avg_files_per_dir))
    if [ "$estimate" -lt "$quick_estimate" ]; then
        echo "$quick_estimate"
    else
        echo "$estimate"
    fi
}

# Function to monitor file copy progress
# Parameters:
#   src: Source directory
#   dest: Destination directory
#   operation_name: Name of the operation for progress display
copy_with_progress() {
    debug "Starting copy_with_progress"
    local src="$1"
    local dest="$2"
    local operation_name="$3"

    # Count total files
    local total_files=$(find "$src" -type f | wc -l)
    local copied_files=0

    # Create destination if needed
    mkdir -p "$dest"

    # Use find to process files with progress
    find "$src" -type f | while read file; do
        # Get relative path
        local rel_path="${file#$src/}"

        # Create directory if needed
        mkdir -p "$(dirname "$dest/$rel_path")"

        # Copy file
        cp "$file" "$dest/$rel_path"

        # Update counter
        copied_files=$((copied_files + 1))

        # Update progress every 5 files
        if [ $((copied_files % 5)) -eq 0 ] || [ "$copied_files" -eq "$total_files" ]; then
            show_progress "$operation_name" "$copied_files" "$total_files" "Copied $copied_files of $total_files files"
        fi
    done
}

# Function to monitor composer installation progress with improved error handling
# Parameters:
#   directory: Directory where composer should run
#   [retry_count]: Optional retry count, defaults to 0 for initial call
# Returns:
#   0 if installation succeeded, non-zero if failed
composer_install_with_progress() {
    debug "Starting composer_install_with_progress"
    local directory="$1"
    local max_retries=2
    local retry_count=0

    cd "$directory" || {
        error "Failed to change to directory: $directory"
        return 1
    }

    # Set environment variables to optimize Composer
    export COMPOSER_MEMORY_LIMIT=2G
    export PHP_MEMORY_LIMIT=2G
    export COMPOSER_DISABLE_XDEBUG_WARN=1
    export COMPOSER_ALLOW_SUPERUSER=1
    export COMPOSER_NO_INTERACTION=1

    # Use an iterative approach for retries
    while [ $retry_count -le $max_retries ]; do
        # Log start of composer install
        _1_2_info "Starting composer install in $directory (attempt $((retry_count + 1)))"

        # Execute with progress tracking
        execute_with_progress "Composer Installation" \
            "sudo -u www-data composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader" \
            "total=100" "timeout=1800" "pulse=true"

        local exit_code=$?

        # Check for errors
        if [ "$exit_code" -ne 0 ]; then
            error "Composer installation failed with exit code $exit_code."

            # Check for memory issues in the log
            if grep -q "Out of memory" "$LOG_FILE" || grep -q "Allowed memory size" "$LOG_FILE"; then
                _1_4_warning "Composer ran out of memory. Trying with increased memory limit."

                # Increase memory limit for next attempt
                export COMPOSER_MEMORY_LIMIT=3G
                export PHP_MEMORY_LIMIT=3G

                # Increment retry count and continue to next iteration
                retry_count=$((retry_count + 1))

                # Check if we've exceeded max retries
                if [ "$retry_count" -gt "$max_retries" ]; then
                    error "Failed to install composer dependencies after $max_retries retries due to memory issues."
                    return 1
                fi

                _1_2_info "Retrying composer install with increased memory limit (attempt $((retry_count + 1)))..."
                # Continue to next iteration of the while loop
                continue
            fi

            # For other errors, check if we should retry
            if [ "$retry_count" -lt "$max_retries" ] &&
                (grep -q "failed to open stream: Timeout" "$LOG_FILE" ||
                    grep -q "Connection timed out" "$LOG_FILE" ||
                    grep -q "ConnectionException" "$LOG_FILE"); then
                _1_4_warning "Network issue detected. Retrying composer install..."
                retry_count=$((retry_count + 1))
                continue # Try again
            fi

            return $exit_code
        fi

        # If we got here, installation was successful
        1_3_success "Composer dependencies installed successfully."
        return 0
    done

    # If we've exhausted all retries
    error "Failed to install composer dependencies after multiple attempts."
    return 1
}

# Enhanced unified progress tracking function
# Parameters:
#   operation_name: Name of the operation for progress display
#   command: Command to execute (optional)
#   options: Options in key=value format (total=100 timeout=300 pulse=false indent=0 persist=false)
execute_with_progress() {
    debug "Starting execute_with_progress"
    local operation_name="$1"
    local command="$2"
    shift 2

    # Default options
    local total=100
    local timeout=300
    local pulse=false
    local indent=0
    local persist=false

    # Parse options
    for opt in "$@"; do
        key="${opt%%=*}"
        value="${opt#*=}"
        case "$key" in
        total) total="$value" ;;
        timeout) timeout="$value" ;;
        pulse) pulse="$value" ;;
        indent) indent="$value" ;;
        persist) persist="$value" ;;
        esac
    done

    # If no command provided, just show initial progress
    if [ -z "$command" ]; then
        show_progress "$operation_name" 0 "$total" "Starting..." "$persist" "$indent"
        return 0
    fi

    # Create temp files for output capture
    local output_file=$(mktemp)
    local error_file=$(mktemp)

    # Run command in background
    eval "$command" > >(tee -a "$LOG_FILE" >"$output_file") 2> >(tee -a "$LOG_FILE" >"$error_file") &
    local cmd_pid=$!

    # Monitor progress
    local start_time=$(date +%s)
    local progress=0
    local status="Starting..."
    local last_update=""

    while kill -0 $cmd_pid 2>/dev/null; do
        # Calculate current time and elapsed time
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Check for timeout
        if [ "$elapsed" -gt "$timeout" ]; then
            _1_4_warning "Command timed out after ${timeout}s. Killing process."
            kill -9 $cmd_pid 2>/dev/null || true
            show_progress "$operation_name" "$total" "$total" "Timed out" "true" "$indent"
            rm -f "$output_file" "$error_file"
            return 1
        fi

        # Get status from output file
        if [ -f "$output_file" ]; then
            local latest_output=$(tail -n1 "$output_file" | tr -d '\r\n' | cut -c 1-40)
            if [ -n "$latest_output" ]; then
                status="$latest_output..."
            fi
        fi

        # Calculate progress
        if [ "$pulse" = "true" ]; then
            # Pulsing progress (0-100-0-100) for indeterminate operations
            progress=$(((elapsed % 60) * 100 / 60))
        else
            # Linear progress based on time
            progress=$((elapsed * 90 / timeout))
            [ "$progress" -gt 90 ] && progress=90
        fi

        # Update progress display
        if [ "$status" != "$last_update" ] || [ $((current_time % 2)) -eq 0 ]; then
            show_progress "$operation_name" "$progress" "$total" "$status" "false" "$indent"
            last_update="$status"
        fi

        sleep 0.5
    done

    # Get command exit code
    wait $cmd_pid
    local exit_code=$?

    # Show final progress
    if [ "$exit_code" -eq 0 ]; then
        show_progress "$operation_name" "$total" "$total" "Completed successfully" "true" "$indent"
    else
        show_progress "$operation_name" "$total" "$total" "Completed with errors" "true" "$indent"

        # Log error information
        if [ -s "$error_file" ]; then
            error "Command errors:"
            cat "$error_file" >>"$LOG_FILE"
            tail -n 5 "$error_file" | while read -r line; do
                error "  $line"
            done
        fi
    fi

    # Clean up
    rm -f "$output_file" "$error_file"

    return $exit_code
}

# Function to run PHP Artisan commands with filtered output and progress tracking
# Parameters:
#   command: The artisan command to run
#   description: Description for the progress bar
# Returns:
#   The exit code of the command
run_artisan_command_with_progress() {
    local command="$1"
    local description="$2"

    debug "Running Artisan command: $command"
    _1_2_info "Running command: php artisan $command"

    # Execute with progress tracking
    execute_with_progress "$description" "sudo -u www-data php artisan $command" "pulse=true" "timeout=600"
    return $?
}

# Main system preparation function
# Returns:
#   0 if preparation succeeded, 1 if failed
prepare_system() {
    _1_2_info "Starting system preparation..."

    # Update system packages
    package_manager "update" "" || return 1

    # Ensure required commands (including Apache) are installed
    ensure_commands_installed "curl jq wget unzip openssl gpg tar apache2" || return 1

    # Optional: Validate Apache configuration if installed
    if command -v apachectl &>/dev/null || command -v httpd &>/dev/null; then
        apache_control "configtest" || return 1
    fi

    1_3_success "System preparation completed successfully."
    return 0
}

# Default settings
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
HAS_DOMAIN="${HAS_DOMAIN:-false}"

# ASCII Image (Splash screen)
cat <<"EOF"
                                          +*##########@@@                                           
                                       +****##########@@@@@@@                                       
                                      ******#########@@@@@@@@@                                      
                                    ++#*****#####@@%######@@@@@@                                    
                                   ++@******#####@@@@@@@@@@%#@@@@                                   
                                  ++@*******###########@@@@@@@#@@@                                  
                                 ++@********######%@@@@@@@@@@@@#@@@                                 
                                 +@++*******@@@@%###%@@@@@@@@@@@@@@@                                
                               #+@++*********####*:%###@@@@@@@@@@@@@@                               
                            #  +++++*****..@@@#########%@@@@@@@@@@@@@  @                            
                         #     +@+++**.########........######@@@@##@@     @                         
                      #       ++++++.######...............#####%@####@       @                      
                    #         ++++=######...................#####@.###         @                    
                  #          ++++.@#####.....................#####@.###          @                  
                #            +++.@@####.......................#####@.###                            
                            +++.@@##@....%@:...........:-@+....@###@@.##                            
                  @         *+.@@@#@@@@@%#...%-:....:-+...#@@@@@###@@@.##                           
                    @  @ @ **.@@@@@.#-##.@@@@@:::..- #+@@@@.+: *.@#@@@@.### #  #                    
                     @ @  **.@@@@#:.......-.%@@@%..@@@@=@-........#@@@@@##  # #                     
         @               +*.@@@@@@:....@@@..##@..... @**-.@@@....-#@@@@@:##               @         
        @         @      ** @@@@@@@*.@@@@@@@@.@@....@@.@@@@@@@@=-@@@@@@@@-##   # #         @        
       @                **.@@@@@#%#-...@@@@@@.*-#...@#.%@@@@@.:.+#@@@@@@@@##                @       
      @        @        *-@@@@@@#.............--:...--:............@@@@@@@+#        @        @      
     @        @         *.@@@@@@@..............-....-:.............@@@@@@@+##        @        @     
             @         #*.@@@@@@@..............-....-:.............@@@@@@@@##         @             
            @         ###.@@@@@@@#@............-....:+...........@#@@@@@@@@##          @            
   @               #    #.@@@@@@@@+%@@@@@......+....@......@@@@@@#%@@@@@@@%##   @               @   
            @         *###@@@@@@@@#-%:@.:.....@+....+@*....-*@@@++@@@@@@@@##@  #       @            
  @       @        #    ##@@@@@@@@@::@.@@#:....*@::@+....:+@@*@::@@@@@@@@@##             @       @  
         @ @      *#    ###@@@@@@@@@:.@@@@@@%.%@@@@@@#..+@@@:@..@@@@@@@@@###    ##                  
 @                 *     ##@@@@@@@@@@@. @==@@@@@@@@@@@@@@@.@@..@@@@@@@@@@##                         
 @                       ###@*@@@@@@@@@..@.@............@% @.-@@@@@@@@*@###                       @ 
                         #-#@@*@@@@@@@@@..@....:@@@@........@@@@@@@@@#@@###   #                     
                    +######=#@#%@@@@@@@@@+.-....@@@@*......@@@@@@@@@@#@########                     
                +****#######-#@*@@@@@@@@@@@.....:@@@.....-@@@@@@@@@@*@###########**                 
@@@@@@@@@@   ********########:@@*@@@@@@@@@@@....:@@#....@@@@@@@@@@@*@@##########*******   @@@@@@@@@@
         ************###@#####:@@*@@@@@@@@@@@@...@@-..@@@@@@@@@@@@*@@######@#####**********         
         ************###@######=@@*@@@@@%@@@@@@@@+@@@@@@@@@@@@@@@*@@@######@####***********         
      ++@@ **********###@#######@@@*@@@@@#@@@@@@@@@@@@@@@@@@@@@@*@@@#######@####********* @@+       
   ++++++@@@+********##@@@######%%@@*@@@@@#@@@@@@@@@@@@@@@@@@@@*@@%########@@###*******+@@%*+++++   
+++++++++***@ ******+##@@@#######@#@@*@@@@@#@@@@@@@@@@@@@#@@@@*@@%@########@@###****** @****++++++++
  ++++++******@ ****+##@@@#######@@#+@*@@@@##@@@@@@@@@@@#@@@@#@#%@@#######@@@####*** @*******+++++  
     +++*******% +**###@@@#######@@@#+@@@@@@#@@@@@@@@@@#@@@@@@*#@@@#######@@@####** @#*******++     
          +******* #####@@########@@@%+@@@@@@#@@@@@@@@##@@@@@%#@@@@#######@@%#### #####**+          
         @    +**** ####%@@#######@@@@#%#@@@@##@@@@@@##@@@@*@#@@@@@######@@@#### #####    @         
          @       #######%@@#######@@@@+@@@@@@#@@@@@@#@@@@@@+@@@@@@@####@@@#######*                 
                   #######@@@#######@@@@+@@@@@##@@@@@#@@@@@+#@@@@@@@####@@#######                   
                     ######@@@######@@@@#+@@@@@#@@@@#%@@@@##@@@@@@@@##%@@@#####                     
                      ######@@@######@@@@+@@@@@#@@@@#@@@@@+@@@@@@@@@#@@@@@####         @            
                       ######@@@######@@@#+@@@@#@@@@#@@@@@#@@@@@@@@@@@@@@@@##         @             
                         #####@@@#####@@@%+@@@@@@@@@@@@@@+@@@@@@@@@@@@@@@@@                         
                         @   #@@@@@##%@@@@+@@@@@#@@@@@@@@+@@@@@@@@ @@@@                             
                 @     @        @@@@#@@@@@+@@@@@#@@#@@@@@+@@@@@@@@  @       @     @                 
                     @           # @@@@@@@%@@@@@#@@#@@@@@+@@@@@@@  @          @                     
                   @@            @   @@@@@@@@@@@@@@#@@@@@*@@@@@@ @@@ @         @@                   
                      @                @@@@@@@@@@@@@@@@@@%@@@       @                               
                        @                @@@@@@@@  @@@@@@@@       @@@@                              
                          @               @@@@@@@  @@@@@@@       @@@ @   @                          
                                            @@@@@  @@@@@          @@@  @                            
                               @             @@@@  @@@@            @@                               
                                               @@@ @@                                               
                                                @ @@                                                
EOF

# Global Variables
MYSQL_ROOT_PASS=""
DB_NAME=""
DB_USER=""
DB_PASS=""
STATIC_CRON_TOKEN=""
APP_KEY=""
CRON_HOUR=""
CREDENTIALS_FILE="$HOME/firefly_credentials.txt"

#####################################################################################################################################################
#
#   SCRIPT FUNCTIONS
#
#####################################################################################################################################################

# Function to set up the log file for the current run
# Creates a new log file and sets up log rotation
setup_log_file() {
    debug "Starting setup_log_file"
    LOG_DIR="/var/log"                                     # Directory for storing log files
    TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')                 # Timestamp to make the log file unique
    LOG_FILE="${LOG_DIR}/firefly_install_${TIMESTAMP}.log" # New log file for this run

    # Ensure the log directory exists with error handling
    if [ ! -d "$LOG_DIR" ]; then
        echo "Log directory $LOG_DIR does not exist. Creating it now..."
        if ! mkdir -p "$LOG_DIR"; then
            echo "Failed to create log directory at $LOG_DIR. Please check your permissions."
            exit 1
        fi
    fi

    # Ensure the log directory is writable
    if [ ! -w "$LOG_DIR" ]; then
        echo "Setting correct permissions on $LOG_DIR..."
        if ! chmod 755 "$LOG_DIR"; then
            echo "Failed to set correct permissions on $LOG_DIR. Please check your permissions."
            exit 1
        fi
    fi

    # Create the new log file for this run
    if ! touch "$LOG_FILE"; then
        echo "Failed to create log file: $LOG_FILE"
        exit 1
    fi

    chmod 666 "$LOG_FILE" # Ensure the log file is writable by the script

    # Clean up old logs
    cleanup_old_logs
}

# Function to clean up old log files by age and number of logs
# Parameters:
#   None - Uses global constants for configuration
cleanup_old_logs() {
    debug "Starting cleanup_old_logs"
    LOG_DIR="/var/log"                # Directory where logs are stored
    LOG_FILE_PREFIX="firefly_install" # Prefix for your log files
    MAX_LOG_AGE=7                     # Maximum number of days to keep logs (e.g., 7 days)
    MAX_LOG_COUNT=5                   # Maximum number of logs to retain

    # Check if the log directory exists, and if not, create it
    if [ ! -d "$LOG_DIR" ]; then
        echo "Log directory $LOG_DIR does not exist. Creating it now..."
        mkdir -p "$LOG_DIR" || {
            echo "Failed to create log directory $LOG_DIR"
            exit 1
        }
        chmod 700 "$LOG_DIR" || {
            echo "Failed to set permissions on $LOG_DIR"
            exit 1
        }
    fi

    # Find and delete log files older than MAX_LOG_AGE days
    find "$LOG_DIR" -name "${LOG_FILE_PREFIX}*.log" -type f -mtime +$MAX_LOG_AGE -exec rm {} \;

    # Find log files and check if the number exceeds MAX_LOG_COUNT
    log_files=($(ls -1t "$LOG_DIR"/${LOG_FILE_PREFIX}*.log 2>/dev/null)) # List logs by modified time, newest first
    log_count=${#log_files[@]}

    if [ "$log_count" -gt "$MAX_LOG_COUNT" ]; then
        logs_to_delete=$((log_count - MAX_LOG_COUNT))
        _1_2_info "Deleting $logs_to_delete oldest logs to maintain $MAX_LOG_COUNT logs."

        # Loop to delete the oldest logs
        for ((i = MAX_LOG_COUNT; i < log_count; i++)); do
            rm -f "${log_files[i]}"
            _1_2_info "Deleted old log file: ${log_files[i]}"
        done
    fi

    # Print a message indicating which log files were deleted
    _1_2_info "Log cleanup completed. Retaining up to $MAX_LOG_COUNT logs."
}

# Function to validate password strength
# Parameters:
#   password: The password to validate
# Returns:
#   0 if password is strong enough, 1 if too weak
validate_password_strength() {
    debug "Starting validate_password_strength"
    local password="$1"
    local min_length=8

    # Check minimum length
    if [ ${#password} -lt $min_length ]; then
        return 1
    fi

    # Check for at least one number
    if ! echo "$password" | grep -q '[0-9]'; then
        return 1
    fi

    # Check for at least one special character
    if ! echo "$password" | grep -q '[^A-Za-z0-9]'; then
        return 1
    fi

    # Password meets requirements
    return 0
}

# Function to properly escape MySQL special characters to prevent SQL injection
#
# This function performs comprehensive escaping of MySQL special characters
# to ensure that user-provided inputs can be safely used in SQL statements.
# It handles backslashes, quotes, NULL bytes, newlines, and other special chars.
#
# Parameters:
#   string: String to escape
# Returns:
#   Escaped string via stdout
# Usage:
#   safe_value=$(mysql_escape "User's input with special ' chars")
#   mysql -e "SELECT * FROM table WHERE name = '$safe_value'"
mysql_escape() {
    debug "Starting mysql_escape with input length: ${#1}"
    local string="$1"

    # Handle empty input
    if [ -z "$string" ]; then
        echo ""
        return 0
    fi

    # Perform comprehensive escaping:
    # 1. Backslashes must be doubled
    # 2. Single quotes must be escaped with a backslash
    # 3. Double quotes must be escaped with a backslash
    # 4. NUL bytes become \0
    # 5. Newlines become \n
    # 6. Carriage returns become \r
    # 7. Ctrl-Z becomes \Z
    local escaped
    escaped=$(echo "$string" | sed -e 's/\\/\\\\/g' \
        -e "s/'/\\'/g" \
        -e 's/"/\\"/g' \
        -e 's/\x00/\\0/g' \
        -e 's/\n/\\n/g' \
        -e 's/\r/\\r/g' \
        -e 's/\x1A/\\Z/g')

    echo "$escaped"

    # Log the escaping activity without exposing the full string
    local input_length=${#string}
    local output_length=${#escaped}
    debug "Escaped MySQL string of length $input_length → $output_length"

    return 0
}

# Function to safely remove directories with validation checks
# Parameters:
#   dir_to_remove: The directory to remove
# Returns:
#   0 if removal succeeded, 1 if checks failed or removal failed
safe_remove_directory() {
    debug "Starting safe_remove_directory function..."
    local dir_to_remove="$1"

    # Safety check 1: Verify we're not removing critical directories
    if [[ "$dir_to_remove" == "/" || "$dir_to_remove" == "/etc" || "$dir_to_remove" == "/var" ||
        "$dir_to_remove" == "/usr" || "$dir_to_remove" == "/bin" || "$dir_to_remove" == "/boot" ||
        "$dir_to_remove" == "/home" || "$dir_to_remove" == "/root" || -z "$dir_to_remove" ]]; then
        error "SAFETY CHECK FAILED: Refusing to remove critical directory: $dir_to_remove"
        return 1
    fi

    # Safety check 2: Check for suspiciously short path length
    if [ ${#dir_to_remove} -lt 10 ]; then
        error "SAFETY CHECK FAILED: Directory path suspiciously short: $dir_to_remove"
        return 1
    fi

    # Safety check 3: Confirm directory exists
    if [ ! -d "$dir_to_remove" ]; then
        _1_4_warning "Directory doesn't exist: $dir_to_remove. Nothing to remove."
        return 0
    fi

    # Safety check 4: Ensure directory is within expected path for web applications
    if [[ "$dir_to_remove" != /var/www/* && "$dir_to_remove" != /tmp/* ]]; then
        error "SAFETY CHECK FAILED: Directory is outside expected paths: $dir_to_remove"
        return 1
    fi

    # Safety check 5: Additional check for path normalization to prevent tricks with ../ etc.
    local normalized_path=$(cd "$dir_to_remove" 2>/dev/null && pwd)
    if [ -z "$normalized_path" ]; then
        error "SAFETY CHECK FAILED: Could not normalize path: $dir_to_remove"
        return 1
    fi

    if [[ "$normalized_path" == "/" || "$normalized_path" == "/etc" || "$normalized_path" == "/var" ||
        "$normalized_path" == "/usr" || "$normalized_path" == "/bin" || "$normalized_path" == "/boot" ||
        "$normalized_path" == "/home" || "$normalized_path" == "/root" ]]; then
        error "SAFETY CHECK FAILED: Normalized path is a critical directory: $normalized_path"
        return 1
    fi

    # Proceed with removal
    _1_2_info "Safely removing directory: $dir_to_remove"
    rm -rf "$dir_to_remove"
    local result=$?

    if [ $result -eq 0 ]; then
        1_3_success "Directory successfully removed: $dir_to_remove"
    else
        error "Failed to remove directory: $dir_to_remove"
    fi

    return $result
}

# Function to safely empty a directory without deleting the directory itself
# Parameters:
#   dir_to_empty: The directory to empty
# Returns:
#   0 if emptying succeeded, 1 if checks failed or emptying failed
safe_empty_directory() {
    debug "Starting safe_empty_directory"
    local dir_to_empty="$1"

    # Safety check 1: Verify we're not emptying critical directories
    if [[ "$dir_to_empty" == "/" || "$dir_to_empty" == "/etc" || "$dir_to_empty" == "/var" ||
        "$dir_to_empty" == "/usr" || "$dir_to_empty" == "/bin" || "$dir_to_empty" == "/boot" ||
        -z "$dir_to_empty" ]]; then
        error "SAFETY CHECK FAILED: Refusing to empty critical directory: $dir_to_empty"
        return 1
    fi

    # Safety check 2: Confirm directory exists
    if [ ! -d "$dir_to_empty" ]; then
        _1_4_warning "Directory doesn't exist: $dir_to_empty. Nothing to empty."
        return 0
    fi

    # Safety check 3: Ensure directory is within expected path for web applications
    if [[ "$dir_to_empty" != /var/www/* && "$dir_to_empty" != /tmp/* ]]; then
        error "SAFETY CHECK FAILED: Directory is outside expected paths: $dir_to_empty"
        return 1
    fi

    # Proceed with emptying
    _1_2_info "Safely emptying directory: $dir_to_empty"
    find "$dir_to_empty" -mindepth 1 -delete
    local result=$?

    if [ $result -eq 0 ]; then
        1_3_success "Directory successfully emptied: $dir_to_empty"
    else
        error "Failed to empty directory: $dir_to_empty"
    fi

    return $result
}

# Function to validate or set environment variables in .env file
# Parameters:
#   var_name: The variable name to set/update in the .env file
#   var_value: The value to set for the variable
validate_env_var() {
    debug "Starting validate_env_var"
    local var_name=$1
    local var_value=$2

    # Check if the variable exists and has the correct value
    if grep -q "^${var_name}=.*" "$FIREFLY_INSTALL_DIR/.env"; then
        sed -i "s|^${var_name}=.*|${var_name}=${var_value}|" "$FIREFLY_INSTALL_DIR/.env"
    else
        echo "${var_name}=${var_value}" >>"$FIREFLY_INSTALL_DIR/.env"
    fi

    # Indicate successful completion
    return 0
}

# General countdown function with dynamic box size and padding for single digits
# Parameters:
#   MESSAGE: The message to display during countdown
#   COLOR: The color to use for the countdown box
countdown_timer() {
    local SECONDS_LEFT=30
    local MESSAGE=$1
    local COLOR=$2
    local INPUT_RECEIVED=false

    # Calculate box width based on message length and countdown seconds
    local TOTAL_MESSAGE="${MESSAGE} ${SECONDS_LEFT}s..."
    local BOX_WIDTH=$((${#TOTAL_MESSAGE} + 2)) # 2 accounts for box characters │ │
    local BOX_TOP="┌$(printf '─%.0s' $(seq 1 $BOX_WIDTH))┐"
    local BOX_BOTTOM="└$(printf '─%.0s' $(seq 1 $BOX_WIDTH))┘"

    # Print the initial dynamic countdown box
    echo -e "${COLOR}${BOX_TOP}${COLOR_RESET}"
    printf "${COLOR}│ ${COLOR_GREEN}%s${COLOR} │${COLOR_RESET}\n" "$TOTAL_MESSAGE"
    echo -e "${COLOR}${BOX_BOTTOM}${COLOR_RESET}"
    echo "" # Add a blank line after the box at its inception

    # Countdown logic with live update
    while [ $SECONDS_LEFT -gt 0 ]; do
        # Wait for user input with a timeout of 1 second (matches the countdown speed)
        if read -t 1 -n 1 mode; then
            INPUT_RECEIVED=true
            break
        fi

        SECONDS_LEFT=$((SECONDS_LEFT - 1))

        # Adjust padding for single-digit seconds
        if [ $SECONDS_LEFT -lt 10 ]; then
            TOTAL_MESSAGE="${MESSAGE} ${SECONDS_LEFT}s... "
        else
            TOTAL_MESSAGE="${MESSAGE} ${SECONDS_LEFT}s..."
        fi

        # Recalculate box width for the updated message
        BOX_WIDTH=$((${#TOTAL_MESSAGE} + 2))
        BOX_TOP="┌$(printf '─%.0s' $(seq 1 $BOX_WIDTH))┐"
        BOX_BOTTOM="└$(printf '─%.0s' $(seq 1 $BOX_WIDTH))┘"

        # Move the cursor up to overwrite the previous box (4 lines total: top, content, bottom, and the blank line)
        echo -ne "\033[4A" # Move cursor up 4 lines (3 lines for the box + 1 for the blank line)

        # Clear the previous content of the box and redraw
        echo -ne "\033[2K" # Clear the entire line (box top)
        echo -e "${COLOR}${BOX_TOP}${COLOR_RESET}"

        echo -ne "\033[2K" # Clear the entire line (box content)
        printf "${COLOR}│ ${COLOR_GREEN}%s${COLOR} │${COLOR_RESET}\n" "$TOTAL_MESSAGE"

        echo -ne "\033[2K" # Clear the entire line (box bottom)
        echo -e "${COLOR}${BOX_BOTTOM}${COLOR_RESET}"

        # Clear the blank line and print a new one
        echo -ne "\033[2K" # Clear the entire line (blank line)
        echo ""            # Add a blank line after the box
    done

    # Fallback if no input was received, assume non-interactive mode
    if [[ $INPUT_RECEIVED == false ]]; then
        mode=""
    fi
}

# Function to display the mode options and prompt
# Parameters:
#   None - Sets global variables based on user input
display_mode_options() {
    # Set the flag to true to indicate countdown is called from this function
    FROM_DISPLAY_MODE=true

    echo -e "\n───────────────────────────────────────────────────────────────────────────"
    echo -e "\nℹ ${COLOR_CYAN}[INFO]${COLOR_RESET} ${BOLD}To continue:${RESET}"
    echo -e "\n   • Type 'M' to view the ${BOLD}Menu${RESET}."
    echo -e "   • Press [Enter] to proceed in ${BOLD}non-interactive mode${RESET}."
    echo -e "   • Type 'I' to switch to ${BOLD}interactive mode${RESET}."
    echo -e "   • Type 'C' to ${BOLD}cancel${RESET} and exit the script.\n"
    echo -e "───────────────────────────────────────────────────────────────────────────\n"

    countdown_timer "Continuing in non-interactive mode in" "$COLOR_YELLOW"

    # Reset the flag after countdown is complete
    FROM_DISPLAY_MODE=false

    # Process user input after the countdown
    case "$mode" in
    "M" | "m")
        display_menu
        ;;
    "C" | "c")
        echo -e "\n\n${COLOR_RED}Script cancelled by the user.${COLOR_RESET}\n"
        exit 0
        ;;
    "I" | "i")
        echo -e "\n\n${COLOR_GREEN}Interactive mode selected.${COLOR_RESET}\n"
        NON_INTERACTIVE=false
        ;;
    *)
        echo -e "\n\n${COLOR_YELLOW}Non-interactive mode selected.${COLOR_RESET}\n"
        NON_INTERACTIVE=true
        ;;
    esac
}

# Function to offer user a choice to return to the menu or main flow after a menu selection
# Parameters:
#   None - Uses global variables and prompts for user input
return_or_menu_prompt() {
    echo -e "${BOLD}Would you like to:${RESET}"
    echo -e "  1) Return to the main script"
    echo -e "  2) Return to the menu"
    echo -e "  3) Exit the Script\n"
    echo -e "───────────────────────────────────────────────────────────────────────────\n"

    countdown_timer "Returning to the main script in" "$COLOR_YELLOW"

    case "$mode" in
    "1")
        echo -e "\n\n${COLOR_YELLOW}Returning to the main script.${COLOR_RESET}"
        display_mode_options
        ;;
    "2")
        echo -e "\n\n${COLOR_YELLOW}Returning to the menu.${COLOR_RESET}"
        display_menu
        ;;
    "3")
        echo -e "\n\n${COLOR_RED}Script cancelled by the user.${COLOR_RESET}"
        exit 0
        ;;
    *)
        echo -e "\n\n${COLOR_YELLOW}No valid choice made. Returning to the main flow.${COLOR_RESET}\n"
        display_mode_options
        ;;
    esac

    # Indicate successful completion
    return 0
}

# Function to display the menu with options
# Parameters:
#   None - Uses global variables and prompts for user input
display_menu() {
    echo -e "\n\n───────────────────────────────────────────────────────────────────────────"
    echo -e "\n${BOLD}Select an option to view details:${RESET}"
    echo -e "  1) Interactive Mode Details"
    echo -e "  2) Non-Interactive Mode Details"
    echo -e "  3) Fully Non-Interactive Mode Details"
    echo -e "  4) Return to the main script"
    echo -e "  5) Exit the Script\n"
    echo -e "───────────────────────────────────────────────────────────────────────────"

    countdown_timer "Returning to the main script in" "$COLOR_YELLOW"

    # Process user input after the countdown
    case "$mode" in
    "1")
        echo -e "\n\n───────────────────────────────────────────────────────────────────────────"
        echo -e "\n✔ ${COLOR_GREEN}Interactive Mode:${COLOR_RESET}"
        echo -e "    - You will be prompted to provide the following information:"
        echo -e "      • Database name"
        echo -e "      • Database user"
        echo -e "      • Database password"
        echo -e "      • PHP version preference"
        echo -e "      • Option to retain older PHP versions"
        echo -e "      • Domain name (optional)"
        echo -e "      • Email address for SSL certificates (optional)\n"
        echo -e "───────────────────────────────────────────────────────────────────────────\n"
        return_or_menu_prompt
        ;;
    "2")
        echo -e "\n\n───────────────────────────────────────────────────────────────────────────"
        echo -e "\n⚠ ${COLOR_YELLOW}[WARNING]${COLOR_RESET} ${BOLD}Non-Interactive Mode:${RESET}"
        echo -e "    - The script will automatically use default values for database names, credentials, and other settings."
        echo -e "    - Best for automated deployments or when you're comfortable with the default configuration.\n"
        echo -e "ℹ ${COLOR_CYAN}${BOLD}Important Note:${RESET}"
        echo -e "    - In non-interactive mode, the following default values will be used unless overridden by environment variables:\n"
        echo -e "      • Database Name: ${DB_NAME:-[Generated]}"
        echo -e "      • Database User: ${DB_USER:-[Generated]}"
        echo -e "      • Database Password: [Generated]"
        echo -e "      • PHP Version: ${LATEST_PHP_VERSION:-[Latest Available]}"
        echo -e "      • Domain Name: ${DOMAIN_NAME:-[None]}"
        echo -e "      • SSL Certificate: ${HAS_DOMAIN:-false} (A self-signed certificate will be created if no domain is set)\n"
        echo -e "    - This mode is ideal for automation environments where no user input is expected.\n"
        echo -e "───────────────────────────────────────────────────────────────────────────\n"
        return_or_menu_prompt
        ;;
    "3")
        echo -e "\n\n───────────────────────────────────────────────────────────────────────────"
        echo -e "\nℹ ${COLOR_CYAN}[INFO]${COLOR_RESET} ${BOLD}Fully Non-Interactive Mode:${RESET}"
        echo -e "    To run the script without any user prompts, you can pass the necessary settings as environment variables."
        echo -e "    This is useful for automated deployments or headless execution (e.g., in CI/CD pipelines).\n"
        echo -e "    ${BOLD}Usage:${RESET}"
        echo -e "      1. Set the required environment variables before executing the script."
        echo -e "      2. Use the \`--non-interactive\` flag to skip all prompts.\n"
        echo -e "    ${BOLD}Required Variables:${RESET}"
        echo -e "      • \`DB_NAME\`: The name of the database to create"
        echo -e "      • \`DB_USER\`: The database user to assign"
        echo -e "      • \`DB_PASS\`: The database user password"
        echo -e "      • \`DOMAIN_NAME\`: The domain name for SSL setup (optional)"
        echo -e "      • \`HAS_DOMAIN\`: Set to \`true\` if using a custom domain with SSL certificates"
        echo -e "      • \`EMAIL_ADDRESS\`: The email address for SSL certificate registration (optional)"
        echo -e "      • \`GITHUB_TOKEN\`: Your GitHub token for downloading Firefly releases (optional)"
        echo -e "      • \`PHP_VERSION\`: The PHP version to install (optional)\n"
        echo -e "    ${BOLD}Example Command:${RESET}"
        echo -e "      \`DB_NAME=mydb DB_USER=myuser DB_PASS=mypassword DOMAIN_NAME=mydomain.com HAS_DOMAIN=true ./firefly.sh --non-interactive\`\n"
        echo -e "    This command will:"
        echo -e "      • Set the database name to 'mydb'"
        echo -e "      • Set the database user to 'myuser'"
        echo -e "      • Set the database password to 'mypassword'"
        echo -e "      • Set the domain name to 'mydomain.com'"
        echo -e "      • Enable SSL certificates for the specified domain\n"
        echo -e "    This mode is useful for automated deployments or headless execution (e.g., in CI/CD pipelines).\n"
        echo -e "───────────────────────────────────────────────────────────────────────────\n"
        return_or_menu_prompt
        ;;
    "4")
        echo -e "\n\n${COLOR_YELLOW}Returning to the main script.${COLOR_RESET}\n"
        display_mode_options
        ;;
    "5")
        echo -e "\n\n${COLOR_RED}Script cancelled by the user.${COLOR_RESET}\n"
        exit 0
        ;;
    *)
        echo -e "\n\n${COLOR_YELLOW}Returning to the main script.${COLOR_RESET}\n"
        display_mode_options
        ;;
    esac

    # Indicate successful completion
    return 0
}

# Comprehensive PHP version management function
# This function handles PHP detection, installation, configuration, and extension management
# across different distributions
#
# Parameters:
#   action: Action to perform (detect, install, configure, check-extension, install-extension)
#   version: PHP version to use (optional, defaults to latest available)
#   extension: Name of extension for check/install actions (optional)
#
# Returns:
#   For detect action: Returns the detected PHP version via stdout
#   For other actions: Returns 0 if successful, 1 if failed
php_manager() {
    debug "Starting php_manager function with action: $1, version: $2, extension: $3"
    local action="$1"
    local version="$2"
    local extension="$3"
    local result=0

    # Step 1: Define PHP package names and configurations for different distributions
    declare -A php_packages=(
        ["debian"]="php VERSION php VERSION-fpm libapache2-mod-php VERSION"
        ["rhel"]="php php-fpm mod_php"
        ["alpine"]="php VERSION php VERSION-fpm php VERSION-apache2"
    )

    declare -A php_extensions=(
        ["debian"]="php VERSION-EXTENSION"
        ["rhel"]="php-EXTENSION"
        ["alpine"]="php VERSION-EXTENSION"
    )

    declare -A php_service=(
        ["debian"]="php VERSION-fpm"
        ["rhel"]="php-fpm"
        ["alpine"]="php-fpm VERSION"
    )

    declare -A php_conf_dir=(
        ["debian"]="/etc/php/VERSION/SAPI"
        ["rhel"]="/etc/php.d"
        ["alpine"]="/etc/php VERSION/SAPI"
    )

    # Step 2: Process the requested action
    case "$action" in
    "detect")
        debug "Detecting PHP version"
        local php_command=""

        # Find PHP command
        for cmd in php php8.2 php8.1 php8.0 php7.4 php7.3; do
            if command -v "$cmd" &>/dev/null; then
                php_command="$cmd"
                break
            fi
        done

        # If PHP command found, get its version
        if [ -n "$php_command" ]; then
            local installed_version
            installed_version=$("$php_command" -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")

            if [ -n "$installed_version" ]; then
                echo "$installed_version"
                debug "Detected PHP version: $installed_version"
                return 0
            else
                debug "Failed to get PHP version from $php_command"
                echo ""
                return 1
            fi
        else
            # If no PHP command found, try to detect from package manager
            case "$os_type" in
            "debian")
                local php_pkg=$(dpkg -l | grep -E '^ii +php[0-9]+\.[0-9]+ ' | head -n1 | awk '{print $2}')
                if [ -n "$php_pkg" ]; then
                    local detected_version=$(echo "$php_pkg" | grep -oP 'php\K[0-9]+\.[0-9]+')
                    if [ -n "$detected_version" ]; then
                        echo "$detected_version"
                        debug "Detected PHP version from package: $detected_version"
                        return 0
                    fi
                fi
                ;;

            "rhel")
                local php_version=$(rpm -qa | grep -oP 'php-[0-9]+\.[0-9]+' | sort -u | head -n1)
                if [ -n "$php_version" ]; then
                    local detected_version=$(echo "$php_version" | grep -oP '[0-9]+\.[0-9]+')
                    if [ -n "$detected_version" ]; then
                        echo "$detected_version"
                        debug "Detected PHP version from package: $detected_version"
                        return 0
                    fi
                fi
                ;;

            "alpine")
                local php_version=$(apk _1_2_info | grep -oP 'php[0-9]+' | sort -u | head -n1)
                if [ -n "$php_version" ]; then
                    local detected_version=$(echo "$php_version" | grep -oP '[0-9]+')
                    # Format Alpine PHP version (e.g., php81 -> 8.1)
                    detected_version="${detected_version:0:1}.${detected_version:1}"
                    if [ -n "$detected_version" ]; then
                        echo "$detected_version"
                        debug "Detected PHP version from package: $detected_version"
                        return 0
                    fi
                fi
                ;;
            esac

            debug "No PHP version detected"
            echo ""
            return 1
        fi
        ;;

    "install")
        debug "Installing PHP version: $version"

        # Ensure version is specified
        if [ -z "$version" ]; then
            error "PHP version must be specified for installation"
            return 1
        fi

        # Prepare package names by replacing VERSION placeholder
        local packages="${php_packages[$os_type]}"
        packages="${packages//VERSION/$version}"

        # Skip version suffix for RHEL/CentOS systems which handle PHP version differently
        if [ "$os_type" = "rhel" ]; then
            # Enable appropriate module on RHEL systems
            if command -v dnf &>/dev/null; then
                _1_2_info "Enabling PHP $version module for RHEL/CentOS"
                dnf module reset php -y
                dnf module enable php:remi-$version -y
            fi
        fi

        # Install packages
        _1_2_info "Installing PHP $version packages: $packages"
        if ! package_manager install "$packages"; then
            error "Failed to install PHP $version packages"
            return 1
        fi

        # Install essential extensions
        local essential_extensions="bcmath intl curl zip gd xml mbstring mysql sqlite3"
        for ext in $essential_extensions; do
            if ! php_manager "install-extension" "$version" "$ext"; then
                _1_4_warning "Failed to install PHP extension: $ext"
                # Continue despite extension installation failure
            fi
        done

        # Enable PHP for Apache
        case "$os_type" in
        "debian")
            _1_2_info "Enabling PHP $version for Apache"
            a2dismod php* 2>/dev/null || true
            a2enmod php$version
            ;;

        "rhel")
            _1_2_info "Configuring PHP-FPM for Apache"
            # Create Apache PHP-FPM configuration
            cat <<EOF >/etc/httpd/conf.d/php-fpm.conf
<FilesMatch \.php$>
    SetHandler "proxy:unix:/var/run/php-fpm/www.sock|fcgi://localhost"
</FilesMatch>
EOF
            ;;

        "alpine")
            _1_2_info "Configuring PHP for Apache"
            # Ensure PHP module is loaded in Apache
            if ! grep -q "LoadModule php${version/./}_module" /etc/apache2/httpd.conf; then
                echo "LoadModule php${version/./}_module modules/mod_php${version/./}.so" >>/etc/apache2/httpd.conf
            fi
            ;;
        esac

        # Restart Apache to apply changes
        _1_2_info "Restarting Apache to apply PHP configuration"
        apache_control restart

        # Verify installation
        if php -v | grep -q "PHP $version"; then
            1_3_success "Successfully installed PHP $version"
            return 0
        else
            _1_4_warning "PHP $version seems installed but not activated as default"
            return 1
        fi
        ;;

    "configure")
        debug "Configuring PHP version: $version"

        # Determine current PHP version if not specified
        if [ -z "$version" ]; then
            version=$(php_manager "detect")
            if [ -z "$version" ]; then
                error "Could not detect PHP version to configure"
                return 1
            fi
        fi

        # Determine config directories
        local fpm_conf_dir="${php_conf_dir[$os_type]//VERSION/$version}"
        fpm_conf_dir="${fpm_conf_dir//SAPI/fpm}"

        local apache_conf_dir="${php_conf_dir[$os_type]//VERSION/$version}"
        apache_conf_dir="${apache_conf_dir//SAPI/apache2}"

        local cli_conf_dir="${php_conf_dir[$os_type]//VERSION/$version}"
        cli_conf_dir="${cli_conf_dir//SAPI/cli}"

        # Special case for RHEL/CentOS
        if [ "$os_type" = "rhel" ]; then
            fpm_conf_dir="/etc/php-fpm.d"
            apache_conf_dir="/etc/php.d"
            cli_conf_dir="/etc/php.d"
        fi

        # Configure PHP settings for each SAPI
        for conf_dir in "$fpm_conf_dir" "$apache_conf_dir" "$cli_conf_dir"; do
            if [ -d "$conf_dir" ]; then
                local php_ini="$conf_dir/php.ini"

                if [ -f "$php_ini" ]; then
                    _1_2_info "Configuring PHP settings in $php_ini"

                    # Create backup of original php.ini
                    cp "$php_ini" "${php_ini}.backup"

                    # Configure optimized settings for Firefly III
                    sed -i 's/memory_limit = .*/memory_limit = 512M/' "$php_ini"
                    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$php_ini"
                    sed -i 's/post_max_size = .*/post_max_size = 64M/' "$php_ini"
                    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$php_ini"
                    sed -i 's/max_input_time = .*/max_input_time = 300/' "$php_ini"

                    # Enable recommended settings for security
                    sed -i 's/expose_php = .*/expose_php = Off/' "$php_ini"

                    # Configure date.timezone if not set
                    if grep -q '^;date.timezone =' "$php_ini" || ! grep -q '^date.timezone =' "$php_ini"; then
                        timezone=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || echo "UTC")
                        sed -i "s/;date.timezone =.*/date.timezone = $timezone/" "$php_ini"
                        if ! grep -q "^date.timezone = " "$php_ini"; then
                            echo "date.timezone = $timezone" >>"$php_ini"
                        fi
                    fi
                else
                    _1_4_warning "PHP configuration file not found at $php_ini"
                fi
            fi
        done

        # Restart PHP-FPM if it's in use
        local php_fpm_service="${php_service[$os_type]//VERSION/$version}"
        if systemctl list-units --type=service | grep -q "$php_fpm_service"; then
            _1_2_info "Restarting PHP-FPM service: $php_fpm_service"
            systemctl restart "$php_fpm_service"
        fi

        # Restart Apache to apply changes
        _1_2_info "Restarting Apache to apply PHP configuration changes"
        apache_control restart

        1_3_success "PHP $version configured successfully for Firefly III"
        return 0
        ;;

    "check-extension")
        debug "Checking PHP extension: $extension for version: $version"

        # Ensure extension is specified
        if [ -z "$extension" ]; then
            error "Extension name must be specified for check-extension action"
            return 1
        fi

        # Determine current PHP version if not specified
        if [ -z "$version" ]; then
            version=$(php_manager "detect")
            if [ -z "$version" ]; then
                error "Could not detect PHP version to check extension"
                return 1
            fi
        fi

        # Check if extension is loaded
        if php -m | grep -i -q "$extension"; then
            debug "PHP extension $extension is already loaded"
            return 0
        else
            debug "PHP extension $extension is not loaded"
            return 1
        fi
        ;;

    "install-extension")
        debug "Installing PHP extension: $extension for version: $version"

        # Ensure extension is specified
        if [ -z "$extension" ]; then
            error "Extension name must be specified for install-extension action"
            return 1
        fi

        # Determine current PHP version if not specified
        if [ -z "$version" ]; then
            version=$(php_manager "detect")
            if [ -z "$version" ]; then
                error "Could not detect PHP version to install extension"
                return 1
            fi
        fi

        # Skip if extension is already installed
        if php_manager "check-extension" "$version" "$extension"; then
            _1_2_info "PHP extension $extension is already installed"
            return 0
        fi

        # Prepare package name for the extension
        local ext_package="${php_extensions[$os_type]}"
        ext_package="${ext_package//VERSION/$version}"
        ext_package="${ext_package//EXTENSION/$extension}"

        # Handle special cases for extension naming
        if [ "$extension" = "mysql" ] && [ "$os_type" = "debian" ]; then
            ext_package="php$version-mysql"
            if ! apt-cache show "php$version-mysql" &>/dev/null; then
                ext_package="php$version-mysqlnd"
            fi
        elif [ "$extension" = "mysql" ] && [ "$os_type" = "rhel" ]; then
            ext_package="php-mysqlnd"
        fi

        # Install the extension
        _1_2_info "Installing PHP extension: $ext_package"
        if ! package_manager install "$ext_package"; then
            _1_4_warning "Failed to install PHP extension package: $ext_package"
            return 1
        fi

        # Check if installation was successful
        if php_manager "check-extension" "$version" "$extension"; then
            1_3_success "PHP extension $extension installed successfully"
            return 0
        else
            _1_4_warning "PHP extension $extension was not properly loaded after installation"
            return 1
        fi
        ;;

    *)
        error "Unknown PHP manager action: $action"
        return 1
        ;;
    esac
}

# Function to manage services with cross-distribution compatibility
manage_service() {
    local service_name="$1"
    local action="$2"

    debug "Managing service $service_name, action: $action"

    case "$INIT_SYSTEM" in
    "systemd")
        _1_2_info "Using systemd to $action $service_name..."
        if systemctl is-active --quiet "$service_name" && [ "$action" = "start" ]; then
            _1_2_info "Service $service_name is already running."
            return 0
        fi

        if ! systemctl is-active --quiet "$service_name" && [ "$action" = "stop" ]; then
            _1_2_info "Service $service_name is already stopped."
            return 0
        fi

        systemctl "$action" "$service_name"
        return $?
        ;;

    "openrc")
        _1_2_info "Using OpenRC to $action $service_name..."
        if rc-service "$service_name" status &>/dev/null && [ "$action" = "start" ]; then
            _1_2_info "Service $service_name is already running."
            return 0
        fi

        if ! rc-service "$service_name" status &>/dev/null && [ "$action" = "stop" ]; then
            _1_2_info "Service $service_name is already stopped."
            return 0
        fi

        rc-service "$service_name" "$action"
        return $?
        ;;

    "sysv" | "upstart")
        _1_2_info "Using SysV/Upstart to $action $service_name..."
        if [ "$action" = "start" ] && service "$service_name" status &>/dev/null; then
            _1_2_info "Service $service_name is already running."
            return 0
        fi

        if [ "$action" = "stop" ] && ! service "$service_name" status &>/dev/null; then
            _1_2_info "Service $service_name is already stopped."
            return 0
        fi

        service "$service_name" "$action"
        return $?
        ;;

    *)
        _1_4_warning "Unknown init system. Attempting generic service management commands..."
        case "$action" in
        "start")
            if command -v service &>/dev/null; then
                service "$service_name" start
            elif [ -x "/etc/init.d/$service_name" ]; then
                "/etc/init.d/$service_name" start
            elif command -v systemctl &>/dev/null; then
                systemctl start "$service_name"
            else
                error "Could not find a way to start service $service_name"
                return 1
            fi
            ;;

        "stop")
            if command -v service &>/dev/null; then
                service "$service_name" stop
            elif [ -x "/etc/init.d/$service_name" ]; then
                "/etc/init.d/$service_name" stop
            elif command -v systemctl &>/dev/null; then
                systemctl stop "$service_name"
            else
                error "Could not find a way to stop service $service_name"
                return 1
            fi
            ;;

        "restart")
            if command -v service &>/dev/null; then
                service "$service_name" restart
            elif [ -x "/etc/init.d/$service_name" ]; then
                "/etc/init.d/$service_name" restart
            elif command -v systemctl &>/dev/null; then
                systemctl restart "$service_name"
            else
                error "Could not find a way to restart service $service_name"
                return 1
            fi
            ;;

        *)
            error "Unsupported action: $action"
            return 1
            ;;
        esac
        ;;
    esac

    return 0
}

# Function to set up firewall rules with cross-distribution support

configure_firewall() {
    local port="$1"
    local protocol="${2:-tcp}"
    local action="${3:-allow}"

    debug "Configuring firewall for port $port/$protocol, action: $action"

    # Detect which firewall system is in use
    local firewall_type=""

    if command -v ufw &>/dev/null && ufw status &>/dev/null; then
        firewall_type="ufw"
    elif command -v firewall-cmd &>/dev/null; then
        firewall_type="firewalld"
    elif command -v iptables &>/dev/null; then
        firewall_type="iptables"
    else
        _1_4_warning "No supported firewall system detected. Skipping firewall configuration."
        return 0
    fi

    _1_2_info "Detected firewall system: $firewall_type"

    case "$firewall_type" in
    "ufw")
        _1_2_info "Configuring UFW firewall rule for port $port/$protocol..."
        if [ "$action" = "allow" ]; then
            ufw allow "$port/$protocol"
        else
            ufw delete allow "$port/$protocol"
        fi
        ;;

    "firewalld")
        _1_2_info "Configuring FirewallD rule for port $port/$protocol..."
        if [ "$action" = "allow" ]; then
            firewall-cmd --permanent --add-port="$port/$protocol"
            firewall-cmd --reload
        else
            firewall-cmd --permanent --remove-port="$port/$protocol"
            firewall-cmd --reload
        fi
        ;;

    "iptables")
        _1_2_info "Configuring iptables rule for port $port/$protocol..."
        if [ "$action" = "allow" ]; then
            iptables -A INPUT -p "$protocol" --dport "$port" -j ACCEPT

            # Persist rules if possible
            if command -v iptables-save &>/dev/null; then
                if [ -d /etc/iptables ]; then
                    iptables-save >/etc/iptables/rules.v4
                elif [ -f /etc/sysconfig/iptables ]; then
                    iptables-save >/etc/sysconfig/iptables
                else
                    _1_4_warning "Could not determine where to save iptables rules. Changes may not persist after reboot."
                fi
            else
                _1_4_warning "iptables-save not found. Firewall rules may not persist after reboot."
            fi
        else
            iptables -D INPUT -p "$protocol" --dport "$port" -j ACCEPT 2>/dev/null || true
            # Persist removed rules
            if command -v iptables-save &>/dev/null; then
                if [ -d /etc/iptables ]; then
                    iptables-save >/etc/iptables/rules.v4
                elif [ -f /etc/sysconfig/iptables ]; then
                    iptables-save >/etc/sysconfig/iptables
                fi
            fi
        fi
        ;;
    esac

    1_3_success "Firewall rule configured successfully."
    return 0
}

# Function to determine the latest available stable PHP version
# Parameters:
#   None
# Returns:
#   Latest available stable PHP version, or empty string if none found
get_latest_php_version() {
    debug "Starting get_latest_php_version"

    # Get available PHP versions
    local available_versions=$(get_available_php_versions)

    if [ -z "$available_versions" ]; then
        error "No PHP versions found. Check repository configuration."
        return 1
    fi

    # Filter out unstable versions
    local stable_versions=""
    while read -r version; do
        if [[ ! "$version" =~ (alpha|beta|RC) ]]; then
            stable_versions="$stable_versions$version
"
        fi
    done <<<"$available_versions"

    # Get the highest stable version
    local latest_version=$(echo -e "$stable_versions" | sort -V | tail -n1)

    if [ -z "$latest_version" ]; then
        error "No stable PHP versions found."
        return 1
    fi

    debug "Latest PHP version: $latest_version"
    echo "$latest_version"
    return 0
}

# Comprehensive PHP management system for Firefly III installation
# Handles version detection, installation, configuration, and extension management
# across different Linux distributions

# Function to compare version strings
# Parameters:
#   version1: First version to compare
#   operator: Comparison operator (>=, >, <=, <, =)
#   version2: Second version to compare
# Returns:
#   0 if the comparison is true, 1 if false, 2 if operator is invalid
compare_versions() {
    debug "Starting compare_versions: $1 $2 $3"
    local version1="$1"
    local operator="$2"
    local version2="$3"

    # Validate input
    if [ -z "$version1" ] || [ -z "$operator" ] || [ -z "$version2" ]; then
        error "Missing arguments for version comparison. Required: version1, operator, version2."
        return 2
    fi

    # Normalize versions to remove any prefix (like 'v')
    version1="${version1#v}"
    version2="${version2#v}"

    # Use sort -V for natural version sorting
    case "$operator" in
    ">=")
        # version1 >= version2 if version1 is NOT less than version2
        if [ "$(printf '%s\n%s' "$version1" "$version2" | sort -V | head -n1)" = "$version2" ] ||
            [ "$version1" = "$version2" ]; then
            return 0
        else
            return 1
        fi
        ;;
    ">")
        # version1 > version2 if version1 is NOT less than or equal to version2
        if [ "$(printf '%s\n%s' "$version1" "$version2" | sort -V | head -n1)" = "$version2" ] &&
            [ "$version1" != "$version2" ]; then
            return 0
        else
            return 1
        fi
        ;;
    "<=")
        # version1 <= version2 if version1 is less than or equal to version2
        if [ "$(printf '%s\n%s' "$version1" "$version2" | sort -V | head -n1)" = "$version1" ] ||
            [ "$version1" = "$version2" ]; then
            return 0
        else
            return 1
        fi
        ;;
    "<")
        # version1 < version2 if version1 is less than version2
        if [ "$(printf '%s\n%s' "$version1" "$version2" | sort -V | head -n1)" = "$version1" ] &&
            [ "$version1" != "$version2" ]; then
            return 0
        else
            return 1
        fi
        ;;
    "=")
        # Simple string comparison for equality
        if [ "$version1" = "$version2" ]; then
            return 0
        else
            return 1
        fi
        ;;
    *)
        error "Unknown operator: $operator. Must be one of: >=, >, <=, <, ="
        return 2
        ;;
    esac
}

# Function to install PHP extensions with proper error handling
# Parameters:
#   extension: The extension to install
#   php_version: PHP version to use (optional, uses detected version if not specified)
# Returns:
#   0 if installation succeeded, 1 if failed
install_php_extension() {
    debug "Starting install_php_extension"
    local extension="$1"
    local php_version="$2"

    # If PHP version not specified, detect it
    if [ -z "$php_version" ]; then
        php_version=$(detect_php_version)
        if [ -z "$php_version" ]; then
            error "No PHP version detected. Cannot install extension: $extension"
            return 1
        fi
    fi

    _1_2_info "Installing PHP extension: $extension for PHP $php_version"

    # Check if extension is already installed
    if php -m | grep -iw "$extension" &>/dev/null; then
        _1_2_info "PHP extension $extension is already installed."
        return 0
    fi

    # Distribution-specific installation
    case "$os_type" in
    "debian")
        # Handle special extension names for Debian/Ubuntu
        local package_name=""
        case "$extension" in
        "mysql")
            # Try with different MySQL extension names
            if apt-cache show "php$php_version-mysql" &>/dev/null; then
                package_name="php$php_version-mysql"
            elif apt-cache show "php$php_version-mysqlnd" &>/dev/null; then
                package_name="php$php_version-mysqlnd"
            else
                package_name="php$php_version-mysql php$php_version-mysqli php$php_version-mysqlnd"
            fi
            ;;
        "pgsql")
            package_name="php$php_version-pgsql"
            ;;
        "sqlite")
            package_name="php$php_version-sqlite3"
            ;;
        "pdo")
            package_name="php$php_version-pdo"
            ;;
        *)
            package_name="php$php_version-$extension"
            ;;
        esac

        # Install the package
        execute_with_progress "Installing PHP Extension" "apt-get install -y $package_name" "pulse=true"
        ;;

    "rhel")
        # Handle special extension names for RHEL/CentOS
        local package_name=""
        case "$extension" in
        "mysql")
            package_name="php-mysqlnd"
            ;;
        "pgsql")
            package_name="php-pgsql"
            ;;
        "sqlite")
            package_name="php-sqlite3"
            ;;
        "pdo")
            package_name="php-pdo"
            ;;
        *)
            package_name="php-$extension"
            ;;
        esac

        # Install the package
        if command -v dnf &>/dev/null; then
            execute_with_progress "Installing PHP Extension" "dnf install -y $package_name" "pulse=true"
        else
            execute_with_progress "Installing PHP Extension" "yum install -y $package_name" "pulse=true"
        fi
        ;;

    "alpine")
        # Handle special extension names for Alpine
        local alpine_version=${php_version//./}
        local package_name=""
        case "$extension" in
        "mysql")
            package_name="php$alpine_version-mysqli php$alpine_version-mysqlnd"
            ;;
        "pgsql")
            package_name="php$alpine_version-pgsql"
            ;;
        "sqlite")
            package_name="php$alpine_version-sqlite3"
            ;;
        "pdo")
            package_name="php$alpine_version-pdo"
            ;;
        *)
            package_name="php$alpine_version-$extension"
            ;;
        esac

        # Install the package
        execute_with_progress "Installing PHP Extension" "apk add $package_name" "pulse=true"
        ;;

    *)
        error "Unsupported OS type: $os_type. Cannot install PHP extension."
        return 1
        ;;
    esac

    # Verify installation
    if php -m | grep -iw "$extension" &>/dev/null; then
        1_3_success "PHP extension $extension installed successfully."
        return 0
    else
        _1_4_warning "PHP extension $extension may not have been installed correctly."
        return 1
    fi
}

# Function to install multiple PHP extensions with parallel processing if available
# Parameters:
#   php_version: PHP version to use
#   extensions: Space-separated list of extensions to install
# Returns:
#   0 if all installations succeeded, 1 if any failed
install_php_extensions() {
    debug "Starting install_php_extensions"
    local php_version="$1"
    local extensions="$2"
    local result=0

    # Convert space-separated list to array
    IFS=' ' read -r -a extension_array <<<"$extensions"

    _1_2_info "Installing ${#extension_array[@]} PHP extensions for PHP $php_version..."

    # Check for parallel command
    if command -v parallel &>/dev/null && [ "$NON_INTERACTIVE" != "true" ]; then
        _1_2_info "Using parallel processing for faster extension installation..."

        # Create a temp file to track progress
        local progress_file=$(mktemp)
        echo "0" >"$progress_file"

        # Export functions needed by parallel
        export -f install_php_extension debug _1_2_info _1_3_success _1_4_warning error execute_with_progress show_progress
        export php_version os_type progress_file

        # Function to install extension and update progress
        install_extension_with_progress() {
            local ext="$1"
            install_php_extension "$ext" "$php_version"
            local result=$?

            # Update progress
            local current=$(cat "$progress_file")
            echo $((current + 1)) >"$progress_file"

            return $result
        }
        export -f install_extension_with_progress

        # Run installations in parallel with limited jobs
        parallel --will-cite -j 4 "install_extension_with_progress {}" ::: "${extension_array[@]}" &
        local parallel_pid=$!

        # Monitor progress
        show_progress "Installing PHP Extensions" 0 "${#extension_array[@]}" "Starting..."

        while kill -0 $parallel_pid 2>/dev/null; do
            local completed=$(cat "$progress_file")
            show_progress "Installing PHP Extensions" "$completed" "${#extension_array[@]}" "Installed $completed of ${#extension_array[@]} extensions"
            sleep 0.5
        done

        # Final progress update
        show_progress "Installing PHP Extensions" "${#extension_array[@]}" "${#extension_array[@]}" "Complete" true

        # Get result
        wait $parallel_pid
        result=$?

        # Clean up
        rm -f "$progress_file"
    else
        # Install extensions sequentially
        local count=0
        for extension in "${extension_array[@]}"; do
            show_progress "Installing PHP Extensions" "$count" "${#extension_array[@]}" "Installing $extension..."

            if ! install_php_extension "$extension" "$php_version"; then
                _1_4_warning "Failed to install PHP extension: $extension"
                result=1
            fi

            count=$((count + 1))
            show_progress "Installing PHP Extensions" "$count" "${#extension_array[@]}" "Installed $count of ${#extension_array[@]} extensions"
        done

        show_progress "Installing PHP Extensions" "${#extension_array[@]}" "${#extension_array[@]}" "Complete" true
    fi

    if [ $result -eq 0 ]; then
        1_3_success "All PHP extensions installed successfully."
    else
        _1_4_warning "Some PHP extensions could not be installed."
    fi

    return $result
}

# Function to configure PHP settings for optimal Firefly III performance
# Parameters:
#   php_version: PHP version to configure
# Returns:
#   0 if configuration succeeded, 1 if failed
configure_php() {
    debug "Starting configure_php"
    local php_version="$1"

    _1_2_info "Configuring PHP $php_version for optimal performance..."

    # Determine configuration directories based on OS type
    local conf_dirs=()

    case "$os_type" in
    "debian")
        conf_dirs=(
            "/etc/php/$php_version/cli"
            "/etc/php/$php_version/apache2"
            "/etc/php/$php_version/fpm"
        )
        ;;

    "rhel")
        conf_dirs=(
            "/etc/php.d"
            "/etc/php-fpm.d"
        )
        ;;

    "alpine")
        conf_dirs=(
            "/etc/php$php_version"
            "/etc/php$php_version/cli"
            "/etc/php$php_version/apache2"
            "/etc/php$php_version/fpm"
        )
        ;;

    *)
        error "Unsupported OS type: $os_type. Cannot configure PHP."
        return 1
        ;;
    esac

    # Update configuration in each directory
    for conf_dir in "${conf_dirs[@]}"; do
        if [ -d "$conf_dir" ]; then
            local php_ini="$conf_dir/php.ini"

            if [ -f "$php_ini" ]; then
                _1_2_info "Configuring PHP settings in $php_ini"

                # Create backup of original php.ini
                cp "$php_ini" "${php_ini}.backup.$(date +%Y%m%d%H%M%S)"

                # Configure optimized settings for Firefly III
                sed -i 's/memory_limit = .*/memory_limit = 512M/' "$php_ini"
                sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$php_ini"
                sed -i 's/post_max_size = .*/post_max_size = 64M/' "$php_ini"
                sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$php_ini"
                sed -i 's/max_input_time = .*/max_input_time = 300/' "$php_ini"

                # Enable recommended settings for security
                sed -i 's/expose_php = .*/expose_php = Off/' "$php_ini"

                # Configure date.timezone if not set
                if grep -q '^;date.timezone =' "$php_ini" || ! grep -q '^date.timezone =' "$php_ini"; then
                    timezone=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || echo "UTC")
                    sed -i "s/;date.timezone =.*/date.timezone = $timezone/" "$php_ini"
                    if ! grep -q "^date.timezone = " "$php_ini"; then
                        echo "date.timezone = $timezone" >>"$php_ini"
                    fi
                fi

                # Enable opcache for improved performance
                if ! grep -q "zend_extension=opcache" "$php_ini"; then
                    echo "zend_extension=opcache" >>"$php_ini"
                fi

                sed -i 's/opcache.memory_consumption=.*/opcache.memory_consumption=128/' "$php_ini"
                sed -i 's/opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=8/' "$php_ini"
                sed -i 's/opcache.max_accelerated_files=.*/opcache.max_accelerated_files=4000/' "$php_ini"
                sed -i 's/opcache.revalidate_freq=.*/opcache.revalidate_freq=60/' "$php_ini"
                sed -i 's/opcache.fast_shutdown=.*/opcache.fast_shutdown=1/' "$php_ini"
                sed -i 's/opcache.enable_cli=.*/opcache.enable_cli=1/' "$php_ini"

                # If the settings don't exist, add them at the end of the file
                if ! grep -q "opcache.memory_consumption" "$php_ini"; then
                    cat >>"$php_ini" <<EOF

; Opcache settings for improved performance
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
opcache.enable_cli=1
EOF
                fi
            else
                _1_4_warning "PHP configuration file not found at $php_ini"
            fi
        fi
    done

    # Restart PHP-FPM if it's in use
    case "$os_type" in
    "debian")
        if systemctl is-active --quiet "php$php_version-fpm"; then
            _1_2_info "Restarting PHP-FPM service..."
            systemctl restart "php$php_version-fpm"
        fi
        ;;

    "rhel")
        if systemctl is-active --quiet "php-fpm"; then
            _1_2_info "Restarting PHP-FPM service..."
            systemctl restart "php-fpm"
        fi
        ;;

    "alpine")
        if rc-service "php-fpm$php_version" status &>/dev/null; then
            _1_2_info "Restarting PHP-FPM service..."
            rc-service "php-fpm$php_version" restart
        fi
        ;;
    esac

    # Configure Apache for PHP
    configure_apache_php "$php_version"

    1_3_success "PHP $php_version configured successfully for Firefly III."
    return 0
}

# Function to configure Apache for PHP
# Parameters:
#   php_version: PHP version to configure
# Returns:
#   0 if configuration succeeded, 1 if failed
configure_apache_php() {
    debug "Starting configure_apache_php"
    local php_version="$1"

    _1_2_info "Configuring Apache for PHP $php_version..."

    case "$os_type" in
    "debian")
        # Disable all other PHP modules
        a2dismod php* 2>/dev/null || true

        # Enable the target PHP version
        if ! a2enmod "php$php_version"; then
            error "Failed to enable PHP $php_version module in Apache."
            return 1
        fi
        ;;

    "rhel")
        # Configure PHP handler for Apache on RHEL
        if [ ! -f "/etc/httpd/conf.d/php.conf" ]; then
            cat >"/etc/httpd/conf.d/php.conf" <<EOF
<FilesMatch \.php$>
    SetHandler application/x-httpd-php
</FilesMatch>
EOF
        fi

        # Check if PHP-FPM is being used
        if systemctl is-active --quiet php-fpm; then
            # Configure PHP-FPM for Apache
            cat >"/etc/httpd/conf.d/php-fpm.conf" <<EOF
<FilesMatch \.php$>
    SetHandler "proxy:fcgi://127.0.0.1:9000"
</FilesMatch>
EOF
        fi
        ;;

    "alpine")
        # Configure Apache for PHP on Alpine
        local alpine_version=${php_version//./}

        if [ ! -f "/etc/apache2/conf.d/php$alpine_version-module.conf" ]; then
            cat >"/etc/apache2/conf.d/php$alpine_version-module.conf" <<EOF
LoadModule php${alpine_version}_module modules/mod_php${alpine_version}.so
<FilesMatch \.php$>
    SetHandler application/x-httpd-php
</FilesMatch>
EOF
        fi
        ;;

    *)
        error "Unsupported OS type: $os_type. Cannot configure Apache for PHP."
        return 1
        ;;
    esac

    # Restart Apache to apply changes
    _1_2_info "Restarting Apache to apply PHP configuration changes..."
    if ! apache_control restart; then
        error "Failed to restart Apache. PHP configuration changes may not be applied."
        return 1
    fi

    1_3_success "Apache configured successfully for PHP $php_version."
    return 0
}

# Function to install a specific PHP version with all required dependencies and extensions
# Parameters:
#   php_version: PHP version to install (e.g., "8.1")
#   skip_config: Whether to skip configuration (default: false)
# Returns:
#   0 if installation succeeded, 1 if failed
install_php_version() {
    debug "Starting install_php_version"
    local php_version="$1"
    local skip_config="${2:-false}"

    # Step 1: Validate input
    if [ -z "$php_version" ]; then
        error "PHP version parameter is required for installation."
        return 1
    fi

    _1_2_info "Installing PHP $php_version and required extensions..."

    # Step 2: Before installation, add appropriate repositories
    if ! _2_4_add_php_repository; then
        _1_4_warning "Failed to add PHP repository, but continuing with default repos."
    fi

    # Step 3: Install PHP packages based on distribution
    case "$os_type" in
    "debian")
        # Install PHP packages for Debian/Ubuntu
        local packages="php$php_version php$php_version-cli php$php_version-common php$php_version-fpm libapache2-mod-php$php_version"
        execute_with_progress "Installing PHP Core Packages" "apt-get install -y $packages" "pulse=true"
        ;;

    "rhel")
        # Install PHP packages for RHEL/CentOS
        if command -v dnf &>/dev/null; then
            # For newer RHEL/CentOS with DNF
            execute_with_progress "Enabling PHP Module" "dnf module reset php -y && dnf module enable php:remi-$php_version -y" "pulse=true"
            execute_with_progress "Installing PHP Core Packages" "dnf install -y php php-cli php-common php-fpm mod_php" "pulse=true"
        else
            # For older RHEL/CentOS with YUM
            execute_with_progress "Installing PHP Core Packages" "yum install -y php php-cli php-common php-fpm mod_php" "pulse=true"
        fi
        ;;

    "alpine")
        # Install PHP packages for Alpine Linux
        local alpine_version=${php_version//./}
        local packages="php$alpine_version php$alpine_version-cli php$alpine_version-common php$alpine_version-fpm php$alpine_version-apache2"
        execute_with_progress "Installing PHP Core Packages" "apk add $packages" "pulse=true"
        ;;

    *)
        error "Unsupported OS type: $os_type. Cannot install PHP."
        return 1
        ;;
    esac

    if [ $? -ne 0 ]; then
        error "Failed to install PHP $php_version core packages."
        return 1
    fi

    # Step 4: Install essential PHP extensions for Firefly III
    local essential_extensions="bcmath curl gd intl mbstring xml zip opcache json"

    if ! install_php_extensions "$php_version" "$essential_extensions"; then
        _1_4_warning "Some PHP extensions could not be installed. Firefly III may not function correctly."
    fi

    # Step 5: Install database extensions
    local db_extensions="mysql sqlite3 pdo"
    if ! install_php_extensions "$php_version" "$db_extensions"; then
        _1_4_warning "Database extensions could not be installed. Firefly III may not function correctly."
    fi

    # Step 6: Configure PHP if not skipped
    if [ "$skip_config" != "true" ]; then
        if ! configure_php "$php_version"; then
            _1_4_warning "PHP $php_version was installed but configuration failed. Continuing anyway..."
        fi
    else
        _1_2_info "Skipping PHP configuration as requested."
    fi

    # Step 7: Verify installation
    local installed_version=$(detect_php_version)

    if [ "$installed_version" = "$php_version" ]; then
        1_3_success "Successfully installed and configured PHP $php_version."
        return 0
    else
        _1_4_warning "PHP $php_version was installed but does not seem to be the default version."
        _1_4_warning "Current default PHP version: $installed_version"

        # Try to explicitly set the new version as default
        if ! configure_apache_php "$php_version"; then
            error "Failed to set PHP $php_version as the default for Apache."
            return 1
        fi

        # Verify again
        installed_version=$(detect_php_version)
        if [ "$installed_version" = "$php_version" ]; then
            1_3_success "Fixed PHP activation. PHP $php_version is now the default."
            return 0
        else
            error "Failed to set PHP $php_version as default even after manual intervention."
            return 1
        fi
    fi
}

# Function to check PHP compatibility with specified Firefly III version
# Parameters:
#   firefly_tag: Firefly III release tag or version
#   php_version: Current PHP version
# Returns:
#   0 if compatible, 1 if not compatible
check_php_compatibility() {
    debug "Starting check_php_compatibility"
    local firefly_tag="$1"
    local php_version="$2"

    _1_2_info "Checking PHP compatibility for Firefly III $firefly_tag with PHP $php_version..."

    # Get composer.json for this release
    local composer_url="https://raw.githubusercontent.com/firefly-iii/firefly-iii/$firefly_tag/composer.json"
    local composer_json

    composer_json=$(curl -s "$composer_url")
    if [ -z "$composer_json" ]; then
        error "Failed to retrieve composer.json for Firefly III $firefly_tag."
        return 1
    fi

    # Extract PHP requirement
    local php_req
    php_req=$(echo "$composer_json" | grep -o '"php": *"[^"]*"' | sed 's/"php": *"\([^"]*\)"/\1/')

    if [ -z "$php_req" ]; then
        _1_4_warning "Could not determine PHP requirement for Firefly III $firefly_tag."
        # Assume compatible if requirement can't be determined
        return 0
    fi

    # Parse minimum PHP version
    local min_php_version
    min_php_version=$(echo "$php_req" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    if [ -z "$min_php_version" ]; then
        min_php_version=$(echo "$php_req" | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        if [ -z "$min_php_version" ]; then
            _1_4_warning "Could not parse PHP version requirement for Firefly III $firefly_tag: $php_req"
            # Assume compatible if requirement can't be parsed
            return 0
        fi
        min_php_version="${min_php_version}.0"
    fi

    # Compare current PHP version with minimum required version
    if compare_versions "$php_version" ">=" "$min_php_version"; then
        1_3_success "PHP $php_version is compatible with Firefly III $firefly_tag (requires PHP $min_php_version)"
        return 0
    else
        _1_4_warning "PHP $php_version is not compatible with Firefly III $firefly_tag (requires PHP $min_php_version)"

        # Check if a compatible PHP version is available
        local latest_available=$(get_latest_php_version)

        if [ -n "$latest_available" ] && compare_versions "$latest_available" ">=" "$min_php_version"; then
            _1_4_warning "You can upgrade to PHP $latest_available which is compatible with Firefly III $firefly_tag."

            # Ask if user wants to upgrade PHP automatically
            if [ "$NON_INTERACTIVE" = false ]; then
                prompt "Do you want to upgrade to PHP $latest_available? (y/N): "
                read upgrade_php

                if [[ "$upgrade_php" =~ ^[Yy]$ ]]; then
                    _1_2_info "Upgrading to PHP $latest_available..."
                    if install_php_version "$latest_available"; then
                        1_3_success "Successfully upgraded to PHP $latest_available."

                        # Check compatibility again with new PHP version
                        return check_php_compatibility "$firefly_tag" "$latest_available"
                    else
                        error "Failed to upgrade PHP. Please upgrade manually or try a different Firefly III version."
                        return 1
                    fi
                fi
            fi
        else
            _1_4_warning "No compatible PHP version available in repositories."
        fi

        return 1
    fi
}

# Function to find a Firefly III version compatible with current PHP
# Parameters:
#   current_php_version: The currently installed PHP version
# Returns:
#   A compatible Firefly III release tag, or empty string if not found
find_compatible_firefly_release() {
    debug "Starting find_compatible_firefly_release"
    local current_php_version="$1"
    local max_releases=10

    _1_2_info "Searching for Firefly III releases compatible with PHP $current_php_version..."

    # Step 1: Get the list of releases from GitHub API
    local releases_json=$(curl -s "https://api.github.com/repos/firefly-iii/firefly-iii/releases" | head -n 5000)

    # Step 2: Check if we got a valid response
    if ! echo "$releases_json" | grep -q "tag_name"; then
        error "Failed to fetch Firefly III releases from GitHub API. Check your internet connection and if GitHub is accessible from your server."
        return 1
    fi

    # Step 3: Extract tags and process them
    local tags=$(echo "$releases_json" | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4)
    local checked=0

    # Step 4: Check each release for compatibility
    local progress_count=0
    local total_tags=$(echo "$tags" | wc -l)
    for tag in $tags; do
        # Limit the number of releases to check
        if [ $checked -ge $max_releases ]; then
            break
        fi
        checked=$((checked + 1))
        progress_count=$((progress_count + 1))

        show_progress "Checking Firefly Compatibility" $progress_count $total_tags "Checking $tag"

        # Get composer.json for this release
        local composer_url="https://raw.githubusercontent.com/firefly-iii/firefly-iii/$tag/composer.json"
        local composer_json=$(curl -s "$composer_url")

        # Extract PHP requirement
        local php_req=$(echo "$composer_json" | grep -o '"php": *"[^"]*"' | sed 's/"php": *"\([^"]*\)"/\1/')

        if [ -z "$php_req" ]; then
            _1_4_warning "Could not determine PHP requirement for $tag. Skipping."
            continue
        fi

        # Parse min PHP version
        local min_php_version=$(echo "$php_req" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        if [ -z "$min_php_version" ]; then
            min_php_version=$(echo "$php_req" | grep -o '[0-9]\+\.[0-9]\+' | head -1)
            if [ -z "$min_php_version" ]; then
                _1_4_warning "Could not parse PHP version requirement for $tag: $php_req. Skipping."
                continue
            fi
            min_php_version="${min_php_version}.0"
        fi

        # Compare with current PHP version
        if compare_versions "$current_php_version" ">=" "$min_php_version"; then
            1_3_success "Found compatible release: Firefly III $tag (requires PHP $min_php_version)"
            echo "$tag"
            return 0
        else
            _1_2_info "Firefly III $tag requires PHP $min_php_version, not compatible with current PHP $current_php_version."
        fi
    done

    _1_4_warning "Could not find a compatible Firefly III release after checking $checked releases. Consider upgrading your PHP version to use the latest Firefly III."
    return 1
}

# Function to download a specific release with progress bar
# Parameters:
#   repo: The GitHub repository (e.g., "firefly-iii/firefly-iii")
#   dest_dir: The destination directory for the download
#   tag: The release tag to download
# Returns:
#   0 if download succeeded, 1 if failed
download_specific_release() {
    debug "Starting download_specific_release"
    local repo="$1"
    local dest_dir="$2"
    local tag="$3"

    _1_2_info "Downloading $repo $tag..."

    # Step 1: Construct the download URL for the specific release
    local download_url="https://github.com/$repo/releases/download/$tag/$(echo $repo | cut -d'/' -f2)-$tag.zip"
    local release_filename="$(echo $repo | cut -d'/' -f2)-$tag.zip"

    # Step 2: Download the release with a progress bar
    _1_2_info "Downloading from $download_url..."
    if ! wget --progress=bar:force:noscroll --tries=3 --timeout=30 -O "$dest_dir/$release_filename" "$download_url" 2>&1 | stdbuf -o0 awk '{if(NR>1)print "\r\033[K" $0, "\r"}'; then
        _1_4_warning "wget failed, falling back to curl."
        if ! curl -L --retry 3 --max-time 30 -o "$dest_dir/$release_filename" --progress-bar "$download_url"; then
            error "Failed to download $repo $tag. Check your internet connection and ensure GitHub is accessible from your server."
            return 1
        fi
    fi

    # Step 3: Validate download (check if the zip file is valid)
    if ! unzip -t "$dest_dir/$release_filename" >/dev/null 2>&1; then
        error "The downloaded file is not a valid zip archive. Try downloading it manually to verify the issue."
        return 1
    fi

    1_3_success "Successfully downloaded $repo $tag."
    return 0
}

# Function to fetch release info from GitHub API with rate limiting
# Parameters:
#   repo: The GitHub repository (e.g., "firefly-iii/firefly-iii")
#   auth_header: The authorization header for GitHub API
# Returns:
#   0 if successful, 1 if failed or rate limited
fetch_release_info() {
    debug "Starting fetch_release_info"
    local repo="$1"
    local auth_header="$2"
    local api_url="https://api.github.com/repos/$repo/releases/latest"

    # Step 1: Fetch release information from GitHub
    curl -sSL -H "$auth_header" "$api_url" -D headers.txt || {
        error "Failed to fetch release info from GitHub API. Check your internet connection and if GitHub is accessible from your server."
        return 1
    }

    # Step 2: Check for rate limiting
    if grep -q "API rate limit exceeded" headers.txt; then
        # Fetch the reset time from headers
        local reset_time=$(grep "^x-ratelimit-reset:" headers.txt | awk '{print $2}')
        local current_time=$(date +%s)

        if [ -n "$reset_time" ]; then
            local wait_time=$((reset_time - current_time))
            _1_4_warning "GitHub API rate limit exceeded. Waiting for $wait_time seconds before retrying. Consider using a GITHUB_TOKEN to avoid rate limiting."
            sleep "$wait_time"
        else
            _1_4_warning "Rate limit exceeded but no reset time provided. Waiting for 60 seconds before retrying. Consider using a GITHUB_TOKEN to avoid rate limiting."
            sleep 60
        fi
        return 1 # Indicate that the retry logic should retry
    fi

    # Step 3: Check if the API response contains errors
    if grep -q "Bad credentials" headers.txt; then
        error "Invalid GitHub API token. Please check your token and try again. You can create a token at https://github.com/settings/tokens."
        return 1
    fi

    # Step 4: Parse the API response and return the JSON data
    cat headers.txt

    # Indicate successful completion
    return 0
}

# Function to get the latest Firefly III version from the JSON file
# Returns:
#   The latest Firefly III version, or empty string on error
get_latest_firefly_version() {
    debug "Starting get_latest_firefly_version"
    # Step 1: Download the version information
    local json
    json=$(curl -s "https://version.firefly-iii.org/index.json")
    if [ -z "$json" ]; then
        error "Failed to retrieve latest Firefly III version information. Check your internet connection and if the version server is accessible."
        return 1
    fi

    # Step 2: Extract the version from the 'firefly_iii' section, removing the leading 'v'
    local latest_version
    latest_version=$(echo "$json" | jq -r '.firefly_iii.stable.version' | sed 's/^v//')
    echo "$latest_version"
    return 0
}

# Function to get the latest Firefly Importer version from the JSON file
# Returns:
#   The latest Firefly Importer version, or empty string on error
get_latest_importer_version() {
    debug "Starting get_latest_importer_version"
    # Step 1: Download the version information
    local json
    json=$(curl -s "https://version.firefly-iii.org/index.json")
    if [ -z "$json" ]; then
        error "Failed to retrieve latest Firefly Importer version information. Check your internet connection and if the version server is accessible."
        return 1
    fi

    # Step 2: Extract the version from the 'data' section, removing the leading 'v'
    local latest_importer_version
    latest_importer_version=$(echo "$json" | jq -r '.data.stable.version' | sed 's/^v//')
    echo "$latest_importer_version"
    return 0
}

# Function to get the latest release download URL from GitHub using jq
# Parameters:
#   repo: The GitHub repository (e.g., "firefly-iii/firefly-iii")
#   file_pattern: A regex pattern to match the desired file
# Returns:
#   The download URL for the latest release that matches the pattern
get_latest_release_url() {
    debug "Starting get_latest_release_url"
    local repo="$1"
    local file_pattern="$2"
    local release_info

    # Step 1: Fetch the release information
    release_info=$(curl -s "https://api.github.com/repos/$repo/releases/latest")

    # Step 2: Check if the API response contains valid data
    if [ -z "$release_info" ] || [ "$release_info" = "null" ]; then
        error "Failed to retrieve release information from GitHub. Check your internet connection and if GitHub is accessible from your server."
        return 1
    fi

    # Step 3: Check if the rate limit has been exceeded
    if echo "$release_info" | grep -q "API rate limit exceeded"; then
        error "GitHub API rate limit exceeded. Please try again later or use a GitHub API token. You can create a token at https://github.com/settings/tokens."
        return 1
    fi

    # Step 4: Extract and filter download URLs using jq, with an additional safeguard against missing assets
    echo "$release_info" | jq -r --arg file_pattern "$file_pattern" '
        if .assets then 
            .assets[] | select(.name | test($file_pattern)) | .browser_download_url 
        else 
            empty 
        end' | head -n1

    return 0
}

# Check and display Firefly III version
# Returns:
#   The installed Firefly III version, or an error message
check_firefly_version() {
    debug "Starting check_firefly_version"
    local firefly_path="/var/www/firefly-iii"

    # Step 1: Check if the directory exists
    if [ ! -d "$firefly_path" ]; then
        echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} Firefly III directory not found at $firefly_path"
        return 1
    fi

    _1_2_info "Checking Firefly III version..."

    # Step 2: Get the version from artisan command
    if cd "$firefly_path"; then
        local version
        version=$(php artisan firefly-iii:output-version 2>/dev/null)
    else
        echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} Could not access $firefly_path. Check directory permissions."
        return 1
    fi

    version=$(echo "$version" | tr -d '\n') # Trim newlines
    _1_2_info "Firefly III Version (artisan): $version"

    echo "$version" # Return the version
    return 0
}

# Function to get the installed Firefly Importer version
# Returns:
#   The installed Firefly Importer version, or an error message
get_importer_version() {
    debug "Starting get_importer_version"
    local importer_path="/var/www/data-importer"
    local version

    # Step 1: Ensure the correct directory is used
    if [ ! -d "$importer_path" ]; then
        echo "Error: Firefly Importer directory not found at $importer_path. Check if it's installed correctly." >&2
        return 1
    fi

    # Step 2: Retrieve the version using artisan
    version=$(php "$importer_path/artisan" config:show importer.version 2>/dev/null | awk '{print $NF}')

    if [[ -n "$version" ]]; then
        echo "$version"
    else
        echo "Error: Could not retrieve importer version. Try checking the config file manually." >&2
        return 1
    fi
}

# Function to check the installed Firefly Importer version
# Returns:
#   The installed Firefly Importer version, or an error message
check_firefly_importer_version() {
    debug "Starting check_firefly_importer_version"
    local firefly_importer_path="/var/www/data-importer"

    # Step 1: Check if the directory exists
    if [ ! -d "$firefly_importer_path" ]; then
        error "Firefly Importer directory not found at $firefly_importer_path. Check if it's installed correctly."
        return 1
    fi

    _1_2_info "Checking Firefly Importer version..."

    # Step 2: Get the importer version
    local importer_version
    importer_version=$(get_importer_version)
    importer_version=$(echo "$importer_version" | tr -d '\n')

    if [[ -z "$importer_version" ]]; then
        error "Could not determine Firefly Importer version. Try checking the config file manually or reinstall."
        return 1
    fi

    1_3_success "Firefly Importer Version: $importer_version"

    echo "$importer_version" # Return the version
    return 0
}

# Function to download and validate a release with a cleaner progress display
# Parameters:
#   repo: The GitHub repository (e.g., "firefly-iii/firefly-iii")
#   dest_dir: The destination directory for the download
#   file_pattern: A regex pattern to match the desired file
# Returns:
#   0 if download and validation succeeded, 1 if failed
download_and_validate_release() {
    debug "Starting download_and_validate_release"
    local repo="$1"
    local dest_dir="$2"
    local file_pattern="$3"

    # Step 1: Ensure the destination directory exists and is writable
    if [ ! -d "$dest_dir" ]; then
        _1_2_info "Creating directory $dest_dir..."
        if ! mkdir -p "$dest_dir"; then
            error "Failed to create directory $dest_dir. Check permissions."
            return 1
        fi
    fi

    if [ ! -w "$dest_dir" ]; then
        error "Directory $dest_dir is not writable. Check permissions: chmod 755 $dest_dir"
        return 1
    fi

    _1_2_info "Downloading the latest release of $repo..."

    # Step 2: Get the release URL
    local release_url
    release_url=$(get_latest_release_url "$repo" "$file_pattern")

    if [ -z "$release_url" ]; then
        error "Failed to retrieve release URL for $repo. Check internet connection."
        return 1
    fi

    local release_filename
    release_filename=$(basename "$release_url")
    local archive_file="$dest_dir/$release_filename"

    _1_2_info "Downloading $release_filename from $repo..."

    show_progress "Download" 1 100 "Starting download..."

    # Step 3: Download the release file with retry and fallback mechanism
    local temp_log
    temp_log=$(mktemp)

    if command -v wget >/dev/null 2>&1; then
        wget --progress=dot:mega -q --show-progress --tries=3 --timeout=30 -O "$archive_file" "$release_url" 2>"$temp_log" &
        local wget_pid=$!

        local prog=1
        while kill -0 $wget_pid 2>/dev/null; do
            if grep -q "%" "$temp_log"; then
                local percent
                percent=$(grep -o "[0-9]\+%" "$temp_log" | tail -n1 | grep -o "[0-9]\+")
                [ -n "$percent" ] && prog=$percent
            else
                prog=$((prog + 1))
                [ $prog -gt 99 ] && prog=99
            fi

            show_progress "Download" $prog 100 "Downloading $release_filename"
            sleep 0.2
        done

        rm -f "$temp_log"

        if ! wait $wget_pid; then
            error "Download failed. Falling back to curl."
            if ! curl -L --retry 3 --max-time 30 -o "$archive_file" --progress-bar "$release_url"; then
                error "Failed to download the release file after retries."
                return 1
            fi
        fi
    else
        curl -L --retry 3 --max-time 30 -o "$archive_file" --progress-bar "$release_url" || {
            error "Failed to download the release file. Check internet connection."
            return 1
        }
    fi

    # Changed to just show "Complete" instead of repeating the filename
    show_progress "Download" 100 100 "Complete" "true"
    1_3_success "Downloaded $release_filename successfully."

    # Step 4: Validate the SHA256 checksum
    local sha256_filename="${release_filename}.sha256"
    local sha256_file="$dest_dir/$sha256_filename"
    local sha256_url

    sha256_url=$(get_latest_release_url "$repo" "^${sha256_filename}$")
    [ -z "$sha256_url" ] && sha256_url="${release_url}.sha256"

    if [ -z "$sha256_url" ]; then
        _1_4_warning "No SHA256 checksum found. Skipping validation. Proceeding without verification may pose security risks."
    else
        _1_2_info "Downloading SHA256 checksum from $sha256_url..."

        if ! wget -q --tries=3 --timeout=30 --content-disposition -O "$sha256_file" "$sha256_url"; then
            _1_4_warning "wget failed for SHA256, trying curl."
            if ! curl -s -L --retry 3 --max-time 30 -o "$sha256_file" "$sha256_url"; then
                error "Failed to download SHA256 checksum file."
                return 1
            fi
        fi

        if [ ! -f "$archive_file" ] || [ ! -f "$sha256_file" ]; then
            error "Missing downloaded files. Archive or checksum not found."
            return 1
        fi

        _1_2_info "Validating the downloaded archive file..."
        if ! (cd "$dest_dir" && sha256sum -c "$(basename "$sha256_file")" 2>/dev/null); then
            error "SHA256 checksum validation failed for $archive_file."
            return 1
        fi

        1_3_success "Download and validation completed successfully."
    fi

    return 0
}

# Function to extract an archive file with progress tracking
# Parameters:
#   $1 - Archive file (zip or tar.gz)
#   $2 - Destination directory
# Returns:
#   0 if extraction succeeded, 1 if failed
extract_archive() {
    debug "Starting extract_archive function..."
    local archive_file="$1"
    local dest_dir="$2"

    _1_2_info "Extracting $archive_file to $dest_dir..."

    # Step 1: Determine the total number of files inside the archive
    local total_files=0
    if [[ "$archive_file" == *.zip ]]; then
        total_files=$(unzip -l "$archive_file" | awk 'NR>3 {print $NF}' | grep -v '^$' | wc -l)
    elif [[ "$archive_file" == *.tar.gz ]]; then
        total_files=$(tar -tzf "$archive_file" | wc -l)
    else
        error "Unsupported archive format: $archive_file. Only zip and tar.gz files are supported."
        return 1
    fi

    # Ensure total_files is valid
    if [[ "$total_files" -le 0 ]]; then
        error "Failed to determine the number of files in the archive."
        return 1
    fi

    # Create the destination directory
    mkdir -p "$dest_dir"

    local extracted_files=0 # Track extracted files

    if [[ "$archive_file" == *.zip ]]; then
        # Extract ZIP while tracking progress
        unzip -o "$archive_file" -d "$dest_dir" | while read -r line; do
            ((extracted_files++))
            show_progress "Extracting ZIP" "$extracted_files" "$total_files" "Processing..."
        done
    elif [[ "$archive_file" == *.tar.gz ]]; then
        # Extract TAR while tracking progress
        tar --checkpoint=10 --checkpoint-action=exec='extracted_files=$((extracted_files+10)); show_progress "Extracting TAR" "$extracted_files" "$total_files" "Processing..."' \
            -xzf "$archive_file" -C "$dest_dir" || {
            error "Extraction failed."
            return 1
        }
    fi

    # Final progress update
    show_progress "Extracting" "$total_files" "$total_files" "Completed" true
    1_3_success "Extraction of $archive_file into $dest_dir completed successfully."

    return 0
}

# Integrate with existing setup_env_file function
# This function uses the existing setup_env_file code but calls our new initialize_database function
# Parameters:
#   target_dir: The target directory containing the .env file
# Returns:
#   0 if setup succeeded, 1 if failed
setup_env_file() {
    debug "Starting setup_env_file_integrated function..."
    local target_dir="$1"

    # Step 1: Check if .env file exists, otherwise use template
    if [ ! -f "$target_dir/.env" ]; then
        _1_2_info "No .env file found, using .env.example as a template."

        # Search for the .env.example file in case it's not in the expected location
        env_example_path=$(find "$target_dir" -name ".env.example" -print -quit)

        if [ -n "$env_example_path" ]; then
            # Copy the .env.example to .env
            cp "$env_example_path" "$target_dir/.env"
            _1_2_info "Created new .env file from .env.example."
        else
            error ".env.example not found. Ensure the example file is present. Check if the installation archive is complete."
            return 1
        fi
    else
        _1_2_info ".env file already exists. Validating required environment variables..."
    fi

    # Step 2: Set ownership and permissions for the .env file
    chown www-data:www-data "$target_dir/.env" # Set the owner to www-data
    chmod 640 "$target_dir/.env"               # Set secure permissions for the .env file

    # Step 3: Ask the user which database to use
    local DB_CHOICE
    if [ "$NON_INTERACTIVE" = true ]; then
        DB_CHOICE="mysql" # Default to MySQL in non-interactive mode
        _1_2_info "Using MySQL for database in non-interactive mode."
    else
        echo -e "\n${COLOR_CYAN}Select the database type:${COLOR_RESET}"
        echo "1) MySQL"
        echo "2) SQLite"

        while true; do
            prompt "Enter your choice [1-2] (default: 1): "
            read DB_SELECTION
            DB_SELECTION=${DB_SELECTION:-1} # Default to MySQL if Enter is pressed

            case "$DB_SELECTION" in
            1)
                DB_CHOICE="mysql"
                break
                ;; # Valid input, exit loop
            2)
                DB_CHOICE="sqlite"
                break
                ;; # Valid input, exit loop
            *)
                error "Invalid option. Please select 1 for MySQL or 2 for SQLite."
                ;;
            esac
        done
    fi

    # Step 4: Initialize database using our new consolidated function
    if ! initialize_database "$target_dir" "$DB_CHOICE"; then
        error "Failed to initialize database. Please check the logs."
        return 1
    fi

    # Step 5: Set APP_URL based on whether a domain is configured or not
    if [ "$HAS_DOMAIN" = true ]; then
        validate_env_var "APP_URL" "https://$DOMAIN_NAME/firefly-iii"
        _1_2_info "APP_URL set to https://$DOMAIN_NAME/firefly-iii in .env."
    else
        validate_env_var "APP_URL" "http://${server_ip}/firefly-iii"
        _1_2_info "APP_URL set to http://${server_ip}/firefly-iii in .env."
    fi

    # Step 6: Generate STATIC_CRON_TOKEN and set in .env
    _1_2_info "Generating STATIC_CRON_TOKEN..."
    STATIC_CRON_TOKEN=$(openssl rand -hex 16)
    validate_env_var "STATIC_CRON_TOKEN" "$STATIC_CRON_TOKEN"
    export STATIC_CRON_TOKEN
    1_3_success "STATIC_CRON_TOKEN set in .env file."

    # Step 7: Set up the cron job
    setup_cron_job

    # Step 8: Set the log channel to prevent log file permission issues
    validate_env_var "LOG_CHANNEL" "stack"

    # Step 9: Set default locale and timezone if not already set
    local timezone=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || echo "UTC")
    local locale="en_US"

    validate_env_var "TZ" "${TZ:-$timezone}"
    validate_env_var "DEFAULT_LOCALE" "${DEFAULT_LOCALE:-$locale}"

    # Step 10: Set app environment to production
    validate_env_var "APP_ENV" "production"
    validate_env_var "APP_DEBUG" "false"

    1_3_success ".env file validated and populated successfully."

    # Verify the database configuration
    if ! verify_database_config "$target_dir"; then
        error "Database configuration verification failed."
        return 1
    fi

    1_3_success ".env file and database configuration completed successfully."

    # Indicate successful completion
    return 0
}

# Function to create MySQL database
# Returns:
#   0 if database creation succeeded, 1 if failed
create_mysql_db() {
    debug "Starting create_mysql_db function"
    # Step 1: Prompt for MySQL root password or use unix_socket authentication only if not set
    if [ -z "$MYSQL_ROOT_PASS" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            MYSQL_ROOT_PASS="" # Default to empty in non-interactive mode (uses unix_socket)
        else
            while true; do
                prompt "Enter the MySQL root password (press Enter to skip and use unix_socket authentication): "
                read -s MYSQL_ROOT_PASS
                echo

                if [ -z "$MYSQL_ROOT_PASS" ]; then
                    _1_4_warning "Using unix_socket authentication (no password required)."
                    break
                fi

                prompt "Confirm your MySQL root password: "
                read -s MYSQL_ROOT_PASS_CONFIRM
                echo

                if [ "$MYSQL_ROOT_PASS" != "$MYSQL_ROOT_PASS_CONFIRM" ]; then
                    error "Passwords do not match. Please try again."
                else
                    break # Exit loop if passwords match
                fi
            done
        fi
    fi

    # Step 2: Create a temporary MySQL configuration file for secure authentication
    local temp_mysql_conf=$(mktemp)
    chmod 600 "$temp_mysql_conf" # Secure permissions for sensitive file

    if [ -z "$MYSQL_ROOT_PASS" ]; then
        # Use unix_socket authentication
        cat >"$temp_mysql_conf" <<EOF
[client]
user=root
protocol=socket
EOF
    else
        # Use password authentication
        cat >"$temp_mysql_conf" <<EOF
[client]
user=root
password=${MYSQL_ROOT_PASS}
EOF
    fi

    # Step 3: Define MySQL command using the secure config file
    MYSQL_CMD="mysql --defaults-file=$temp_mysql_conf"

    # Step 4: Attempt to connect to MySQL and handle connection errors
    debug "Attempting to connect to MySQL with user: root, database: system"

    # Create a temp file to capture error output
    local mysql_error_output=$(mktemp)

    # First check if MySQL service is running
    if ! systemctl is-active --quiet mysql && ! systemctl is-active --quiet mariadb; then
        error "MySQL/MariaDB service is not running. Start it with: systemctl start mysql"
        # Clean up temporary files
        rm -f "$temp_mysql_conf" "$mysql_error_output"
        return 1
    fi

    # Test connection with error capture
    if ! echo "SELECT 1;" | $MYSQL_CMD 2>"$mysql_error_output"; then
        local error_msg=$(cat "$mysql_error_output")

        # Check for specific error conditions
        if grep -q "Access denied" "$mysql_error_output"; then
            error "MySQL authentication failed. Access denied for root user."
            error "Error details: $error_msg"
            error "Possible solutions:"
            error "1. If using password: verify the password is correct"
            error "2. If using socket: ensure root user has plugin auth_socket enabled"
            error "3. Try running: sudo mysql -u root # to test socket authentication"
        elif grep -q "Can't connect" "$mysql_error_output"; then
            error "Cannot connect to MySQL server."
            error "Error details: $error_msg"
            error "Possible solutions:"
            error "1. Check if MySQL is running: systemctl status mysql"
            error "2. Verify MySQL is listening on expected socket or port"
            error "3. Check MySQL error log: tail -n 50 /var/log/mysql/error.log"
        else
            error "Failed to connect to MySQL: $error_msg"
        fi

        # Clean up temporary files
        rm -f "$temp_mysql_conf" "$mysql_error_output"
        return 1
    fi

    # Clean up error output file, keep config file for further commands
    rm -f "$mysql_error_output"
    _1_2_info "Successfully connected to MySQL server."

    # Step 5: Check if the database exists, create if needed
    if echo "USE $DB_NAME;" | $MYSQL_CMD &>/dev/null; then
        _1_2_info "Database '$DB_NAME' already exists. Skipping creation."
    else
        _1_2_info "Database '$DB_NAME' does not exist. Creating it now..."
        # Create the database
        if ! echo "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" | $MYSQL_CMD; then
            error "Failed to create database '$DB_NAME'. Please check:
1. You have sufficient privileges
2. MySQL has enough disk space
3. The database name is valid"
            # Clean up temporary config file
            rm -f "$temp_mysql_conf"
            return 1
        fi
        1_3_success "Database '$DB_NAME' created successfully."
    fi

    # Export the MySQL command for other functions
    export MYSQL_CMD="$MYSQL_CMD"

    # Save the temp config file path for later cleanup
    export MYSQL_TEMP_CONF="$temp_mysql_conf"

    debug "MySQL connection result: $?"

    # Indicate successful completion
    return 0
}

# Function to create MySQL user
# Returns:
#   0 if user creation succeeded, 1 if failed
create_mysql_user() {
    debug "Starting create_mysql_user function"
    # Step 1: Check if the MySQL user exists
    if echo "SELECT 1 FROM mysql.user WHERE user = '$DB_USER';" | "${MYSQL_ROOT_CMD[@]}" | grep 1 &>/dev/null; then
        _1_2_info "MySQL user '$DB_USER' already exists. Updating privileges..."

        # Update privileges for existing user
        if ! echo "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" | "${MYSQL_ROOT_CMD[@]}"; then
            error "Failed to update privileges for MySQL user '$DB_USER'. Please check if you have sufficient privileges."
            return 1
        fi
        1_3_success "Privileges updated for existing user '$DB_USER'."
    else
        _1_2_info "Creating MySQL user '$DB_USER'..."
        # Properly escape all database identifiers and values
        ESCAPED_DB_USER=$(mysql_escape "$DB_USER")
        ESCAPED_DB_PASS=$(mysql_escape "$DB_PASS")
        ESCAPED_DB_NAME=$(mysql_escape "$DB_NAME")

        # Step 2: Create the user with properly escaped password
        if ! echo "CREATE USER '$ESCAPED_DB_USER'@'localhost' IDENTIFIED BY '$ESCAPED_DB_PASS';" | "${MYSQL_ROOT_CMD[@]}"; then
            error "Failed to create MySQL user '$DB_USER'. Please check:
1. If the user already exists
2. If you have sufficient privileges
3. If the username is valid"
            return 1
        fi

        # Step 3: Grant privileges
        if ! echo "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" | "${MYSQL_ROOT_CMD[@]}"; then
            error "Failed to grant privileges to MySQL user '$DB_USER'. Please check:
1. If the user was created successfully
2. If you have sufficient privileges to grant permissions
3. If the database exists"
            return 1
        fi
        1_3_success "MySQL user '$DB_USER' created and granted privileges successfully."
    fi

    # Indicate successful completion
    return 0
}

# Function to install required dependencies for Firefly III
# Returns:
#   0 if installation succeeded, 1 if failed
install_dependencies() {
    debug "Starting install_dependencies function"
    _1_2_info "Installing required dependencies for $os_type..."

    # Step 1: Update package lists
    if ! package_manager update ""; then
        error "Failed to update package lists. Please check your network connection."
        return 1
    fi

    # Step 2: Install core dependencies
    local core_packages=""

    case "$os_type" in
    "debian")
        core_packages="curl wget unzip gnupg2 ca-certificates lsb-release apt-transport-https software-properties-common jq cron"
        ;;
    "rhel")
        core_packages="curl wget unzip gnupg2 ca-certificates redhat-lsb-core dnf-plugins-core jq cronie"
        ;;
    "alpine")
        core_packages="curl wget unzip gnupg ca-certificates lsb-release jq cron"
        ;;
    esac

    if ! package_manager install "$core_packages"; then
        error "Failed to install core dependencies. Please check error logs."
        return 1
    fi

    1_3_success "Core dependencies installed."

    # Step 3: Check and generate locales if needed
    if ! locale -a | grep -qi "en_US\\.UTF-8"; then
        _1_2_info "Locales not found. Generating locales (this might take a while)..."

        case "$os_type" in
        "debian")
            package_manager install "language-pack-en"
            ;;
        "rhel")
            package_manager install "glibc-langpack-en"
            ;;
        "alpine")
            package_manager install "musl-locales"
            ;;
        esac

        locale-gen en_US.UTF-8 >/dev/null 2>&1
    else
        _1_2_info "Locales already generated. Skipping locale generation."
    fi

    # Step 4: Add PHP repository
    case "$os_type" in
    "debian")
        _2_4_add_php_repository
        ;;
    "rhel")
        package_manager install "epel-release dnf-utils"
        dnf install -y "http://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %rhel).rpm"
        ;;
    "alpine")
        _1_2_info "Alpine uses built-in PHP packages. No external repository needed."
        ;;
    esac

    # Update package lists after adding repositories
    package_manager update ""

    # Step 5: Install Apache and MariaDB
    case "$os_type" in
    "debian")
        if ! package_manager install "apache2 mariadb-server"; then
            error "Failed to install Apache and MariaDB. Please check error logs."
            return 1
        fi
        ;;
    "rhel")
        if ! package_manager install "httpd mariadb-server"; then
            error "Failed to install Apache and MariaDB. Please check error logs."
            return 1
        fi
        systemctl enable --now httpd mariadb
        ;;
    "alpine")
        if ! package_manager install "apache2 mariadb"; then
            error "Failed to install Apache and MariaDB. Please check error logs."
            return 1
        fi
        rc-service apache2 start
        rc-service mariadb start
        ;;
    esac

    # Step 6: Install SSL Tools (Certbot)
    case "$os_type" in
    "debian")
        package_manager install "certbot python3-certbot-apache"
        ;;
    "rhel")
        package_manager install "certbot python3-certbot-apache"
        ;;
    "alpine")
        package_manager install "certbot certbot-apache"
        ;;
    esac

    1_3_success "Dependencies installed successfully."
    return 0
}

# Function to configure SSL certificates
# Parameters:
#   $1 - domain_name: The domain name for the certificate (if already set)
#   $2 - email_address: The email address for Let's Encrypt registration (if already set)
# Returns:
#   0 if certificate setup succeeded, 1 if failed
configure_ssl() {
    debug "Starting configure_ssl function"
    local domain_name="$1"
    local email_address="$2"
    local use_self_signed="${3:-false}"

    _1_2_info "Configuring SSL certificate for $domain_name..."

    # Step 1: Validate domain name format
    if ! validate_input "$domain_name" "domain" "Invalid domain format: $domain_name" "true"; then
        error "SSL configuration requires a valid domain name."

        # Offer self-signed certificate in interactive mode
        if [ "$NON_INTERACTIVE" = false ] && [ "$use_self_signed" = false ]; then
            prompt "Would you like to use a self-signed certificate instead? (y/N): "
            read USE_SELF_SIGNED

            if [[ "$USE_SELF_SIGNED" =~ ^[Yy]$ ]]; then
                _1_2_info "Proceeding with self-signed certificate."
                use_self_signed=true
            else
                error "SSL configuration aborted. Please provide a valid domain name."
                return 1
            fi
        else
            return 1
        fi
    fi

    # Step 2: Validate email address if we're using Let's Encrypt
    if [ "$use_self_signed" = false ]; then
        while [ -z "$email_address" ]; do
            prompt "Enter your email address for SSL certificate registration: "
            read email_address

            if validate_input "$email_address" "email"; then
                break
            else
                error "Invalid email format. Please provide a valid email (e.g., user@example.com)."
                email_address=""
            fi
        done
    fi

    # Step 3: Create certificate directory if it doesn't exist
    local cert_dir="/etc/ssl/firefly"
    mkdir -p "$cert_dir"

    # Step 4: Check if appropriate certificates already exist
    if [ "$use_self_signed" = false ] && [ -d "/etc/letsencrypt/live/$domain_name" ]; then
        _1_2_info "Let's Encrypt certificates already exist for $domain_name. Checking validity..."

        # Check certificate expiration (within 30 days of expiring?)
        if openssl x509 -checkend 2592000 -noout -in "/etc/letsencrypt/live/$domain_name/cert.pem"; then
            1_3_success "Existing certificates are valid and not near expiration."
            return 0
        else
            _1_2_info "Certificates are near expiration. Attempting to renew..."
            if ! certbot renew --cert-name "$domain_name"; then
                _1_4_warning "Certificate renewal failed. Will attempt to obtain a new certificate."
            else
                1_3_success "Certificate renewed successfully."
                return 0
            fi
        fi
    elif [ "$use_self_signed" = true ] && [ -f "$cert_dir/self-signed.cert" ] && [ -f "$cert_dir/self-signed.key" ]; then
        _1_2_info "Self-signed certificates already exist. Checking validity..."

        # Check certificate expiration
        if openssl x509 -checkend 2592000 -noout -in "$cert_dir/self-signed.cert"; then
            1_3_success "Existing self-signed certificates are valid and not near expiration."
            return 0
        else
            _1_2_info "Self-signed certificates are near expiration. Generating new ones..."
        fi
    fi

    # Step 5: Generate appropriate certificate based on mode
    if [ "$use_self_signed" = true ]; then
        _1_2_info "Generating self-signed SSL certificate..."

        # Create OpenSSL configuration for SAN support
        local openssl_conf=$(mktemp)
        cat >"$openssl_conf" <<EOL
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Firefly III
OU = Self Hosted
CN = $domain_name

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $domain_name
DNS.2 = www.$domain_name
IP.1 = 127.0.0.1
EOL

        # Generate a new self-signed certificate
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$cert_dir/self-signed.key" \
            -out "$cert_dir/self-signed.cert" \
            -config "$openssl_conf"

        local result=$?
        rm -f "$openssl_conf"

        if [ $result -ne 0 ]; then
            error "Failed to generate self-signed certificate."
            return 1
        fi

        # Set proper permissions
        chmod 600 "$cert_dir/self-signed.key"
        chmod 644 "$cert_dir/self-signed.cert"

        1_3_success "Self-signed SSL certificate generated successfully."
    else
        # Step 6: Install prerequisite packages if needed
        _1_2_info "Checking for Certbot and required packages..."
        if ! command -v certbot &>/dev/null; then
            case "$os_type" in
            "debian")
                package_manager install "certbot python3-certbot-apache"
                ;;
            "rhel")
                package_manager install "certbot python3-certbot-apache"
                ;;
            "alpine")
                package_manager install "certbot certbot-apache"
                ;;
            esac
        fi

        # Step 7: Perform DNS validation check
        _1_2_info "Checking DNS resolution for $domain_name..."
        local server_ip=$(hostname -I | awk '{print $1}')
        local resolved_ip=$(dig +short "$domain_name" | head -n1)

        if [ -z "$resolved_ip" ]; then
            _1_4_warning "Could not resolve DNS for $domain_name. This may cause certificate validation to fail."

            # Offer to continue anyway or switch to self-signed in interactive mode
            if [ "$NON_INTERACTIVE" = false ]; then
                prompt "DNS resolution failed. Would you like to (1) continue anyway or (2) use a self-signed certificate instead? (1/2): "
                read DNS_CHOICE

                if [ "$DNS_CHOICE" = "2" ]; then
                    _1_2_info "Switching to self-signed certificate."
                    configure_ssl "$domain_name" "$email_address" "true"
                    return $?
                fi
                # Otherwise continue with Let's Encrypt
            fi
        elif [ "$resolved_ip" != "$server_ip" ]; then
            _1_4_warning "DNS for $domain_name resolves to $resolved_ip but this server's IP is $server_ip."
            _1_4_warning "Let's Encrypt validation may fail if DNS is not properly configured."

            # Offer to continue anyway or switch to self-signed in interactive mode
            if [ "$NON_INTERACTIVE" = false ]; then
                prompt "DNS mismatch detected. Would you like to (1) continue anyway or (2) use a self-signed certificate instead? (1/2): "
                read DNS_CHOICE

                if [ "$DNS_CHOICE" = "2" ]; then
                    _1_2_info "Switching to self-signed certificate."
                    configure_ssl "$domain_name" "$email_address" "true"
                    return $?
                fi
                # Otherwise continue with Let's Encrypt
            fi
        else
            _1_2_info "DNS resolution successful: $domain_name resolves to $resolved_ip"
        fi

        # Step 8: Obtain SSL certificate using Let's Encrypt
        _1_2_info "Obtaining SSL certificate using Let's Encrypt for $domain_name..."

        # Temporarily stop Apache to free up port 80
        apache_control "stop" || true

        # Try certbot with standalone method first (more reliable)
        if certbot certonly --standalone --non-interactive --agree-tos --email "$email_address" -d "$domain_name"; then
            1_3_success "SSL certificate successfully obtained for $domain_name using standalone method."
        else
            _1_4_warning "Standalone certificate request failed. Trying Apache method..."

            # Restart Apache and try the Apache plugin
            apache_control "start"

            if certbot --apache --non-interactive --agree-tos --email "$email_address" -d "$domain_name"; then
                1_3_success "SSL certificate successfully obtained for $domain_name using Apache method."
            else
                error "Failed to obtain SSL certificate. Please check:
1. Domain DNS settings (make sure $domain_name points to this server)
2. Firewall rules (ports 80 and 443 must be open)
3. Network connectivity
4. Apache configuration (must be running and correctly configured)"

                # Offer to use self-signed certificate as fallback in interactive mode
                if [ "$NON_INTERACTIVE" = false ]; then
                    prompt "Would you like to use a self-signed certificate instead? (y/N): "
                    read USE_SELF_SIGNED_FALLBACK

                    if [[ "$USE_SELF_SIGNED_FALLBACK" =~ ^[Yy]$ ]]; then
                        _1_2_info "Falling back to self-signed certificate."
                        configure_ssl "$domain_name" "$email_address" "true"
                        return $?
                    fi
                fi

                return 1
            fi
        fi

        # Make sure Apache is running after certificate setup
        apache_control "start" || true
    fi

    1_3_success "SSL certificate configuration completed successfully."
    return 0
}

# Function to configure Apache for Firefly III
# Parameters:
#   domain_name: The domain name (or empty if no domain is used)
#   document_root: The document root directory
#   has_ssl: Whether SSL is configured (true/false)
# Returns:
#   0 if configuration succeeded, 1 if failed
configure_apache() {
    debug "Starting configure_apache function"
    local domain_name="$1"
    local document_root="$2"
    local has_ssl="$3"

    _1_2_info "Configuring Apache for Firefly III..."

    # Step 1: Back up existing configuration
    if [ -f /etc/apache2/sites-available/firefly-iii.conf ]; then
        cp /etc/apache2/sites-available/firefly-iii.conf /etc/apache2/sites-available/firefly-iii.conf.bak
        _1_2_info "Backed up existing Apache configuration."
    fi

    # Step 2: Create configuration based on whether SSL is used
    if [ "$has_ssl" = true ]; then
        # Configuration with SSL
        cat >/etc/apache2/sites-available/firefly-iii.conf <<EOF
<VirtualHost *:80>
    ServerName $domain_name
    Redirect permanent / https://$domain_name/
</VirtualHost>

<VirtualHost *:443>
    ServerName $domain_name
    DocumentRoot $document_root/public

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$domain_name/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$domain_name/privkey.pem

    <Directory $document_root/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/firefly-error.log
    CustomLog \${APACHE_LOG_DIR}/firefly-access.log combined
</VirtualHost>
EOF

        # Enable required modules
        a2enmod ssl
        a2enmod rewrite
    else
        # Configuration without SSL
        cat >/etc/apache2/sites-available/firefly-iii.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $document_root/public

    <Directory $document_root/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/firefly-error.log
    CustomLog \${APACHE_LOG_DIR}/firefly-access.log combined
</VirtualHost>
EOF

        # Disable SSL module if enabled
        a2dismod ssl 2>/dev/null || true
        a2enmod rewrite
    fi

    # Step 3: Enable the site and disable default site
    a2ensite firefly-iii
    a2dissite 000-default.conf 2>/dev/null || true

    # Step 4: Test Apache configuration
    if ! apachectl configtest; then
        error "Apache configuration test failed. Please check the configuration file for errors. Try running 'apachectl configtest' manually."
        return 1
    fi

    # Step 5: Restart Apache
    if ! apache_control "restart"; then
        error "Failed to restart Apache. Please check:
1. Apache error logs: sudo tail -f /var/log/apache2/error.log
2. Apache configuration: sudo apachectl configtest
3. Apache status: sudo systemctl status apache2"
        return 1
    fi

    1_3_success "Apache configured successfully for Firefly III."
    return 0
}

# Function to install Firefly III
# Returns:
#   0 if installation succeeded, 1 if failed
install_firefly() {
    debug "Starting install_firefly function"
    _1_2_info "Starting Firefly III installation..."

    # Step 1: Install dependencies and prepare environment
    install_dependencies || return 1

    # Step 2: Detect PHP version
    LATEST_PHP_VERSION=$(get_latest_php_version)
    _1_2_info "Latest available stable PHP version is: $LATEST_PHP_VERSION"

    # Step 3: Check if PHP is already installed
    if command -v php &>/dev/null; then
        # PHP is installed, detect the current version
        CURRENT_PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
        _1_2_info "PHP is currently installed with version: $CURRENT_PHP_VERSION"

        # Determine if an upgrade is needed based on version comparison
        if [ "$(printf '%s\n' "$LATEST_PHP_VERSION" "$CURRENT_PHP_VERSION" | sort -V | head -n1)" != "$LATEST_PHP_VERSION" ]; then
            UPGRADE_NEEDED=true
        else
            UPGRADE_NEEDED=false
        fi

        # Check if non-interactive or prompt user for PHP upgrade
        if [ "$NON_INTERACTIVE" = true ]; then
            UPGRADE_PHP=${UPGRADE_NEEDED}
        else
            if [ "$UPGRADE_NEEDED" = true ]; then
                while true; do
                    prompt "A newer stable PHP version ($LATEST_PHP_VERSION) is available. Do you want to upgrade? (Y/n): "
                    read UPGRADE_PHP_INPUT
                    UPGRADE_PHP_INPUT=${UPGRADE_PHP_INPUT:-Y} # Default to "Y" if no input

                    if validate_input "$UPGRADE_PHP_INPUT" "yes_no"; then
                        UPGRADE_PHP=$([[ "$UPGRADE_PHP_INPUT" =~ ^[Yy]$ ]] && echo true || echo false)
                        break # Exit loop if input is valid
                    fi
                done
            else
                UPGRADE_PHP=false
                _1_2_info "PHP is up to date."
            fi
        fi

        # Upgrade PHP if needed
        if [ "$UPGRADE_PHP" = true ]; then
            _1_2_info "Upgrading to PHP $LATEST_PHP_VERSION..."
            php_manager "configure" "$LATEST_PHP_VERSION" || return 1

            # Handle retaining or disabling older PHP versions
            if [ "$NON_INTERACTIVE" = true ]; then
                RETAIN_OLD_PHP="N" # Default to not retaining old PHP versions in non-interactive mode
            else
                while true; do
                    prompt "Do you want to retain older PHP versions? (y/N): "
                    read RETAIN_OLD_PHP
                    RETAIN_OLD_PHP=${RETAIN_OLD_PHP:-N}

                    if validate_input "$RETAIN_OLD_PHP" "yes_no"; then
                        break
                    fi
                done
            fi

            if [[ "$RETAIN_OLD_PHP" =~ ^[Yy]$ ]]; then
                _1_2_info "Retaining all older PHP versions. This might increase disk usage and may cause conflicts if other applications depend on older PHP versions."
            else
                _1_4_warning "Disabling older PHP versions may affect other applications that use these versions. Ensure that other applications are compatible with the new PHP version before proceeding."

                # Proceed with disabling old PHP versions
                for version in $(ls /etc/apache2/mods-enabled/php*.load 2>/dev/null | grep -oP 'php\K[\d.]+(?=.load)' | grep -v "$LATEST_PHP_VERSION"); do
                    # Backup the current PHP configuration before disabling it
                    PHP_CONF="/etc/apache2/mods-available/php${version}.conf"
                    if [ -f "$PHP_CONF" ]; then
                        cp "$PHP_CONF" "${PHP_CONF}.bak"
                        _1_2_info "Backed up $PHP_CONF to ${PHP_CONF}.bak"
                    fi
                    a2dismod "php${version}" 2>/dev/null
                    _1_2_info "Disabled PHP $version"
                done
                1_3_success "Older PHP versions have been disabled."
            fi
        else
            _1_2_info "Skipping PHP upgrade. Using installed version: $CURRENT_PHP_VERSION"
            LATEST_PHP_VERSION=$CURRENT_PHP_VERSION
        fi
    else
        # PHP is not installed, proceed to install the latest stable version
        _1_2_info "PHP is not currently installed. Installing PHP $LATEST_PHP_VERSION..."
        php_manager "configure" "$LATEST_PHP_VERSION" || return 1
    fi

    # Step 4: Remove any installed RC versions of PHP dynamically
    _1_2_info "Checking for any installed RC versions of PHP..."
    RC_PHP_PACKAGES=$(dpkg -l | awk '/^ii/{print $2}' | grep -E '^php[0-9\.]+(-|$)' | while read -r pkg; do
        # Get the package version
        pkg_version=$(dpkg -s "$pkg" | awk '/Version:/{print $2}')
        # Check if the version contains 'RC', 'alpha', or 'beta'
        if [[ "$pkg_version" =~ (alpha|beta|RC) ]]; then
            echo "$pkg"
        fi
    done)

    if [ -n "$RC_PHP_PACKAGES" ]; then
        _1_2_info "Found installed PHP RC versions: $RC_PHP_PACKAGES"
        apt purge -y $RC_PHP_PACKAGES
        _1_2_info "Purged PHP RC versions."
    else
        _1_2_info "No PHP RC versions installed."
    fi

    # Step 5: Prompt for domain name and email address
    if [ "$NON_INTERACTIVE" = true ]; then
        # Use environment variables or defaults in non-interactive mode
        HAS_DOMAIN="${HAS_DOMAIN:-false}"
        if [ "$HAS_DOMAIN" = true ]; then
            DOMAIN_NAME="${DOMAIN_NAME:?Error: DOMAIN_NAME is required when HAS_DOMAIN=true}"
            EMAIL_ADDRESS="${EMAIL_ADDRESS:?Error: EMAIL_ADDRESS is required when HAS_DOMAIN=true}"
        else
            DOMAIN_NAME=""
            EMAIL_ADDRESS=""
        fi
    else
        while true; do
            prompt "Do you have a registered domain name you want to use? (y/N): "
            read HAS_DOMAIN_INPUT
            HAS_DOMAIN_INPUT=${HAS_DOMAIN_INPUT:-N} # Default to 'N' if Enter is pressed

            if validate_input "$HAS_DOMAIN_INPUT" "yes_no"; then
                break # Exit loop if input is valid
            fi
        done

        if [[ "$HAS_DOMAIN_INPUT" =~ ^[Yy]$ ]]; then
            HAS_DOMAIN=true

            # Loop until a valid domain is entered
            while true; do
                prompt "Enter your domain name (e.g., example.com): "
                read DOMAIN_NAME
                DOMAIN_NAME=${DOMAIN_NAME:-example.com} # Default to example.com if empty

                if validate_input "$DOMAIN_NAME" "domain"; then
                    break # Exit loop if valid domain is provided
                else
                    error "Invalid domain format: $DOMAIN_NAME. Please enter a valid domain (e.g., example.com)."
                fi
            done

            # Loop until a valid email is entered
            while true; do
                prompt "Enter your email address for SSL certificate registration: "
                read EMAIL_ADDRESS
                EMAIL_ADDRESS=${EMAIL_ADDRESS:-your-email@example.com} # Default email if empty

                if validate_input "$EMAIL_ADDRESS" "email"; then
                    break # Exit loop if valid email is provided
                else
                    error "Invalid email format: $EMAIL_ADDRESS. Please enter a valid email (e.g., user@example.com)."
                fi
            done
        else
            HAS_DOMAIN=false
            DOMAIN_NAME=""
            EMAIL_ADDRESS=""
        fi
    fi

    # Step 6: Configure SSL if domain is provided
    if [ "$HAS_DOMAIN" = true ]; then
        configure_ssl "$DOMAIN_NAME" "$EMAIL_ADDRESS" || return 1
    else
        _1_4_warning "No domain name provided. Skipping SSL certificate generation."
    fi

    # Step: Verify if Certbot's systemd timer or cron job for renewal exists
    check_certbot_auto_renewal

    # Step 7: Install Composer
    _1_2_info "Installing Composer..."
    EXPECTED_SIGNATURE=$(curl -s https://composer.github.io/installer.sig)
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_SIGNATURE=$(php -r "echo hash_file('sha384', 'composer-setup.php');")

    if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
        error "Invalid Composer installer signature. This could indicate a compromised download. Please try again or install Composer manually from https://getcomposer.org/download/."
        rm composer-setup.php
        return 1
    fi

    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php

    # Step 8: Download and validate Firefly III
    download_and_validate_release "firefly-iii/firefly-iii" "$FIREFLY_TEMP_DIR" "\\.zip$" || return 1

    # Step 9: Extract the archive file
    archive_file=$(ls "$FIREFLY_TEMP_DIR"/*.zip | head -n 1)
    extract_archive "$archive_file" "$FIREFLY_INSTALL_DIR" || return 1

    # Step 10: Ensure Composer cache directory exists
    _1_2_info "Ensuring Composer cache directory exists..."
    mkdir -p /var/www/.cache/composer/files/
    chown -R www-data:www-data /var/www/.cache/composer
    chmod -R 775 /var/www/.cache/composer

    # Step 11: Run composer install if vendor directory is missing
    if [ ! -d "$FIREFLY_INSTALL_DIR/vendor" ]; then
        _1_2_info "Running composer install for Firefly III..."
        if ! composer_install_with_progress "$FIREFLY_INSTALL_DIR"; then
            error "Composer install failed. This might indicate compatibility issues."
            return 1
        fi
    else
        _1_2_info "Vendor directory exists. Skipping composer install."
    fi

    # Step 12: Set permissions for Firefly III
    _1_2_info "Setting permissions for Firefly III..."
    chown -R www-data:www-data "$FIREFLY_INSTALL_DIR"
    chmod -R 775 "$FIREFLY_INSTALL_DIR/storage"

    # Step 13: Configure Firefly III environment
    _1_2_info "Configuring Firefly III..."
    setup_env_file "$FIREFLY_INSTALL_DIR"

    # Step 14: Set permissions before running artisan commands
    _1_2_info "Setting ownership and permissions for Firefly III..."
    chown -R www-data:www-data "$FIREFLY_INSTALL_DIR"
    chmod -R 775 "$FIREFLY_INSTALL_DIR"

    # Step 15: Run artisan commands with error handling
    _1_2_info "Running artisan commands for Firefly III..."
    cd "$FIREFLY_INSTALL_DIR"

    # Step 15.1: Check if APP_KEY is already set in the .env file and not the placeholder
    setup_app_key || return 1

    # Step 15.2: Run database migrations
    _1_2_info "Running database migrations..."
    run_database_migrations || return 1

    # Step 15.3: Update database schema and correct any issues
    update_database_schema || return 1

    # Step 15.4: Install Laravel Passport if not already installed
    install_laravel_passport || return 1

    # Step 16: Configure Apache for Firefly III
    if [ "$HAS_DOMAIN" = true ]; then
        configure_apache "$DOMAIN_NAME" "$FIREFLY_INSTALL_DIR" true || return 1
    else
        configure_apache "" "$FIREFLY_INSTALL_DIR" false || return 1
    fi

    1_3_success "Firefly III installation completed successfully."
    return 0
}

# Function to set up APP_KEY for Firefly III
# Returns:
#   0 if setup succeeded, 1 if failed
setup_app_key() {
    debug "Starting setup_app_key function..."
    # Step 1: Check if APP_KEY is already set and valid
    if grep -q '^APP_KEY=SomeRandomStringOf32CharsExactly' "$FIREFLY_INSTALL_DIR/.env" ||
        ! grep -q '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env" ||
        [ -z "$(grep '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2)" ]; then

        _1_2_info "APP_KEY is missing or using a placeholder. Generating a new APP_KEY."

        # Step 2: Ensure the .env file exists and is writable
        if [ ! -f "$FIREFLY_INSTALL_DIR/.env" ]; then
            cp "$FIREFLY_INSTALL_DIR/.env.example" "$FIREFLY_INSTALL_DIR/.env"
            _1_2_info ".env file created from .env.example."
        fi

        # Step 3: Generate the application key using php artisan, keep the base64: prefix
        APP_KEY=$(sudo -u www-data php artisan key:generate --show)

        # Step 4: Validate the generated APP_KEY (without base64: it should be 32 characters long)
        decoded_key=$(echo "${APP_KEY#base64:}" | base64 --decode 2>/dev/null)
        if [ ${#decoded_key} -ne 32 ]; then
            error "Generated APP_KEY is invalid. Expected a base64-encoded 32-character key. Try generating a key manually with: php artisan key:generate --show"
            return 1
        fi

        # Step 5: Set the new APP_KEY in the .env file, ensuring base64 prefix is retained
        sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|" "$FIREFLY_INSTALL_DIR/.env"

        # Step 6: Capture the newly generated APP_KEY
        if [ -z "$APP_KEY" ]; then
            error "Failed to retrieve APP_KEY from .env file. Check if the key was properly generated and stored."
            return 1
        else
            _1_2_info "APP_KEY generated and set successfully."
            export APP_KEY
        fi

    else
        _1_2_info "APP_KEY already set and valid. Skipping key generation."
        export APP_KEY=$(grep '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2)
    fi

    return 0
}

# Unified database management system for Firefly III installation
# Handles connection, credential management, schema operations, and error handling

# Function to create a secure database connection configuration
# Parameters:
#   user: Database user (default: root)
#   password: Database password (optional, uses socket auth if empty)
#   host: Database host (default: localhost)
# Returns:
#   Path to config file on success, empty string on failure
create_db_config() {
    debug "Starting create_db_config function"
    local user="${1:-root}"
    local password="$2"
    local host="${3:-localhost}"

    # Create a temporary MySQL configuration file for secure authentication
    local config_file=$(mktemp)
    chmod 600 "$config_file" # Secure permissions for sensitive file

    if [ -z "$password" ]; then
        # Use unix_socket authentication
        cat >"$config_file" <<EOF
[client]
user=$user
protocol=socket
EOF
    else
        # Use password authentication
        cat >"$config_file" <<EOF
[client]
user=$user
password=$password
host=$host
EOF
    fi

    echo "$config_file"
    return 0
}

# Function to execute SQL commands with error handling
# Parameters:
#   config_file: Path to MySQL config file
#   database: Database name (optional)
#   query: SQL query to execute
# Returns:
#   0 on success, 1 on failure
execute_sql() {
    debug "Starting execute_sql function"
    local config_file="$1"
    local database="$2"
    local query="$3"

    # Validate inputs
    if [ ! -f "$config_file" ]; then
        error "Database configuration file not found: $config_file"
        return 1
    fi

    # Execute the query
    local mysql_cmd="mysql --defaults-file=$config_file"
    if [ -n "$database" ]; then
        mysql_cmd="$mysql_cmd -D $database"
    fi

    # Create temp files for output and errors
    local output_file=$(mktemp)
    local error_file=$(mktemp)

    # Execute the query with error handling
    debug "Executing SQL: $query"
    if ! echo "$query" | $mysql_cmd >"$output_file" 2>"$error_file"; then
        local error_msg=$(cat "$error_file")

        # Check for specific error conditions
        if grep -q "Access denied" "$error_file"; then
            error "MySQL authentication failed. Access denied for user $1."
            error "Error details: $error_msg"
        elif grep -q "Can't connect" "$error_file"; then
            error "Cannot connect to MySQL server."
            error "Error details: $error_msg"
        else
            error "Failed to execute SQL query: $error_msg"
        fi

        # Clean up
        rm -f "$output_file" "$error_file"
        return 1
    fi

    # Return success and cleanup
    local result=$(cat "$output_file")
    rm -f "$output_file" "$error_file"

    # If there's output, echo it
    if [ -n "$result" ]; then
        echo "$result"
    fi

    return 0
}

# Function to setup and validate database connection
# Parameters:
#   user: Database user
#   password: Database password
#   db_name: Database name to check/create
# Returns:
#   Path to config file on success, empty string on failure
setup_database_connection() {
    debug "Starting setup_database_connection function"
    local user="$1"
    local password="$2"
    local db_name="$3"

    # Create MySQL config for connection
    local config_file=$(create_db_config "$user" "$password")

    # Test connection
    _1_2_info "Testing database connection..."
    if ! execute_sql "$config_file" "" "SELECT 1" >/dev/null; then
        error "Database connection test failed"
        rm -f "$config_file"
        return 1
    fi

    # Check if database exists, create if needed
    if execute_sql "$config_file" "" "USE $db_name" &>/dev/null; then
        _1_2_info "Database '$db_name' already exists."
    else
        _1_2_info "Database '$db_name' does not exist. Creating it now..."
        if ! execute_sql "$config_file" "" "CREATE DATABASE $db_name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"; then
            error "Failed to create database '$db_name'."
            rm -f "$config_file"
            return 1
        fi
        1_3_success "Database '$db_name' created successfully."
    fi

    echo "$config_file"
    return 0
}

# Function to create database user with proper privileges
# Parameters:
#   config_file: Path to MySQL config file with admin privileges
#   db_user: User to create
#   db_pass: Password for the user
#   db_name: Database name to grant privileges on
# Returns:
#   0 on success, 1 on failure
create_database_user() {
    debug "Starting create_database_user function"
    local config_file="$1"
    local db_user="$2"
    local db_pass="$3"
    local db_name="$4"

    # Check if the user exists
    if execute_sql "$config_file" "mysql" "SELECT 1 FROM user WHERE user = '$db_user'" | grep -q 1; then
        _1_2_info "MySQL user '$db_user' already exists. Updating privileges..."

        # Update privileges for existing user
        local query="GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost'; FLUSH PRIVILEGES;"
        if ! execute_sql "$config_file" "" "$query"; then
            error "Failed to update privileges for MySQL user '$db_user'."
            return 1
        fi
        1_3_success "Privileges updated for existing user '$db_user'."
    else
        _1_2_info "Creating MySQL user '$db_user'..."

        # Properly escape all database identifiers and values
        local escaped_db_user=$(mysql_escape "$db_user")
        local escaped_db_pass=$(mysql_escape "$db_pass")
        local escaped_db_name=$(mysql_escape "$db_name")

        # Create user with privileges
        local create_query="CREATE USER '$escaped_db_user'@'localhost' IDENTIFIED BY '$escaped_db_pass';"
        local grant_query="GRANT ALL PRIVILEGES ON $escaped_db_name.* TO '$escaped_db_user'@'localhost'; FLUSH PRIVILEGES;"

        if ! execute_sql "$config_file" "" "$create_query"; then
            error "Failed to create MySQL user '$db_user'."
            return 1
        fi

        if ! execute_sql "$config_file" "" "$grant_query"; then
            error "Failed to grant privileges to MySQL user '$db_user'."
            return 1
        fi

        1_3_success "MySQL user '$db_user' created and granted privileges successfully."
    fi

    return 0
}

# Function to run database migrations with improved error handling
# Parameters:
#   firefly_dir: Firefly III installation directory
# Returns:
#   0 on success, 1 on failure
run_database_migrations() {
    debug "Starting run_database_migrations function..."
    local firefly_dir="$1"
    local max_retries=3
    local retry_count=0
    local migration_success=false

    # Step 1: Check database connection before attempting migrations
    _1_2_info "Verifying database connection before migrations..."
    if ! cd "$firefly_dir" || ! sudo -u www-data php artisan db:show &>/dev/null; then
        error "Failed to connect to database. Please check:
1. Database service is running
2. Database credentials in .env are correct
3. Database exists and is accessible"
        return 1
    fi

    # Step 2: Check migration status to determine if migrations are needed
    _1_2_info "Checking database migration status..."
    local migration_status_output=$(mktemp)

    if sudo -u www-data php artisan migrate:status >"$migration_status_output" 2>&1; then
        # Check if all migrations are already run
        if grep -q 'No migrations to run' "$migration_status_output" ||
            ! grep -q 'not found in "migrations"' "$migration_status_output"; then
            _1_2_info "All migrations have already been applied. Skipping migration step."
            rm -f "$migration_status_output"
            return 0
        else
            _1_2_info "Pending migrations found. Proceeding with database migration."
        fi
    else
        # Migration:status can fail if the migrations table doesn't exist yet
        _1_2_info "Migration status check indicates fresh installation."
    fi

    rm -f "$migration_status_output"

    # Step 3: Attempt migrations with retries
    while [ $retry_count -lt $max_retries ] && [ "$migration_success" = false ]; do
        _1_2_info "Running database migrations (attempt $((retry_count + 1))/$max_retries)..."

        # Capture both stdout and stderr
        local migration_output=$(mktemp)

        # Increase timeouts and memory limits before migrations
        if [ -f "$firefly_dir/.env" ]; then
            # Temporarily adjust PHP settings for migrations
            sed -i 's/^MAX_EXECUTION_TIME=.*/MAX_EXECUTION_TIME=300/' "$firefly_dir/.env"
            sed -i 's/^MEMORY_LIMIT=.*/MEMORY_LIMIT=512M/' "$firefly_dir/.env"
        fi

        # Run the migration command
        if run_artisan_command_with_progress "migrate --force" "Database Migration"; then
            migration_success=true
            _1_2_info "Database migration completed successfully."
        else
            retry_count=$((retry_count + 1))

            if [ $retry_count -lt $max_retries ]; then
                _1_4_warning "Migration attempt $retry_count failed. Waiting before retry..."
                sleep 5 # Wait before retrying

                # Additional error handling based on common migration issues
                if grep -q "could not find driver" "$migration_output"; then
                    _1_4_warning "Missing database driver detected. Installing required PHP extensions..."
                    install_php_extension "pdo"
                    install_php_extension "mysql"
                elif grep -q "Access denied" "$migration_output"; then
                    error "Database access denied. Please check your database credentials in .env"
                    cat "$migration_output" >>"$LOG_FILE"
                    rm -f "$migration_output"
                    return 1
                elif grep -q "Connection refused" "$migration_output"; then
                    _1_4_warning "Database connection refused. Checking if database service is running..."
                    service mysql status >/dev/null || service mariadb status >/dev/null || {
                        _1_4_warning "Database service appears to be stopped. Attempting to restart..."
                        service mysql start || service mariadb start
                    }
                fi
            else
                error "Failed to migrate database after $max_retries attempts."
                cat "$migration_output" >>"$LOG_FILE"
                rm -f "$migration_output"
                return 1
            fi
        fi

        rm -f "$migration_output"
    done

    # Step 4: Verify migrations were applied correctly
    _1_2_info "Verifying database schema after migrations..."
    if ! sudo -u www-data php artisan migrate:status | grep -q 'Migration table created successfully'; then
        # Run a simple query to check database health
        if ! sudo -u www-data php artisan db:show --tables | grep -q 'migrations'; then
            _1_4_warning "Migration verification shows potential issues. Checking database health..."
            if ! sudo -u www-data php artisan db:show --tables; then
                error "Database appears to be in an inconsistent state after migrations."
                return 1
            fi
        fi
    fi

    1_3_success "Database migrations completed and verified successfully."
    return 0
}

# Function to update database schema with improved error reporting
# Parameters:
#   firefly_dir: Firefly III installation directory
# Returns:
#   0 on success, 1 on failure
update_database_schema() {
    debug "Starting update_database_schema function..."
    local firefly_dir="$1"

    # Change to the Firefly III directory
    cd "$firefly_dir" || {
        error "Failed to change to Firefly III directory: $firefly_dir"
        return 1
    }

    _1_2_info "Updating database schema and correcting any issues..."

    # Step 1: Cache configuration
    if ! run_artisan_command_with_progress "config:cache" "Caching Configuration"; then
        error "Failed to cache configuration with php artisan. Check your .env configuration for errors."
        return 1
    fi

    # Step 2: Upgrade database
    if ! run_artisan_command_with_progress "firefly-iii:upgrade-database" "Upgrading Database"; then
        error "Failed to upgrade Firefly III database. Check the logs for detailed errors."
        return 1
    fi

    # Step 3: Correct database
    if ! run_artisan_command_with_progress "firefly-iii:correct-database" "Correcting Database"; then
        error "Failed to correct database issues with Firefly III. Check the logs for detailed errors."
        return 1
    fi

    # Step 4: Report integrity
    if ! run_artisan_command_with_progress "firefly-iii:report-integrity" "Checking Database Integrity"; then
        error "Failed to report database integrity issues with Firefly III. Check the logs for detailed errors."
        return 1
    fi

    1_3_success "Database schema updated and corrected successfully."
    return 0
}

# Function to initialize a database environment for Firefly III
# Parameters:
#   target_dir: Target directory where .env file is located
#   db_type: Database type ("mysql" or "sqlite")
# Returns:
#   0 if initialization succeeded, 1 if failed
initialize_database() {
    debug "Starting initialize_database function"
    local target_dir="$1"
    local db_type="${2:-mysql}" # Default to MySQL if not specified

    _1_2_info "Initializing database environment for Firefly III..."

    case "$db_type" in
    "sqlite")
        # Configure for SQLite
        _1_2_info "Configuring SQLite database..."

        # Update .env file to use SQLite
        sed -i 's/DB_CONNECTION=.*/DB_CONNECTION=sqlite/' "$target_dir/.env"
        sed -i '/DB_HOST/d' "$target_dir/.env"
        sed -i '/DB_PORT/d' "$target_dir/.env"
        sed -i '/DB_DATABASE/d' "$target_dir/.env"
        sed -i '/DB_USERNAME/d' "$target_dir/.env"
        sed -i '/DB_PASSWORD/d' "$target_dir/.env"

        # Create SQLite database file
        mkdir -p "$target_dir/storage/database"
        touch "$target_dir/storage/database/database.sqlite"
        chown -R www-data:www-data "$target_dir/storage/database"

        1_3_success "SQLite database configured successfully."
        ;;

    "mysql")
        # Configure for MySQL
        _1_2_info "Configuring MySQL database..."

        # Array of adjectives and nouns for sensible random names
        ADJECTIVES=("brave" "happy" "clever" "bold" "calm" "keen" "quick" "bright")
        NOUNS=("sparrow" "lion" "eagle" "falcon" "tiger" "whale" "dolphin" "panther")

        # Function to generate a sensible name
        generate_sensible_name() {
            local adjective=${ADJECTIVES[$RANDOM % ${#ADJECTIVES[@]}]}
            local noun=${NOUNS[$RANDOM % ${#NOUNS[@]}]}
            echo "${adjective}_${noun}"
        }

        # Define default database name and user
        default_db_name="firefly_$(generate_sensible_name)"
        default_db_user="user_$(generate_sensible_name)"

        # Step 1: Prompt user for database info or use defaults
        if [ "$NON_INTERACTIVE" = true ]; then
            # Use default values in non-interactive mode
            DB_NAME="${DB_NAME:-$default_db_name}"
            DB_USER="${DB_USER:-$default_db_user}"
            DB_PASS="${DB_PASS:-$(openssl rand -base64 16)}"
        else
            # Interactive mode: prompt the user for input
            while true; do
                prompt "Enter the database name (press Enter for default: $default_db_name): "
                read DB_NAME_INPUT
                DB_NAME=${DB_NAME_INPUT:-$default_db_name}

                if validate_input "$DB_NAME" "db_identifier"; then
                    break
                else
                    error "Invalid database name. Only letters, numbers, underscores, and dashes are allowed."
                fi
            done

            while true; do
                prompt "Enter the database username (press Enter for default: $default_db_user): "
                read DB_USER_INPUT
                DB_USER=${DB_USER_INPUT:-$default_db_user}

                if validate_input "$DB_USER" "db_identifier" "Invalid username. Only letters, numbers, underscores, and dashes are allowed."; then
                    break
                fi
            done

            while true; do
                prompt "Enter the database password (press Enter for a randomly generated password): "
                read -s DB_PASS_INPUT
                echo

                if [ -z "$DB_PASS_INPUT" ]; then
                    # Generate a secure password that definitely meets our requirements
                    # Ensure it contains lowercase, uppercase, numbers, and special chars
                    local chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+"
                    DB_PASS=""

                    # Ensure at least one of each character type
                    DB_PASS+="${chars:$((RANDOM % 26)):1}"      # lowercase
                    DB_PASS+="${chars:$((RANDOM % 26 + 26)):1}" # uppercase
                    DB_PASS+="${chars:$((RANDOM % 10 + 52)):1}" # number
                    DB_PASS+="${chars:$((RANDOM % 15 + 62)):1}" # special

                    # Fill to 16 characters with random characters
                    while [ ${#DB_PASS} -lt 16 ]; do
                        DB_PASS+="${chars:$((RANDOM % ${#chars})):1}"
                    done

                    # Shuffle the password characters
                    DB_PASS=$(echo "$DB_PASS" | fold -w1 | shuf | tr -d '\n')

                    _1_2_info "A secure random password has been generated."
                    break
                fi

                prompt "Confirm your database password: "
                read -s DB_PASS_CONFIRM
                echo

                if [ "$DB_PASS_INPUT" != "$DB_PASS_CONFIRM" ]; then
                    error "Passwords do not match. Please try again."
                else
                    DB_PASS="$DB_PASS_INPUT"
                    break
                fi
            done
        fi

        # Step 2: Create the MySQL database and user
        if ! create_mysql_db; then
            error "Failed to create MySQL database."
            return 1
        fi

        if ! create_mysql_user; then
            error "Failed to create MySQL user."
            return 1
        fi

        # Step 3: Populate the .env file with the generated credentials
        validate_env_var "DB_CONNECTION" "mysql"
        validate_env_var "DB_HOST" "127.0.0.1"
        validate_env_var "DB_DATABASE" "$DB_NAME"
        validate_env_var "DB_USERNAME" "$DB_USER"
        validate_env_var "DB_PASSWORD" "$DB_PASS"

        1_3_success "MySQL database initialized successfully."
        ;;

    *)
        error "Unsupported database type: $db_type. Must be 'mysql' or 'sqlite'."
        return 1
        ;;
    esac

    # Export values for other functions
    export DB_NAME DB_USER DB_PASS

    return 0
}

# Function to verify database configuration and connection
# Parameters:
#   target_dir: Target directory where .env file is located
# Returns:
#   0 if database configuration is valid, 1 if not
verify_database_config() {
    debug "Starting verify_database_config function"
    local target_dir="$1"

    # Check if .env file exists
    if [ ! -f "$target_dir/.env" ]; then
        error "Cannot find .env file in $target_dir"
        return 1
    fi

    # Read database configuration from .env
    local db_connection=$(grep '^DB_CONNECTION=' "$target_dir/.env" | cut -d '=' -f2-)

    _1_2_info "Verifying database configuration for $db_connection..."

    # Handle different database types
    if [ "$db_connection" = "sqlite" ]; then
        # Check SQLite file
        local db_file="$target_dir/storage/database/database.sqlite"
        if [ ! -f "$db_file" ]; then
            error "SQLite database file not found: $db_file"
            return 1
        fi

        # Check if the file is writable by www-data
        if ! sudo -u www-data test -w "$db_file"; then
            error "SQLite database file is not writable by www-data: $db_file"
            return 1
        fi

        1_3_success "SQLite database configuration verified."
    elif [ "$db_connection" = "mysql" ]; then
        # Extract MySQL configuration
        local db_host=$(grep '^DB_HOST=' "$target_dir/.env" | cut -d '=' -f2-)
        local db_port=$(grep '^DB_PORT=' "$target_dir/.env" | cut -d '=' -f2-)
        local db_name=$(grep '^DB_DATABASE=' "$target_dir/.env" | cut -d '=' -f2-)
        local db_user=$(grep '^DB_USERNAME=' "$target_dir/.env" | cut -d '=' -f2-)
        local db_pass=$(grep '^DB_PASSWORD=' "$target_dir/.env" | cut -d '=' -f2-)

        # Create temp MySQL config
        local temp_config=$(mktemp)
        chmod 600 "$temp_config"
        cat >"$temp_config" <<EOF
[client]
host=$db_host
port=$db_port
user=$db_user
password=$db_pass
EOF

        # Test connection
        if ! mysql --defaults-file="$temp_config" -e "SELECT 1" "$db_name" &>/dev/null; then
            error "Failed to connect to MySQL database. Please check your credentials."
            rm -f "$temp_config"
            return 1
        fi

        rm -f "$temp_config"
        1_3_success "MySQL database configuration verified."
    else
        error "Unsupported database connection type: $db_connection"
        return 1
    fi

    return 0
}

# Function to install Laravel Passport with simplified output
# Returns:
#   0 if installation succeeded, 1 if failed
install_laravel_passport() {
    debug "Starting install_laravel_passport function..."
    # Step 1: Check if Passport tables already exist
    _1_2_info "Checking if Laravel Passport tables already exist..."
    PASSPORT_TABLE_EXISTS=$(mysql -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES LIKE 'oauth_auth_codes';" | grep -c "oauth_auth_codes" || echo "0")

    if [ "$PASSPORT_TABLE_EXISTS" -eq 0 ]; then
        _1_2_info "Passport tables do not exist. Installing Laravel Passport..."

        # Properly escape all database identifiers and values
        ESCAPED_DB_USER=$(mysql_escape "$DB_USER")
        ESCAPED_DB_PASS=$(mysql_escape "$DB_PASS")
        ESCAPED_DB_NAME=$(mysql_escape "$DB_NAME")

        if ! run_artisan_command_with_progress "passport:install --force --no-interaction" "Installing Laravel Passport"; then
            error "Failed to install Laravel Passport. Try running 'php artisan passport:install --force' manually to see detailed errors."
            return 1
        fi

        1_3_success "Laravel Passport installed successfully."
    else
        _1_2_info "Passport tables already exist. Skipping Laravel Passport installation."
    fi

    # Step 2: Remove Passport migration files if tables already exist
    if [ "$PASSPORT_TABLE_EXISTS" -ne 0 ]; then
        _1_2_info "Passport tables exist. Removing Passport migration files to prevent migration conflicts."
        rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000001_create_oauth_auth_codes_table.php"
        rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000002_create_oauth_access_tokens_table.php"
        rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000003_create_oauth_refresh_tokens_table.php"
        rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000004_create_oauth_clients_table.php"
        rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000005_create_oauth_personal_access_clients_table.php"
    fi

    return 0
}

# Function to validate or create .env file for Firefly Importer
# Accepts the directory (either $IMPORTER_INSTALL_DIR or $IMPORTER_TEMP_DIR) as an argument
# Parameters:
#   target_dir: The target directory containing the .env file
# Returns:
#   0 if setup succeeded, 1 if failed
setup_importer_env_file() {
    debug "Starting setup_importer_env_file function..."
    local target_dir="$1"

    # Step 1: Check if .env file exists, otherwise use template
    if [ ! -f "$target_dir/.env" ]; then
        _1_2_info "No .env file found in $target_dir, attempting to find .env.example as a template."

        # Search for .env.example in the target directory and subdirectories
        env_example_path=$(find "$target_dir" -name ".env.example" -print -quit)

        if [ -n "$env_example_path" ]; then
            cp "$env_example_path" "$target_dir/.env"
            _1_2_info "Created new .env file from .env.example at $env_example_path."
        else
            _1_4_warning ".env.example not found, creating a new .env file with default settings."
            # Create a default .env file
            cat >"$target_dir/.env" <<EOF
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://${server_ip}:8080
FIREFLY_III_URL=http://${server_ip}
EOF
            _1_2_info "Created new .env file with default settings."
        fi
    else
        _1_2_info ".env file already exists in $target_dir."
    fi

    # Step 2: Set URLs based on configuration
    local FIREFLY_III_URL
    local APP_URL

    if [ "$HAS_DOMAIN" = true ]; then
        FIREFLY_III_URL="https://$DOMAIN_NAME"
        APP_URL="https://$DOMAIN_NAME:8080"
    else
        FIREFLY_III_URL="http://${server_ip}"
        APP_URL="http://${server_ip}:8080"
    fi

    validate_env_var "FIREFLY_III_URL" "$FIREFLY_III_URL"
    validate_env_var "APP_URL" "$APP_URL"

    # Set production environment values
    validate_env_var "APP_ENV" "production"
    validate_env_var "APP_DEBUG" "false"

    # Configure basic security settings
    validate_env_var "TRUSTED_PROXIES" "*"
    validate_env_var "CACHE_DRIVER" "file"
    validate_env_var "QUEUE_CONNECTION" "sync"

    # Set logging configuration
    validate_env_var "LOG_CHANNEL" "stack"
    validate_env_var "LOG_LEVEL" "info"

    _1_2_info "FIREFLY_III_URL set to $FIREFLY_III_URL in .env."
    _1_2_info "APP_URL set to $APP_URL in .env."

    # Step 3: Set ownership and permissions for the .env file
    chown www-data:www-data "$target_dir/.env"
    chmod 640 "$target_dir/.env"

    1_3_success ".env file validated and updated for Firefly Importer."
    return 0
}

# Function to check Certbot auto-renewal mechanism
# Returns:
#   0 if checks succeeded, 1 if failed
check_certbot_auto_renewal() {
    debug "Starting check_certbot_auto_renewal function..."
    _1_2_info "Checking for Certbot auto-renewal mechanism..."

    # Step 1: Check for systemd timer
    if systemctl list-timers | grep -q certbot; then
        _1_2_info "Certbot systemd timer found. Auto-renewal is already configured."
    else
        # Step 2: Check for existing cron job for Certbot
        if crontab -l | grep -q "certbot renew"; then
            _1_2_info "Certbot cron job for auto-renewal found. No further action needed."
        else
            # Step 3: Add a cron job to auto-renew the SSL certificate if neither exists
            _1_2_info "No existing auto-renewal mechanism found. Setting up cron job for Certbot renewal..."
            (
                crontab -l 2>/dev/null
                echo "0 */12 * * * certbot renew --quiet --renew-hook 'systemctl reload apache2'"
            ) | crontab -
            _1_2_info "Cron job for Certbot renewal added. It will run twice a day."
        fi
    fi

    return 0
}

# Function to install Firefly Importer
# Returns:
#   0 if installation succeeded, 1 if failed
install_firefly_importer() {
    debug "Starting install_firefly_importer function..."
    _1_2_info "Installing Firefly Importer..."

    # Step 1: Download and validate Firefly Importer
    download_and_validate_release "firefly-iii/data-importer" "$IMPORTER_TEMP_DIR" "\\.zip$" || return 1

    # Step 2: Extract the archive file
    archive_file=$(ls "$IMPORTER_TEMP_DIR"/*.zip | head -n 1)
    extract_archive "$archive_file" "$IMPORTER_TEMP_DIR" || return 1

    # Step 3: Move the extracted files to the installation directory
    _1_2_info "Installing Firefly Importer to $IMPORTER_INSTALL_DIR..."
    mv "$IMPORTER_TEMP_DIR"/* "$IMPORTER_INSTALL_DIR/"

    # Step 4: Set ownership and permissions
    _1_2_info "Setting ownership and permissions for Firefly Importer..."
    chown -R www-data:www-data "$IMPORTER_INSTALL_DIR"
    find "$IMPORTER_INSTALL_DIR" -type f -exec chmod 644 {} \;
    find "$IMPORTER_INSTALL_DIR" -type d -exec chmod 755 {} \;
    chmod -R 775 "$IMPORTER_INSTALL_DIR/storage" "$IMPORTER_INSTALL_DIR/bootstrap/cache"

    # Step 5: Setup the .env file before running artisan commands
    setup_importer_env_file "$IMPORTER_INSTALL_DIR"

    # Step 6: Ensure Composer is ready for Firefly Importer installation
    setup_composer_for_importer || return 1

    # Step 7: Install Composer dependencies
    install_importer_dependencies || return 1

    # Step 8: Generate application key
    _1_2_info "Generating application key for Firefly Importer..."
    sudo -u www-data php artisan key:generate --no-interaction --force || {
        error "Failed to generate application key for Firefly Importer. Try running 'php artisan key:generate --no-interaction --force' manually to see detailed errors."
        return 1
    }

    # Step 9: Configure Apache for Firefly Importer
    configure_apache_for_importer || return 1

    1_3_success "Firefly Importer installation completed."
    return 0
}

# Function to set up Composer for the Importer
# Returns:
#   0 if setup succeeded, 1 if failed
setup_composer_for_importer() {
    debug "Starting setup_composer_for_importer function..."
    _1_2_info "Ensuring Composer is installed for Firefly Importer dependencies..."

    # Step 1: Verify Composer installation or install it
    if ! command -v composer &>/dev/null; then
        EXPECTED_SIGNATURE=$(curl -s https://composer.github.io/installer.sig)
        php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
        ACTUAL_SIGNATURE=$(php -r "echo hash_file('sha384', 'composer-setup.php');")

        if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
            echo >&2 'ERROR: Invalid installer signature for Composer.'
            rm composer-setup.php
            return 1
        fi

        php composer-setup.php --install-dir=/usr/local/bin --filename=composer
        rm composer-setup.php
    fi

    # Step 2: Prepare Composer cache directories
    _1_2_info "Ensuring Composer cache directories exist..."
    mkdir -p /var/www/.cache/composer/files/
    chown -R www-data:www-data /var/www/.cache/composer
    chmod -R 775 /var/www/.cache/composer

    return 0
}

# Function to install Importer dependencies
# Returns:
#   0 if installation succeeded, 1 if failed
install_importer_dependencies() {
    debug "Starting install_importer_dependencies function..."
    _1_2_info "Installing Composer dependencies for Firefly Importer..."

    # Check if vendor directory exists
    if [ ! -d "$IMPORTER_INSTALL_DIR/vendor" ]; then
        _1_2_info "No vendor directory found. Running composer install..."
        if ! composer_install_with_progress "$IMPORTER_INSTALL_DIR"; then
            error "Composer install failed for Firefly Importer. Please check:
    1. Internet connectivity 
    2. PHP version compatibility
    3. Memory limits
    4. Try running composer manually with: cd $IMPORTER_INSTALL_DIR && composer install --no-dev"
            return 1
        fi
    else
        _1_2_info "Vendor directory exists. Skipping composer install."
    fi
}

# Function to configure Apache for the Importer
# Returns:
#   0 if configuration succeeded, 1 if failed
configure_apache_for_importer() {
    debug "Starting configure_apache_for_importer function..."
    # Step 1: Configure based on whether a domain is provided
    if [ "$HAS_DOMAIN" = true ]; then
        configure_apache_for_importer_with_domain || return 1
    else
        configure_apache_for_importer_without_domain || return 1
    fi

    # Step 3: Restart Apache to apply changes
    _1_2_info "Restarting Apache to apply changes..."
    apache_control "restart" || return 1

    return 0
}

# Function to configure Apache for Importer with a domain
# Returns:
#   0 if configuration succeeded, 1 if failed
configure_apache_for_importer_with_domain() {
    debug "Starting configure_apache_for_importer_with_domain function..."
    # Step 1: Validate domain name
    if [ -z "$DOMAIN_NAME" ]; then
        error "DOMAIN_NAME is not set. Cannot configure IMPORTER_DOMAIN."
        return 1
    fi

    # Step 2: Set importer domain (subdomain)
    IMPORTER_DOMAIN="${IMPORTER_DOMAIN:-importer.$DOMAIN_NAME}"

    # Step 3: Obtain SSL certificate for the importer domain
    _1_2_info "Obtaining SSL certificate for $IMPORTER_DOMAIN using Let's Encrypt..."
    if ! certbot --apache --non-interactive --agree-tos --email "$EMAIL_ADDRESS" -d "$IMPORTER_DOMAIN"; then
        error "Failed to obtain SSL certificate for $IMPORTER_DOMAIN. Please check:
1. Domain DNS settings (make sure $IMPORTER_DOMAIN points to this server)
2. Firewall rules (ports 80 and 443 must be open)
3. Network connectivity"
        return 1
    fi
    1_3_success "SSL certificate successfully obtained for $IMPORTER_DOMAIN."

    # Step 4: Create Apache configuration
    cat >/etc/apache2/sites-available/firefly-importer.conf <<EOF
<VirtualHost *:80>
    ServerName $IMPORTER_DOMAIN
    Redirect permanent / https://$IMPORTER_DOMAIN/
</VirtualHost>

<VirtualHost *:443>
    ServerName $IMPORTER_DOMAIN
    DocumentRoot $IMPORTER_INSTALL_DIR/public

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$IMPORTER_DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$IMPORTER_DOMAIN/privkey.pem

    <Directory $IMPORTER_INSTALL_DIR/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/firefly-importer-error.log
    CustomLog \${APACHE_LOG_DIR}/firefly-importer-access.log combined
</VirtualHost>
EOF

    # Step 5: Enable the SSL module and the new site configuration
    a2enmod ssl
    a2enmod rewrite
    a2ensite firefly-importer

    # Step 6: Update the APP_URL in .env to use HTTPS and the importer domain
    sed -i "s|APP_URL=.*|APP_URL=https://$IMPORTER_DOMAIN|" "$IMPORTER_INSTALL_DIR/.env"
    _1_2_info "APP_URL set to https://$IMPORTER_DOMAIN in .env."

    return 0
}

# Function to configure Apache for Importer without a domain
# Returns:
#   0 if configuration succeeded, 1 if failed
configure_apache_for_importer_without_domain() {
    debug "Starting configure_apache_for_importer_without_domain function..."
    # Step 1: Set port for Importer
    IMPORTER_PORT=8080

    _1_2_info "Configuring Apache for Firefly Importer on port $IMPORTER_PORT..."

    # Step 2: Add Listen directive if not present
    if ! grep -q "^Listen $IMPORTER_PORT" /etc/apache2/ports.conf; then
        echo "Listen $IMPORTER_PORT" >>/etc/apache2/ports.conf
    fi

    # Step 3: Create Apache configuration
    cat >/etc/apache2/sites-available/firefly-importer.conf <<EOF
<VirtualHost *:$IMPORTER_PORT>
    ServerAdmin webmaster@localhost
    DocumentRoot $IMPORTER_INSTALL_DIR/public

    <Directory $IMPORTER_INSTALL_DIR/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/firefly-importer-error.log
    CustomLog \${APACHE_LOG_DIR}/firefly-importer-access.log combined
</VirtualHost>
EOF

    # Step 4: Enable modules and site
    a2ensite firefly-importer
    a2enmod rewrite

    # Step 5: Open the port in the firewall
    _1_2_info "Opening port $IMPORTER_PORT in the firewall..."
    ufw allow $IMPORTER_PORT/tcp || {
        _1_4_warning "Failed to open port $IMPORTER_PORT in the firewall. You may need to open it manually with: ufw allow $IMPORTER_PORT/tcp"
    }

    # Step 6: Update the APP_URL in .env
    sed -i "s|APP_URL=.*|APP_URL=http://${server_ip}:$IMPORTER_PORT|" "$IMPORTER_INSTALL_DIR/.env"
    _1_2_info "APP_URL set to http://${server_ip}:$IMPORTER_PORT in .env."

    return 0
}

# Function to detect the active Apache service
# Returns:
#   The name of the active Apache service if found, otherwise an empty string
#   Returns 0 if the service is detected, 1 if not
detect_apache_service() {
    debug "Starting detect_apache_service function"

    # Check for common service names
    for service_name in apache2 httpd apache httpd.service apache2.service; do
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            _1_2_info "Detected active Apache service: $service_name"
            echo "$service_name"
            return 0
        fi
    done

    # Check for Alpine's init system (OpenRC)
    if command -v rc-service &>/dev/null; then
        for service_name in apache2 httpd; do
            if rc-service "$service_name" status &>/dev/null; then
                _1_2_info "Detected active Apache service (OpenRC): $service_name"
                echo "$service_name"
                return 0
            fi
        done
    fi

    # Check for Apache processes
    if pgrep -f "apache2|httpd" &>/dev/null; then
        # Found Apache processes but couldn't identify service
        _1_4_warning "Apache process found but service name could not be determined. Using default 'apache2'."
        echo "apache2"
        return 0
    fi

    _1_4_warning "Could not detect Apache service. Will use 'apache2' as default."
    echo "apache2"
    return 1
}

# Function to handle Apache operations in a cross-platform manner
# Parameters:
#   action: The action to perform (restart, reload, configtest)
# Returns:
#   0 if operation succeeded, 1 if failed
apache_control() {
    debug "Starting apache_control function with action: $1"
    local action="$1"
    local result=1

    # Detect Apache service
    local apache_service=$(detect_apache_service)
    local apache_command=""

    # Find Apache control command
    if command -v apachectl &>/dev/null; then
        apache_command="apachectl"
    elif command -v apache2ctl &>/dev/null; then
        apache_command="apache2ctl"
    elif command -v httpd &>/dev/null; then
        apache_command="httpd"
    else
        error "No Apache control command found. Please ensure Apache is installed."
        return 1
    fi

    # Handle the restart action specially with config testing
    if [ "$action" = "restart" ]; then
        # Test configuration before restart
        _1_2_info "Testing Apache configuration before restart..."

        local config_ok=true
        case "$apache_command" in
        apachectl | apache2ctl)
            "$apache_command" configtest >/dev/null 2>&1 || config_ok=false
            ;;
        httpd)
            "$apache_command" -t >/dev/null 2>&1 || config_ok=false
            ;;
        esac

        if [ "$config_ok" = false ]; then
            error "Apache configuration test failed. Please check the configuration files for errors:
1. Look for syntax errors in Apache configuration files
2. Check for duplicate port or domain configurations
3. Verify SSL certificate paths if using HTTPS"
            return 1
        fi

        _1_2_info "Apache configuration test passed. Restarting Apache..."
    fi

    # Execute the requested action
    case "$action" in
    restart)
        # Try systemd first, then fallback to commands
        if command -v systemctl &>/dev/null && [ -n "$apache_service" ]; then
            _1_2_info "Restarting Apache using systemctl..."
            systemctl restart "$apache_service"
            result=$?
        elif command -v rc-service &>/dev/null; then
            _1_2_info "Restarting Apache using rc-service (Alpine)..."
            rc-service "$apache_service" restart
            result=$?
        else
            _1_2_info "Restarting Apache using $apache_command..."
            case "$apache_command" in
            apachectl | apache2ctl)
                "$apache_command" restart
                ;;
            httpd)
                "$apache_command" -k restart
                ;;
            esac
            result=$?
        fi

        if [ $result -ne 0 ]; then
            error "Failed to restart Apache. Please check:
1. Apache error logs: sudo tail -f /var/log/apache2/error.log or /var/log/httpd/error_log
2. System service logs: sudo journalctl -u $apache_service
3. Verify Apache is installed correctly"
        else
            1_3_success "Apache restarted successfully."
        fi
        ;;

    reload)
        # Similar pattern to restart...
        if command -v systemctl &>/dev/null && [ -n "$apache_service" ]; then
            _1_2_info "Reloading Apache using systemctl..."
            systemctl reload "$apache_service"
            result=$?
        elif command -v rc-service &>/dev/null; then
            _1_2_info "Reloading Apache using rc-service (Alpine)..."
            rc-service "$apache_service" reload
            result=$?
        else
            _1_2_info "Reloading Apache using $apache_command..."
            case "$apache_command" in
            apachectl | apache2ctl)
                "$apache_command" graceful
                ;;
            httpd)
                "$apache_command" -k graceful
                ;;
            esac
            result=$?
        fi

        if [ $result -ne 0 ]; then
            error "Failed to reload Apache configuration."
        else
            1_3_success "Apache configuration reloaded successfully."
        fi
        ;;

    configtest)
        case "$apache_command" in
        apachectl | apache2ctl)
            "$apache_command" configtest
            ;;
        httpd)
            "$apache_command" -t
            ;;
        esac
        result=$?

        if [ $result -ne 0 ]; then
            error "Apache configuration test failed."
        else
            1_3_success "Apache configuration test passed."
        fi
        ;;

    *)
        error "Unknown Apache action: $action. Supported actions are: restart, reload, configtest"
        return 1
        ;;
    esac

    return $result
}

# Function to update Firefly Importer
# Returns:
#   0 if update succeeded, 1 if failed
update_firefly_importer() {
    debug "Starting update_firefly_importer function..."
    _1_2_info "An existing Firefly Importer installation was detected."

    # Step 1: Prompt for update confirmation
    if [ "$NON_INTERACTIVE" = true ]; then
        CONFIRM_UPDATE="Y"
    else
        while true; do
            prompt "Do you want to proceed with the update? (y/N): "
            read CONFIRM_UPDATE
            CONFIRM_UPDATE=${CONFIRM_UPDATE:-N}

            if validate_input "$CONFIRM_UPDATE" "yes_no"; then
                break
            fi
        done
    fi

    if [[ "$CONFIRM_UPDATE" =~ ^[Yy]$ ]]; then
        _1_2_info "Proceeding to update..."

        # Step 2: Create a backup of the current installation
        create_backup "$IMPORTER_INSTALL_DIR"

        # Step 3: Download and validate Firefly Importer
        download_and_validate_release "firefly-iii/data-importer" "$IMPORTER_TEMP_DIR" "\\.zip$" || return 1

        # Step 4: Extract the archive file
        archive_file=$(ls "$IMPORTER_TEMP_DIR"/*.zip | head -n 1)
        extract_archive "$archive_file" "$IMPORTER_TEMP_DIR" || return 1

        # Step 5: Copy over the .env file
        _1_2_info "Copying configuration files..."
        copy_importer_config_files || return 1

        # Step 6: Set permissions
        _1_2_info "Setting permissions..."
        chown -R www-data:www-data "$IMPORTER_TEMP_DIR"
        chmod -R 775 "$IMPORTER_TEMP_DIR/storage"

        # Step 7: Move the old installation and replace with new
        _1_2_info "Moving old Firefly Importer installation to ${IMPORTER_INSTALL_DIR}-old"
        mv "$IMPORTER_INSTALL_DIR" "${IMPORTER_INSTALL_DIR}-old"
        mv "$IMPORTER_TEMP_DIR" "$IMPORTER_INSTALL_DIR"

        # Step 8: Configure Apache
        _1_2_info "Configuring Apache for Firefly Importer..."
        configure_apache_for_importer || return 1

        1_3_success "Firefly Importer update completed."

    else
        _1_2_info "Update canceled by the user."
        exit 0
    fi

    # Capture installed version
    installed_importer_version=$(check_firefly_importer_version)
    return 0
}

# Function to copy Importer configuration files
# Returns:
#   0 if copy succeeded, 1 if failed
copy_importer_config_files() {
    debug "Starting copy_importer_config_files function..."
    # Step 1: Check for existing .env file
    if [ -f "$IMPORTER_INSTALL_DIR/.env" ]; then
        cp "$IMPORTER_INSTALL_DIR/.env" "$IMPORTER_TEMP_DIR/.env"
        chown www-data:www-data "$IMPORTER_TEMP_DIR/.env"
        chmod 640 "$IMPORTER_TEMP_DIR/.env"
    else
        _1_4_warning "No .env file found in $IMPORTER_INSTALL_DIR. Creating a new .env file from .env.example..."

        # Step 2: Search for .env.example
        env_example_path=$(find "$IMPORTER_TEMP_DIR" -name ".env.example" -print -quit)

        if [ -n "$env_example_path" ]; then
            cp "$env_example_path" "$IMPORTER_TEMP_DIR/.env"
            chown www-data:www-data "$IMPORTER_TEMP_DIR/.env"
            chmod 640 "$IMPORTER_TEMP_DIR/.env"
            _1_2_info "Created new .env file from .env.example."

            # Step 3: Call the Firefly Importer-specific setup function
            setup_importer_env_file "$IMPORTER_TEMP_DIR"
        else
            error ".env.example not found in $IMPORTER_TEMP_DIR. Please ensure the example file is present for creating a new .env file."
            return 1
        fi
    fi

    return 0
}

# Function to setup cron job for scheduled tasks
# Returns:
#   0 if setup succeeded, 1 if failed
setup_cron_job() {
    debug "Starting setup_cron_job function..."
    _1_2_info "Setting up cron job for Firefly III scheduled tasks..."

    # Step 1: Prompt for cron job time or use default
    if [ "$NON_INTERACTIVE" = true ]; then
        CRON_HOUR="${CRON_HOUR:-3}"
    else
        while true; do
            prompt "Enter the hour (0-23) to run the Firefly III cron job (default: 3): "
            read CRON_HOUR
            CRON_HOUR="${CRON_HOUR:-3}"

            if validate_input "$CRON_HOUR" "number" && [ "$CRON_HOUR" -ge 0 ] && [ "$CRON_HOUR" -le 23 ]; then
                break
            else
                error "Invalid input. Please enter a number between 0 and 23."
            fi
        done
    fi

    # Step 2: Specify environment variables for cron job
    echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin" >/etc/cron.d/firefly-iii-cron

    # Step 3: Define the cron job command
    PHP_BINARY=$(which php) # Get the path to the PHP binary
    CRON_CMD="/usr/bin/flock -n /tmp/firefly_cron.lock $PHP_BINARY $FIREFLY_INSTALL_DIR/artisan firefly-iii:cron"

    # Step 4: Ensure the cron job is only added once
    if ! grep -q "$CRON_CMD" /etc/cron.d/firefly-iii-cron; then
        # Create a cron job with the chosen hour, running as www-data user
        if [[ "$CRON_HOUR" =~ ^[0-9]+$ ]]; then
            echo "0 $CRON_HOUR * * * www-data $CRON_CMD" >>/etc/cron.d/firefly-iii-cron
        else
            error "Invalid CRON_HOUR value: $CRON_HOUR. Must be a numeric value between 0-23."
            return 1
        fi
        _1_2_info "Cron job for Firefly III added."
    else
        _1_2_info "Cron job for Firefly III already exists. No changes made."
    fi

    # Step 5: Ensure the cron job file has the correct permissions
    chmod 644 /etc/cron.d/firefly-iii-cron

    # Step 6: Restart cron service to apply changes
    systemctl restart cron || {
        error "Failed to restart cron service. Try manually restarting with: systemctl restart cron"
        return 1
    }

    # Export CRON_HOUR to make it accessible globally
    export CRON_HOUR

    1_3_success "Cron job for Firefly III scheduled tasks has been set up."
    return 0
}

# Function to validate a backup archive's integrity
# Returns:
#   0 if backup is valid, 1 if backup is invalid or missing
verify_backup_integrity() {
    local backup_file="$1"
    local src_dir="$2"

    # Check 1: File exists
    if [ ! -f "$backup_file" ]; then
        error "Backup file does not exist: $backup_file"
        return 1
    fi

    # Check 2: File size is reasonable
    local backup_size=$(stat -c %s "$backup_file" 2>/dev/null || stat -f %z "$backup_file" 2>/dev/null)
    local expected_min_size=$((1024 * 100)) # At least 100KB for a meaningful backup

    if [ -z "$backup_size" ]; then
        error "Failed to check backup file size."
        return 1
    elif [ "$backup_size" -lt "$expected_min_size" ]; then
        error "Backup file appears to be too small ($backup_size bytes). Backup may be corrupt."
        return 1
    fi

    # Check 3: Valid tar.gz format
    if ! tar -tzf "$backup_file" &>/dev/null; then
        error "Backup verification failed. Not a valid tar.gz archive."
        return 1
    fi

    # Check 4: Contains critical files and directories
    local critical_files=(".env" "artisan" "composer.json")
    local critical_dirs=("app" "config" "public" "storage")
    local missing_items=()

    for file in "${critical_files[@]}"; do
        if ! tar -tzf "$backup_file" | grep -q "$(basename "$src_dir")/$file$"; then
            missing_items+=("$file")
        fi
    done

    for dir in "${critical_dirs[@]}"; do
        if ! tar -tzf "$backup_file" | grep -q "$(basename "$src_dir")/$dir/"; then
            missing_items+=("$dir/")
        fi
    done

    if [ ${#missing_items[@]} -gt 0 ]; then
        _1_4_warning "Backup may be incomplete. Missing critical files/directories:"
        for item in "${missing_items[@]}"; do
            _1_4_warning "  - $item"
        done

        # If missing more than half of critical items, consider it invalid
        if [ ${#missing_items[@]} -gt $(((${#critical_files[@]} + ${#critical_dirs[@]}) / 2)) ]; then
            error "Too many critical files/directories missing. Backup considered invalid."
            return 1
        else
            _1_4_warning "Some items are missing but backup might still be usable."
            return 0
        fi
    fi

    1_3_success "Backup verification completed successfully."
    return 0
}

# Function to create a compressed tar.gz backup of the current installation with progress
# Parameters:
#   src_dir: The source directory to backup
# Returns:
#   0 if backup succeeded, 1 if failed
create_backup() {
    debug "Starting create_backup function..."
    local src_dir="$1"
    local backup_base="${src_dir}-backup"
    local date_stamp="$(date +%Y%m%d)"
    local backup_file="${backup_base}-${date_stamp}.tar.gz"

    # Step 1: Check if the source directory exists
    if [ ! -d "$src_dir" ]; then
        error "Source directory $src_dir doesn't exist. Cannot create backup."
        return 1
    fi

    # Step 2: Check write permissions on destination directory
    local dest_dir=$(dirname "$backup_file")
    if [ ! -w "$dest_dir" ]; then
        error "Cannot write to destination directory $dest_dir. Check permissions."
        return 1
    fi

    # Step 3: Check if a backup already exists for today
    if [ -f "$backup_file" ]; then
        # Verify the existing backup
        _1_2_info "A backup already exists for today: $backup_file. Verifying integrity..."

        if ! verify_backup_integrity "$backup_file" "$src_dir"; then
            _1_4_warning "Existing backup appears to be invalid or incomplete. Creating a new backup..."
            # Rename the old backup with .invalid suffix
            mv "$backup_file" "${backup_file}.invalid"
        else
            {
                _1_2_info "Existing backup is valid. Skipping backup creation."
                return 0
            }
        fi
    fi

    # Step 4: Get total number of files for progress tracking
    local total_files=$(find "$src_dir" -type f | wc -l)
    if [ "$total_files" -eq 0 ]; then
        error "No files found in $src_dir to backup."
        return 1
    fi

    # Step 5: Creating compressed tar.gz backup with progress tracking
    _1_2_info "Creating compressed backup of $src_dir at $backup_file"

    local current_step=0

    # Use tar with --checkpoint and --checkpoint-action to trigger updates
    tar --checkpoint=10 --checkpoint-action=exec='current_step=$((current_step+10)); show_progress "Backup Creation" "$current_step" "$total_files" "Compressing..."' \
        -czf "$backup_file" -C "$(dirname "$src_dir")" "$(basename "$src_dir")" || {
        error "Failed to create backup."
        return 1
    }

    # Final progress update
    show_progress "Backup Creation" "$total_files" "$total_files" "Completed" true

    # Step 6: Verify the created backup
    _1_2_info "Verifying backup integrity..."
    if ! verify_backup_integrity "$backup_file" "$src_dir"; then
        error "Backup verification failed. The backup may be corrupt or incomplete."
        # Rename the failed backup to prevent it from being used
        mv "$backup_file" "${backup_file}.failed"
        return 1
    fi

    1_3_success "Backup of $src_dir created and verified at $backup_file"

    # Step 7: Remove old backups to conserve space
    prune_old_backups "$backup_base"

    return 0
}

# Function to manage and delete old backup archives
#
# Description:
#   This function identifies and removes `.tar.gz` backup files older than a
#   specified retention period to conserve disk space. It ensures that only
#   the most recent backups are retained while preventing excessive storage usage.
#
# Parameters:
#   $1 - The base name of the backup file (e.g., "/path/to/backup")
#
# Behavior:
#   - Finds backup files matching the pattern "${backup_base}-YYYYMMDD.tar.gz".
#   - Deletes files older than the specified retention period.
#   - Logs the deletion process for tracking purposes.
#
# Returns:
#   0 if successful, non-zero if an error occurs.
prune_old_backups() {
    debug "Starting prune_old_backups function..."
    local backup_base="$1"
    local backup_retention_days=7 # Number of days to retain backups

    _1_2_info "Checking for old backups to delete (retaining last $backup_retention_days days)..."

    # Find and delete backup archives older than the retention period
    find "${backup_base}"-*.tar.gz -maxdepth 0 -type f -mtime +$backup_retention_days -print -exec rm -f {} \; |
        while read -r file; do
            _1_4_warning "Deleting old backup: $file"
        done

    1_3_success "Old backups older than $backup_retention_days days removed."
}

# Function to save credentials to a file
# Returns:
#   0 if save succeeded, 1 if failed
save_credentials() {
    debug "Starting save_credentials function..."
    _1_2_info "Saving credentials to $CREDENTIALS_FILE..."

    # Step 1: Create the credentials file with all the relevant info
    {
        echo "Firefly III Installation Credentials"
        echo "===================================="
        if [ -z "$MYSQL_ROOT_PASS" ]; then
            echo "MySQL Root Password: (using unix_socket authentication)"
        else
            echo "MySQL Root Password: $MYSQL_ROOT_PASS"
        fi
        echo "Database Name: $DB_NAME"
        echo "Database User: $DB_USER"
        echo "Database Password: $DB_PASS"
        echo "STATIC_CRON_TOKEN: $STATIC_CRON_TOKEN"
        echo "APP_KEY: $APP_KEY"
    } >"$CREDENTIALS_FILE"

    # Step 2: If running in interactive mode, prompt for passphrase to encrypt
    if [ "$NON_INTERACTIVE" = false ]; then
        # Check if gpg is installed, install if missing
        if ! command -v gpg &>/dev/null; then
            _1_4_warning "gpg not found. Installing it now..."
            apt-get install -y gnupg
            if ! command -v gpg &>/dev/null; then
                error "Failed to install gpg. Credentials cannot be encrypted."
                return 1
            fi
        fi

        # Prompt user for passphrase
        while true; do
            prompt "Enter a passphrase to encrypt the credentials (leave blank to skip encryption): "
            read -s PASSPHRASE
            echo

            if [ -z "$PASSPHRASE" ]; then
                _1_4_warning "Encryption skipped. Credentials are stored in plain text at $CREDENTIALS_FILE."
                break
            fi

            prompt "Confirm your passphrase: "
            read -s PASSPHRASE_CONFIRM
            echo

            if [ "$PASSPHRASE" != "$PASSPHRASE_CONFIRM" ]; then
                error "Passphrases do not match. Please try again."
            else
                _1_2_info "Encrypting credentials file with gpg for security..."
                if gpg --batch --yes --passphrase "$PASSPHRASE" -c "$CREDENTIALS_FILE"; then
                    rm "$CREDENTIALS_FILE"
                    1_3_success "Credentials saved and encrypted at $CREDENTIALS_FILE.gpg."
                    _1_4_warning "Please keep this file safe and decrypt it using 'gpg --decrypt $CREDENTIALS_FILE.gpg'."
                else
                    error "Failed to encrypt credentials file. The file remains unencrypted."
                fi
                break # Exit loop after successful encryption
            fi
        done
    else
        _1_2_info "Non-interactive mode detected. Credentials saved in plaintext for automation."
    fi

    # Step 3: Secure the credentials file
    chmod 600 "${CREDENTIALS_FILE}"*

    1_3_success "Credentials have been saved."
    return 0
}

# Function to update Firefly III with version compatibility handling
# Returns:
#   0 if update succeeded, 1 if failed
update_firefly() {
    debug "Starting update_firefly function..."
    _1_2_info "An existing Firefly III installation was detected."

    # Step 1: Prompt for update confirmation
    if [ "$NON_INTERACTIVE" = true ]; then
        CONFIRM_UPDATE="Y"
    else
        while true; do
            prompt "Do you want to proceed with the update? (y/N): "
            read CONFIRM_UPDATE
            CONFIRM_UPDATE=${CONFIRM_UPDATE:-N}

            if validate_input "$CONFIRM_UPDATE" "yes_no"; then
                break
            fi
        done
    fi

    if [[ "$CONFIRM_UPDATE" =~ ^[Yy]$ ]]; then
        _1_2_info "Proceeding with update..."

        # Step 2: Create a backup of the current installation
        create_backup "$FIREFLY_INSTALL_DIR" || {
            error "Backup failed. Aborting update."
            return 1
        }

        # Step 3: Detect the current PHP version
        if command -v php &>/dev/null; then
            CURRENT_PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION.'.'.PHP_RELEASE_VERSION;")
            _1_2_info "PHP is currently installed with version: $CURRENT_PHP_VERSION"
        else
            error "PHP is not installed. Please install PHP before updating Firefly III."
            return 1
        fi

        # Step 4: Get the latest Firefly III release
        LATEST_TAG=$(curl -s https://api.github.com/repos/firefly-iii/firefly-iii/releases/latest | grep "tag_name" | cut -d '"' -f 4)

        if [ -z "$LATEST_TAG" ]; then
            error "Failed to determine the latest Firefly III release. Please check your internet connection."
            return 1
        fi

        _1_2_info "Latest Firefly III release is $LATEST_TAG"

        # Step 5: Check PHP compatibility and determine download URL
        if ! check_php_compatibility "$LATEST_TAG" "$CURRENT_PHP_VERSION"; then
            if [ -n "$FIREFLY_RELEASE_TAG" ]; then
                _1_2_info "Using compatible Firefly III version $FIREFLY_RELEASE_TAG with current PHP $CURRENT_PHP_VERSION"
                local download_url="https://github.com/firefly-iii/firefly-iii/releases/download/$FIREFLY_RELEASE_TAG/FireflyIII-$FIREFLY_RELEASE_TAG.zip"
            else
                error "PHP compatibility check failed. Cannot proceed with the update."
                return 1
            fi
        else
            download_and_validate_release "firefly-iii/firefly-iii" "$FIREFLY_TEMP_DIR" "\\.zip$" || return 1
            archive_file=$(ls "$FIREFLY_TEMP_DIR"/*.zip | head -n 1)
        fi

        # Step 6: Extract the archive file
        _1_2_info "Extracting Firefly III archive..."
        if ! extract_archive "$archive_file" "$FIREFLY_TEMP_DIR"; then
            error "Extraction failed. Attempting to restore from backup..."
            if ! handle_update_failure; then
                error "Both extraction and restore failed. Your installation may be in an inconsistent state."
                error "Consider manual restoration or a fresh installation."
                return 1
            fi
            return 1 # Stop the update process after successful restoration
        fi

        # Step 7: Copy the .env file
        _1_2_info "Copying configuration files..."
        if [ -f "$FIREFLY_INSTALL_DIR/.env" ]; then
            if ! cp "$FIREFLY_INSTALL_DIR/.env" "$FIREFLY_TEMP_DIR/.env"; then
                error "Failed to copy .env file. Attempting to restore from backup..."
                if ! handle_update_failure; then
                    error "Restore failed. Your installation may be in an inconsistent state."
                    return 1
                fi
                return 1
            fi

            chown www-data:www-data "$FIREFLY_TEMP_DIR/.env"
            chmod 640 "$FIREFLY_TEMP_DIR/.env"
            _1_2_info "Configuration file copied successfully."
        else
            _1_4_warning "No .env file found. Creating a new .env file from .env.example..."

            env_example_path=$(find "$FIREFLY_TEMP_DIR" -name ".env.example" -print -quit)
            if [ -n "$env_example_path" ]; then
                if ! cp "$env_example_path" "$FIREFLY_TEMP_DIR/.env"; then
                    error "Failed to create .env file from template. Attempting to restore from backup..."
                    if ! handle_update_failure; then
                        error "Restore failed. Your installation may be in an inconsistent state."
                        return 1
                    fi
                    return 1
                fi

                chown www-data:www-data "$FIREFLY_TEMP_DIR/.env"
                chmod 640 "$FIREFLY_TEMP_DIR/.env"
                _1_2_info "Created new .env file from .env.example."

                if ! setup_env_file "$FIREFLY_TEMP_DIR"; then
                    error "Failed to configure .env file. Attempting to restore from backup..."
                    if ! handle_update_failure; then
                        error "Restore failed. Your installation may be in an inconsistent state."
                        return 1
                    fi
                    return 1
                fi
            else
                error ".env.example not found. Aborting update."
                if ! handle_update_failure; then
                    error "Restore failed. Your installation may be in an inconsistent state."
                    return 1
                fi
                return 1
            fi
        fi

        # Step 8: Set permissions for the new installation
        _1_2_info "Setting permissions..."
        chown -R www-data:www-data "$FIREFLY_TEMP_DIR"
        chmod -R 775 "$FIREFLY_TEMP_DIR/storage"

        # Step 9: Replace the old installation with the new version
        _1_2_info "Replacing existing Firefly III installation..."
        safe_remove_directory "$FIREFLY_INSTALL_DIR"
        mv "$FIREFLY_TEMP_DIR" "$FIREFLY_INSTALL_DIR"

        # Step 10: Run composer install
        _1_2_info "Running composer install to update dependencies..."
        cd "$FIREFLY_INSTALL_DIR"
        if ! composer_install_with_progress "$FIREFLY_INSTALL_DIR"; then
            error "Composer install failed. Restoring from backup..."
            handle_update_failure || return 1
        fi

        # Step 11: Setup application key
        setup_app_key || {
            error "Failed to set up APP key. Restoring backup..."
            handle_update_failure || return 1
        }

        # Step 12: Run database migrations
        run_database_migrations || {
            error "Database migration failed. Restoring backup..."
            handle_update_failure || return 1
        }

        # Step 13: Update database schema
        update_database_schema || {
            error "Database schema update failed. Restoring backup..."
            handle_update_failure || return 1
        }

        # Step 14: Install Laravel Passport if needed
        install_laravel_passport || {
            error "Laravel Passport installation failed. Restoring backup..."
            handle_update_failure || return 1
        }

        # Step 15: Configure Apache for Firefly III
        if [ "$HAS_DOMAIN" = true ]; then
            configure_apache "$DOMAIN_NAME" "$FIREFLY_INSTALL_DIR" true || return 1
        else
            configure_apache "" "$FIREFLY_INSTALL_DIR" false || return 1
        fi

        1_3_success "Firefly III update completed successfully."

    else
        _1_2_info "Update canceled by the user."
        exit 0
    fi

    # Capture installed version
    installed_version=$(check_firefly_version)
    return 0
}

# Function to handle update failures by finding and restoring from backup
# This function searches for backups in multiple locations and offers options
# Returns:
#   0 if restoration succeeded, 1 if failed or canceled
handle_update_failure() {
    debug "Starting handle_update_failure function..."

    # Step 1: Define backup search locations and patterns
    local primary_backup_dir="$(dirname "$FIREFLY_INSTALL_DIR")"
    local alternate_backup_dirs=("/root" "/home" "/tmp" "/var/backups")
    local backup_patterns=(
        "$(basename "$FIREFLY_INSTALL_DIR")-backup-*.tar.gz"
        "firefly-backup-*.tar.gz"
        "firefly_iii-backup-*.tar.gz"
        "firefly-iii-backup-*.tar.gz"
    )

    local today_backup="${FIREFLY_INSTALL_DIR}-backup-$(date +%Y%m%d).tar.gz"
    local yesterday_backup="${FIREFLY_INSTALL_DIR}-backup-$(date -d "yesterday" +%Y%m%d 2>/dev/null || date -v-1d +%Y%m%d 2>/dev/null).tar.gz"
    local backup_file=""
    local backup_files=()
    local backup_found=false

    # Step 2: Check for today's and yesterday's backups first
    _1_2_info "Looking for recent backups..."
    for specific_backup in "$today_backup" "$yesterday_backup"; do
        if [ -f "$specific_backup" ]; then
            backup_files+=("$specific_backup")
            backup_found=true
            debug "Found specific backup: $specific_backup"
        fi
    done

    # Step 3: If no specific backups found, search directories with patterns
    if [ "$backup_found" = false ]; then
        _1_4_warning "No recent backup found. Searching for any available backups..."

        # Search primary location first
        for pattern in "${backup_patterns[@]}"; do
            local found_backups=$(find "$primary_backup_dir" -maxdepth 1 -name "$pattern" -type f -print 2>/dev/null | sort -r)
            if [ -n "$found_backups" ]; then
                mapfile -t new_backups <<<"$found_backups"
                backup_files+=("${new_backups[@]}")
                backup_found=true
                debug "Found $(echo "$found_backups" | wc -l) backups in primary location with pattern $pattern"
            fi
        done

        # Search alternate locations if nothing found in primary
        if [ "$backup_found" = false ]; then
            for dir in "${alternate_backup_dirs[@]}"; do
                if [ -d "$dir" ]; then
                    for pattern in "${backup_patterns[@]}"; do
                        local found_backups=$(find "$dir" -maxdepth 2 -name "$pattern" -type f -print 2>/dev/null | sort -r)
                        if [ -n "$found_backups" ]; then
                            mapfile -t new_backups <<<"$found_backups"
                            backup_files+=("${new_backups[@]}")
                            backup_found=true
                            debug "Found $(echo "$found_backups" | wc -l) backups in $dir with pattern $pattern"
                        fi
                    done
                fi

                # Break once we've found backups in an alternate location
                if [ "$backup_found" = true ]; then
                    break
                fi
            done
        fi
    fi

    # Step 4: Process the found backups
    if [ "$backup_found" = false ] || [ ${#backup_files[@]} -eq 0 ]; then
        error "No backup files found for ${FIREFLY_INSTALL_DIR}. Cannot restore."
        error "You may need to manually reinstall or recover your Firefly III installation."
        return 1
    fi

    # Step 5: Clean up any partial installation
    if [ -d "$FIREFLY_TEMP_DIR" ] && [ -n "$(ls -A "$FIREFLY_TEMP_DIR" 2>/dev/null)" ]; then
        _1_2_info "Cleaning up partial installation files..."
        safe_remove_directory "$FIREFLY_TEMP_DIR"
    fi

    # Step 6: Select a backup to restore from
    if [ ${#backup_files[@]} -eq 1 ]; then
        # Only one backup found, use it directly
        backup_file="${backup_files[0]}"
        _1_2_info "Found one backup file: $backup_file"
    else
        # Multiple backups found
        _1_2_info "Found ${#backup_files[@]} backup files:"

        if [ "$NON_INTERACTIVE" = true ]; then
            # In non-interactive mode, use the most recent backup
            backup_file="${backup_files[0]}"
            _1_2_info "Non-interactive mode: Using most recent backup: $backup_file"
        else
            # In interactive mode, let the user choose
            echo "Select a backup to restore from:"
            for i in "${!backup_files[@]}"; do
                local backup_size=$(du -h "${backup_files[$i]}" 2>/dev/null | cut -f1)
                local backup_date=$(stat -c "%y" "${backup_files[$i]}" 2>/dev/null ||
                    stat -f "%Sm" "${backup_files[$i]}" 2>/dev/null)
                echo "  $((i + 1)). ${backup_files[$i]} ($backup_size, $backup_date)"
            done

            local valid_selection=false
            while [ "$valid_selection" = false ]; do
                prompt "Enter backup number [1-${#backup_files[@]}] (default: 1): "
                read selection
                selection=${selection:-1}

                if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#backup_files[@]}" ]; then
                    backup_file="${backup_files[$((selection - 1))]}"
                    valid_selection=true
                else
                    error "Invalid selection. Please enter a number between 1 and ${#backup_files[@]}."
                fi
            done
        fi
    fi

    # Step 7: Validate the selected backup
    _1_2_info "Verifying backup integrity: $backup_file"
    if ! tar -tzf "$backup_file" &>/dev/null; then
        error "The selected backup appears to be corrupt or invalid."
        error "Please select a different backup or consider a fresh installation."
        return 1
    fi

    # Step 8: Offer to restore or proceed with interactive mode
    if [ "$NON_INTERACTIVE" = false ]; then
        while true; do
            prompt "Update process failed. Would you like to restore from backup? (Y/n): "
            read RESTORE_BACKUP
            RESTORE_BACKUP=${RESTORE_BACKUP:-Y}

            if validate_input "$RESTORE_BACKUP" "yes_no"; then
                break
            fi

            error "Please enter 'y/Y' for Yes or 'n/N' for No."
        done

        if [[ ! "$RESTORE_BACKUP" =~ ^[Yy]$ ]]; then
            _1_4_warning "Not restoring from backup. The installation may be in an inconsistent state."
            return 1
        fi
    fi

    # Step 9: Perform the restoration
    _1_2_info "Restoring from backup: $backup_file"

    # Remove the current installation directory if it exists
    if [ -d "$FIREFLY_INSTALL_DIR" ]; then
        safe_remove_directory "$FIREFLY_INSTALL_DIR"
    fi

    # Extract the backup archive
    if ! extract_archive "$backup_file" "$(dirname "$FIREFLY_INSTALL_DIR")"; then
        error "Failed to extract backup archive. The installation could not be restored."
        return 1
    fi

    # Check if the directory was properly restored
    if [ ! -d "$FIREFLY_INSTALL_DIR" ] || [ ! -f "$FIREFLY_INSTALL_DIR/.env" ]; then
        error "Backup extraction completed, but the Firefly III directory structure appears invalid."
        error "The backup may have a different directory structure than expected."
        return 1
    fi

    # Set proper permissions
    chown -R www-data:www-data "$FIREFLY_INSTALL_DIR"
    chmod -R 755 "$FIREFLY_INSTALL_DIR"
    chmod -R 775 "$FIREFLY_INSTALL_DIR/storage"

    1_3_success "Successfully restored Firefly III from backup: $backup_file"

    # Attempt to restart Apache to ensure the restored site is accessible
    _1_2_info "Restarting Apache to apply changes..."
    if ! apache_control "restart"; then
        _1_4_warning "Failed to restart Apache. You may need to restart it manually."
    fi

    return 0
}

# Function to cleanup temporary files
# Returns:
#   0 if cleanup succeeded, 1 if failed
cleanup() {
    debug "Starting cleanup function..."
    _1_2_info "Cleaning up temporary files..."
    debug "Checking for temporary directories to clean up"

    # Check if the temporary directories exist before trying to remove them
    if [ -d "$FIREFLY_TEMP_DIR" ]; then
        debug "Removing temporary directory: $FIREFLY_TEMP_DIR"
        safe_remove_directory "$FIREFLY_TEMP_DIR"
    else
        debug "Temporary directory not found: $FIREFLY_TEMP_DIR"
    fi

    if [ -d "$IMPORTER_TEMP_DIR" ]; then
        debug "Removing temporary directory: $IMPORTER_TEMP_DIR"
        safe_remove_directory "$IMPORTER_TEMP_DIR"
    else
        debug "Temporary directory not found: $IMPORTER_TEMP_DIR"
    fi

    debug "Cleanup completed"
    return 0
}

# Ensure log file is set up and rotate if necessary
setup_log_file

# Log file creation message (adjustable box)
LOG_FILE_MESSAGE="Log file created for this run: $LOG_FILE"

# Calculate the dynamic width for the box based on the length of the message
BOX_WIDTH=$((${#LOG_FILE_MESSAGE} + 4))

# Print the log file message only once with an adjustable box
echo -e "┌$(printf '─%.0s' $(seq 1 $BOX_WIDTH))┐"
echo -e "│ $LOG_FILE_MESSAGE   │"
echo -e "└$(printf '─%.0s' $(seq 1 $BOX_WIDTH))┘"

#####################################################################################################################################################
#
#   INITIAL SETUP
#
#####################################################################################################################################################

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    error "Please run this script as root. Try using sudo: 'sudo ./firefly.sh'"
    exit 1
fi

# Call the function to detect OS before running the script
detect_os
_1_2_info "Detected OS: $os_type"

# Start by displaying mode options
display_mode_options

# Variables (configurable)
FIREFLY_INSTALL_DIR="${FIREFLY_INSTALL_DIR:-/var/www/firefly-iii}"
IMPORTER_INSTALL_DIR="${IMPORTER_INSTALL_DIR:-/var/www/data-importer}"
FIREFLY_TEMP_DIR="/tmp/firefly-iii-temp"
IMPORTER_TEMP_DIR="/tmp/data-importer-temp"

# Ensure the temporary directories are available and empty
if [ -d "$FIREFLY_TEMP_DIR" ]; then
    safe_empty_directory "$FIREFLY_TEMP_DIR"
else
    mkdir -p "$FIREFLY_TEMP_DIR"
fi

if [ -d "$IMPORTER_TEMP_DIR" ]; then
    safe_empty_directory "$IMPORTER_TEMP_DIR"
else
    mkdir -p "$IMPORTER_TEMP_DIR"
fi

# Detect the server's IP address
server_ip=$(hostname -I | awk '{print $1}')

# Trap exit to ensure cleanup and display log location even on failure
trap 'cleanup; echo -e "${COLOR_YELLOW}Log file for this run: ${LOG_FILE}${COLOR_RESET}"; echo -e "${COLOR_YELLOW}For troubleshooting, check the log at: ${LOG_FILE}${COLOR_RESET}";' EXIT

# Call the main preparation function
prepare_system || {
    error "System preparation failed. Please check the errors above and resolve any issues before continuing."
    exit 1
}

# Ensure directories exist and are writable
for dir in "$FIREFLY_INSTALL_DIR" "$IMPORTER_INSTALL_DIR"; do
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || {
            error "Failed to create directory '$dir'. Please check permissions and try again."
            return 1
        }
    fi
    if [ ! -w "$dir" ]; then
        error "The directory '$dir' is not writable. Please check permissions and try again."
        return 1
    fi
done

# Function to check if Firefly III is installed and functional
check_firefly_installation() {
    debug "Starting check_firefly_installation function..."
    if [ -d "$FIREFLY_INSTALL_DIR" ]; then
        _1_2_info "Firefly III directory exists. Verifying installation..."

        # Step 1: Check if important directories exist
        if [ ! -d "$FIREFLY_INSTALL_DIR/public" ] || [ ! -d "$FIREFLY_INSTALL_DIR/storage" ]; then
            error "Important Firefly III directories are missing (public or storage). This may indicate a broken installation."
            return 1
        fi

        # Step 2: Check for critical files
        if [ ! -f "$FIREFLY_INSTALL_DIR/.env" ] || [ ! -f "$FIREFLY_INSTALL_DIR/artisan" ] || [ ! -f "$FIREFLY_INSTALL_DIR/config/app.php" ]; then
            error "Critical Firefly III files are missing (.env, artisan, config/app.php)."
            return 1
        fi

        # Step 3: Check if the .env file contains APP_KEY and it's not the placeholder
        if ! grep -q '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env"; then
            error "APP_KEY is missing from the .env file."
            return 1
        elif grep -q '^APP_KEY=SomeRandomStringOf32CharsExactly' "$FIREFLY_INSTALL_DIR/.env"; then
            error "APP_KEY is set to the placeholder value. Firefly III is not fully configured."
            return 1
        else
            _1_2_info "APP_KEY is set and valid."
        fi

        # Step 4: Check database configuration
        if ! grep -q '^DB_CONNECTION=' "$FIREFLY_INSTALL_DIR/.env"; then
            error "Database configuration is missing from the .env file."
            return 1
        fi

        # Step 5: Check vendor directory exists
        if [ ! -d "$FIREFLY_INSTALL_DIR/vendor" ]; then
            error "Composer dependencies (vendor directory) are missing. You may need to run 'composer install'."
            return 1
        fi

        # Step 6: Read database credentials from .env file
        if [ -f "$FIREFLY_INSTALL_DIR/.env" ]; then
            DB_CONNECTION=$(grep '^DB_CONNECTION=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2-)
            DB_HOST=$(grep '^DB_HOST=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2-)
            DB_PORT=$(grep '^DB_PORT=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2-)
            DB_NAME=$(grep '^DB_DATABASE=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2-)
            DB_USER=$(grep '^DB_USERNAME=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2-)
            DB_PASS=$(grep '^DB_PASSWORD=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2-)
        else
            error ".env file not found in $FIREFLY_INSTALL_DIR. Cannot read database credentials."
            return 1
        fi

        # Step 7: Verify database connectivity
        if [ "$DB_CONNECTION" = "mysql" ]; then
            _1_2_info "Checking MySQL database connection..."

            # Create a temporary MySQL configuration file
            TEMP_MY_CNF=$(mktemp)
            chmod 600 "$TEMP_MY_CNF"
            cat >"$TEMP_MY_CNF" <<EOF
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USER
password=$DB_PASS
EOF

            # Attempt to connect using the temporary configuration file
            debug "Attempting to connect to MySQL with user: $DB_USER, database: $DB_NAME"
            if ! mysql --defaults-extra-file="$TEMP_MY_CNF" -D "$DB_NAME" -e 'SELECT 1;' &>/dev/null; then
                rm -f "$TEMP_MY_CNF"
                error "Failed to connect to MySQL database. Please check:
1. MySQL service is running (systemctl status mysql)
2. Database credentials in .env are correct
3. Database exists and is accessible"
                return 1
            fi
            rm -f "$TEMP_MY_CNF"
            1_3_success "Successfully connected to MySQL database."
        elif [ "$DB_CONNECTION" = "sqlite" ]; then
            _1_2_info "Checking SQLite database file..."
            if [ ! -f "$FIREFLY_INSTALL_DIR/database/database.sqlite" ]; then
                error "SQLite database file is missing."
                return 1
            fi
            1_3_success "SQLite database file exists."
            debug "MySQL connection result: $?"
        else
            error "Unknown database connection type specified in .env file."
            return 1
        fi

        # Step 8: Check if Apache or Nginx is running
        if systemctl is-active --quiet apache2; then
            1_3_success "Apache is running."
        elif systemctl is-active --quiet nginx; then
            1_3_success "Nginx is running."
        else
            _1_4_warning "Neither Apache nor Nginx is running. The web server may not be properly configured."
            return 1
        fi

        # If all checks passed
        1_3_success "Firefly III is installed and seems functional."
        return 0
    else
        # Directory does not exist, likely a fresh install
        _1_4_warning "Firefly III directory does not exist. Proceeding with a fresh installation..."
        return 1
    fi
}

# Function to check if Firefly Importer is installed and functional
check_firefly_importer_installation() {
    debug "Starting check_firefly_importer_installation function..."
    if [ -d "$IMPORTER_INSTALL_DIR" ]; then
        _1_2_info "Firefly Importer directory exists. Verifying installation..."

        # Step 1: Check if important directories exist
        if [ ! -d "$IMPORTER_INSTALL_DIR/public" ] || [ ! -d "$IMPORTER_INSTALL_DIR/storage" ]; then
            error "Important Firefly Importer directories are missing (public or storage). This may indicate a broken installation."
            return 1
        fi

        # Step 2: Check for critical files
        if [ ! -f "$IMPORTER_INSTALL_DIR/.env" ] || [ ! -f "$IMPORTER_INSTALL_DIR/artisan" ] || [ ! -f "$IMPORTER_INSTALL_DIR/config/app.php" ]; then
            error "Critical Firefly Importer files are missing (.env, artisan, config/app.php)."
            return 1
        fi

        # Step 3: Check if the .env file contains APP_KEY and it's not the placeholder
        if ! grep -q '^APP_KEY=' "$IMPORTER_INSTALL_DIR/.env"; then
            error "APP_KEY is missing from the .env file."
            return 1
        elif grep -q '^APP_KEY=SomeRandomStringOf32CharsExactly' "$IMPORTER_INSTALL_DIR/.env"; then
            error "APP_KEY is set to the placeholder value. Firefly Importer is not fully configured."
            return 1
        else
            _1_2_info "APP_KEY is set and valid."
        fi

        # Step 4: Check Firefly III URL configuration
        if ! grep -q '^FIREFLY_III_URL=' "$IMPORTER_INSTALL_DIR/.env"; then
            error "Firefly III URL configuration is missing from the .env file."
            return 1
        fi

        # Step 5: Check vendor directory exists
        if [ ! -d "$IMPORTER_INSTALL_DIR/vendor" ]; then
            error "Composer dependencies (vendor directory) are missing. You may need to run 'composer install'."
            return 1
        fi

        # Step 6: Read configuration from .env file
        if [ -f "$IMPORTER_INSTALL_DIR/.env" ]; then
            DB_CONNECTION=$(grep '^DB_CONNECTION=' "$IMPORTER_INSTALL_DIR/.env" | cut -d '=' -f2-)
            DB_HOST=$(grep '^DB_HOST=' "$IMPORTER_INSTALL_DIR/.env" | cut -d '=' -f2-)
            DB_PORT=$(grep '^DB_PORT=' "$IMPORTER_INSTALL_DIR/.env" | cut -d '=' -f2-)
            DB_NAME=$(grep '^DB_DATABASE=' "$IMPORTER_INSTALL_DIR/.env" | cut -d '=' -f2-)
            DB_USER=$(grep '^DB_USERNAME=' "$IMPORTER_INSTALL_DIR/.env" | cut -d '=' -f2-)
            DB_PASS=$(grep '^DB_PASSWORD=' "$IMPORTER_INSTALL_DIR/.env" | cut -d '=' -f2-)
        else
            error ".env file not found in $IMPORTER_INSTALL_DIR. Cannot read configuration."
            return 1
        fi

        # Step 7: Verify database connectivity if applicable
        if [ "$DB_CONNECTION" = "mysql" ]; then
            _1_2_info "Checking MySQL database connection for Importer..."

            # Create a temporary MySQL configuration file
            TEMP_MY_CNF=$(mktemp)
            chmod 600 "$TEMP_MY_CNF"
            cat >"$TEMP_MY_CNF" <<EOF
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USER
password=$DB_PASS
EOF

            # Attempt to connect using the temporary configuration file
            if ! mysql --defaults-extra-file="$TEMP_MY_CNF" -D "$DB_NAME" -e 'SELECT 1;' &>/dev/null; then
                rm -f "$TEMP_MY_CNF"
                error "Failed to connect to MySQL database for Importer. Please check:
1. MySQL service is running
2. Database credentials in .env are correct
3. Database exists and is accessible"
                return 1
            fi
            rm -f "$TEMP_MY_CNF"
            1_3_success "Successfully connected to MySQL database for Importer."
        elif [ "$DB_CONNECTION" = "sqlite" ]; then
            _1_2_info "Checking SQLite database file for Importer..."
            if [ ! -f "$IMPORTER_INSTALL_DIR/database/database.sqlite" ]; then
                error "SQLite database file is missing for Importer."
                return 1
            fi
            1_3_success "SQLite database file for Importer exists."
        else
            _1_4_warning "No database connection configured for Importer or unknown connection type."
        fi

        # Step 8: Check if Apache or Nginx is running
        if systemctl is-active --quiet apache2; then
            1_3_success "Apache is running."
        elif systemctl is-active --quiet nginx; then
            1_3_success "Nginx is running."
        else
            _1_4_warning "Neither Apache nor Nginx is running. The web server may not be properly configured for Importer."
            return 1
        fi

        # If all checks passed
        1_3_success "Firefly Importer is installed and seems functional."
        return 0
    else
        # Directory does not exist, likely a fresh install
        _1_4_warning "Firefly Importer directory does not exist. Proceeding with a fresh installation..."
        return 1
    fi
}

# Function to print messages in a dynamically sized box with icons, colors, and word wrapping
print_message_box() {
    local color="${1}"
    local message="${2}"
    local title="${3:-}"
    local max_width=60 # Maximum width for word wrapping

    # Function to wrap text by word and limit each line's length.
    wrap_text() {
        local text="$1"
        local width="$2"
        echo -e "$text" | fold -s -w "$width"
    }

    # Function to repeat a character n times.
    repeat_char() {
        local char="$1"
        local count="$2"
        for ((i = 0; i < count; i++)); do
            printf "%s" "$char"
        done
    }

    # Get the length of a string (number of characters).
    display_length() {
        local input="$1"
        echo "${#input}"
    }

    # Wrap the message text and split it into lines.
    local wrapped_message
    wrapped_message=$(wrap_text "$message" "$max_width")
    IFS=$'\n' read -r -d '' -a lines <<<"$wrapped_message"$'\0'

    # Determine the maximum display width from message lines.
    local max_length=0
    local dlen
    for line in "${lines[@]}"; do
        dlen=$(display_length "$line")
        if ((dlen > max_length)); then
            max_length=$dlen
        fi
    done

    # Prepare the title and update max_length if needed.
    if [ -n "$title" ]; then
        local title_length
        title_length=$(display_length "$title")
        if ((title_length > max_length)); then
            max_length=$title_length
        fi
    fi

    # Calculate the total box width (4 extra characters for borders and spaces).
    local box_width=$((max_length + 4))

    # Print the top border.
    printf "${color}┌"
    repeat_char "─" $((box_width - 2))
    printf "┐\n"

    # If a title is provided, print the title line and a separator.
    if [ -n "$title" ]; then
        local title_length
        title_length=$(display_length "$title")
        local pad=$((max_length - title_length))
        printf "${color}│ %s" "$title"
        repeat_char " " "$pad"
        printf " │\n"
        printf "${color}├"
        repeat_char "─" $((box_width - 2))
        printf "┤\n"
    fi

    # Print each wrapped message line with proper manual padding.
    for line in "${lines[@]}"; do
        dlen=$(display_length "$line")
        local pad=$((max_length - dlen))
        printf "${color}│ %s" "$line"
        repeat_char " " "$pad"
        printf " │\n"
    done

    # Print the bottom border.
    printf "${color}└"
    repeat_char "─" $((box_width - 2))
    printf "┘\n"
    echo -e "${COLOR_RESET}"
}

#####################################################################################################################################################
#
#   SCRIPT EXECUTION
#
#####################################################################################################################################################

# Main check for Firefly III installation or update
if check_firefly_installation; then
    # Get the installed version
    installed_version=$(check_firefly_version)

    # Fetch the latest available version
    latest_version=$(get_latest_firefly_version)

    if [ -z "$latest_version" ]; then
        error "Failed to retrieve the latest Firefly III version. Skipping update check."
    else
        _1_2_info "Installed version: $installed_version"
        _1_2_info "Latest available version: $latest_version"

        if [ "$installed_version" = "$latest_version" ]; then
            1_3_success "Firefly III is already up-to-date. No update needed."
        else
            _1_2_info "Updating Firefly III from $installed_version to $latest_version..."
            if ! update_firefly; then
                error "Firefly III update failed."
                exit 1
            fi
        fi
    fi
else
    # Fresh installation of Firefly III
    if ! install_firefly; then
        error "Firefly III installation failed."
        exit 1
    fi
fi

# Main check for Firefly Importer installation or update
if check_firefly_importer_installation; then
    # Similar check for Firefly Importer
    installed_importer_version=$(check_firefly_importer_version)
    latest_importer_version=$(get_latest_importer_version)

    if [ -z "$latest_importer_version" ]; then
        error "Failed to retrieve the latest Firefly Importer version. Skipping update check."
    else
        _1_2_info "Installed Firefly Importer version: $installed_importer_version"
        _1_2_info "Latest available Firefly Importer version: $latest_importer_version"

        if [ "$installed_importer_version" = "$latest_importer_version" ]; then
            1_3_success "Firefly Importer is already up-to-date. No update needed."
        else
            _1_2_info "Updating Firefly Importer from $installed_importer_version to $latest_importer_version..."
            if ! update_firefly_importer; then
                error "Firefly Importer update failed."
                exit 1
            fi
        fi
    fi
else
    # Fresh installation of Firefly Importer
    if ! install_firefly_importer; then
        error "Firefly Importer installation failed."
        exit 1
    fi
fi

# Save credentials after installation
save_credentials

# Ensure variables are not empty before displaying them
if [ -z "$installed_version" ]; then
    installed_version="Unknown"
fi

if [ -z "$installed_importer_version" ]; then
    installed_importer_version="Unknown"
fi

# Print final message
echo ""
final_message="Installation and Update Process Completed\nFirefly III Version: $installed_version\nFirefly Importer Version: $installed_importer_version"
print_message_box "${COLOR_GREEN}" "${final_message}" "PROCESS COMPLETE"

access_message="Firefly III: http://${server_ip}:80\nFirefly Importer: http://${server_ip}:8080"
print_message_box "${COLOR_CYAN}" "${access_message}" "ACCESS INFORMATION"

config_message="Configuration Files:\nFirefly III: ${FIREFLY_INSTALL_DIR}/.env\nFirefly Importer: ${IMPORTER_INSTALL_DIR}/.env\nCron Job: /etc/cron.d/firefly-iii-cron\nCredentials: /root/firefly_credentials.txt"
print_message_box "${COLOR_YELLOW}" "${config_message}" "CONFIGURATION FILES"

_1_1_log_message="Log File: ${LOG_FILE}\nView Logs: cat ${LOG_FILE}\nLogs older than 7 days auto-deleted."
print_message_box "${COLOR_BLUE}" "${_1_1_log_message}" "LOG DETAILS"
