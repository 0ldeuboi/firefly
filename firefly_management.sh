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

#####################################################################################################################################################
#
#   KEY ACTIONS
#
#####################################################################################################################################################

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    error "Please run this script as root."
    exit 1
fi

# Set exit on failure
# set -e
# set -o pipefail

# Define colors and bold formatting for messages
COLOR_RESET="\033[0m"
COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_BLUE="\033[34m"
COLOR_CYAN="\033[36m"
BOLD="\033[1m"
RESET="\033[0m"

# Functions for colored output
info() {
    TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')         # Current timestamp for logging
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*" # Always print info to console
    echo "$TIMESTAMP [INFO] $*" >>"$LOG_FILE"      # Log info to the log file
}

success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"
}

warning() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $*"
}

# Function to handle errors
error() {
    TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S') # Current timestamp for logging
    if [ "$NON_INTERACTIVE" = false ]; then
        echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2 # Print error to console if interactive
    fi
    echo "$TIMESTAMP [ERROR] $*" >>"$LOG_FILE" # Log error to the log file regardless
}

# Function to prompt user for input
prompt() {
    echo -ne "${COLOR_CYAN}$*${COLOR_RESET}"
}

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
CREDENTIALS_FILE="/root/firefly_credentials.txt"

#####################################################################################################################################################
#
#   SCRIPT FUNCTIONS
#
#####################################################################################################################################################

# Function to set up the log file for the current run
setup_log_file() {
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
cleanup_old_logs() {
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
        info "Deleting $logs_to_delete oldest logs to maintain $MAX_LOG_COUNT logs."

        # Loop to delete the oldest logs
        for ((i = MAX_LOG_COUNT; i < log_count; i++)); do
            rm -f "${log_files[i]}"
            info "Deleted old log file: ${log_files[i]}"
        done
    fi

    # Print a message indicating which log files were deleted
    info "Log cleanup completed. Retaining up to $MAX_LOG_COUNT logs."
}

# Function to validate or set environment variables in .env file
validate_env_var() {
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

# Function to run test mode with a countdown and menu
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

# Function to determine the latest available PHP version from apt repositories
get_latest_php_version() {
    # Fetch the list of PHP versions available via apt-cache and filter valid PHP version formats
    local php_versions
    php_versions=$(apt-cache madison php | awk '{print $3}' | grep -oP '^\d+\.\d+' | sort -V | uniq)

    # Filter out RC and beta versions dynamically
    local stable_php_versions=()
    for version in $php_versions; do
        # Check if the version is a stable release (e.g., does not contain 'alpha', 'beta', 'RC')
        if [[ ! "$version" =~ (alpha|beta|RC) ]]; then
            stable_php_versions+=("$version")
        fi
    done

    # Get the highest stable PHP version
    local php_version
    php_version=$(printf '%s\n' "${stable_php_versions[@]}" | sort -V | tail -n 1)

    # Check if a valid PHP version was found
    if [ -z "$php_version" ]; then
        error "No valid stable PHP version found in the apt repositories."
        return 1
    else
        echo "$php_version"
    fi

    # Indicate successful completion
    return 0
}

# Function to fetch release info from GitHub API with rate limiting
fetch_release_info() {
    local repo="$1"
    local auth_header="$2"
    local api_url="https://api.github.com/repos/$repo/releases/latest"

    # Fetch release information from GitHub
    curl -sSL -H "$auth_header" "$api_url" -D headers.txt || {
        error "Failed to fetch release info from GitHub API."
        return 1
    }

    # Check for rate limiting
    if grep -q "API rate limit exceeded" headers.txt; then
        # Fetch the reset time from headers
        local reset_time=$(grep "^x-ratelimit-reset:" headers.txt | awk '{print $2}')
        local current_time=$(date +%s)

        if [ -n "$reset_time" ]; then
            local wait_time=$((reset_time - current_time))
            warning "GitHub API rate limit exceeded. Waiting for $wait_time seconds before retrying..."
            sleep "$wait_time"
        else
            warning "Rate limit exceeded but no reset time provided. Waiting for 60 seconds before retrying..."
            sleep 60
        fi
        return 1 # Indicate that the retry logic should retry
    fi

    # Check if the API response contains errors
    if grep -q "Bad credentials" headers.txt; then
        error "Invalid GitHub API token. Please check your token and try again."
        return 1
    fi

    # Parse the API response and return the JSON data
    cat headers.txt

    # Indicate successful completion
    return 0
}

# Function to get the latest release download URL from GitHub using jq
get_latest_release_url() {
    local repo="$1"
    local file_pattern="$2"
    local release_info
    release_info=$(curl -s "https://api.github.com/repos/$repo/releases/latest")

    # Check if the rate limit has been exceeded
    if echo "$release_info" | grep -q "API rate limit exceeded"; then
        error "GitHub API rate limit exceeded. Please try again later or use a GitHub API token."
        return 1
    fi

    echo "$release_info" | jq -r --arg file_pattern "$file_pattern" '.assets[] | select(.name | test($file_pattern)) | .browser_download_url' | head -n1

    # Indicate successful completion
    return 0
}

# Function to download and validate a release
download_and_validate_release() {
    local repo="$1"
    local dest_dir="$2"
    local file_pattern="$3"

    # Ensure the destination directory exists and is writable
    if [ ! -d "$dest_dir" ]; then
        info "Creating directory $dest_dir..."
        if ! mkdir -p "$dest_dir"; then
            error "Failed to create directory $dest_dir. Please check your permissions."
            return 1
        fi
    fi

    # Check if the directory is writable
    if [ ! -w "$dest_dir" ]; then
        error "The directory $dest_dir is not writable. Please check permissions and try again."
        return 1
    fi

    info "Downloading the latest release of $repo..."

    # Get the release URL
    local release_url
    release_url=$(get_latest_release_url "$repo" "$file_pattern")

    # Error if the release URL is empty
    if [ -z "$release_url" ]; then
        error "Failed to retrieve the latest release URL for $repo."
        return 1
    fi

    # Extract filename from release URL
    local release_filename
    release_filename=$(basename "$release_url")

    # Construct the sha256 filename
    local sha256_filename="${release_filename}.sha256"

    # Get the sha256 checksum URL
    local sha256_url
    sha256_url=$(get_latest_release_url "$repo" "^${sha256_filename}$")

    # If sha256 URL is empty, try to construct it from the release URL
    if [ -z "$sha256_url" ]; then
        sha256_url="${release_url}.sha256"
    fi

    # Download the release file using wget, fall back to curl if wget fails, with detailed logging
    info "Attempting to download release from $release_url using wget..."
    if ! wget --tries=3 --timeout=30 --content-disposition -P "$dest_dir" "$release_url" 2>&1 | tee -a "$LOG_FILE"; then
        warning "wget failed, falling back to curl. Attempting to download $release_filename using curl..."
        if ! curl -L --retry 3 --max-time 30 -o "$dest_dir/$release_filename" "$release_url" 2>&1 | tee -a "$LOG_FILE"; then
            error "Failed to download the release file from $release_url after retries. See log for details."
            return 1
        fi
        success "Downloaded $release_filename using curl."
    else
        success "Downloaded $release_filename using wget."
    fi

    # If no sha256 checksum is available, skip validation
    if [ -z "$sha256_url" ]; then
        warning "No SHA256 checksum found for $repo. Skipping checksum validation."
    else
        # Download the sha256 checksum file
        info "Downloading SHA256 checksum from $sha256_url..."
        if ! wget --tries=3 --timeout=30 --content-disposition -P "$dest_dir" "$sha256_url"; then
            warning "wget failed for sha256, falling back to curl."
            if ! curl -L --retry 3 --max-time 30 -o "$dest_dir/$sha256_filename" "$sha256_url"; then
                error "Failed to download the SHA256 checksum file from $sha256_url after retries."
                return 1
            fi
        fi

        # Validate the downloaded archive using SHA256 checksum
        local archive_file sha256_file
        archive_file="$dest_dir/$release_filename"
        sha256_file="$dest_dir/$sha256_filename"

        if [ ! -f "$archive_file" ] || [ ! -f "$sha256_file" ]; then
            error "Missing downloaded files. Archive or checksum not found."
            return 1
        fi

        info "Validating the downloaded archive file..."
        if ! (cd "$dest_dir" && sha256sum -c "$(basename "$sha256_file")"); then
            error "SHA256 checksum validation failed for $archive_file."
            return 1
        fi

        success "Download and validation of $repo completed successfully."
    fi

    return 0
}

# Function to extract the archive file
extract_archive() {
    local archive_file="$1"
    local dest_dir="$2"

    info "Extracting $archive_file to $dest_dir..."
    if [[ "$archive_file" == *.zip ]]; then
        unzip -q "$archive_file" -d "$dest_dir" || {
            error "Extraction failed: Could not extract $archive_file into $dest_dir. Ensure the file is valid and permissions are correct."
            return 1
        }
    elif [[ "$archive_file" == *.tar.gz ]]; then
        mkdir -p "$dest_dir"
        tar -xzf "$archive_file" -C "$dest_dir" || {
            error "Extraction failed: Could not extract $archive_file into $dest_dir. Ensure the file is valid and permissions are correct."
            return 1
        }
    else
        error "Unsupported archive format: $archive_file. Only zip and tar.gz files are supported."
        return 1
    fi

    success "Extraction of $archive_file into $dest_dir completed successfully."
}

# Function to validate or create .env file for Firefly III
# Accepts the directory (either $FIREFLY_INSTALL_DIR or $FIREFLY_TEMP_DIR) as an argument
setup_env_file() {
    local target_dir="$1"

    if [ ! -f "$target_dir/.env" ]; then
        info "No .env file found, using .env.example as a template."

        # Search for the .env.example file in case it's not in the expected location
        env_example_path=$(find "$target_dir" -name ".env.example" -print -quit)

        if [ -n "$env_example_path" ]; then
            # Copy the .env.example to .env
            cp "$env_example_path" "$target_dir/.env"
            info "Created new .env file from .env.example."
        else
            error ".env.example not found. Ensure the example file is present."
            return 1
        fi
    else
        info ".env file already exists. Validating required environment variables..."
    fi

    # Set ownership and permissions for the .env file
    chown www-data:www-data "$target_dir/.env" # Set the owner to www-data
    chmod 640 "$target_dir/.env"               # Set secure permissions for the .env file

    # Ask the user which database to use
    if [ "$NON_INTERACTIVE" = true ]; then
        DB_CHOICE="mysql" # Default to MySQL in non-interactive mode
        info "Using MySQL for database in non-interactive mode."
    else
        prompt "Which database do you want to use? [mysql/sqlite] (default: mysql): "
        read DB_CHOICE
        DB_CHOICE=${DB_CHOICE:-mysql}
    fi

    if [[ "$DB_CHOICE" =~ ^[Ss][Qq][Ll][Ii][Tt][Ee]$ ]]; then
        # Use SQLite
        info "Configuring SQLite database..."
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
    else
        # Use MySQL
        info "Configuring MySQL database..."

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

        # Prompt user for database name, username, and password or use defaults
        if [ "$NON_INTERACTIVE" = true ]; then
            # Use default values in non-interactive mode
            DB_NAME="${DB_NAME:-$default_db_name}"
            DB_USER="${DB_USER:-$default_db_user}"
            DB_PASS="${DB_PASS:-$(openssl rand -base64 16)}"
        else
            # Interactive mode: prompt the user for input
            prompt "Enter the database name (press Enter for default: $default_db_name): "
            read DB_NAME_INPUT
            DB_NAME=${DB_NAME_INPUT:-$default_db_name}

            prompt "Enter the database username (press Enter for default: $default_db_user): "
            read DB_USER_INPUT
            DB_USER=${DB_USER_INPUT:-$default_db_user}

            prompt "Enter the database password (press Enter for a randomly generated password): "
            read -s DB_PASS_INPUT
            DB_PASS=${DB_PASS_INPUT:-"$(openssl rand -base64 16)"}
            echo
        fi

        DB_HOST="127.0.0.1"

        # Call functions to create the MySQL database and user
        create_mysql_db
        create_mysql_user

        # Populate the .env file with the generated credentials or update if already present
        validate_env_var "DB_CONNECTION" "mysql"
        validate_env_var "DB_HOST" "$DB_HOST"
        validate_env_var "DB_DATABASE" "$DB_NAME"
        validate_env_var "DB_USERNAME" "$DB_USER"
        validate_env_var "DB_PASSWORD" "$DB_PASS"
    fi

    # Set APP_URL based on whether a domain is configured or not
    if [ "$HAS_DOMAIN" = true ]; then
        validate_env_var "APP_URL" "https://$DOMAIN_NAME/firefly-iii"
        info "APP_URL set to https://$DOMAIN_NAME/firefly-iii in .env."
    else
        validate_env_var "APP_URL" "http://${server_ip}/firefly-iii"
        info "APP_URL set to http://${server_ip}/firefly-iii in .env."
    fi

    # Generate STATIC_CRON_TOKEN and set in .env
    info "Generating STATIC_CRON_TOKEN..."
    STATIC_CRON_TOKEN=$(openssl rand -hex 16)
    validate_env_var "STATIC_CRON_TOKEN" "$STATIC_CRON_TOKEN"
    export STATIC_CRON_TOKEN
    success "STATIC_CRON_TOKEN set in .env file."

    # Set up the cron job
    setup_cron_job

    success ".env file validated and populated successfully."

    # Indicate successful completion
    return 0
}

# Function to create MySQL database
create_mysql_db() {
    # Prompt for MySQL root password or use unix_socket authentication only if not set
    if [ -z "$MYSQL_ROOT_PASS" ]; then
        if [ "$NON_INTERACTIVE" = true ]; then
            MYSQL_ROOT_PASS=""
        else
            prompt "Enter the MySQL root password (leave blank to use unix_socket authentication): "
            read -s MYSQL_ROOT_PASS
            echo
        fi
    fi

    # Assign MYSQL_ROOT_CMD based on MYSQL_ROOT_PASS
    if [ -z "$MYSQL_ROOT_PASS" ]; then
        info "Using unix_socket authentication for MySQL root access."
        # Remove 'sudo' since we're already running as root
        MYSQL_ROOT_CMD=("mysql")
    else
        MYSQL_ROOT_CMD=("mysql" "-u" "root" "-p$MYSQL_ROOT_PASS")
    fi

    # Ensure MYSQL_ROOT_PASS is accessible in save_credentials
    export MYSQL_ROOT_PASS

    # Attempt to connect to MySQL and handle connection errors
    if ! echo "SELECT 1;" | "${MYSQL_ROOT_CMD[@]}" &>/dev/null; then
        error "Failed to connect to MySQL. Please check your MySQL root credentials or server status."
        return 1
    fi

    # Check if the database exists
    if echo "USE $DB_NAME;" | "${MYSQL_ROOT_CMD[@]}" &>/dev/null; then
        info "Database '$DB_NAME' already exists. Skipping creation."
    else
        info "Database '$DB_NAME' does not exist. Creating it now..."
        # Create the database
        echo "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" | "${MYSQL_ROOT_CMD[@]}" || {
            error "Failed to create database '$DB_NAME'. Please check your MySQL setup."
            return 1
        }
        success "Database '$DB_NAME' created successfully."
    fi

    # Indicate successful completion
    return 0
}

# Function to create MySQL user
create_mysql_user() {
    # Check if the MySQL user exists using the appropriate authentication method
    if echo "SELECT 1 FROM mysql.user WHERE user = '$DB_USER';" | "${MYSQL_ROOT_CMD[@]}" | grep 1 &>/dev/null; then
        info "MySQL user '$DB_USER' already exists. Skipping creation."
    else
        info "Creating MySQL user '$DB_USER'..."
        if ! echo "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" | "${MYSQL_ROOT_CMD[@]}"; then
            error "Failed to create MySQL user '$DB_USER'. Please check if the user already exists or if the credentials are correct."
            return 1
        fi

        if ! echo "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;" | "${MYSQL_ROOT_CMD[@]}"; then
            error "Failed to grant privileges to MySQL user '$DB_USER'. Please check your MySQL permissions."
            return 1
        fi
        success "MySQL user '$DB_USER' created and granted privileges successfully."
    fi

    # Indicate successful completion
    return 0
}

# Function to install Firefly III
install_firefly() {
    # Update package lists
    info "Updating package lists..."

    # Install required packages
    info "Installing required packages..."
    apt install -y curl wget unzip gnupg2 ca-certificates lsb-release apt-transport-https software-properties-common jq cron

    # Check if the necessary locales are already generated
    if ! locale -a | grep -qi "en_US\\.UTF-8"; then
        info "Locales not found. Generating locales (this might take a while)..."
        apt install -y language-pack-en-base
        locale-gen en_US.UTF-8
    else
        info "Locales already generated. Skipping locale generation."
    fi

    # Add PHP PPA repository
    info "Adding PHP PPA repository..."
    add-apt-repository ppa:ondrej/php -y

    # Update package lists again
    apt update

    # Detect the latest available stable PHP version
    LATEST_PHP_VERSION=$(get_latest_php_version)
    info "Latest available stable PHP version is: $LATEST_PHP_VERSION"

    # Check if PHP is already installed
    if command -v php &>/dev/null; then
        # PHP is installed, detect the current version
        CURRENT_PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
        info "PHP is currently installed with version: $CURRENT_PHP_VERSION"

        # Determine if an upgrade is needed based on version comparison
        if [ "$(printf '%s\n' "$LATEST_PHP_VERSION" "$CURRENT_PHP_VERSION" | sort -V | head -n1)" != "$LATEST_PHP_VERSION" ]; then
            UPGRADE_NEEDED=true
        else
            UPGRADE_NEEDED=false
        fi

        if [ "$NON_INTERACTIVE" = true ]; then
            UPGRADE_PHP=${UPGRADE_NEEDED}
        else
            if [ "$UPGRADE_NEEDED" = true ]; then
                prompt "A newer stable PHP version ($LATEST_PHP_VERSION) is available. Do you want to upgrade? (Y/n): "
                read UPGRADE_PHP_INPUT
                UPGRADE_PHP_INPUT=${UPGRADE_PHP_INPUT:-Y}
                UPGRADE_PHP=$([[ "$UPGRADE_PHP_INPUT" =~ ^[Yy]$ ]] && echo true || echo false)
            else
                UPGRADE_PHP=false
                info "PHP is up to date."
            fi
        fi

        if [ "$UPGRADE_PHP" = true ]; then
            info "Upgrading to PHP $LATEST_PHP_VERSION..."
            # Proceed with upgrade logic
        else
            info "Skipping PHP upgrade. Using installed version: $CURRENT_PHP_VERSION"
            LATEST_PHP_VERSION=$CURRENT_PHP_VERSION
        fi
    else
        # PHP is not installed, proceed to install the latest stable version
        info "PHP is not currently installed. Installing PHP $LATEST_PHP_VERSION..."
        if [ "$NON_INTERACTIVE" = true ]; then
            INSTALL_PHP="Y" # Automatically install the latest PHP in non-interactive mode
        else
            prompt "PHP $LATEST_PHP_VERSION is the latest available. Do you want to install this version? (Y/n): "
            read INSTALL_PHP
            INSTALL_PHP=${INSTALL_PHP:-Y}
        fi

        if [[ "$INSTALL_PHP" =~ ^[Nn]$ ]]; then
            prompt "Enter the PHP version you want to install (available: $LATEST_PHP_VERSION): "
            read PHP_VERSION
            PHP_VERSION=${PHP_VERSION:-$LATEST_PHP_VERSION}
            LATEST_PHP_VERSION=$PHP_VERSION
        fi

        info "Installing PHP $LATEST_PHP_VERSION..."
    fi

    # Remove any installed RC versions of PHP dynamically
    info "Checking for any installed RC versions of PHP..."
    RC_PHP_PACKAGES=$(dpkg -l | awk '/^ii/{print $2}' | grep -E '^php[0-9\.]+(-|$)' | while read -r pkg; do
        # Get the package version
        pkg_version=$(dpkg -s "$pkg" | awk '/Version:/{print $2}')
        # Check if the version contains 'RC', 'alpha', or 'beta'
        if [[ "$pkg_version" =~ (alpha|beta|RC) ]]; then
            echo "$pkg"
        fi
    done)

    if [ -n "$RC_PHP_PACKAGES" ]; then
        info "Found installed PHP RC versions: $RC_PHP_PACKAGES"
        apt purge -y $RC_PHP_PACKAGES
        info "Purged PHP RC versions."
    else
        info "No PHP RC versions installed."
    fi

    # Install the latest stable PHP version and required extensions
    apt install -y php$LATEST_PHP_VERSION php$LATEST_PHP_VERSION-bcmath php$LATEST_PHP_VERSION-intl \
        php$LATEST_PHP_VERSION-curl php$LATEST_PHP_VERSION-zip php$LATEST_PHP_VERSION-gd \
        php$LATEST_PHP_VERSION-xml php$LATEST_PHP_VERSION-mbstring php$LATEST_PHP_VERSION-mysql \
        php$LATEST_PHP_VERSION-sqlite3 libapache2-mod-php$LATEST_PHP_VERSION

    # Handle retaining or disabling older PHP versions
    if [ "$NON_INTERACTIVE" = true ]; then
        RETAIN_OLD_PHP="N" # Default to not retaining old PHP versions in non-interactive mode
    else
        prompt "Do you want to retain older PHP versions? (y/N): "
        read RETAIN_OLD_PHP
        RETAIN_OLD_PHP=${RETAIN_OLD_PHP:-N}
    fi

    if [[ "$RETAIN_OLD_PHP" =~ ^[Yy]$ ]]; then
        info "Retaining all older PHP versions. This might increase disk usage and may cause conflicts if other applications depend on older PHP versions."
    else
        warning "Disabling older PHP versions may affect other applications that use these versions. Ensure that other applications are compatible with the new PHP version before proceeding."

        # Proceed with disabling old PHP versions
        for version in $(ls /etc/apache2/mods-enabled/php*.load | grep -oP 'php\K[\d.]+(?=.load)' | grep -v "$LATEST_PHP_VERSION"); do
            # Backup the current PHP configuration before disabling it
            PHP_CONF="/etc/apache2/mods-available/php${version}.conf"
            if [ -f "$PHP_CONF" ]; then
                cp "$PHP_CONF" "${PHP_CONF}.bak"
                info "Backed up $PHP_CONF to ${PHP_CONF}.bak"
            fi
            a2dismod "php${version}"
            info "Disabled PHP $version"
        done
        success "Older PHP versions have been disabled."
    fi

    # Enable the latest PHP version
    info "Enabling PHP $LATEST_PHP_VERSION..."
    a2enmod php"$LATEST_PHP_VERSION"

    # Install Apache2 and MariaDB
    info "Installing Apache2 and MariaDB..."
    apt install -y apache2 mariadb-server

    # Install Certbot for Let's Encrypt SSL (or use a self-signed certificate if needed)
    apt install -y certbot python3-certbot-apache || {
        error "Failed to install Certbot. Please install manually and re-run the script."
        return 1
    }

    # Prompt for domain name and email address
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
        prompt "Do you have a registered domain name you want to use? (y/N): "
        read HAS_DOMAIN_INPUT
        HAS_DOMAIN_INPUT=${HAS_DOMAIN_INPUT:-N}

        if [[ "$HAS_DOMAIN_INPUT" =~ ^[Yy]$ ]]; then
            HAS_DOMAIN=true
            prompt "Enter your domain name (e.g., example.com): "
            read DOMAIN_NAME
            DOMAIN_NAME=${DOMAIN_NAME:-example.com}

            prompt "Enter your email address for SSL certificate registration: "
            read EMAIL_ADDRESS
            EMAIL_ADDRESS=${EMAIL_ADDRESS:-your-email@example.com}
        else
            HAS_DOMAIN=false
            DOMAIN_NAME=""
            EMAIL_ADDRESS=""
        fi
    fi

    if [ "$HAS_DOMAIN" = true ]; then
        # Obtain an SSL certificate using Let's Encrypt with error handling
        info "Obtaining SSL certificate using Let's Encrypt..."
        if ! certbot --apache --non-interactive --agree-tos --email "$EMAIL_ADDRESS" -d "$DOMAIN_NAME"; then
            error "Failed to obtain SSL certificate. Please check domain DNS settings, firewall rules, or network connectivity and try again."
            return 1
        fi
        success "SSL certificate successfully obtained for $DOMAIN_NAME."
    else
        # No domain name provided, skip SSL certificate generation
        warning "No domain name provided. Skipping SSL certificate generation."
    fi

    # Verify if Certbot's systemd timer or cron job for renewal exists
    check_certbot_auto_renewal

    # Install Composer
    info "Installing Composer..."
    EXPECTED_SIGNATURE=$(curl -s https://composer.github.io/installer.sig)
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_SIGNATURE=$(php -r "echo hash_file('sha384', 'composer-setup.php');")

    if [ "$EXPECTED_SIGNATURE" != "$ACTUAL_SIGNATURE" ]; then
        echo >&2 'ERROR: Invalid installer signature'
        rm composer-setup.php
        return 1
    fi

    php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php

    # Restart Apache to apply the new PHP configuration
    info "Restarting Apache web server to apply PHP configuration..."
    apachectl configtest || {
        error "Apache configuration test failed. Please check the configuration."
        return 1
    }

    if ! systemctl restart apache2; then
        error "Failed to restart Apache. Please check the Apache error logs for more details."
        return 1
    fi

    # Download and validate Firefly III
    download_and_validate_release "firefly-iii/firefly-iii" "$FIREFLY_TEMP_DIR" "\\.zip$" || return 1

    # Extract the archive file
    archive_file=$(ls "$FIREFLY_TEMP_DIR"/*.zip | head -n 1)
    extract_archive "$archive_file" "$FIREFLY_INSTALL_DIR" || return 1

    # Check if composer is installed before running it
    if ! command -v composer &>/dev/null; then
        error "Composer is not installed. Please install Composer and try again."
        return 1
    fi

    # Check if composer is installed before running it
    if ! command -v composer &>/dev/null; then
        error "Composer is not installed. Please install Composer and try again."
        return 1
    fi

    # Run composer install if vendor directory is missing
    if [ ! -d "$FIREFLY_INSTALL_DIR/vendor" ]; then
        info "Running composer install for Firefly III..."
        sudo -u www-data composer install --no-dev --prefer-dist --working-dir="$FIREFLY_INSTALL_DIR"
    fi

    # Set permissions for Firefly III
    info "Setting permissions for Firefly III..."
    chown -R www-data:www-data "$FIREFLY_INSTALL_DIR"
    chmod -R 775 "$FIREFLY_INSTALL_DIR/storage"

    # Copy .env.example to .env and configure
    info "Configuring Firefly III..."
    setup_env_file "$FIREFLY_INSTALL_DIR"

    # Set permissions before running artisan commands
    info "Setting ownership and permissions for Firefly III..."
    chown -R www-data:www-data "$FIREFLY_INSTALL_DIR"
    chmod -R 775 "$FIREFLY_INSTALL_DIR"

    # Run artisan commands with error handling
    info "Running artisan commands for Firefly III..."
    cd "$FIREFLY_INSTALL_DIR"

    # Generate application key if not already set
    if grep -q '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env" && [ -n "$(grep '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2)" ]; then
        info "APP_KEY already set. Skipping key generation."
    else
        if ! sudo -u www-data php artisan key:generate; then
            error "Failed to generate application key with php artisan. Please check your configuration."
            return 1
        fi
    fi

    # Capture the APP_KEY
    APP_KEY=$(grep '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2)
    export APP_KEY

    # Check if migrations have already been run
    info "Checking if database migrations have already been applied..."
    if sudo -u www-data php artisan migrate:status &>/dev/null; then
        info "Migrations have already been applied. Skipping migration step."
    else
        info "No migrations found. Proceeding with database migration."
        if ! sudo -u www-data php artisan migrate --force; then
            error "Failed to migrate database with php artisan. Please check your configuration."
            return 1
        fi
    fi

    # Update database schema and correct any issues with error handling
    info "Updating database schema and correcting any issues..."
    if ! sudo -u www-data php artisan config:cache; then
        error "Failed to cache configuration with php artisan. Please check your configuration."
        return 1
    fi

    if ! sudo -u www-data php artisan firefly-iii:upgrade-database; then
        error "Failed to upgrade Firefly III database. Please check your configuration."
        return 1
    fi

    if ! sudo -u www-data php artisan firefly-iii:correct-database; then
        error "Failed to correct database issues with Firefly III. Please check your configuration."
        return 1
    fi

    if ! sudo -u www-data php artisan firefly-iii:report-integrity; then
        error "Failed to report database integrity issues with Firefly III. Please check your configuration."
        return 1
    fi

    # Install Laravel Passport if not already installed
    info "Checking if Laravel Passport tables already exist..."
    PASSPORT_TABLE_EXISTS=$(mysql -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES LIKE 'oauth_auth_codes';" | grep -c "oauth_auth_codes")

    if [ "$PASSPORT_TABLE_EXISTS" -eq 0 ]; then
        info "Passport tables do not exist. Installing Laravel Passport..."
        if ! sudo -u www-data php artisan passport:install --force --no-interaction; then
            error "Failed to install Laravel Passport. Please check your configuration."
            return 1
        fi
    else
        info "Passport tables already exist. Skipping Laravel Passport installation."
    fi

    # Remove Passport migration files if tables already exist
    if [ "$PASSPORT_TABLE_EXISTS" -ne 0 ]; then
        info "Passport tables exist. Removing Passport migration files to prevent migration conflicts."
        rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000001_create_oauth_auth_codes_table.php"
        rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000002_create_oauth_access_tokens_table.php"
        rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000003_create_oauth_refresh_tokens_table.php"
        rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000004_create_oauth_clients_table.php"
        rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000005_create_oauth_personal_access_clients_table.php"
    fi

    # Configure Apache for Firefly III
    info "Configuring Apache for Firefly III..."

    if [ -f /etc/apache2/sites-available/firefly-iii.conf ]; then
        cp /etc/apache2/sites-available/firefly-iii.conf /etc/apache2/sites-available/firefly-iii.conf.bak
    fi

    if [ "$HAS_DOMAIN" = true ]; then
        # Configuration when a domain name is provided
        cat >/etc/apache2/sites-available/firefly-iii.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    Redirect permanent / https://$DOMAIN_NAME/
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN_NAME
    DocumentRoot $FIREFLY_INSTALL_DIR/public

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem

    <Directory $FIREFLY_INSTALL_DIR/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/firefly-error.log
    CustomLog \${APACHE_LOG_DIR}/firefly-access.log combined
</VirtualHost>
EOF

        # Enable the SSL module and the new site configuration
        a2enmod ssl
        a2enmod rewrite
        a2ensite firefly-iii

        # Disable the default site
        a2dissite 000-default.conf || true

        # Update the APP_URL in .env to use HTTPS and the domain name without '/firefly-iii'
        sed -i "s|APP_URL=.*|APP_URL=https://$DOMAIN_NAME|" "$FIREFLY_INSTALL_DIR/.env"
        info "APP_URL set to https://$DOMAIN_NAME in .env."
    else
        # Configuration when no domain name is provided
        cat >/etc/apache2/sites-available/firefly-iii.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $FIREFLY_INSTALL_DIR/public

    <Directory $FIREFLY_INSTALL_DIR/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/firefly-error.log
    CustomLog \${APACHE_LOG_DIR}/firefly-access.log combined
</VirtualHost>
EOF

        # Disable SSL module and ensure the site is enabled
        a2dismod ssl || true
        a2enmod rewrite
        a2ensite firefly-iii

        # Disable the default site
        a2dissite 000-default.conf || true

        # Update the APP_URL in .env to use HTTP and the server IP address without '/firefly-iii'
        sed -i "s|APP_URL=.*|APP_URL=http://${server_ip}|" "$FIREFLY_INSTALL_DIR/.env"
        info "APP_URL set to http://${server_ip} in .env."
    fi

    # Restart Apache to apply changes and add proper error handling
    info "Restarting Apache web server..."
    apachectl configtest || {
        error "Apache configuration test failed. Please check the configuration."
        return 1
    }

    if ! systemctl restart apache2; then
        error "Failed to restart Apache. Please check the Apache error logs for more details."
        return 1
    fi

    success "Apache successfully reloaded or started."

    # Indicate successful completion
    return 0
}

# Function to validate or create .env file for Firefly Importer
# Accepts the directory (either $IMPORTER_INSTALL_DIR or $IMPORTER_TEMP_DIR) as an argument
setup_importer_env_file() {
    local target_dir="$1"

    if [ ! -f "$target_dir/.env" ]; then
        info "No .env file found in $target_dir, using .env.example as a template."
        cp "$target_dir/.env.example" "$target_dir/.env"
        info "Created new .env file from .env.example."
    else
        info ".env file already exists in $target_dir."
    fi

    # Set FIREFLY_III_URL to the root URL of Firefly III
    if [ "$HAS_DOMAIN" = true ]; then
        validate_env_var "FIREFLY_III_URL" "https://$DOMAIN_NAME"
        info "FIREFLY_III_URL set to https://$DOMAIN_NAME in .env."
    else
        validate_env_var "FIREFLY_III_URL" "http://${server_ip}"
        info "FIREFLY_III_URL set to http://${server_ip} in .env."
    fi

    # Set ownership and permissions for the .env file
    chown www-data:www-data "$target_dir/.env"
    chmod 640 "$target_dir/.env"

    success ".env file validated and updated for Firefly Importer."

    # Indicate successful completion
    return 0
}

# Function to install Firefly Importer
install_firefly_importer() {
    info "Installing Firefly Importer..."

    # Download and validate Firefly Importer
    download_and_validate_release "firefly-iii/data-importer" "$IMPORTER_TEMP_DIR" "\\.zip$" || return 1

    # Extract the archive file
    archive_file=$(ls "$IMPORTER_TEMP_DIR"/*.zip | head -n 1)
    extract_archive "$archive_file" "$IMPORTER_TEMP_DIR" || return 1

    # Move the extracted files to the installation directory
    info "Installing Firefly Importer to $IMPORTER_INSTALL_DIR..."
    mv "$IMPORTER_TEMP_DIR"/* "$IMPORTER_INSTALL_DIR/"

    # Set ownership and permissions **before** running composer
    info "Setting ownership and permissions for Firefly Importer..."
    chown -R www-data:www-data "$IMPORTER_INSTALL_DIR"
    find "$IMPORTER_INSTALL_DIR" -type f -exec chmod 644 {} \;
    find "$IMPORTER_INSTALL_DIR" -type d -exec chmod 755 {} \;
    chmod -R 775 "$IMPORTER_INSTALL_DIR/storage" "$IMPORTER_INSTALL_DIR/bootstrap/cache"

    # Run composer install in the Firefly Importer directory
    info "Installing Composer dependencies for Firefly Importer..."
    if ! command -v composer &>/dev/null; then
        error "Composer is not installed. Please install Composer and try again."
        return 1
    fi
    cd "$IMPORTER_INSTALL_DIR"
    sudo -u www-data composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader || {
        error "Composer install failed for Firefly Importer. Please check the error messages above."
        return 1
    }

    # Generate application key
    info "Generating application key for Firefly Importer..."
    sudo -u www-data php artisan key:generate --no-interaction || {
        error "Failed to generate application key for Firefly Importer."
        return 1
    }

    # Setup the .env file
    setup_importer_env_file "$IMPORTER_INSTALL_DIR"

    # Configure Apache to serve Firefly Importer under '/data-importer'
    info "Configuring Apache for Firefly Importer under '/data-importer'..."

    # Create Apache configuration with Alias for importer
    cat >/etc/apache2/sites-available/firefly-importer.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $FIREFLY_INSTALL_DIR/public

    Alias /data-importer $IMPORTER_INSTALL_DIR/public

    <Directory $IMPORTER_INSTALL_DIR/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/firefly-importer-error.log
    CustomLog \${APACHE_LOG_DIR}/firefly-importer-access.log combined
</VirtualHost>
EOF

    # Enable the site and required modules
    a2enmod rewrite
    a2ensite firefly-importer

    # Restart Apache to apply changes
    info "Restarting Apache web server..."
    apachectl configtest || {
        error "Apache configuration test failed. Please check the configuration."
        return 1
    }

    if ! systemctl restart apache2; then
        {
        error "Failed to restart Apache. Please check the Apache error logs for more details."
        return 1
    }

    success "Firefly Importer installation completed."

    # Indicate successful completion
    return 0
}

# Function to update Firefly Importer
update_firefly_importer() {
    info "An existing Firefly Importer installation was detected."

    # Prompt the user to confirm whether to proceed with the update
    if [ "$NON_INTERACTIVE" = true ]; then
        CONFIRM_UPDATE="Y"
    else
        prompt "Do you want to proceed with the update? (y/N): "
        read CONFIRM_UPDATE
        CONFIRM_UPDATE=${CONFIRM_UPDATE:-N}
    fi

    if [[ "$CONFIRM_UPDATE" =~ ^[Yy]$ ]]; then
        info "Proceeding to update..."

        # Create a backup of the current installation
        create_backup "$IMPORTER_INSTALL_DIR"

        # Download and validate Firefly Importer
        download_and_validate_release "firefly-iii/data-importer" "$IMPORTER_TEMP_DIR" "\\.zip$" || return 1

        # Extract the archive file
        archive_file=$(ls "$IMPORTER_TEMP_DIR"/*.zip | head -n 1)
        extract_archive "$archive_file" "$IMPORTER_TEMP_DIR" || return 1

        # Copy over the .env file
        info "Copying configuration files..."
        if [ -f "$IMPORTER_INSTALL_DIR/.env" ]; then
            cp "$IMPORTER_INSTALL_DIR/.env" "$IMPORTER_TEMP_DIR/.env"
            chown www-data:www-data "$IMPORTER_TEMP_DIR/.env"
            chmod 640 "$IMPORTER_TEMP_DIR/.env"
        else
            warning "No .env file found in $IMPORTER_INSTALL_DIR. Creating a new .env file from .env.example..."

            # Search for .env.example using find to ensure it exists
            env_example_path=$(find "$IMPORTER_TEMP_DIR" -name ".env.example" -print -quit)

            if [ -n "$env_example_path" ]; then
                cp "$env_example_path" "$IMPORTER_TEMP_DIR/.env"
                chown www-data:www-data "$IMPORTER_TEMP_DIR/.env"
                chmod 640 "$IMPORTER_TEMP_DIR/.env"
                info "Created new .env file from .env.example."

                # Call the Firefly Importer-specific setup function to validate .env
                setup_importer_env_file "$IMPORTER_TEMP_DIR"
            else
                error ".env.example not found in $IMPORTER_TEMP_DIR. Please ensure the example file is present for creating a new .env file."
                return 1
            fi
        fi

        # Set ownership and permissions for the .env file
        chown www-data:www-data "$IMPORTER_TEMP_DIR/.env"
        chmod 640 "$IMPORTER_TEMP_DIR/.env"

        # Set ownership and permissions for the .env file
        chown www-data:www-data "$IMPORTER_TEMP_DIR/.env"
        chmod 640 "$IMPORTER_TEMP_DIR/.env"

        # Set permissions
        info "Setting permissions..."
        chown -R www-data:www-data "$IMPORTER_TEMP_DIR"
        chmod -R 775 "$IMPORTER_TEMP_DIR/storage"

        # Move the old installation
        info "Moving old Firefly Importer installation to ${IMPORTER_INSTALL_DIR}-old"
        mv "$IMPORTER_INSTALL_DIR" "${IMPORTER_INSTALL_DIR}-old"

        # Move the new installation to the install directory
        mv "$IMPORTER_TEMP_DIR" "$IMPORTER_INSTALL_DIR"

        # Adjust Apache configuration to serve Firefly Importer with HTTPS
        info "Configuring Apache for Firefly Importer with HTTPS..."

        # Check if SSL certificates exist before configuring Apache
        if [ ! -f "/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem" ] || [ ! -f "/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem" ]; then
            error "SSL certificates for $DOMAIN_NAME are missing. Please ensure Certbot has successfully obtained certificates."
            return 1
        fi

        # Backup existing Apache configuration if present
        if [ -f /etc/apache2/sites-available/firefly-importer.conf ]; then
            cp /etc/apache2/sites-available/firefly-importer.conf /etc/apache2/sites-available/firefly-importer.conf.bak
        fi

        # Create new Apache configuration
        cat >/etc/apache2/sites-available/firefly-importer.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    Redirect permanent / https://$DOMAIN_NAME/data-importer
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN_NAME
    DocumentRoot $IMPORTER_INSTALL_DIR/public

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem

    <Directory $IMPORTER_INSTALL_DIR/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/firefly-importer-error.log
    CustomLog \${APACHE_LOG_DIR}/firefly-importer-access.log combined
</VirtualHost>
EOF

        # Enable the SSL module and the new site configuration
        a2enmod ssl
        a2ensite firefly-importer

        # Restart Apache to apply changes and add proper error handling
        info "Restarting Apache web server..."
        apachectl configtest || {
            error "Apache configuration test failed. Please check the configuration."
            return 1
        }

        # Attempt to reload Apache, and if that fails, try starting it
        if ! systemctl restart apache2; then
            error "Failed to restart Apache. Please check the Apache error logs for more details."
            return 1
        fi

        success "Apache successfully reloaded or started."

        # Verify if Certbot's systemd timer or cron job for renewal exists
        info "Checking for Certbot auto-renewal mechanism..."

        # Check for systemd timer
        if systemctl list-timers | grep -q certbot; then
            info "Certbot systemd timer found. Auto-renewal is already configured."
        else
            # Check for existing cron job for Certbot
            if crontab -l | grep -q "certbot renew"; then
                info "Certbot cron job for auto-renewal found. No further action needed."
            else
                # Add a cron job to auto-renew the SSL certificate if neither exists
                info "No existing auto-renewal mechanism found. Setting up cron job for Certbot renewal..."
                (
                    crontab -l 2>/dev/null
                    echo "0 */12 * * * certbot renew --quiet --renew-hook 'systemctl reload apache2'"
                ) | crontab -
                info "Cron job for Certbot renewal added. It will run twice a day."
            fi
        fi

        success "Firefly Importer update completed. The old installation has been moved to ${IMPORTER_INSTALL_DIR}-old"

    else
        info "Update canceled by the user."
        exit 0
    fi

    # Indicate successful completion
    return 0
}

# Function to setup cron job for scheduled tasks
setup_cron_job() {
    info "Setting up cron job for Firefly III scheduled tasks..."

    # Prompt the user to choose a cron job time, defaulting to 3 AM
    if [ "$NON_INTERACTIVE" = true ]; then
        CRON_HOUR="${CRON_HOUR:-3}"
    else
        prompt "Enter the hour (0-23) to run the Firefly III cron job (default: 3): "
        read CRON_HOUR
        CRON_HOUR="${CRON_HOUR:-3}"
    fi

    # Specify environment variables for cron job (add PATH or other required variables)
    echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin" >/etc/cron.d/firefly-iii-cron

    # Define the cron job command
    PHP_BINARY=$(which php) # Get the path to the PHP binary
    CRON_CMD="/usr/bin/flock -n /tmp/firefly_cron.lock $PHP_BINARY $FIREFLY_INSTALL_DIR/artisan firefly-iii:cron"

    # Ensure the cron job is only added once
    if ! grep -q "$CRON_CMD" /etc/cron.d/firefly-iii-cron; then
        # Create a cron job with the chosen hour, running as www-data user
        if [[ "$CRON_HOUR" =~ ^[0-9]+$ ]]; then
            echo "0 $CRON_HOUR * * * www-data $CRON_CMD" >>/etc/cron.d/firefly-iii-cron
        else
            error "Invalid CRON_HOUR value: $CRON_HOUR. Must be a numeric value between 0-23."
            return 1
        fi
        info "Cron job for Firefly III added."
    else
        info "Cron job for Firefly III already exists. No changes made."
    fi

    # Ensure the cron job file has the correct permissions
    chmod 644 /etc/cron.d/firefly-iii-cron

    # Restart cron service to apply changes
    systemctl restart cron || {
        error "Failed to restart cron service."
        return 1
    }

    # Export CRON_HOUR to make it accessible globally
    export CRON_HOUR

    success "Cron job for Firefly III scheduled tasks has been set up."

    # Indicate successful completion
    return 0
}

# Function to check Certbot auto-renewal mechanism
check_certbot_auto_renewal() {
    info "Checking for Certbot auto-renewal mechanism..."

    # Check for systemd timer
    if systemctl list-timers | grep -q certbot; then
        info "Certbot systemd timer found. Auto-renewal is already configured."
    else
        # Check for existing cron job for Certbot
        if crontab -l | grep -q "certbot renew"; then
            info "Certbot cron job for auto-renewal found. No further action needed."
        else
            # Add a cron job to auto-renew the SSL certificate if neither exists
            info "No existing auto-renewal mechanism found. Setting up cron job for Certbot renewal..."
            (
                crontab -l 2>/dev/null
                echo "0 */12 * * * certbot renew --quiet --renew-hook 'systemctl reload apache2'"
            ) | crontab -
            info "Cron job for Certbot renewal added. It will run twice a day."
        fi
    fi
}

# Function to create a backup of the current installation
create_backup() {
    local src_dir="$1"
    local backup_dir="${src_dir}-backup-$(date +%Y%m%d%H%M%S)"

    # Check if the backup directory already exists and append a random suffix if needed
    if [ -d "$backup_dir" ]; then
        backup_dir="${backup_dir}_$(openssl rand -hex 2)"
    fi

    info "Creating backup of $src_dir at $backup_dir"
    cp -R "$src_dir" "$backup_dir"

    success "Backup of $src_dir created at $backup_dir"
}

# Function to save credentials to a file
save_credentials() {
    CREDENTIALS_FILE="/root/firefly_credentials.txt"
    info "Saving credentials to $CREDENTIALS_FILE..."

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

    # If running in interactive mode, prompt for passphrase to encrypt
    if [ "$NON_INTERACTIVE" = false ]; then
        prompt "Enter a passphrase to encrypt the credentials (leave blank to skip encryption): "
        read -s PASSPHRASE

        if [ -n "$PASSPHRASE" ]; then
            info "Encrypting credentials file with gpg for security..."
            if echo "$PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 -c "$CREDENTIALS_FILE"; then
                rm "$CREDENTIALS_FILE"
                success "Credentials saved and encrypted at $CREDENTIALS_FILE.gpg."
                warning "Please keep this file safe and decrypt it using 'gpg --decrypt $CREDENTIALS_FILE.gpg'."
            else
                error "Failed to encrypt credentials file. The file remains unencrypted."
            fi
        else
            warning "Encryption skipped. Credentials are stored in plain text."
        fi
    else
        info "Non-interactive mode detected. Credentials saved in plaintext for automation."
    fi

    # Secure the credentials file (plaintext or encrypted)
    chmod 600 "${CREDENTIALS_FILE}"*
}

# Function to update Firefly III
update_firefly() {
    info "An existing Firefly III installation was detected."

    # Prompt the user to confirm whether to proceed with the update
    if [ "$NON_INTERACTIVE" = true ]; then
        CONFIRM_UPDATE="Y"
    else
        prompt "Do you want to proceed with the update? (y/N): "
        read CONFIRM_UPDATE
        CONFIRM_UPDATE=${CONFIRM_UPDATE:-N}
    fi

    if [[ "$CONFIRM_UPDATE" =~ ^[Yy]$ ]]; then
        info "Proceeding to update..."

        # Update package lists
        info "Updating package lists..."
        apt update

        # Detect the latest available stable PHP version
        LATEST_PHP_VERSION=$(get_latest_php_version)
        info "Latest available stable PHP version is: $LATEST_PHP_VERSION"

        # Check if PHP is already installed
        if command -v php &>/dev/null; then
            # PHP is installed, detect the current version
            CURRENT_PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
            info "PHP is currently installed with version: $CURRENT_PHP_VERSION"

            # Determine if an upgrade is needed based on version comparison
            if [ "$(printf '%s\n' "$LATEST_PHP_VERSION" "$CURRENT_PHP_VERSION" | sort -V | head -n1)" != "$LATEST_PHP_VERSION" ]; then
                UPGRADE_NEEDED=true
            else
                UPGRADE_NEEDED=false
            fi

            if [ "$NON_INTERACTIVE" = true ]; then
                UPGRADE_PHP=${UPGRADE_NEEDED}
            else
                if [ "$UPGRADE_NEEDED" = true ]; then
                    prompt "A newer stable PHP version ($LATEST_PHP_VERSION) is available. Do you want to upgrade? (Y/n): "
                    read UPGRADE_PHP_INPUT
                    UPGRADE_PHP_INPUT=${UPGRADE_PHP_INPUT:-Y}
                    UPGRADE_PHP=$([[ "$UPGRADE_PHP_INPUT" =~ ^[Yy]$ ]] && echo true || echo false)
                else
                    UPGRADE_PHP=false
                    info "PHP is up to date."
                fi
            fi

            if [ "$UPGRADE_PHP" = true ]; then
                info "Upgrading to PHP $LATEST_PHP_VERSION..."
                # Proceed with upgrade logic
            else
                info "Skipping PHP upgrade. Using installed version: $CURRENT_PHP_VERSION"
                LATEST_PHP_VERSION=$CURRENT_PHP_VERSION
            fi
        else
            # PHP is not installed, proceed to install the latest stable version
            info "PHP is not currently installed. Installing PHP $LATEST_PHP_VERSION..."
            if [ "$NON_INTERACTIVE" = true ]; then
                INSTALL_PHP="Y" # Automatically install the latest PHP in non-interactive mode
            else
                prompt "PHP $LATEST_PHP_VERSION is the latest available. Do you want to install this version? (Y/n): "
                read INSTALL_PHP
                INSTALL_PHP=${INSTALL_PHP:-Y}
            fi

            if [[ "$INSTALL_PHP" =~ ^[Nn]$ ]]; then
                prompt "Enter the PHP version you want to install (available: $LATEST_PHP_VERSION): "
                read PHP_VERSION
                PHP_VERSION=${PHP_VERSION:-$LATEST_PHP_VERSION}
                LATEST_PHP_VERSION=$PHP_VERSION
            fi

            info "Installing PHP $LATEST_PHP_VERSION..."
        fi

        # **Insert the Dynamic Removal of RC Versions code here**

        # Remove any installed RC versions of PHP dynamically
        info "Checking for any installed RC versions of PHP..."
        RC_PHP_PACKAGES=$(dpkg -l | awk '/^ii/{print $2}' | grep -E '^php[0-9\.]+(-|$)' | while read -r pkg; do
            # Get the package version
            pkg_version=$(dpkg -s "$pkg" | awk '/Version:/{print $2}')
            # Check if the version contains 'RC', 'alpha', or 'beta'
            if [[ "$pkg_version" =~ (alpha|beta|RC) ]]; then
                echo "$pkg"
            fi
        done)

        if [ -n "$RC_PHP_PACKAGES" ]; then
            info "Found installed PHP RC versions: $RC_PHP_PACKAGES"
            apt purge -y $RC_PHP_PACKAGES
            info "Purged PHP RC versions."
        else
            info "No PHP RC versions installed."
        fi

        # Install the latest PHP version and required extensions
        apt install -y php$LATEST_PHP_VERSION php$LATEST_PHP_VERSION-bcmath php$LATEST_PHP_VERSION-intl \
            php$LATEST_PHP_VERSION-curl php$LATEST_PHP_VERSION-zip php$LATEST_PHP_VERSION-gd \
            php$LATEST_PHP_VERSION-xml php$LATEST_PHP_VERSION-mbstring php$LATEST_PHP_VERSION-mysql \
            php$LATEST_PHP_VERSION-sqlite3 libapache2-mod-php$LATEST_PHP_VERSION

        # Get the latest installed PHP version
        LATEST_PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
        info "Detected latest PHP version: $LATEST_PHP_VERSION"

        # Handle retaining or disabling older PHP versions
        if [ "$NON_INTERACTIVE" = true ]; then
            RETAIN_OLD_PHP="N" # Default to not retaining old PHP versions in non-interactive mode
        else
            prompt "Do you want to retain older PHP versions? (y/N): "
            read RETAIN_OLD_PHP
            RETAIN_OLD_PHP=${RETAIN_OLD_PHP:-N}
        fi

        if [[ "$RETAIN_OLD_PHP" =~ ^[Yy]$ ]]; then
            info "Retaining all older PHP versions. This might increase disk usage and may cause conflicts if other applications depend on older PHP versions."
        else
            warning "Disabling older PHP versions may affect other applications that use these versions. Ensure that other applications are compatible with the new PHP version before proceeding."

            # Proceed with disabling old PHP versions
            for version in $(ls /etc/apache2/mods-enabled/php*.load | grep -oP 'php\K[\d.]+(?=.load)' | grep -v "$LATEST_PHP_VERSION"); do
                # Backup the current PHP configuration before disabling it
                PHP_CONF="/etc/apache2/mods-available/php${version}.conf"
                if [ -f "$PHP_CONF" ]; then
                    cp "$PHP_CONF" "${PHP_CONF}.bak"
                    info "Backed up $PHP_CONF to ${PHP_CONF}.bak"
                fi
                a2dismod "php${version}"
                info "Disabled PHP $version"
            done
            success "Older PHP versions have been disabled."
        fi

        # Enable the latest PHP version
        info "Enabling PHP $LATEST_PHP_VERSION..."
        a2enmod php"$LATEST_PHP_VERSION"

        # Create a backup of the current installation
        create_backup "$FIREFLY_INSTALL_DIR"

        # Download and validate the latest release
        download_and_validate_release "firefly-iii/firefly-iii" "$FIREFLY_TEMP_DIR" "\\.zip$" || return 1

        # Extract the archive file
        archive_file=$(ls "$FIREFLY_TEMP_DIR"/*.zip | head -n 1)
        extract_archive "$archive_file" "$FIREFLY_TEMP_DIR" || return 1

        # Search for the .env.example file
        env_example_path=$(find "$FIREFLY_TEMP_DIR" -name ".env.example" -print -quit)

        # Copy over the .env file
        info "Copying configuration files..."
        if [ -f "$FIREFLY_INSTALL_DIR/.env" ]; then
            cp "$FIREFLY_INSTALL_DIR/.env" "$FIREFLY_TEMP_DIR/.env"
            chown www-data:www-data "$FIREFLY_TEMP_DIR/.env"
            chmod 640 "$FIREFLY_TEMP_DIR/.env"
        else
            warning "No .env file found in $FIREFLY_INSTALL_DIR. Creating a new .env file from .env.example..."

            # Check if the .env.example file was found
            if [ -n "$env_example_path" ]; then
                cp "$env_example_path" "$FIREFLY_TEMP_DIR/.env"
                chown www-data:www-data "$FIREFLY_TEMP_DIR/.env"
                chmod 640 "$FIREFLY_TEMP_DIR/.env"
                setup_env_file "$FIREFLY_TEMP_DIR" # Populate the new .env file with necessary configurations
            else
                error ".env.example not found. Please ensure the example file is present."
                return 1
            fi
        fi

        # Set permissions for the rest of the files in the temp directory
        info "Setting permissions..."
        chown -R www-data:www-data "$FIREFLY_TEMP_DIR"
        chmod -R 775 "$FIREFLY_TEMP_DIR/storage"

        # Move the old installation
        info "Moving old installation to ${FIREFLY_INSTALL_DIR}-old"
        mv "$FIREFLY_INSTALL_DIR" "${FIREFLY_INSTALL_DIR}-old"

        # Move the new installation to the install directory
        mv "$FIREFLY_TEMP_DIR" "$FIREFLY_INSTALL_DIR"

        # Set ownership and permissions for the new installation
        chown -R www-data:www-data "$FIREFLY_INSTALL_DIR"
        chmod -R 775 "$FIREFLY_INSTALL_DIR/storage"

        # Run artisan commands with error handling
        info "Running artisan commands for Firefly III..."
        cd "$FIREFLY_INSTALL_DIR"

        # Generate application key if not already set
        if grep -q '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env" && [ -n "$(grep '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2)" ]; then
            info "APP_KEY already set. Skipping key generation."
        else
            if ! sudo -u www-data php artisan key:generate; then
                error "Failed to generate application key with php artisan. Please check your configuration."
                return 1
            fi
        fi

        # Capture the APP_KEY
        APP_KEY=$(grep '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env" | cut -d '=' -f2)
        export APP_KEY

        # Check if migrations have already been run
        info "Checking if database migrations have already been applied..."
        if sudo -u www-data php artisan migrate:status &>/dev/null; then
            info "Migrations have already been applied. Proceeding to migrate any new changes."
            if ! sudo -u www-data php artisan migrate --force; then
                error "Failed to migrate database with php artisan. Please check your configuration."
                return 1
            fi
        else
            info "No migrations found. Proceeding with database migration."
            if ! sudo -u www-data php artisan migrate --force; then
                error "Failed to migrate database with php artisan. Please check your configuration."
                return 1
            fi
        fi

        # Update database schema and correct any issues with error handling
        info "Updating database schema and correcting any issues..."
        if ! sudo -u www-data php artisan config:cache; then
            error "Failed to cache configuration with php artisan. Please check your configuration."
            return 1
        fi

        if ! sudo -u www-data php artisan firefly-iii:upgrade-database; then
            error "Failed to upgrade Firefly III database. Please check your configuration."
            return 1
        fi

        if ! sudo -u www-data php artisan firefly-iii:correct-database; then
            error "Failed to correct database issues with Firefly III. Please check your configuration."
            return 1
        fi

        if ! sudo -u www-data php artisan firefly-iii:report-integrity; then
            error "Failed to report database integrity issues with Firefly III. Please check your configuration."
            return 1
        fi

        # Check if Passport tables already exist
        info "Checking if Laravel Passport tables already exist..."
        PASSPORT_TABLE_EXISTS=$(mysql -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES LIKE 'oauth_auth_codes';" | grep -c "oauth_auth_codes")

        if [ "$PASSPORT_TABLE_EXISTS" -eq 0 ]; then
            info "Passport tables do not exist. Installing Laravel Passport..."
            if ! sudo -u www-data php artisan passport:install --force --no-interaction; then
                error "Failed to install Laravel Passport. Please check your configuration."
                return 1
            fi
        else
            info "Passport tables already exist. Skipping Laravel Passport installation."
        fi

        # Remove Passport migration files if tables already exist
        if [ "$PASSPORT_TABLE_EXISTS" -ne 0 ]; then
            info "Passport tables exist. Removing Passport migration files to prevent migration conflicts."
            rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000001_create_oauth_auth_codes_table.php"
            rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000002_create_oauth_access_tokens_table.php"
            rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000003_create_oauth_refresh_tokens_table.php"
            rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000004_create_oauth_clients_table.php"
            rm -f "$FIREFLY_INSTALL_DIR/database/migrations/2016_06_01_000005_create_oauth_personal_access_clients_table.php"
        fi

        # Adjust Apache configuration to serve Firefly III with HTTPS
        info "Configuring Apache for Firefly III with HTTPS..."

        # Check if SSL certificates exist before configuring Apache
        if [ ! -f "/etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem" ] || [ ! -f "/etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem" ]; then
            error "SSL certificates for $DOMAIN_NAME are missing. Please ensure Certbot has successfully obtained certificates."
            return 1
        fi

        # Backup existing Apache configuration if present
        if [ -f /etc/apache2/sites-available/firefly-iii.conf ]; then
            cp /etc/apache2/sites-available/firefly-iii.conf /etc/apache2/sites-available/firefly-iii.conf.bak
        fi

        # Create new Apache configuration
        cat >/etc/apache2/sites-available/firefly-iii.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    Redirect permanent / https://$DOMAIN_NAME/
</VirtualHost>

<VirtualHost *:443>
    ServerName $DOMAIN_NAME
    DocumentRoot $FIREFLY_INSTALL_DIR/public

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem

    <Directory $FIREFLY_INSTALL_DIR/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/firefly-error.log
    CustomLog \${APACHE_LOG_DIR}/firefly-access.log combined
</VirtualHost>
EOF

        # Set APP_URL based on whether a domain is configured or not
        if [ "$HAS_DOMAIN" = true ]; then
            sed -i "s|APP_URL=.*|APP_URL=https://$DOMAIN_NAME/firefly-iii|" "$FIREFLY_INSTALL_DIR/.env"
            info "APP_URL set to https://$DOMAIN_NAME/firefly-iii in .env."
        else
            sed -i "s|APP_URL=.*|APP_URL=http://${server_ip}/firefly-iii|" "$FIREFLY_INSTALL_DIR/.env"
            info "APP_URL set to http://${server_ip}/firefly-iii in .env."
        fi

        # Enable the SSL module and the new site configuration
        a2enmod ssl
        a2ensite firefly-iii

        # Restart Apache to apply changes and add proper error handling
        info "Restarting Apache web server..."
        apachectl configtest || {
            error "Apache configuration test failed. Please check the configuration."
            return 1
        }

        # Attempt to reload Apache, and if that fails, try starting it
        if ! systemctl restart apache2; then
            error "Failed to restart Apache. Please check the Apache error logs for more details."
            return 1
        fi

        success "Apache successfully reloaded or started."

        # Verify if Certbot's systemd timer or cron job for renewal exists
        info "Checking for Certbot auto-renewal mechanism..."

        # Check for systemd timer
        if systemctl list-timers | grep -q certbot; then
            info "Certbot systemd timer found. Auto-renewal is already configured."
        else
            # Check for existing cron job for Certbot
            if crontab -l | grep -q "certbot renew"; then
                info "Certbot cron job for auto-renewal found. No further action needed."
            else
                # Add a cron job to auto-renew the SSL certificate if neither exists
                info "No existing auto-renewal mechanism found. Setting up cron job for Certbot renewal..."
                (
                    crontab -l 2>/dev/null
                    echo "0 */12 * * * certbot renew --quiet --renew-hook 'systemctl reload apache2'"
                ) | crontab -
                info "Cron job for Certbot renewal added. It will run twice a day."
            fi
        fi

        success "Firefly III update completed. The old installation has been moved to ${FIREFLY_INSTALL_DIR}-old"

    else
        info "Update canceled by the user."
        exit 0
    fi

    # Indicate successful completion
    return 0
}

# Function to cleanup temporary files
cleanup() {
    info "Cleaning up temporary files..."

    # Check if the temporary directories exist before trying to remove them
    if [ -d "$FIREFLY_TEMP_DIR" ]; then
        rm -rf "$FIREFLY_TEMP_DIR"
    fi

    if [ -d "$IMPORTER_TEMP_DIR" ]; then
        rm -rf "$IMPORTER_TEMP_DIR"
    fi
}

# Register the cleanup function to run on script exit
trap cleanup EXIT

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

# Start by displaying mode options
display_mode_options

# Variables (configurable)
FIREFLY_INSTALL_DIR="${FIREFLY_INSTALL_DIR:-/var/www/firefly-iii}"
IMPORTER_INSTALL_DIR="${IMPORTER_INSTALL_DIR:-/var/www/data-importer}"
FIREFLY_TEMP_DIR="/tmp/firefly-iii-temp"
IMPORTER_TEMP_DIR="/tmp/data-importer-temp"

# Ensure the temporary directories are available and empty
if [ -d "$FIREFLY_TEMP_DIR" ]; then
    rm -rf "$FIREFLY_TEMP_DIR"/*
else
    mkdir -p "$FIREFLY_TEMP_DIR"
fi

if [ -d "$IMPORTER_TEMP_DIR" ]; then
    rm -rf "$IMPORTER_TEMP_DIR"/*
else
    mkdir -p "$IMPORTER_TEMP_DIR"
fi

# Detect the server's IP address
server_ip=$(hostname -I | awk '{print $1}')

# Trap exit to ensure cleanup and display log location even on failure
trap 'cleanup; echo -e "${COLOR_YELLOW}Log file for this run: ${LOG_FILE}${COLOR_RESET}"; echo -e "${COLOR_YELLOW}For troubleshooting, check the log at: ${LOG_FILE}${COLOR_RESET}";' EXIT

# Update package lists once
apt-get update
apt-get full-upgrade -y
for cmd in curl jq wget unzip openssl gpg; do # Add gpg here
    if ! command -v $cmd &>/dev/null; then
        warning "Command '$cmd' is missing. Installing it now..."
        apt-get install -y $cmd || {
            error "Failed to install '$cmd'. Please install it manually and re-run the script."
            return 1
        }
    fi
done

# Check if Apache is installed to use 'apachectl' instead of a2query
if ! command -v apachectl &>/dev/null; then
    info "Apache is not installed. Proceeding to install Apache..."
    apt-get install -y apache2 || {
        error "Failed to install Apache. Please check your network connection and package manager settings, and then try installing Apache manually with 'apt-get install apache2'."
        return 1
    }

    # Start Apache after installation
    info "Starting Apache service..."
    systemctl start apache2 || {
        error "Failed to start Apache. Please check the system logs for more details and manually start the service using 'systemctl start apache2'."
        return 1
    }

    success "Apache installed and started successfully."
else
    apachectl configtest &>/dev/null || {
        error "Apache is installed but the configuration is incorrect. Please check '/etc/apache2/apache2.conf' or run 'apachectl configtest' to identify issues."

        # Check for non-interactive mode
        if [ "$NON_INTERACTIVE" = true ]; then
            error "Apache configuration issues must be fixed manually in non-interactive mode. Exiting."
            return 1
        fi

        # Ask if the user wants to retry in interactive mode
        prompt "Do you want to try fixing the configuration and retry? (Y/n): "
        read RETRY_APACHE
        RETRY_APACHE=${RETRY_APACHE:-Y}

        if [[ "$RETRY_APACHE" =~ ^[Yy]$ ]]; then
            info "Retrying Apache configuration test..."
            apachectl configtest || {
                error "Apache configuration test failed again. Please resolve the issue and re-run the script."
                return 1
            }
        else
            error "Apache configuration issues must be fixed before proceeding. Exiting."
            return 1
        fi
    }

    success "Apache is already installed and configured correctly."
fi

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
    if [ -d "$FIREFLY_INSTALL_DIR" ]; then
        info "Firefly III directory exists. Verifying installation..."

        # Check if important directories exist
        if [ ! -d "$FIREFLY_INSTALL_DIR/public" ] || [ ! -d "$FIREFLY_INSTALL_DIR/storage" ]; then
            error "Important Firefly III directories are missing (public or storage). This may indicate a broken installation."
            return 1
        fi

        # Check for critical files
        if [ ! -f "$FIREFLY_INSTALL_DIR/.env" ] || [ ! -f "$FIREFLY_INSTALL_DIR/artisan" ] || [ ! -f "$FIREFLY_INSTALL_DIR/config/app.php" ]; then
            error "Critical Firefly III files are missing (.env, artisan, config/app.php)."
            return 1
        fi

        # Check if .env file contains necessary configurations
        if ! grep -q '^APP_KEY=' "$FIREFLY_INSTALL_DIR/.env"; then
            error "APP_KEY is missing from the .env file."
            return 1
        fi

        if ! grep -q '^DB_CONNECTION=' "$FIREFLY_INSTALL_DIR/.env"; then
            error "Database configuration is missing from the .env file."
            return 1
        fi

        # Check if the vendor directory exists (Composer dependencies)
        if [ ! -d "$FIREFLY_INSTALL_DIR/vendor" ]; then
            error "Composer dependencies (vendor directory) are missing. You may need to run 'composer install'."
            return 1
        fi

        # Read database credentials from .env file
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

        # Verify database connectivity based on DB_CONNECTION in the .env file
        if [ "$DB_CONNECTION" = "mysql" ]; then
            info "Checking MySQL database connection..."

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
                error "Failed to connect to MySQL database. Please check your database credentials."
                return 1
            fi
            rm -f "$TEMP_MY_CNF"
            success "Successfully connected to MySQL database."
        elif [ "$DB_CONNECTION" = "sqlite" ]; then
            info "Checking SQLite database file..."
            if [ ! -f "$FIREFLY_INSTALL_DIR/database/database.sqlite" ]; then
                error "SQLite database file is missing."
                return 1
            fi
            success "SQLite database file exists."
        else
            error "Unknown database connection type specified in .env file."
            return 1
        fi

        # Check if Apache or Nginx is running
        if systemctl is-active --quiet apache2; then
            success "Apache is running."
        elif systemctl is-active --quiet nginx; then
            success "Nginx is running."
        else
            warning "Neither Apache nor Nginx is running. The web server may not be properly configured."
            return 1
        fi

        # If all checks passed
        success "Firefly III is installed and seems functional."
        return 0
    else
        # Directory does not exist, likely a fresh install
        warning "Firefly III directory does not exist. Proceeding with a fresh installation..."
        return 1
    fi
}

# Function to check if Firefly Importer is installed and functional
check_firefly_importer_installation() {
    if [ -d "$IMPORTER_INSTALL_DIR" ]; then
        info "Firefly Importer directory exists. Verifying installation..."

        # Check if important directories exist
        if [ ! -d "$IMPORTER_INSTALL_DIR/public" ] || [ ! -d "$IMPORTER_INSTALL_DIR/storage" ]; then
            error "Important Firefly Importer directories are missing (public or storage). This may indicate a broken installation."
            return 1
        fi

        # Check for critical files
        if [ ! -f "$IMPORTER_INSTALL_DIR/.env" ] || [ ! -f "$IMPORTER_INSTALL_DIR/artisan" ] || [ ! -f "$IMPORTER_INSTALL_DIR/config/app.php" ]; then
            error "Critical Firefly Importer files are missing (.env, artisan, config/app.php)."
            return 1
        fi

        # Check if .env file contains necessary configurations
        if ! grep -q '^APP_KEY=' "$IMPORTER_INSTALL_DIR/.env"; then
            error "APP_KEY is missing from the .env file."
            return 1
        fi

        if ! grep -q '^FIREFLY_III_URL=' "$IMPORTER_INSTALL_DIR/.env"; then
            error "Firefly III URL configuration is missing from the .env file."
            return 1
        fi

        # Check if the vendor directory exists (Composer dependencies)
        if [ ! -d "$IMPORTER_INSTALL_DIR/vendor" ]; then
            error "Composer dependencies (vendor directory) are missing. You may need to run 'composer install'."
            return 1
        fi

        # Read database credentials from .env file (if applicable)
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

        # Verify database connectivity if applicable
        if [ "$DB_CONNECTION" = "mysql" ]; then
            info "Checking MySQL database connection for Importer..."

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
                error "Failed to connect to MySQL database for Importer. Please check your database credentials."
                return 1
            fi
            rm -f "$TEMP_MY_CNF"
            success "Successfully connected to MySQL database for Importer."
        elif [ "$DB_CONNECTION" = "sqlite" ]; then
            info "Checking SQLite database file for Importer..."
            if [ ! -f "$IMPORTER_INSTALL_DIR/database/database.sqlite" ]; then
                error "SQLite database file is missing for Importer."
                return 1
            fi
            success "SQLite database file for Importer exists."
        else
            warning "No database connection configured for Importer or unknown connection type."
        fi

        # Check if Apache or Nginx is running and serving Firefly Importer
        if systemctl is-active --quiet apache2; then
            success "Apache is running."
        elif systemctl is-active --quiet nginx; then
            success "Nginx is running."
        else
            warning "Neither Apache nor Nginx is running. The web server may not be properly configured for Importer."
            return 1
        fi

        # If all checks passed
        success "Firefly Importer is installed and seems functional."
        return 0
    else
        # Directory does not exist, likely a fresh install
        warning "Firefly Importer directory does not exist. Proceeding with a fresh installation..."
        return 1
    fi
}

#####################################################################################################################################################
#
#   SCRIPT EXECUTION
#
#####################################################################################################################################################

# Main check for Firefly III installation or update
if check_firefly_installation; then
    # Update Firefly III
    if ! update_firefly; then
        error "Firefly III update failed."
        # Decide whether to exit or proceed
        # For example, you might choose to exit:
        exit 1
        # Or you can choose to proceed to the next steps
    fi
else
    # Fresh installation of Firefly III
    if ! install_firefly; then
        error "Firefly III installation failed."
        # Decide whether to exit or proceed
        exit 1
    fi
fi

# Main check for Firefly Importer installation or update
if check_firefly_importer_installation; then
    # Update Firefly Importer
    if ! update_firefly_importer; then
        error "Firefly Importer update failed."
        exit 1
    fi
else
    # Fresh installation of Firefly Importer
    if ! install_firefly_importer; then
        error "Firefly Importer installation failed."
        exit 1
    fi
fi

# Final message
success "Installation and update process completed."
info "You can access Firefly III at http://${server_ip}/firefly-iii"
info "And Firefly Importer at http://${server_ip}/data-importer"
info "Firefly III configuration file is located at: $FIREFLY_INSTALL_DIR/.env"
info "Firefly Importer configuration file is located at: $IMPORTER_INSTALL_DIR/.env"
info "A cron job has been set up to run scheduled tasks daily at $CRON_HOUR:00."
info "If you need to modify the cron job, edit: /etc/cron.d/firefly-iii-cron"
info "Database credentials and tokens have been saved to /root/firefly_credentials.txt"
info "Please keep this file safe and consider changing the credentials for increased security."

# Provide log file location to the user
info "Log file for this run: ${LOG_FILE}"
info "To view the log, use: 'cat ${LOG_FILE}' or 'less ${LOG_FILE}'"
info "Log files older than 7 days have been automatically deleted."
info "If you encounter issues, check the log file for troubleshooting."
