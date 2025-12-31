#!/usr/bin/env bash
####################################################################################
#  __   __     ______     ______      ______   ______     ______     __            #
# /\ "-.\ \   /\  ___\   /\__  _\    /\__  _\ /\  __ \   /\  __ \   /\ \           #
# \ \ \-.  \  \ \  __\   \/_/\ \/    \/_/\ \/ \ \ \/\ \  \ \ \/\ \  \ \ \____      #
#  \ \_\\"\_\  \ \_____\    \ \_\       \ \_\  \ \_____\  \ \_____\  \ \_____\     #
#   \/_/ \/_/   \/_____/     \/_/        \/_/   \/_____/   \/_____/   \/_____/     #
####################################################################################                                                                            
                            #  NET TOOL V0.3  #

# \\ Test connectivity //
#  \\ Show network information //
#   \\ Subnetting (by number of subnetworks) //
#    \\ Subnetting (by number of hosts) //
#     \\ Save subnetting calculation into .CSV file and import to MySQL database//
#     |||Usage: run the script and choose the menu option|||
#         ~~~ Generated with help from AI (ChatGPT 5 and Google Gemini) ~~~                      
              

# -e (Exit immediately if any command returns a non-zero status)
# -u (Treat using an undefined variable as an error)
# -o pipefail (If any command in a pipeline fails, the entire pipeline is considered failed)
set -euo pipefail

###############################
# Utility / helper functions  # 
###############################

# ip_to_int function
# Convert dotted IPv4 (e.g. 192.168.1.0) to a 32-bit integer.
# Returns value via stdout.
ip_to_int() {
    # \\local attribute//
    # makes the listed names local to this function (so it exist only while the function runs,
    # don’t overwrite variables of the same name outside the function, 
    # disappear when the function returns)

    # IFS temporarily sets the internal field separator to . for this function scope // IFS controls how fields are split when read (and other shell splitting) runs.
    # a b c d will hold the four octets of the IPv4 address.
    # ip="$1" stores the first positional argument (the dotted IP string passed to the function) into the local var ip
    local IFS=. a b c d ip="$1"

    # read -r a b c d reads up to four fields from stdin into the variables a, b, c, d
    # -r disables backslash escapes
    # <<< "$ip" is a here-string: it feeds the contents of $ip into read as input
    # Because IFS is . (set above), read splits the string at . characters. So for "192.168.1.0" you get a=192, b=168, c=1, d=0
    read -r a b c d <<< "$ip"

    # Arithmetic expansion $(( ... )) evaluates a numeric expression in bash.
    # a << 24 shifts the value of a left by 24 bits (same as a * 2^24), placing the first octet into the highest 8 bits of the 32-bit result
    # b << 16 places the second octet into the next 8 bits
    # c << 8 places the third octet into the next 8 bits.
    # d is the lowest 8 bits
    # The bitwise OR operator | combines the shifted octets into one 32-bit integer
    echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

# int_to_ip function
# Convert a 32-bit integer to dotted IPv4, printed to stdout.
int_to_ip() {
    local val=$1
    local a b c d # Declares local variables a, b, c, d that will hold the four octets of the IPv4 address.
    
    # val >> 24 shifts val right by 24 bits — that moves the highest (most significant) 8 bits of the 32-bit value into the least significant byte position
    # & 255 (255 is 0xFF) masks the result to the lowest 8 bits, ensuring a is in range 0..255
    # b=$(( (val >> 16) & 255 )) Moves the bits right by 16 places, then keeps the last 8 bits → second octet
    # c=$(( (val >> 8) & 255 )) Moves the bits right by 8 places, keeps last 8 bits → third octet.
    # d=$(( val & 255 )) Doesn’t shift anything — just keeps the last 8 bits.

    a=$(( (val >> 24) & 255 ))
    b=$(( (val >> 16) & 255 ))
    c=$(( (val >> 8) & 255 ))
    d=$(( val & 255 ))
    echo "${a}.${b}.${c}.${d}"
}

# prefix_to_mask_int function
# Build a mask integer from a CIDR prefix (e.g. 24 -> 0xFFFFFF00) whose binary form represents the subnet mask for that prefix
prefix_to_mask_int() {
    local p=$1

    # Validate that p is between 0 and 32 inclusive. CIDR prefixes outside this range don’t make sense for IPv4.
    if (( p < 0 || p > 32 )); then
        echo "0" ; return 1
    fi

    # left shift the full 32-bit ones and mask to 32 bits
    # 0xFFFFFFFF is 32 ones in hex; 
    # The left shift can create bits beyond 32 bits (Bash uses larger integer widths internally), 
    # so mask ensures we keep only the 32 bits representing the IPv4 mask.
    echo $(( (0xFFFFFFFF << (32 - p)) & 0xFFFFFFFF ))
}

# mask_int_to_dotted function
# Convert mask integer to dotted decimal notation, printed to stdout.
mask_int_to_dotted() {
    int_to_ip "$1"
}

# mask_dotted_to_prefix function
# Convert dotted-decimal mask (255.255.255.0) to prefix length (24).
mask_dotted_to_prefix() {
    local mask="$1"

    # convert dotted to int then count ones
    local mi
    mi=$(ip_to_int "$mask")

    # Initialize a counter cnt to count how many contiguous 1 bits 
    # are at the start (most significant bits) of the mask.
    local cnt=0

    # Loop over bit positions from 31 down to 0
    local i
    for (( i=31; i>=0; i-- )); do

    # Shift mi right by i positions, bringing the bit at position i into the least significant position, 
    # then AND with 1 to test whether that bit is 1
        if (( (mi >> i) & 1 )); then
            cnt=$((cnt + 1))
        else
            break
        fi
    done

    # confirm remaining bits are zero (validate contiguous ones)
    local rest_mask=$(( mi & ((1 << (32 - cnt)) - 1) ))
    if (( rest_mask != 0 )); then
        echo "Error: mask $mask is non-contiguous or invalid" >&2
        return 1
    fi
    echo "$cnt"
}

# count_min_borrow_bits function
# Find smallest n such that 2^n >= requested_subnets.
# How many bits you need to borrow from the host part of a network 
# to create a certain number of subnetworks.
# In subnetting, each extra “borrowed bit” doubles the number of possible subnets.

count_min_borrow_bits() {
    local req=$1
    if (( req <= 0 )); then
        echo "0" ; return
    fi

    # Keep increasing n until 2^n is at least the number of requested subnets.
    local n=0
    while (( (1 << n) < req )); do
        n=$((n + 1))
    done
    echo "$n"
}


#### Definition of CSV Output Files ####
CSV_HOSTS="by_number_of_hosts.csv"
CSV_SUBNETS="by_number_of_subnetworks.csv"

###############################################################################
# Subnetting BY NUMBER OF HOSTS                                               #
###############################################################################

# find_min_prefix_for_hosts function 
# Finds the smallest prefix (>= orig_prefix) that yields usable hosts >= required_hosts.
# Explanation:
#  - For each candidate prefix p (starting at orig_prefix), compute host_bits = 32 - p.
#  - Usable hosts = 2^host_bits - 2 (classical rule: exclude network & broadcast).
#    For host_bits <=1 the usable hosts per classical rule are 0 (we treat them accordingly).
#  - Return the minimal p for which usable >= required_hosts.

find_min_prefix_for_hosts() {
    local orig_prefix=$1
    local req_hosts=$2

    if (( req_hosts <= 0 )); then
        echo "$orig_prefix"
        return
    fi

    # Iterate from 32 down to orig_prefix (largest prefix value = smallest subnet)
    local p
    for (( p = 32; p >= orig_prefix; p-- )); do
        local host_bits=$(( 32 - p ))
        local usable

        # Tests whether host_bits is 1 or 0
        if (( host_bits <= 1 )); then
            usable=0    # /31 and /32 have 0 usable hosts in classical host counting
        else
            usable=$(( (1 << host_bits) - 2 ))
        fi

        # Checks whether the number of usable addresses in this candidate prefix is enough to meet the requested host requirement
        if (( usable >= req_hosts )); then
            echo "$p"
            return 0
        fi
    done

    echo "Error: required hosts ($req_hosts) cannot be satisfied within IPv4 (/32 max)." >&2
    return 1
}


# generate_subnets_by_hosts function
# Main function implementing the "by number of hosts" algorithm.
# Explanation / algorithm steps implemented:
# 1) Resolve the original prefix (from dotted mask or CIDR).
# 2) Determine the minimal new prefix that provides at least required_hosts usable hosts.
# 3) Compute the number of bits borrowed = new_prefix - orig_prefix.
# 4) Compute block_size = 2^(32 - new_prefix) (addresses per subnet).
# 5) Compute the increment (same as block_size) and list all subnets inside the original network.

generate_subnets_by_hosts() {
    local base_ip="$1"
    local maskarg="$2"
    local req_hosts="$3"

    # Resolve maskarg to prefix
    local orig_prefix
    if [[ "$maskarg" =~ ^/?([0-9]|[12][0-9]|3[0-2])$ ]]; then
        orig_prefix="${BASH_REMATCH[1]}"
    else
        orig_prefix=$(mask_dotted_to_prefix "$maskarg") || return 1
    fi

    if ! [[ "$req_hosts" =~ ^[0-9]+$ ]]; then
        echo "Error: required hosts must be a positive integer." >&2
        return 1
    fi

    local ip_int orig_mask_int
    ip_int=$(ip_to_int "$base_ip")
    orig_mask_int=$(prefix_to_mask_int "$orig_prefix")

    # Determine minimal SUBNET SIZE that still fits requested hosts:
    local new_prefix
    new_prefix=$(find_min_prefix_for_hosts "$orig_prefix" "$req_hosts") || return 1

    local borrow=$(( new_prefix - orig_prefix ))
    local new_mask_int
    new_mask_int=$(prefix_to_mask_int "$new_prefix")
    local block_size=$(( 1 << (32 - new_prefix) ))  # addresses per subnet
    local host_bits=$(( 32 - new_prefix ))
    local usable_hosts
    if (( host_bits <= 1 )); then
        usable_hosts=0
    else
        usable_hosts=$(( (1 << host_bits) - 2 ))
    fi

    # Number of subnets inside the original network
    local total_subnets=$(( 1 << borrow ))

    # Calculate Decimal Masks for CSV and Display
    local orig_mask_dotted=$(mask_int_to_dotted "$orig_mask_int")
    local new_mask_dotted=$(mask_int_to_dotted "$new_mask_int")
   

    # Print header/details
    echo "Base IP ...........: $base_ip"
    echo "Original prefix ....: /$orig_prefix"
    echo -n "Original mask (bin): "

    # iterate over the bit positions for each octet in a 32-bit IPv4 address
    for oct in 24 16 8 0; do

    # >> oct shifts the bits right by oct places, effectively isolating one octet’s worth of bits.
    # & 255 masks off everything except the lowest 8 bits
    # So the result (octv) is the integer value of that octet (0–255)
        local octv=$(( (orig_mask_int >> oct) & 255 ))

    # Initializes an empty string b which will store the binary representation
    # Loops from k = 7 down to 0 (so from most significant bit to least significant bit).
    # (octv >> k) shifts the octet value right by k bits.
    # & 1 isolates the last bit — if it’s 1, that bit is set; if 0, it’s clear.
    # The result (0 or 1) is appended to string b.
        local b=""
        for ((k=7;k>=0;k--)); do
            b+=$(( (octv >> k) & 1 ))
        done
        printf '%s.' "$b"
    done
    echo -e "\b "
    echo "Original mask (dec): $(mask_int_to_dotted "$orig_mask_int")"
    echo ""
    echo "Requested hosts ....: $req_hosts"
    echo "Bits to borrow .....: $borrow"
    echo "New prefix .........: /$new_prefix"
    echo "New mask (dec) .....: $(mask_int_to_dotted "$new_mask_int")"
    echo "Addresses per subnet: $block_size (includes network & broadcast)"
    echo "Usable hosts/subnet.: $usable_hosts"
    echo "Increment (addr) ...: $block_size"
    echo "Total subnets ......: $total_subnets"
    echo

    # Align start to the ORIGINAL network boundary (so we subdivide only inside original)
    local start_net=$(( ip_int & orig_mask_int ))

    # Variable to accumulate subnets for the CSV column
    # We will separate individual subnets with a semicolon ';' inside the CSV column
    local csv_subnets_string=""

    # Generate all subnets contained in the original network
    local i
    for (( i = 0; i < total_subnets; i++ )); do
        local net=$(( start_net + i * block_size ))
        local first=$net
        local last=$(( net + block_size - 1 ))
        local net_s first_s last_s usable_from usable_to
        net_s=$(int_to_ip "$net")
        first_s=$(int_to_ip "$first")
        last_s=$(int_to_ip "$last")

        # compute usable range (classical definition), but handle small subnets
        if (( host_bits <= 1 )); then
            usable_from="N/A"
            usable_to="N/A"
        else
            usable_from=$(int_to_ip $(( first + 1 )))
            usable_to=$(int_to_ip $(( last - 1 )))
        fi

        printf 'Subnet %2d : %s - %s    usable: %s - %s\n' $((i+1)) "$net_s" "$last_s" "$usable_from" "$usable_to"
        
        # Append to CSV string (Format: "Subnet X : Network - Broadcast")
        # We use a semicolon separator to keep it valid in a single CSV cell
        csv_subnets_string+="Subnet $((i+1)) : $net_s - $last_s; "
    
    done

    # CSV Export Logic
    # Generate a unique ID (Unix timestamp)
    local row_id=$(date +%s)
    
    # Check if file exists, if not create it with Header
    if [[ ! -f "$CSV_HOSTS" ]]; then
        echo "ID,base_net_IP,base_mask,nr_of_hosts,new_prefix,new_mask,addr_per_subnet,total_subnets,subnets" > "$CSV_HOSTS"
    fi

    # DUPLICATE CHECK: 
    # We look for a line that has the same base_ip, base_mask, and req_hosts.
    # We use grep with anchors (^) to match specific columns.
    if grep -q ",\"${base_ip}\",\"${orig_mask_dotted}\",\"${req_hosts}\"," "$CSV_HOSTS"; then
        echo "[SKIP] This specific calculation already exists in $CSV_HOSTS."
    else
        # Append data only if it's new
        echo "${row_id},\"${base_ip}\",\"${orig_mask_dotted}\",\"${req_hosts}\",\"${new_prefix}\",\"${new_mask_dotted}\",\"${block_size}\",\"${total_subnets}\",\"${csv_subnets_string}\"" >> "$CSV_HOSTS"
        echo "[INFO] Data exported to $CSV_HOSTS"
    fi
}

    
###############################################################################
# Subnetting BY NUMBER OF SUBNETWORKS                                         #
###############################################################################

# generate_subnets_by_count <base-ip> <mask-or-prefix> <requested_subnets>
# Main function that:
#  - accepts base IPv4 network (e.g. 192.168.1.0)
#  - accepts mask in dotted form (255.255.255.0) OR CIDR (/24 or 24)
#  - accepts requested number of subnets (e.g. 4)
# Then prints:
#  - original mask in binary and decimal
#  - number of bits borrowed and new prefix (e.g. /26)
#  - new mask (dotted) and increment/range
#  - each subnetwork: network - broadcast (inclusive)

generate_subnets_by_count() {
    local base_ip="$1"
    local maskarg="$2"
    local requested="$3"

    # Resolve mask argument to prefix length
    local orig_prefix
    if [[ "$maskarg" =~ ^/?([0-9]|[12][0-9]|3[0-2])$ ]]; then
        # format like 24 or /24
        orig_prefix="${BASH_REMATCH[1]}"
    else
        # assume dotted mask like 255.255.255.0
        orig_prefix=$(mask_dotted_to_prefix "$maskarg") || return 1
    fi

    # Convert things to integers
    local ip_int
    ip_int=$(ip_to_int "$base_ip")
    local orig_mask_int
    orig_mask_int=$(prefix_to_mask_int "$orig_prefix")

    # Count bits to borrow
    local borrow
    borrow=$(count_min_borrow_bits "$requested")
    local new_prefix=$(( orig_prefix + borrow ))

    if (( new_prefix > 32 )); then
        echo "Error: can't borrow $borrow bits from prefix /$orig_prefix (would exceed /32)" >&2
        return 1
    fi

    # New mask and sizes
    local new_mask_int
    new_mask_int=$(prefix_to_mask_int "$new_prefix")
    local total_subnets=$(( 1 << borrow ))
    local block_size=$(( 1 << (32 - new_prefix) ))    # number of hosts per subnet (addresses)
    local increment="$block_size"                    # increment in the last changing octet(s), in addresses

    # Prepare string versions for CSV
    local orig_mask_dotted=$(mask_int_to_dotted "$orig_mask_int")
    local new_mask_dotted=$(mask_int_to_dotted "$new_mask_int")


    # Show details
    echo "Base IP ...........: $base_ip"
    echo "Original prefix ....: /$orig_prefix"
    echo -n "Original mask (bin): "

    # print binary mask nicely (octet by octet)
    for oct in 24 16 8 0; do
        local octv=$(( (orig_mask_int >> oct) & 255 ))
        printf '%08d.' "$(echo "obase=2; $octv" | bc | tr -d '\n')"
    done
    echo -e "\b " # remove last dot visually

    echo "Original mask (dec): $(mask_int_to_dotted "$orig_mask_int")"
    echo ""
    echo "Requested subnets ..: $requested"
    echo "Bits to borrow .....: $borrow"
    echo "New prefix .........: /$new_prefix"
    echo "New mask (dec) .....: $(mask_int_to_dotted "$new_mask_int")"
    echo "Addresses per subnet: $block_size (including network & broadcast)"
    echo "Increment (addr) ...: $increment"
    echo "Total subnets ......: $total_subnets"
    echo

    # Align network base to the new network boundary:
    local start_net=$(( ip_int & new_mask_int ))

    # Variable to accumulate subnets for the CSV column
    local csv_subnets_string=""

    # Generate subnets
    local i
    for (( i = 0; i < total_subnets; i++ )); do
        local net=$(( start_net + i * block_size ))
        local first=$net
        local last=$(( net + block_size - 1 ))
        local net_s
        net_s=$(int_to_ip "$net")
        local first_s
        first_s=$(int_to_ip "$first")
        local last_s
        last_s=$(int_to_ip "$last")
        echo "Subnet $((i+1)) : $net_s - $last_s"

        # Append to CSV string
        csv_subnets_string+="Subnet $((i+1)) : $net_s - $last_s; "
    done

    # 4. CSV Export Logic
    local row_id=$(date +%s)

    # Check if file exists, if not create it with Header
    if [[ ! -f "$CSV_SUBNETS" ]]; then
        echo "ID,base_net_IP,base_mask,nr_of_sn,new_prefix,new_mask,addr_per_subnet,total_subnets,subnets" > "$CSV_SUBNETS"
    fi

    # DUPLICATE CHECK: Matches Base IP, Original Mask, and Requested Subnet count
    if grep -q ",\"${base_ip}\",\"${orig_mask_dotted}\",\"${requested}\"," "$CSV_SUBNETS"; then
        echo "[SKIP] This specific calculation already exists in $CSV_SUBNETS."
    else
        echo "${row_id},\"${base_ip}\",\"${orig_mask_dotted}\",\"${requested}\",\"${new_prefix}\",\"${new_mask_dotted}\",\"${block_size}\",\"${total_subnets}\",\"${csv_subnets_string}\"" >> "$CSV_SUBNETS"
        echo "[INFO] Data exported to $CSV_SUBNETS"
    fi
}

###############################################################################
# DATABASE IMPORT FUNCTIONALITY                                               #
###############################################################################

# Check if mysql command exists
check_mysql_installed() {
    if ! command -v mysql &> /dev/null; then
        echo "Error: 'mysql' command is not found."
        echo "Please install MySQL client (e.g. sudo apt install mysql-client) "
        return 1
    fi
    return 0
}

import_csv_to_db() {
    # 1. Check prerequisites
    check_mysql_installed || return 1

    echo "--------------------------------------------------------"
    echo "       Import CSV Data to Database (MySQL)              "
    echo "--------------------------------------------------------"

    # 2. Check if CSV files exist
    if [[ ! -f "$CSV_HOSTS" ]] && [[ ! -f "$CSV_SUBNETS" ]]; then
        echo "Error: No CSV files found to import."
        echo "Please generate subnets (Option 3 or 4) first."
        return 1
    fi

    # 3. Get Database Credentials and Name
    read -rp "Enter Database User (e.g., root): " db_user
    read -rsp "Enter Database Password: " db_pass
    echo ""
    read -rp "Enter Name of Database to Create/Use: " db_name

    # Validate inputs
    # -z STRING returns true if the string length is zero (i.e., the string is empty).
    if [[ -z "$db_name" ]]; then
        echo "Error: Database name cannot be empty."
        return 1
    fi

    # 4. Define Table Names
    local tbl_hosts="by_number_of_hosts"
    local tbl_subnets="by_number_of_subnetworks"

    # 5. Connect and Create Database
    echo "[INFO] Connecting to MySQL and creating database '$db_name'..."

    # exports a MySQL password to the environment so MySQL CLI tools can authenticate automatically
    export MYSQL_PWD="$db_pass"

    # Create DB
    if ! mysql -u "$db_user" -e "CREATE DATABASE IF NOT EXISTS \`$db_name\`;"; then
        echo "Error: Could not connect or create database. Check credentials."
        return 1
    fi

    # 6. Process 'By Hosts' CSV
    if [[ -f "$CSV_HOSTS" ]]; then
        echo "[INFO] Processing $CSV_HOSTS..."
        
        # SQL to create table
        # Mapping CSV Columns: ID,base_net_IP,base_mask,nr_of_hosts,new_prefix,new_mask,addr_per_subnet,total_subnets,subnets
        # We add a UNIQUE KEY named 'unique_calculation' on (base_net_ip, base_mask, nr_of_hosts).
        # This prevents duplicates even if the ID (timestamp) is different.

        local create_hosts_sql="CREATE TABLE IF NOT EXISTS \`$tbl_hosts\` (
            id BIGINT PRIMARY KEY,
            base_net_ip VARCHAR(15),
            base_mask VARCHAR(15),
            nr_of_hosts INT,
            new_prefix INT,
            new_mask VARCHAR(15),
            addr_per_subnet INT,
            total_subnets INT,
            subnets TEXT,
            imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            
        );"
    
        mysql -u "$db_user" -D "$db_name" -e "$create_hosts_sql"

        # Add Unique Index safely (Separated command)
        # We redirect error (2>/dev/null) if the index already exists.

        echo "[INFO] Verifying Unique Constraints...and for duplicates..."
       

        mysql -u "$db_user" -D "$db_name" -e "CREATE UNIQUE INDEX idx_hosts_calc ON \`$tbl_hosts\` (base_net_ip, base_mask, nr_of_hosts);" 2>/dev/null

        sed 1d "$CSV_HOSTS" | while IFS=, read -r id ip mask req prefix nmask addr total subs; do
            # Remove double quotes from variables if present
            ip=$(echo "$ip" | tr -d '"')
            mask=$(echo "$mask" | tr -d '"')
            req=$(echo "$req" | tr -d '"')
            prefix=$(echo "$prefix" | tr -d '"')
            nmask=$(echo "$nmask" | tr -d '"')
            addr=$(echo "$addr" | tr -d '"')
            total=$(echo "$total" | tr -d '"')
            subs=$(echo "$subs" | tr -d '"')

            # Run Insert
            mysql -u "$db_user" -D "$db_name" -e "INSERT IGNORE INTO \`$tbl_hosts\` 
            (id, base_net_ip, base_mask, nr_of_hosts, new_prefix, new_mask, addr_per_subnet, total_subnets, subnets) 
            VALUES 
            ($id, '$ip', '$mask', $req, $prefix, '$nmask', $addr, $total, '$subs');"
        done
        echo "[SUCCESS] Imported $CSV_HOSTS."
    fi

    # 7. Process 'By Subnetworks' CSV
    if [[ -f "$CSV_SUBNETS" ]]; then
        echo "[INFO] Processing $CSV_SUBNETS..."

        # Mapping CSV Columns: ID,base_net_IP,base_mask,nr_of_sn,new_prefix,new_mask,addr_per_subnet,total_subnets,subnets
        local create_subnets_sql="CREATE TABLE IF NOT EXISTS \`$tbl_subnets\` (
            id BIGINT PRIMARY KEY,
            base_net_ip VARCHAR(15),
            base_mask VARCHAR(15),
            nr_of_sn INT,
            new_prefix INT,
            new_mask VARCHAR(15),
            addr_per_subnet INT,
            total_subnets INT,
            subnets TEXT,
            imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );"

        mysql -u "$db_user" -D "$db_name" -e "$create_subnets_sql"

        # Add Unique Index safely

        echo "[INFO] Verifying Unique Constraints...and for duplicates..."
        

        mysql -u "$db_user" -D "$db_name" -e "CREATE UNIQUE INDEX idx_subnets_calc ON \`$tbl_subnets\` (base_net_ip, base_mask, nr_of_sn);" 2>/dev/null

        # sed 1d ( skip CSV header row )
        # IFS = Internal Field Separator
        # Setting it to , tells read to split each line on commas instead of whitespace.
        # tr -d '"' (remove double quotes from the value)
        sed 1d "$CSV_SUBNETS" | while IFS=, read -r id ip mask req prefix nmask addr total subs; do
            # Cleanup quotes
            ip=$(echo "$ip" | tr -d '"')
            mask=$(echo "$mask" | tr -d '"')
            req=$(echo "$req" | tr -d '"')
            prefix=$(echo "$prefix" | tr -d '"')
            nmask=$(echo "$nmask" | tr -d '"')
            addr=$(echo "$addr" | tr -d '"')
            total=$(echo "$total" | tr -d '"')
            subs=$(echo "$subs" | tr -d '"')
            
            mysql -u "$db_user" -D "$db_name" -e "INSERT IGNORE INTO \`$tbl_subnets\` 
            (id, base_net_ip, base_mask, nr_of_sn, new_prefix, new_mask, addr_per_subnet, total_subnets, subnets) 
            VALUES 
            ($id, '$ip', '$mask', $req, $prefix, '$nmask', $addr, $total, '$subs');"
        done
        echo "[SUCCESS] Imported $CSV_SUBNETS."
    fi

    # 8. Show Final Results 
    # We use the \G flag for vertical table format output in terminal
    echo ""
    echo "================ IMPORTED DATA REPORT ================"
    echo "Database: $db_name"
    echo ""
    
    if [[ -f "$CSV_HOSTS" ]]; then
        echo "TABLE: $tbl_hosts"
        echo "------------------------------------------------------"
        # Use \G flag for table formatting
        mysql -u "$db_user" -D "$db_name" -t -e "SELECT id, base_net_ip, nr_of_hosts, new_prefix, total_subnets, subnets FROM \`$tbl_hosts\` ORDER BY id DESC LIMIT 5\G;"
        echo ""
    fi

    if [[ -f "$CSV_SUBNETS" ]]; then
        echo "TABLE: $tbl_subnets"
        echo "------------------------------------------------------"
        mysql -u "$db_user" -D "$db_name" -t -e "SELECT id, base_net_ip, nr_of_sn, new_prefix, total_subnets, subnets FROM \`$tbl_subnets\` ORDER BY id DESC LIMIT 5\G;"
        echo ""
    fi
    
    echo "======================================================"
    
    # Clear password variable
    export MYSQL_PWD=""
}

###############################################################################
# Test Connection                                                             #
###############################################################################
# test_con()
# Test connection using ping (1 packet). Output "Connected!" or "Not connected!".
test_con(){
    ping -c 1 google.com 1>/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "Connected!"
    else
        echo "Not connected!"
    fi
}

###############################################################################
# Show network information                                                    #
###############################################################################
# show_net_info()
# Show IP, netmask and MAC via ifconfig output parsing.
show_net_info(){
    echo "Your IP address is:"
    ifconfig | grep -w inet | grep -v 127.0.0.1 | awk '{print $2}'

    echo ""
    echo "Your netmask is:"
    ifconfig | grep -w inet | grep -v 127.0.0.1 | awk '{print $4}'

    echo ""
    echo "Your MAC address is:"
    ifconfig | grep -w ether | awk '{print $2}'
}

###############################
# Interactive menu            #
###############################

while true; do
    echo ""
    echo "Hello ${USER:-user}, please select an option:"
    echo ""
    echo "1) Test internet connection"
    echo "2) Show network information"
    echo "3) Subnet by number of hosts (Auto-export CSV)"
    echo "4) Subnet by number of subnetworks (Auto-export CSV) "
    echo "5) Import CSV files to Database"
    echo "6) Exit"
    
    echo ""
    read -rp "Option: " opt
    echo ""

case "$opt" in
        1) test_con ;;
        2) show_net_info ;;
        3)
            read -rp "Enter base network IP (example: 10.1.1.0): " base
            read -rp "Enter mask (dotted, e.g. 255.255.255.0) or prefix (24 or /24): " mask
            read -rp "Enter required number of HOSTS per subnet (e.g. 40): " reqh

             # checks that the user’s input ($reqh) is a valid positive integer — meaning it contains only digits (0–9) and nothing else.
            if ! [[ "$reqh" =~ ^[0-9]+$ ]]; then
                echo "Required hosts must be a positive integer." ; continue
            fi
            generate_subnets_by_hosts "$base" "$mask" "$reqh" || echo "Subnet calculation failed."
            ;;
        4)
            read -rp "Enter base network IP (example: 192.168.1.0): " base
            read -rp "Enter mask (dotted, e.g. 255.255.255.0) or prefix (24 or /24): " mask
            read -rp "Enter requested number of subnetworks (e.g. 4): " req

            # checks that the user’s input ($req) is a valid positive integer — meaning it contains only digits (0–9) and nothing else.
            if ! [[ "$req" =~ ^[0-9]+$ ]]; then
                echo "Requested subnets must be a positive integer." ; continue
            fi
            generate_subnets_by_count "$base" "$mask" "$req" || echo "Subnet calculation failed."
            ;;
        
        5) #Call the DB import function
        import_csv_to_db
        ;;
     

        6) exit 0 ;;
        *) echo "Please choose a valid option." ;;
    esac
   
    # Pause to let user read the output
    echo ""
    read -rp "Press Enter to return to menu..."
done
