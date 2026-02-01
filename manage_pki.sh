#!/bin/bash
# manage_pki.sh
# copyright 2025 by somikro
# License: Creative Commons Attribution 4.0 International (see LICENSE file)
# Creates and manages a modern ECDSA-based PKI infrastructure
# Root CA: 
# Intermediate CAs: mydomain.space_CA, servers_CA, peoples_CA, machines_CA
#
# This script can:
# - Setup a complete PKI infrastructure (one-time)
# - Issue server certificates (via mydomain.space_CA or servers_CA)
# - Issue user certificates (via peoples_CA)
# - Issue device certificates (via machines_CA)
#
# This script is intended to be operated on a trusted and air-gaped system.
# See https://github.com/somikro/custom-debian-live-creator on how to setup an air-gapped PKI Debian based live system.
#
# The Root CA private key must be kept offline and secure at all times.
# The Intermediate CA private keys should also be kept secure.
# 
# Adjust OpenSSL configurations as needed. That is kept in CA specific files named openssl.cnf which are created by this script.

script_name=$(basename "$0")
version="2.1"
creator="somikro"
startTS=$(date +%s.%N)
# Version history:
# 2.1 - Added servers_CA for arbitrary servers; CA selection for server certs
#     - changed name from setup_pki.sh to manage_EEFD_pki.sh
# 2.0 - Added PKI management: interactive certificate creation
# 1.1 - Added two Intermediate CAs: peoples_CA and machines_CA
# 1.0 - Initial release



set -e

# ============================================
# Configuration Variables
# ============================================
PKI_DIR="./pki"
ROOT_CA_DIR="$PKI_DIR/root-ca"
MYDOMAIN_CA_DIR="$PKI_DIR/mydomain-ca"
SERVERS_CA_DIR="$PKI_DIR/servers-ca"
PEOPLES_CA_DIR="$PKI_DIR/peoples-ca"
MACHINES_CA_DIR="$PKI_DIR/machines-ca"

# CA names (will be prompted during setup and used throughout)
ROOT_CA_NAME=""
MYDOMAIN_CA_NAME=""

# Location information (will be prompted during setup)
COUNTRY=""
STATE=""
LOCALITY=""

# Setting the validity periods for CAs and certificates
ROOT_CA_VALIDITY_DAYS=7300        # 20 years
MYDOMAIN_CA_VALIDITY_DAYS=3650         # 10 years
# Certificate validity for end-entity (server) certificates
MYDOMAIN_SERVER_CERT_VALIDITY_DAYS=1460    # 4 years - for server_CA
GENERIC_SERVER_CERT_VALIDITY_DAYS=1460     # 4 years - for servers_CA
# Certificate validity for user certificates (issued by peoples_CA)
USER_CERT_VALIDITY_DAYS=1460      # 4 years
# Certificate validity for device certificates (issued by machines_CA)
DEVICE_CERT_VALIDITY_DAYS=1460     # 4 years

# ============================================
# Helper Functions
# ============================================

# Passphrase cache variables
ROOT_CA_PASSPHRASE=""
MYDOMAIN_CA_PASSPHRASE=""
SERVERS_CA_PASSPHRASE=""
PEOPLES_CA_PASSPHRASE=""
MACHINES_CA_PASSPHRASE=""

# Cleanup function to clear passphrases on exit
cleanup_passphrases() {
    ROOT_CA_PASSPHRASE=""
    MYDOMAIN_CA_PASSPHRASE=""
    SERVERS_CA_PASSPHRASE=""
    PEOPLES_CA_PASSPHRASE=""
    MACHINES_CA_PASSPHRASE=""
    unset ROOT_CA_PASSPHRASE
    unset MYDOMAIN_CA_PASSPHRASE
    unset SERVERS_CA_PASSPHRASE
    unset PEOPLES_CA_PASSPHRASE
    unset MACHINES_CA_PASSPHRASE
}

# Register cleanup on exit
trap cleanup_passphrases EXIT

# Function to prompt for CA passphrases if not already cached
prompt_ca_passphrases() {
    echo ""
    echo "[PKI] === CA Passphrase Setup ==="
    echo "[PKI] Enter passphrases for the CA private keys."
    echo "[PKI] These will be cached in memory for this session."
    echo ""
    
    if [ -z "$MYDOMAIN_CA_PASSPHRASE" ] && [ -f "$MYDOMAIN_CA_DIR/private/ca_key.key" ]; then
        read -s -p "[PKI] Enter ${MYDOMAIN_CA_NAME}_CA passphrase: " MYDOMAIN_CA_PASSPHRASE
        echo ""
    fi
    
    if [ -z "$SERVERS_CA_PASSPHRASE" ] && [ -f "$SERVERS_CA_DIR/private/ca_key.key" ]; then
        read -s -p "[PKI] Enter servers_CA passphrase: " SERVERS_CA_PASSPHRASE
        echo ""
    fi
    
    if [ -z "$PEOPLES_CA_PASSPHRASE" ] && [ -f "$PEOPLES_CA_DIR/private/ca_key.key" ]; then
        read -s -p "[PKI] Enter peoples_CA passphrase: " PEOPLES_CA_PASSPHRASE
        echo ""
    fi
    
    if [ -z "$MACHINES_CA_PASSPHRASE" ] && [ -f "$MACHINES_CA_DIR/private/ca_key.key" ]; then
        read -s -p "[PKI] Enter machines_CA passphrase: " MACHINES_CA_PASSPHRASE
        echo ""
    fi
    
    echo "[PKI] Passphrases cached successfully."
}

check_pki_exists() {
    if [ -d "$ROOT_CA_DIR" ] && [ -f "$ROOT_CA_DIR/certs/root_ca.crt" ]; then
        return 0
    else
        return 1
    fi
}

show_menu() {
    echo "" >&2
    echo "============================================" >&2
    echo "  PKI Management Tool - ${ROOT_CA_NAME}_CA" >&2
    echo "  Version $version (Created by $creator)" >&2
    echo "============================================" >&2
    echo "" >&2
    echo "1) Setup complete PKI infrastructure (first time only)" >&2
    echo "2) Issue server certificate (${MYDOMAIN_CA_NAME}_CA or servers_CA)" >&2
    echo "3) Issue user certificate (peoples_CA)" >&2
    echo "4) Issue device certificate (machines_CA)" >&2
    echo "5) Exit" >&2
    echo "" >&2
    read -p "Select an option [1-5]: " choice >&2
    echo "$choice"
}

create_server_certificate() {
    echo ""
    echo "[PKI] === Creating Server Certificate ==="
    echo ""
    
    # Ask which CA to use
    echo "Select Certificate Authority:"
    echo "1) ${MYDOMAIN_CA_NAME}_CA (for ${MYDOMAIN_CA_NAME} servers)"
    echo "2) servers_CA (for arbitrary servers)"
    read -p "Choose CA [1-2]: " CA_CHOICE
    
    case $CA_CHOICE in
        1)
            CA_DIR="$MYDOMAIN_CA_DIR"
            CA_NAME="${MYDOMAIN_CA_NAME}_CA"
            DEFAULT_OU="$MYDOMAIN_CA_NAME"
            DEFAULT_EMAIL="admin@${MYDOMAIN_CA_NAME}"
            CERT_VALIDITY_DAYS=$MYDOMAIN_SERVER_CERT_VALIDITY_DAYS
            ;;
        2)
            CA_DIR="$SERVERS_CA_DIR"
            CA_NAME="servers_CA"
            DEFAULT_OU="Servers Division"
            DEFAULT_EMAIL="servers@${ROOT_CA_NAME,,}.de"
            CERT_VALIDITY_DAYS=$GENERIC_SERVER_CERT_VALIDITY_DAYS
            ;;
        *)
            echo "[PKI] Error: Invalid choice"
            return 1
            ;;
    esac
    
    echo ""
    echo "[PKI] Using $CA_NAME"
    echo ""
    
    # Input validation loop for common name
    while true; do
        read -p "Enter server common name (e.g., server.example.com): " COMMON_NAME
        if [ -z "$COMMON_NAME" ]; then
            echo "[PKI] Error: Common name cannot be empty. Please try again."
        else
            break
        fi
    done
    
    read -p "Enter organization unit [$DEFAULT_OU]: " ORG_UNIT
    ORG_UNIT=${ORG_UNIT:-$DEFAULT_OU}
    
    read -p "Enter email address [$DEFAULT_EMAIL]: " EMAIL
    EMAIL=${EMAIL:-$DEFAULT_EMAIL}
    
    read -p "Enter additional server DNS names this certificate shall be valid for (comma-separated, optional): " ALT_NAMES
    
    CERT_NAME=$(echo "$COMMON_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
    
    # Check if certificate already exists
    if [ -f "$CA_DIR/certs/${CERT_NAME}.key" ] || [ -f "$CA_DIR/certs/${CERT_NAME}.crt" ]; then
        echo ""
        echo "[PKI] WARNING: Certificate for $COMMON_NAME already exists!"
        read -p "[PKI] Overwrite existing certificate? (yes/no): " OVERWRITE
        if [ "$OVERWRITE" != "yes" ]; then
            echo "[PKI] Certificate creation cancelled. Returning to menu..."
            return 0
        fi
        # Remove existing files
        rm -f "$CA_DIR/certs/${CERT_NAME}.key" "$CA_DIR/certs/${CERT_NAME}.crt" \
              "$CA_DIR/certs/${CERT_NAME}.csr" "$CA_DIR/certs/${CERT_NAME}-fullchain.crt"
        echo "[PKI] Removed existing certificate files."
    fi
    
    echo ""
    echo "[PKI] Creating private key for $COMMON_NAME..."
    openssl ecparam -genkey -name prime256v1 -out "$CA_DIR/certs/${CERT_NAME}.key"
    chmod 400 "$CA_DIR/certs/${CERT_NAME}.key"
    
    # Create temporary config with SANs if provided
    if [ -n "$ALT_NAMES" ]; then
        cp "$CA_DIR/openssl.cnf" "$CA_DIR/openssl_temp.cnf"
        echo "" >> "$CA_DIR/openssl_temp.cnf"
        echo "[ alt_names_custom ]" >> "$CA_DIR/openssl_temp.cnf"
        echo "DNS.1 = $COMMON_NAME" >> "$CA_DIR/openssl_temp.cnf"
        counter=2
        IFS=',' read -ra NAMES <<< "$ALT_NAMES"
        for name in "${NAMES[@]}"; do
            name=$(echo "$name" | xargs)
            echo "DNS.$counter = $name" >> "$CA_DIR/openssl_temp.cnf"
            ((counter++))
        done
        
        # Update server_cert section to use custom alt_names
        sed -i 's/subjectAltName = @alt_names/subjectAltName = @alt_names_custom/' "$CA_DIR/openssl_temp.cnf"
        CONFIG_FILE="$CA_DIR/openssl_temp.cnf"
    else
        CONFIG_FILE="$CA_DIR/openssl.cnf"
    fi
    
    echo "[PKI] Creating certificate signing request..."
    openssl req -new -sha256 \
        -key "$CA_DIR/certs/${CERT_NAME}.key" \
        -out "$CA_DIR/certs/${CERT_NAME}.csr" \
        -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=${ROOT_CA_NAME}/OU=${ORG_UNIT}/CN=${COMMON_NAME}/emailAddress=${EMAIL}"
    
    echo "[PKI] Signing certificate with $CA_NAME..."
    
    # Determine which passphrase to use
    if [ "$CA_CHOICE" = "1" ]; then
        CA_PASSPHRASE="$MYDOMAIN_CA_PASSPHRASE"
    else
        CA_PASSPHRASE="$SERVERS_CA_PASSPHRASE"
    fi
    
    openssl ca -config "$CONFIG_FILE" -extensions server_cert \
        -days $CERT_VALIDITY_DAYS -notext -md sha256 -batch \
        -passin pass:"$CA_PASSPHRASE" \
        -in "$CA_DIR/certs/${CERT_NAME}.csr" \
        -out "$CA_DIR/certs/${CERT_NAME}.crt"
    
    chmod 444 "$CA_DIR/certs/${CERT_NAME}.crt"
    
    echo "[PKI] Creating certificate bundle with full chain..."
    cat "$CA_DIR/certs/${CERT_NAME}.crt" "$CA_DIR/certs/ca-chain.crt" > "$CA_DIR/certs/${CERT_NAME}-fullchain.crt"
    chmod 444 "$CA_DIR/certs/${CERT_NAME}-fullchain.crt"
    
    # Cleanup temp config if created
    [ -f "$CA_DIR/openssl_temp.cnf" ] && rm -f "$CA_DIR/openssl_temp.cnf"
    
    echo ""
    echo "[PKI] ✓ Server certificate created successfully!"
    echo "[PKI]   Certificate:  $CA_DIR/certs/${CERT_NAME}.crt"
    echo "[PKI]   Full Chain:   $CA_DIR/certs/${CERT_NAME}-fullchain.crt"
    echo "[PKI]   Private Key:  $CA_DIR/certs/${CERT_NAME}.key"
    echo "[PKI]   Valid Until:  $(openssl x509 -noout -enddate -in "$CA_DIR/certs/${CERT_NAME}.crt" | cut -d= -f2)"
    echo ""
}

create_user_certificate() {
    echo ""
    echo "[PKI] === Creating User Certificate ==="
    echo ""
    
    # Input validation loop for full name
    while true; do
        read -p "Enter user's full name (e.g., Fritz Meier): " FULL_NAME
        if [ -z "$FULL_NAME" ]; then
            echo "[PKI] Error: Full name cannot be empty. Please try again."
        else
            break
        fi
    done
    
    read -p "Enter email address: " EMAIL
    if [ -z "$EMAIL" ]; then
        echo "[PKI] Error: Email address cannot be empty"
        return 1
    fi
    
    read -p "Enter organization unit [Peoples Division]: " ORG_UNIT
    ORG_UNIT=${ORG_UNIT:-Peoples Division}
    
    CERT_NAME=$(echo "$FULL_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
    
    echo ""
    echo "[PKI] Creating private key for $FULL_NAME..."
    openssl ecparam -genkey -name prime256v1 -out "$PEOPLES_CA_DIR/certs/${CERT_NAME}.key"
    chmod 400 "$PEOPLES_CA_DIR/certs/${CERT_NAME}.key"
    
    echo "[PKI] Creating certificate signing request..."
    openssl req -new -sha256 \
        -key "$PEOPLES_CA_DIR/certs/${CERT_NAME}.key" \
        -out "$PEOPLES_CA_DIR/certs/${CERT_NAME}.csr" \
        -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=${ROOT_CA_NAME}/OU=${ORG_UNIT}/CN=${FULL_NAME}/emailAddress=${EMAIL}"
    
    echo "[PKI] Signing certificate with peoples_CA..."
    openssl ca -config "$PEOPLES_CA_DIR/openssl.cnf" -extensions user_cert \
        -days $USER_CERT_VALIDITY_DAYS -notext -md sha256 -batch \
        -passin pass:"$PEOPLES_CA_PASSPHRASE" \
        -in "$PEOPLES_CA_DIR/certs/${CERT_NAME}.csr" \
        -out "$PEOPLES_CA_DIR/certs/${CERT_NAME}.crt"
    
    chmod 444 "$PEOPLES_CA_DIR/certs/${CERT_NAME}.crt"
    
    echo "[PKI] Creating certificate bundle with full chain..."
    cat "$PEOPLES_CA_DIR/certs/${CERT_NAME}.crt" "$PEOPLES_CA_DIR/certs/ca-chain.crt" > "$PEOPLES_CA_DIR/certs/${CERT_NAME}-fullchain.crt"
    chmod 444 "$PEOPLES_CA_DIR/certs/${CERT_NAME}-fullchain.crt"
    
    echo ""
    echo "[PKI] ✓ User certificate created successfully!"
    echo "[PKI]   Certificate:  $PEOPLES_CA_DIR/certs/${CERT_NAME}.crt"
    echo "[PKI]   Full Chain:   $PEOPLES_CA_DIR/certs/${CERT_NAME}-fullchain.crt"
    echo "[PKI]   Private Key:  $PEOPLES_CA_DIR/certs/${CERT_NAME}.key"
    echo "[PKI]   Valid Until:  $(openssl x509 -noout -enddate -in "$PEOPLES_CA_DIR/certs/${CERT_NAME}.crt" | cut -d= -f2)"
    echo "[PKI]   Usage:        Client Authentication, Email Protection"
    echo ""
}

create_device_certificate() {
    echo ""
    echo "[PKI] === Creating Device Certificate ==="
    echo ""
    
    # Input validation loop for device name
    while true; do
        read -p "Enter device name (e.g., sensor-01.mydomain.com): " DEVICE_NAME
        if [ -z "$DEVICE_NAME" ]; then
            echo "[PKI] Error: Device name cannot be empty. Please try again."
        else
            break
        fi
    done
    
    read -p "Enter device type [IoT Device]: " DEVICE_TYPE
    DEVICE_TYPE=${DEVICE_TYPE:-IoT Device}
    
    read -p "Enter organization unit [Machines Division]: " ORG_UNIT
    ORG_UNIT=${ORG_UNIT:-Machines Division}
    
    read -p "Enter contact email [machines@${ROOT_CA_NAME,,}.de]: " EMAIL
    EMAIL=${EMAIL:-machines@${ROOT_CA_NAME,,}.de}
    
    CERT_NAME=$(echo "$DEVICE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
    
    echo ""
    echo "[PKI] Creating private key for $DEVICE_NAME..."
    openssl ecparam -genkey -name prime256v1 -out "$MACHINES_CA_DIR/certs/${CERT_NAME}.key"
    chmod 400 "$MACHINES_CA_DIR/certs/${CERT_NAME}.key"
    
    echo "[PKI] Creating certificate signing request..."
    openssl req -new -sha256 \
        -key "$MACHINES_CA_DIR/certs/${CERT_NAME}.key" \
        -out "$MACHINES_CA_DIR/certs/${CERT_NAME}.csr" \
        -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=${ROOT_CA_NAME}/OU=${ORG_UNIT}/CN=${DEVICE_NAME}/emailAddress=${EMAIL}"
    
    echo "[PKI] Signing certificate with machines_CA..."
    openssl ca -config "$MACHINES_CA_DIR/openssl.cnf" -extensions device_cert \
        -days $DEVICE_CERT_VALIDITY_DAYS -notext -md sha256 -batch \
        -passin pass:"$MACHINES_CA_PASSPHRASE" \
        -in "$MACHINES_CA_DIR/certs/${CERT_NAME}.csr" \
        -out "$MACHINES_CA_DIR/certs/${CERT_NAME}.crt"
    
    chmod 444 "$MACHINES_CA_DIR/certs/${CERT_NAME}.crt"
    
    echo "[PKI] Creating certificate bundle with full chain..."
    cat "$MACHINES_CA_DIR/certs/${CERT_NAME}.crt" "$MACHINES_CA_DIR/certs/ca-chain.crt" > "$MACHINES_CA_DIR/certs/${CERT_NAME}-fullchain.crt"
    chmod 444 "$MACHINES_CA_DIR/certs/${CERT_NAME}-fullchain.crt"
    
    echo ""
    echo "[PKI] ✓ Device certificate created successfully!"
    echo "[PKI]   Certificate:  $MACHINES_CA_DIR/certs/${CERT_NAME}.crt"
    echo "[PKI]   Full Chain:   $MACHINES_CA_DIR/certs/${CERT_NAME}-fullchain.crt"
    echo "[PKI]   Private Key:  $MACHINES_CA_DIR/certs/${CERT_NAME}.key"
    echo "[PKI]   Valid Until:  $(openssl x509 -noout -enddate -in "$MACHINES_CA_DIR/certs/${CERT_NAME}.crt" | cut -d= -f2)"
    echo "[PKI]   Usage:        Server & Client Authentication"
    echo ""
}

setup_pki() {
echo ""
echo "[PKI] === PKI Setup Configuration ==="
echo ""
echo "Please provide names for your Certificate Authorities:"
echo ""

# Prompt for Root CA name
while true; do
    read -p "Enter Root CA name (e.g., MyCompany, ACME Corp): " ROOT_CA_NAME
    if [ -z "$ROOT_CA_NAME" ]; then
        echo "[PKI] Error: Root CA name cannot be empty. Please try again."
    else
        break
    fi
done

# Prompt for Mydomain CA name
while true; do
    read -p "Enter Mydomain CA domain/name (e.g., mydomain.com, myserver): " MYDOMAIN_CA_NAME
    if [ -z "$MYDOMAIN_CA_NAME" ]; then
        echo "[PKI] Error: Mydomain CA name cannot be empty. Please try again."
    else
        break
    fi
done

echo ""
echo "Please provide location information for certificates:"
echo ""

# Prompt for Country
read -p "Enter Country Code (2 letters) [DE]: " COUNTRY
COUNTRY=${COUNTRY:-DE}

# Prompt for State/Province
read -p "Enter State or Province Name [Bavaria]: " STATE
STATE=${STATE:-Bavaria}

# Prompt for Locality/City
read -p "Enter Locality/City Name [Munich]: " LOCALITY
LOCALITY=${LOCALITY:-Munich}

# Update directory paths based on user input
MYDOMAIN_CA_DIR="$PKI_DIR/${MYDOMAIN_CA_NAME}-ca"

echo ""
echo "[PKI] Creating The hierarchical PKI infrastructure ${ROOT_CA_NAME}_CA with multiple Intermediate CAs"
echo "[PKI] Intermediate CAs: ${MYDOMAIN_CA_NAME}_CA, servers_CA, peoples_CA, machines_CA"
echo "[PKI] Creating PKI directory structure..."
mkdir -p "$ROOT_CA_DIR"/{private,certs,newcerts,crl}
mkdir -p "$MYDOMAIN_CA_DIR"/{private,certs,newcerts,crl,csr}
mkdir -p "$SERVERS_CA_DIR"/{private,certs,newcerts,crl,csr}
mkdir -p "$PEOPLES_CA_DIR"/{private,certs,newcerts,crl,csr}
mkdir -p "$MACHINES_CA_DIR"/{private,certs,newcerts,crl,csr}

# Initialize database and serial files
touch "$ROOT_CA_DIR/index.txt"
touch "$MYDOMAIN_CA_DIR/index.txt"
touch "$SERVERS_CA_DIR/index.txt"
touch "$PEOPLES_CA_DIR/index.txt"
touch "$MACHINES_CA_DIR/index.txt"
echo 1000 > "$ROOT_CA_DIR/serial"
echo 1000 > "$MYDOMAIN_CA_DIR/serial"
echo 1500 > "$SERVERS_CA_DIR/serial"
echo 2000 > "$PEOPLES_CA_DIR/serial"
echo 3000 > "$MACHINES_CA_DIR/serial"
echo 1000 > "$ROOT_CA_DIR/crlnumber"
echo 1000 > "$MYDOMAIN_CA_DIR/crlnumber"
echo 1500 > "$SERVERS_CA_DIR/crlnumber"
echo 2000 > "$PEOPLES_CA_DIR/crlnumber"
echo 3000 > "$MACHINES_CA_DIR/crlnumber"

echo "[PKI] Creating OpenSSL configuration for Root CA..."
cat > "$ROOT_CA_DIR/openssl.cnf" << 'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ./pki/root-ca
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand
private_key       = $dir/private/ca_key.key
certificate       = $dir/certs/root_ca.crt
crlnumber         = $dir/crlnumber
crl               = $dir/crl/ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha384
name_opt          = ca_default
cert_opt          = ca_default
default_days      = ROOT_CA_VALIDITY_DAYS
preserve          = no
policy            = policy_strict

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha384
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

countryName_default             = PLACEHOLDER_COUNTRY
stateOrProvinceName_default     = PLACEHOLDER_STATE
localityName_default            = PLACEHOLDER_LOCALITY
0.organizationName_default      = PLACEHOLDER_ROOT_CA_NAME
organizationalUnitName_default  = IT Security
emailAddress_default            = admin@PLACEHOLDER_ROOT_CA_NAME_LOWER.de

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF

sed -i "s/ROOT_CA_VALIDITY_DAYS/$ROOT_CA_VALIDITY_DAYS/g" "$ROOT_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_ROOT_CA_NAME/$ROOT_CA_NAME/g" "$ROOT_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_ROOT_CA_NAME_LOWER/${ROOT_CA_NAME,,}/g" "$ROOT_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_COUNTRY/$COUNTRY/g" "$ROOT_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_STATE/$STATE/g" "$ROOT_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_LOCALITY/$LOCALITY/g" "$ROOT_CA_DIR/openssl.cnf"

echo "[PKI] Creating OpenSSL configuration for Intermediate CA..."
cat > "$MYDOMAIN_CA_DIR/openssl.cnf" << 'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ./pki/PLACEHOLDER_MYDOMAIN_CA_NAME-ca
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand
private_key       = $dir/private/ca_key.key
certificate       = $dir/certs/PLACEHOLDER_MYDOMAIN_CA_NAME_ca.crt
crlnumber         = $dir/crlnumber
crl               = $dir/crl/ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha384
name_opt          = ca_default
cert_opt          = ca_default
default_days      = MYDOMAIN_SERVER_CERT_VALIDITY_DAYS
preserve          = no
policy            = policy_loose

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha384
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

countryName_default             = PLACEHOLDER_COUNTRY
stateOrProvinceName_default     = PLACEHOLDER_STATE
localityName_default            = PLACEHOLDER_LOCALITY
0.organizationName_default      = PLACEHOLDER_ROOT_CA_NAME
organizationalUnitName_default  = PLACEHOLDER_MYDOMAIN_CA_NAME
emailAddress_default            = admin@PLACEHOLDER_MYDOMAIN_CA_NAME

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ alt_names ]
DNS.1 = PLACEHOLDER_MYDOMAIN_CA_NAME
DNS.2 = www.PLACEHOLDER_MYDOMAIN_CA_NAME
EOF

sed -i "s/MYDOMAIN_SERVER_CERT_VALIDITY_DAYS/$MYDOMAIN_SERVER_CERT_VALIDITY_DAYS/g" "$MYDOMAIN_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_ROOT_CA_NAME/$ROOT_CA_NAME/g" "$MYDOMAIN_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_MYDOMAIN_CA_NAME/$MYDOMAIN_CA_NAME/g" "$MYDOMAIN_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_MYDOMAIN_CA_NAME_ca/${MYDOMAIN_CA_NAME}_ca/g" "$MYDOMAIN_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_COUNTRY/$COUNTRY/g" "$MYDOMAIN_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_STATE/$STATE/g" "$MYDOMAIN_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_LOCALITY/$LOCALITY/g" "$MYDOMAIN_CA_DIR/openssl.cnf"

echo "[PKI] Step 1: Creating Root CA (${ROOT_CA_NAME}_CA) private key..."
echo "[PKI] You will be prompted to set a passphrase for the Root CA private key"
echo "[PKI] Please enter the same passphrase twice:"
read -s -p "Enter Root CA passphrase: " ROOT_CA_PASSPHRASE
echo ""
read -s -p "Verify Root CA passphrase: " ROOT_CA_PASSPHRASE_VERIFY
echo ""
if [ "$ROOT_CA_PASSPHRASE" != "$ROOT_CA_PASSPHRASE_VERIFY" ]; then
    echo "[PKI] ERROR: Passphrases do not match!"
    exit 1
fi
openssl ecparam -genkey -name secp384r1 | \
    openssl ec -aes256 -passout pass:"$ROOT_CA_PASSPHRASE" -out "$ROOT_CA_DIR/private/ca_key.key"
chmod 400 "$ROOT_CA_DIR/private/ca_key.key"

echo "[PKI] Step 2: Creating Root CA certificate..."
openssl req -config "$ROOT_CA_DIR/openssl.cnf" \
    -key "$ROOT_CA_DIR/private/ca_key.key" \
    -passin pass:"$ROOT_CA_PASSPHRASE" \
    -new -x509 -days 7300 -sha384 -extensions v3_ca \
    -out "$ROOT_CA_DIR/certs/root_ca.crt" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=${ROOT_CA_NAME}/OU=IT Security/CN=${ROOT_CA_NAME}_CA/emailAddress=admin@${ROOT_CA_NAME,,}.de"

chmod 444 "$ROOT_CA_DIR/certs/root_ca.crt"

echo "[PKI] ✓ Root CA created"
openssl x509 -noout -text -in "$ROOT_CA_DIR/certs/root_ca.crt" | grep -E "Subject:|Issuer:|Not Before|Not After|Public Key Algorithm"

echo ""
echo "[PKI] Step 3: Creating Intermediate CA (${MYDOMAIN_CA_NAME}_CA) private key..."
echo "[PKI] You will be prompted to set a passphrase for the Intermediate CA private key"
read -s -p "Enter ${MYDOMAIN_CA_NAME}_CA passphrase: " MYDOMAIN_CA_PASSPHRASE
echo ""
read -s -p "Verify ${MYDOMAIN_CA_NAME}_CA passphrase: " MYDOMAIN_CA_PASSPHRASE_VERIFY
echo ""
if [ "$MYDOMAIN_CA_PASSPHRASE" != "$MYDOMAIN_CA_PASSPHRASE_VERIFY" ]; then
    echo "[PKI] ERROR: Passphrases do not match!"
    exit 1
fi
openssl ecparam -genkey -name secp384r1 | \
    openssl ec -aes256 -passout pass:"$MYDOMAIN_CA_PASSPHRASE" -out "$MYDOMAIN_CA_DIR/private/ca_key.key"
chmod 400 "$MYDOMAIN_CA_DIR/private/ca_key.key"

echo "[PKI] Step 4: Creating Intermediate CA certificate signing request..."
openssl req -config "$MYDOMAIN_CA_DIR/openssl.cnf" -new -sha384 \
    -key "$MYDOMAIN_CA_DIR/private/ca_key.key" \
    -passin pass:"$MYDOMAIN_CA_PASSPHRASE" \
    -out "$MYDOMAIN_CA_DIR/csr/ca.csr" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=${ROOT_CA_NAME}/OU=${MYDOMAIN_CA_NAME}/CN=${MYDOMAIN_CA_NAME}_CA/emailAddress=admin@${MYDOMAIN_CA_NAME,,}.de"

echo "[PKI] Step 5: Signing Intermediate CA with Root CA..."
# validity of 10 years (3650 days)
openssl ca -config "$ROOT_CA_DIR/openssl.cnf" -extensions v3_intermediate_ca \
    -days $MYDOMAIN_CA_VALIDITY_DAYS -notext -md sha384 -batch \
    -passin pass:"$ROOT_CA_PASSPHRASE" \
    -in "$MYDOMAIN_CA_DIR/csr/ca.csr" \
    -out "$MYDOMAIN_CA_DIR/certs/${MYDOMAIN_CA_NAME}_ca.crt"

chmod 444 "$MYDOMAIN_CA_DIR/certs/${MYDOMAIN_CA_NAME}_ca.crt"

echo "[PKI] ✓ Intermediate CA created"
openssl x509 -noout -text -in "$MYDOMAIN_CA_DIR/certs/${MYDOMAIN_CA_NAME}_ca.crt" | grep -E "Subject:|Issuer:|Not Before|Not After|Public Key Algorithm"

echo ""
echo "[PKI] Step 6: Creating certificate chain..."
cat "$MYDOMAIN_CA_DIR/certs/${MYDOMAIN_CA_NAME}_ca.crt" "$ROOT_CA_DIR/certs/root_ca.crt" > "$MYDOMAIN_CA_DIR/certs/ca-chain.crt"
chmod 444 "$MYDOMAIN_CA_DIR/certs/ca-chain.crt"

echo ""
echo "[PKI] Step 7: Creating Intermediate CA (servers_CA) for arbitrary servers..."
echo "[PKI] You will be prompted to set a passphrase for the servers_CA private key"
read -s -p "Enter servers_CA passphrase: " SERVERS_CA_PASSPHRASE
echo ""
read -s -p "Verify servers_CA passphrase: " SERVERS_CA_PASSPHRASE_VERIFY
echo ""
if [ "$SERVERS_CA_PASSPHRASE" != "$SERVERS_CA_PASSPHRASE_VERIFY" ]; then
    echo "[PKI] ERROR: Passphrases do not match!"
    exit 1
fi
openssl ecparam -genkey -name secp384r1 | \
    openssl ec -aes256 -passout pass:"$SERVERS_CA_PASSPHRASE" -out "$SERVERS_CA_DIR/private/ca_key.key"
chmod 400 "$SERVERS_CA_DIR/private/ca_key.key"

echo "[PKI] Step 8: Creating servers_CA certificate signing request..."
openssl req -config "$ROOT_CA_DIR/openssl.cnf" -new -sha384 \
    -key "$SERVERS_CA_DIR/private/ca_key.key" \
    -passin pass:"$SERVERS_CA_PASSPHRASE" \
    -out "$SERVERS_CA_DIR/csr/ca.csr" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=${ROOT_CA_NAME}/OU=Servers Division/CN=servers_CA/emailAddress=servers@${ROOT_CA_NAME,,}.de"

echo "[PKI] Step 9: Signing servers_CA with Root CA..."
openssl ca -config "$ROOT_CA_DIR/openssl.cnf" -extensions v3_intermediate_ca \
    -days $MYDOMAIN_CA_VALIDITY_DAYS -notext -md sha384 -batch \
    -passin pass:"$ROOT_CA_PASSPHRASE" \
    -in "$SERVERS_CA_DIR/csr/ca.csr" \
    -out "$SERVERS_CA_DIR/certs/servers_ca.crt"

chmod 444 "$SERVERS_CA_DIR/certs/servers_ca.crt"

echo "[PKI] ✓ servers_CA Intermediate CA created"
openssl x509 -noout -text -in "$SERVERS_CA_DIR/certs/servers_ca.crt" | grep -E "Subject:|Issuer:|Not Before|Not After|Public Key Algorithm"

echo ""
echo "[PKI] Step 10: Creating servers_CA certificate chain..."
cat "$SERVERS_CA_DIR/certs/servers_ca.crt" "$ROOT_CA_DIR/certs/root_ca.crt" > "$SERVERS_CA_DIR/certs/ca-chain.crt"
chmod 444 "$SERVERS_CA_DIR/certs/ca-chain.crt"

echo "[PKI] Step 11: Creating OpenSSL configuration for servers_CA..."
cat > "$SERVERS_CA_DIR/openssl.cnf" << 'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ./pki/servers-ca
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand
private_key       = $dir/private/ca_key.key
certificate       = $dir/certs/servers_ca.crt
crlnumber         = $dir/crlnumber
crl               = $dir/crl/ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha384
name_opt          = ca_default
cert_opt          = ca_default
default_days      = GENERIC_SERVER_CERT_VALIDITY_DAYS
preserve          = no
policy            = policy_loose

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha384

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

countryName_default             = PLACEHOLDER_COUNTRY
stateOrProvinceName_default     = PLACEHOLDER_STATE
localityName_default            = PLACEHOLDER_LOCALITY
0.organizationName_default      = PLACEHOLDER_ROOT_CA_NAME
organizationalUnitName_default  = Servers Division
emailAddress_default            = servers@PLACEHOLDER_ROOT_CA_NAME_LOWER.de

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ alt_names ]
DNS.1 = server.PLACEHOLDER_ROOT_CA_NAME_LOWER.de
EOF

sed -i "s/GENERIC_SERVER_CERT_VALIDITY_DAYS/$GENERIC_SERVER_CERT_VALIDITY_DAYS/g" "$SERVERS_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_ROOT_CA_NAME/$ROOT_CA_NAME/g" "$SERVERS_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_ROOT_CA_NAME_LOWER/${ROOT_CA_NAME,,}/g" "$SERVERS_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_COUNTRY/$COUNTRY/g" "$SERVERS_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_STATE/$STATE/g" "$SERVERS_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_LOCALITY/$LOCALITY/g" "$SERVERS_CA_DIR/openssl.cnf"

echo ""
echo "[PKI] Step 12: Creating Intermediate CA (peoples_CA) for natural persons..."
echo "[PKI] You will be prompted to set a passphrase for the peoples_CA private key"
read -s -p "Enter peoples_CA passphrase: " PEOPLES_CA_PASSPHRASE
echo ""
read -s -p "Verify peoples_CA passphrase: " PEOPLES_CA_PASSPHRASE_VERIFY
echo ""
if [ "$PEOPLES_CA_PASSPHRASE" != "$PEOPLES_CA_PASSPHRASE_VERIFY" ]; then
    echo "[PKI] ERROR: Passphrases do not match!"
    exit 1
fi
openssl ecparam -genkey -name secp384r1 | \
    openssl ec -aes256 -passout pass:"$PEOPLES_CA_PASSPHRASE" -out "$PEOPLES_CA_DIR/private/ca_key.key"
chmod 400 "$PEOPLES_CA_DIR/private/ca_key.key"

echo "[PKI] Step 13: Creating peoples_CA certificate signing request..."
openssl req -config "$ROOT_CA_DIR/openssl.cnf" -new -sha384 \
    -key "$PEOPLES_CA_DIR/private/ca_key.key" \
    -passin pass:"$PEOPLES_CA_PASSPHRASE" \
    -out "$PEOPLES_CA_DIR/csr/ca.csr" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=${ROOT_CA_NAME}/OU=Peoples Division/CN=peoples_CA/emailAddress=people@${ROOT_CA_NAME,,}.de"

echo "[PKI] Step 14: Signing peoples_CA with Root CA..."
openssl ca -config "$ROOT_CA_DIR/openssl.cnf" -extensions v3_intermediate_ca \
    -days $MYDOMAIN_CA_VALIDITY_DAYS -notext -md sha384 -batch \
    -passin pass:"$ROOT_CA_PASSPHRASE" \
    -in "$PEOPLES_CA_DIR/csr/ca.csr" \
    -out "$PEOPLES_CA_DIR/certs/peoples_ca.crt"

chmod 444 "$PEOPLES_CA_DIR/certs/peoples_ca.crt"

echo "[PKI] ✓ peoples_CA Intermediate CA created"
openssl x509 -noout -text -in "$PEOPLES_CA_DIR/certs/peoples_ca.crt" | grep -E "Subject:|Issuer:|Not Before|Not After|Public Key Algorithm"

echo ""
echo "[PKI] Step 15: Creating peoples_CA certificate chain..."
cat "$PEOPLES_CA_DIR/certs/peoples_ca.crt" "$ROOT_CA_DIR/certs/root_ca.crt" > "$PEOPLES_CA_DIR/certs/ca-chain.crt"
chmod 444 "$PEOPLES_CA_DIR/certs/ca-chain.crt"

echo "[PKI] Step 16: Creating OpenSSL configuration for peoples_CA..."
cat > "$PEOPLES_CA_DIR/openssl.cnf" << 'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ./pki/peoples-ca
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand
private_key       = $dir/private/ca_key.key
certificate       = $dir/certs/peoples_ca.crt
crlnumber         = $dir/crlnumber
crl               = $dir/crl/ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha384
name_opt          = ca_default
cert_opt          = ca_default
default_days      = USER_CERT_VALIDITY_DAYS
preserve          = no
policy            = policy_loose

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha384

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

countryName_default             = PLACEHOLDER_COUNTRY
stateOrProvinceName_default     = PLACEHOLDER_STATE
localityName_default            = PLACEHOLDER_LOCALITY
0.organizationName_default      = PLACEHOLDER_ROOT_CA_NAME
organizationalUnitName_default  = Peoples Division
emailAddress_default            = people@PLACEHOLDER_ROOT_CA_NAME_LOWER.de

[ user_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated User Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ crl_ext ]
authorityKeyIdentifier=keyid:always
EOF

sed -i "s/USER_CERT_VALIDITY_DAYS/$USER_CERT_VALIDITY_DAYS/g" "$PEOPLES_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_ROOT_CA_NAME/$ROOT_CA_NAME/g" "$PEOPLES_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_ROOT_CA_NAME_LOWER/${ROOT_CA_NAME,,}/g" "$PEOPLES_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_COUNTRY/$COUNTRY/g" "$PEOPLES_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_STATE/$STATE/g" "$PEOPLES_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_LOCALITY/$LOCALITY/g" "$PEOPLES_CA_DIR/openssl.cnf"

echo ""
echo "[PKI] Step 17: Creating Intermediate CA (machines_CA) for devices..."
echo "[PKI] You will be prompted to set a passphrase for the machines_CA private key"
read -s -p "Enter machines_CA passphrase: " MACHINES_CA_PASSPHRASE
echo ""
read -s -p "Verify machines_CA passphrase: " MACHINES_CA_PASSPHRASE_VERIFY
echo ""
if [ "$MACHINES_CA_PASSPHRASE" != "$MACHINES_CA_PASSPHRASE_VERIFY" ]; then
    echo "[PKI] ERROR: Passphrases do not match!"
    exit 1
fi
openssl ecparam -genkey -name secp384r1 | \
    openssl ec -aes256 -passout pass:"$MACHINES_CA_PASSPHRASE" -out "$MACHINES_CA_DIR/private/ca_key.key"
chmod 400 "$MACHINES_CA_DIR/private/ca_key.key"

echo "[PKI] Step 18: Creating machines_CA certificate signing request..."
openssl req -config "$ROOT_CA_DIR/openssl.cnf" -new -sha384 \
    -key "$MACHINES_CA_DIR/private/ca_key.key" \
    -passin pass:"$MACHINES_CA_PASSPHRASE" \
    -out "$MACHINES_CA_DIR/csr/ca.csr" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$LOCALITY/O=${ROOT_CA_NAME}/OU=Machines Division/CN=machines_CA/emailAddress=machines@${ROOT_CA_NAME,,}.de"

echo "[PKI] Step 19: Signing machines_CA with Root CA..."
openssl ca -config "$ROOT_CA_DIR/openssl.cnf" -extensions v3_intermediate_ca \
    -days $MYDOMAIN_CA_VALIDITY_DAYS -notext -md sha384 -batch \
    -passin pass:"$ROOT_CA_PASSPHRASE" \
    -in "$MACHINES_CA_DIR/csr/ca.csr" \
    -out "$MACHINES_CA_DIR/certs/machines_ca.crt"

chmod 444 "$MACHINES_CA_DIR/certs/machines_ca.crt"

echo "[PKI] ✓ machines_CA Intermediate CA created"
openssl x509 -noout -text -in "$MACHINES_CA_DIR/certs/machines_ca.crt" | grep -E "Subject:|Issuer:|Not Before|Not After|Public Key Algorithm"

echo ""
echo "[PKI] Step 20: Creating machines_CA certificate chain..."
cat "$MACHINES_CA_DIR/certs/machines_ca.crt" "$ROOT_CA_DIR/certs/root_ca.crt" > "$MACHINES_CA_DIR/certs/ca-chain.crt"
chmod 444 "$MACHINES_CA_DIR/certs/ca-chain.crt"

echo "[PKI] Step 21: Creating OpenSSL configuration for machines_CA..."
cat > "$MACHINES_CA_DIR/openssl.cnf" << 'EOF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = ./pki/machines-ca
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand
private_key       = $dir/private/ca_key.key
certificate       = $dir/certs/machines_ca.crt
crlnumber         = $dir/crlnumber
crl               = $dir/crl/ca.crl
crl_extensions    = crl_ext
default_crl_days  = 30
default_md        = sha384
name_opt          = ca_default
cert_opt          = ca_default
default_days      = DEVICE_CERT_VALIDITY_DAYS
preserve          = no
policy            = policy_loose

[ policy_loose ]
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha384

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

countryName_default             = PLACEHOLDER_COUNTRY
stateOrProvinceName_default     = PLACEHOLDER_STATE
localityName_default            = PLACEHOLDER_LOCALITY
0.organizationName_default      = PLACEHOLDER_ROOT_CA_NAME
organizationalUnitName_default  = Machines Division
emailAddress_default            = machines@PLACEHOLDER_ROOT_CA_NAME_LOWER.de

[ device_cert ]
basicConstraints = CA:FALSE
nsCertType = client, server
nsComment = "OpenSSL Generated Device Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth

[ crl_ext ]
authorityKeyIdentifier=keyid:always
EOF

sed -i "s/DEVICE_CERT_VALIDITY_DAYS/$DEVICE_CERT_VALIDITY_DAYS/g" "$MACHINES_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_ROOT_CA_NAME/$ROOT_CA_NAME/g" "$MACHINES_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_ROOT_CA_NAME_LOWER/${ROOT_CA_NAME,,}/g" "$MACHINES_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_COUNTRY/$COUNTRY/g" "$MACHINES_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_STATE/$STATE/g" "$MACHINES_CA_DIR/openssl.cnf"
sed -i "s/PLACEHOLDER_LOCALITY/$LOCALITY/g" "$MACHINES_CA_DIR/openssl.cnf"

echo ""
echo "[PKI] ============================================"
echo "[PKI] PKI Setup Complete!"
echo "[PKI] ============================================"
echo "[PKI]"
echo "[PKI] Root CA:"
echo "[PKI]   Certificate: $ROOT_CA_DIR/certs/root_ca.crt"
echo "[PKI]   Private Key: $ROOT_CA_DIR/private/ca_key.key (KEEP SECURE!)"
echo "[PKI]"
echo "[PKI] Intermediate CA (${MYDOMAIN_CA_NAME}_CA):"
echo "[PKI]   Certificate: $MYDOMAIN_CA_DIR/certs/${MYDOMAIN_CA_NAME}_ca.crt"
echo "[PKI]   Chain:       $MYDOMAIN_CA_DIR/certs/ca-chain.crt"
echo "[PKI]   Private Key: $MYDOMAIN_CA_DIR/private/ca_key.key (KEEP SECURE!)"
echo "[PKI]"
echo "[PKI] Intermediate CA (servers_CA) - For Arbitrary Servers:"
echo "[PKI]   Certificate: $SERVERS_CA_DIR/certs/servers_ca.crt"
echo "[PKI]   Chain:       $SERVERS_CA_DIR/certs/ca-chain.crt"
echo "[PKI]   Private Key: $SERVERS_CA_DIR/private/ca_key.key (KEEP SECURE!)"
echo "[PKI]   Config:      $SERVERS_CA_DIR/openssl.cnf"
echo "[PKI]"
echo "[PKI] Intermediate CA (peoples_CA) - For Natural Persons:"
echo "[PKI]   Certificate: $PEOPLES_CA_DIR/certs/peoples_ca.crt"
echo "[PKI]   Chain:       $PEOPLES_CA_DIR/certs/ca-chain.crt"
echo "[PKI]   Private Key: $PEOPLES_CA_DIR/private/ca_key.key (KEEP SECURE!)"
echo "[PKI]   Config:      $PEOPLES_CA_DIR/openssl.cnf"
echo "[PKI]"
echo "[PKI] Intermediate CA (machines_CA) - For Devices:"
echo "[PKI]   Certificate: $MACHINES_CA_DIR/certs/machines_ca.crt"
echo "[PKI]   Chain:       $MACHINES_CA_DIR/certs/ca-chain.crt"
echo "[PKI]   Private Key: $MACHINES_CA_DIR/private/ca_key.key (KEEP SECURE!)"
echo "[PKI]   Config:      $MACHINES_CA_DIR/openssl.cnf"
echo "[PKI]"
echo "[PKI] Next steps:"
echo "[PKI] 1. Distribute Root CA cert to all clients: $ROOT_CA_DIR/certs/root_ca.crt"
echo "[PKI] 2. Use menu option 2 to issue server certificates (via ${MYDOMAIN_CA_NAME}_CA or servers_CA)"
echo "[PKI] 3. Use menu option 3 to issue user certificates (via peoples_CA)"
echo "[PKI] 4. Use menu option 4 to issue device certificates (via machines_CA)"
echo "[PKI] ============================================"
echo ""
echo "[PKI] Certificate Management:"
echo "[PKI] Run this script again: ./$script_name"
echo "[PKI] - Use menu option 2 to issue server certificates (via ${MYDOMAIN_CA_NAME}_CA or servers_CA)"
echo "[PKI] - Use menu option 3 to issue user certificates (via peoples_CA)"
echo "[PKI] - Use menu option 4 to issue device certificates (via machines_CA)"
echo "[PKI]"
echo "[PKI] ============================================"

}

# ============================================
# Main Program
# ============================================

# Check if PKI already exists
if check_pki_exists; then
    PKI_EXISTS=true
    # Extract CA names from existing certificates
    ROOT_CA_NAME=$(openssl x509 -noout -subject -in "$ROOT_CA_DIR/certs/root_ca.crt" | sed -n 's/.*O = \([^,]*\).*/\1/p')
    COUNTRY=$(openssl x509 -noout -subject -in "$ROOT_CA_DIR/certs/root_ca.crt" | sed -n 's/.*C = \([^,]*\).*/\1/p')
    STATE=$(openssl x509 -noout -subject -in "$ROOT_CA_DIR/certs/root_ca.crt" | sed -n 's/.*ST = \([^,]*\).*/\1/p')
    LOCALITY=$(openssl x509 -noout -subject -in "$ROOT_CA_DIR/certs/root_ca.crt" | sed -n 's/.*L = \([^,]*\).*/\1/p')
    # Find the server CA directory (not root-ca, servers-ca, peoples-ca, or machines-ca)
    for dir in "$PKI_DIR"/*-ca; do
        dirname=$(basename "$dir")
        if [ "$dirname" != "root-ca" ] && [ "$dirname" != "servers-ca" ] && [ "$dirname" != "peoples-ca" ] && [ "$dirname" != "machines-ca" ]; then
            MYDOMAIN_CA_DIR="$dir"
            MYDOMAIN_CA_NAME="${dirname%-ca}"
            break
        fi
    done
else
    PKI_EXISTS=false
fi

# If no PKI exists and no arguments provided, setup automatically
if [ "$PKI_EXISTS" = false ] && [ $# -eq 0 ]; then
    echo "" >&2
    echo "============================================" >&2
    echo "  PKI Management Tool" >&2
    echo "  Version $version (Created by $creator)" >&2
    echo "============================================" >&2
    echo "" >&2
    echo "[PKI] No existing PKI found. Starting initial setup..." >&2
    setup_pki
    PKI_EXISTS=true
    echo "" >&2
    echo "[PKI] ============================================" >&2
    echo "[PKI] Initial setup complete!" >&2
    echo "[PKI] CA passphrases are cached in memory for this session." >&2
    echo "[PKI] You can now create certificates without re-entering passphrases." >&2
    echo "[PKI] ============================================" >&2
fi

# Interactive menu loop
while true; do
    if [ "$PKI_EXISTS" = false ]; then
        echo ""
        echo "[PKI] WARNING: No PKI infrastructure found!"
        echo "[PKI] You must setup the PKI first (option 1)"
        echo ""
    fi
    
    choice=$(show_menu)
    
    case $choice in
        1)
            if [ "$PKI_EXISTS" = true ]; then
                echo ""
                read -p "[PKI] WARNING: PKI already exists. Recreate? This will DELETE existing PKI! (yes/no): " confirm
                if [ "$confirm" != "yes" ]; then
                    echo "[PKI] Aborted."
                    continue
                fi
                echo "[PKI] Removing existing PKI..."
                rm -rf "$PKI_DIR"
            fi
            setup_pki
            PKI_EXISTS=true
            ;;
        2)
            if [ "$PKI_EXISTS" = false ]; then
                echo "[PKI] ERROR: No PKI exists. Please setup PKI first (option 1)"
                continue
            fi
            prompt_ca_passphrases
            create_server_certificate
            ;;
        3)
            if [ "$PKI_EXISTS" = false ]; then
                echo "[PKI] ERROR: No PKI exists. Please setup PKI first (option 1)"
                continue
            fi
            prompt_ca_passphrases
            create_user_certificate
            ;;
        4)
            if [ "$PKI_EXISTS" = false ]; then
                echo "[PKI] ERROR: No PKI exists. Please setup PKI first (option 1)"
                continue
            fi
            prompt_ca_passphrases
            create_device_certificate
            ;;
        5)
            echo ""
            echo "[PKI] Clearing cached passphrases and exiting..."
            cleanup_passphrases
            echo "[PKI] Goodbye!"
            echo ""
            exit 0
            ;;
        *)
            echo "[PKI] Invalid option. Please select 1-5."
            ;;
    esac
done