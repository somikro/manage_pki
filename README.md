# PKI Management Tool

A comprehensive bash script for creating and managing a modern ECDSA-based Public Key Infrastructure (PKI) with a root CA and multiple intermediate CAs.

**Version:** 2.1  
**Author:** somikro  
**License:** GPL v3


## Overview

`manage_pki.sh` is an interactive tool designed to simplify PKI management for organizations that need to issue certificates for servers, users, and devices. It creates a secure, hierarchical CA structure with proper certificate chains and modern elliptic curve cryptography (ECDSA with prime256v1).

### Security Considerations

⚠️ **This script is intended to be operated on a trusted and air-gapped Linux system.
It has been tested under a Debian 13.3 Standard Live System
**

- The Root CA private key must be kept offline and secure at all times
- The Intermediate CA private keys should also be kept secure
- Consider using [custom-debian-live-creator](https://github.com/somikro/custom-debian-live-creator) to set up an air-gapped PKI Debian-based live system

## Features

### 1. Complete PKI Infrastructure Setup
- **Root CA**: Long-lived root certificate authority (20 years validity)
- **Four Intermediate CAs**:
  - **mydomain_CA**: For domain-specific servers
  - **servers_CA**: For arbitrary/generic servers  
  - **peoples_CA**: For user/employee certificates
  - **machines_CA**: For device/machine certificates

### 2. Certificate Issuance
Note that the validity may be easily changed through config variables inside the script !
- **Server Certificates** (4 years validity)
  - Choice between domain-specific or generic server CA
  - Support for Subject Alternative Names (SANs)
  - Automatic full-chain certificate generation
  - TLS server authentication extensions
  
- **User Certificates** (4 years validity)
  - Client authentication certificates for people
  - Email protection and digital signature capabilities
  - PKCS#12 (.p12) export for easy distribution
  
- **Device Certificates** (4 years validity)
  - Client authentication for IoT devices, machines, and services
  - Suitable for machine-to-machine authentication

### 3. Modern Cryptography
- ECDSA with prime256v1 (secp256r1) curve
- SHA-256 hashing
- Secure key generation with proper permissions

### 4. User-Friendly Features
- Interactive menu-driven interface
- Passphrase caching for session convenience
- Duplicate certificate detection and overwrite protection
- Automatic certificate chain generation
- Detailed output with certificate information

## Directory Structure

```
pki/
├── root-ca/              # Root Certificate Authority
│   ├── certs/           # Root CA certificate
│   ├── private/         # Root CA private key (highly sensitive!)
│   ├── openssl.cnf      # Root CA OpenSSL configuration
│   └── ...
├── mydomain-ca/         # Intermediate CA for domain-specific servers
│   ├── certs/           # Issued certificates and CA chain
│   ├── private/         # Intermediate CA private key
│   ├── csr/             # Certificate signing requests
│   └── ...
├── servers-ca/          # Intermediate CA for generic servers
│   └── ...
├── peoples-ca/          # Intermediate CA for user certificates
│   └── ...
└── machines-ca/         # Intermediate CA for device certificates
    └── ...
```

## Installation

### Prerequisites

- Linux operating system
- OpenSSL installed (`openssl` command available)
- Bash shell
- Appropriate permissions to create directories

### Setup

1. Clone or download the script to a secure system:
   ```bash
   chmod +x manage_pki.sh
   ```

2. Ensure you're on a trusted, preferably air-gapped system

## Usage

### First Time Setup

Run the script and select option 1 to create the complete PKI infrastructure:

```bash
./manage_pki.sh
```

You will be prompted for:
- Root CA name (e.g., "MYROOT")
- Domain name for the domain-specific CA (e.g., "mydomain.space")
- Country code (2 letters, e.g., "DE")
- State/Province (e.g., "Bayern")
- City/Locality (e.g., "München")
- Passphrases for each CA private key (choose strong passphrases!)

The setup creates:
- Root CA certificate (self-signed, 20 years)
- Four intermediate CA certificates (signed by Root CA, 10 years)
- Certificate chains for each intermediate CA
- Proper OpenSSL configurations for each CA

### Interactive Menu

After setup, the menu provides the following options:

```
1) Setup complete PKI infrastructure (first time only)
2) Issue server certificate (mydomain_CA or servers_CA)
3) Issue user certificate (peoples_CA)
4) Issue device certificate (machines_CA)
5) Exit
```

### Issuing Server Certificates

**Option 2** - Issue server certificate:

1. Choose the appropriate CA:
   - **mydomain_CA**: For servers belonging to your specific domain
   - **servers_CA**: For arbitrary/generic servers

2. Provide certificate details:
   - Common Name (e.g., `mail.example.com`)
   - Organization Unit (optional)
   - Email address (optional)
   - Additional DNS names for SANs (optional, comma-separated)

3. The script generates:
   - Private key: `certs/{name}.key`
   - Certificate: `certs/{name}.crt`
   - Full chain: `certs/{name}-fullchain.crt`

**Example usage:**
```
Common Name: mail.example.com
Additional DNS names: webmail.example.com, smtp.example.com
```

### Issuing User Certificates

**Option 3** - Issue user certificate:

1. Provide user details:
   - Full name (e.g., "Fritz Meier")
   - Email address (e.g., "fritz.meier@example.com")
   - Department/OU (optional)

2. The script generates:
   - Private key: `certs/{name}.key`
   - Certificate: `certs/{name}.crt`
   - PKCS#12 bundle: `certs/{name}.p12` (certificate + private key)

The PKCS#12 file can be easily imported into browsers, email clients, and other applications.

### Issuing Device Certificates

**Option 4** - Issue device certificate:

1. Provide device details:
   - Device name/identifier (e.g., "iot-sensor-01")
   - Organization Unit (optional)

2. The script generates:
   - Private key: `certs/{name}.key`
   - Certificate: `certs/{name}.crt`

### Certificate Validity Periods

| Certificate Type | Validity Period |
|-----------------|-----------------|
| Root CA         | 20 years        |
| Intermediate CAs| 10 years        |
| Server Certs    | 4 years         |
| User Certs      | 4 years         |
| Device Certs    | 4 years         |

## Certificate Deployment

### Server Certificates

For web servers (nginx, Apache, etc.):

```bash
# Copy the certificate files to your server
scp pki/mydomain-ca/certs/server.example.com*.{crt,key} user@server:/etc/ssl/

# Configure your web server
# nginx example:
ssl_certificate /etc/ssl/server.example.com-fullchain.crt;
ssl_certificate_key /etc/ssl/server.example.com.key;
```

### User Certificates

Distribute the `.p12` file to users:
- Import into browser (Firefox, Chrome, Edge)
- Import into email client (Thunderbird, Outlook)
- Use for VPN authentication
- Use for SSH authentication

### Device Certificates

Deploy to IoT devices, services, or machines:
- Use for mutual TLS authentication
- Use for device identification
- Use for secure communication between services

## Trust Store Setup

Clients and servers need to trust your Root CA:

1. Distribute the Root CA certificate: `pki/root-ca/certs/root_ca.crt`

2. Add to system trust store:
   ```bash
   # Debian/Ubuntu
   sudo cp pki/root-ca/certs/root_ca.crt /usr/local/share/ca-certificates/
   sudo update-ca-certificates
   
   # RHEL/CentOS
   sudo cp pki/root-ca/certs/root_ca.crt /etc/pki/ca-trust/source/anchors/
   sudo update-ca-trust
   
   # Windows
   # Import root_ca.crt via Certificate Manager (certmgr.msc)
   # Place in "Trusted Root Certification Authorities"
   ```

## Security Best Practices

1. **Air-gapped System**: Operate the PKI on a system without network connectivity
2. **Strong Passphrases**: Use long, random passphrases for CA private keys
3. **Backup**: Create encrypted backups of the entire PKI directory structure
4. **Root CA Offline**: After initial setup, keep the Root CA offline
5. **Access Control**: Limit physical and logical access to the PKI system
6. **Audit Trail**: The script maintains certificate databases (`index.txt`) for tracking
7. **Regular Reviews**: Periodically review issued certificates and revoke if necessary

## File Permissions

The script automatically sets appropriate permissions:
- Private keys: `400` (read-only by owner)
- Certificates: `444` (read-only by all)

## Customization

### Modifying Validity Periods

Edit these variables in the script:
```bash
ROOT_CA_VALIDITY_DAYS=7300           # 20 years
MYDOMAIN_CA_VALIDITY_DAYS=3650       # 10 years
MYDOMAIN_SERVER_CERT_VALIDITY_DAYS=1460  # 4 years
GENERIC_SERVER_CERT_VALIDITY_DAYS=1460   # 4 years
USER_CERT_VALIDITY_DAYS=1460         # 4 years
DEVICE_CERT_VALIDITY_DAYS=1460       # 4 years
```

### Modifying OpenSSL Configurations

After setup, OpenSSL configurations are located in each CA directory as `openssl.cnf`. You can customize:
- Key usage extensions
- Extended key usage
- Certificate policies
- CRL distribution points
- And more...

## Troubleshooting

### "Permission denied" errors
- Ensure the script has execute permissions: `chmod +x manage_pki.sh`
- Verify you have write permissions in the current directory

### "Passphrase incorrect" errors
- Passphrases are case-sensitive
- Ensure no extra spaces when entering passphrases
- Passphrases are cached during the session; restart the script if needed

### Certificate already exists
- The script will warn you and ask for confirmation before overwriting
- Previous certificate files are removed if you choose to overwrite

### OpenSSL errors
- Ensure OpenSSL is installed: `openssl version`
- The script requires OpenSSL with ECDSA support

## Version History

- **2.1** - Added servers_CA for arbitrary servers; CA selection for server certs
- **2.0** - Added PKI management: interactive certificate creation  
- **1.1** - Added peoples_CA and machines_CA intermediate CAs
- **1.0** - Initial release with Root CA and mydomain_CA

## License

Creative Commons Attribution 4.0 International (CC BY 4.0)

See [LICENSE](LICENSE) file for details.

## Support and Contribution

For issues, questions, or contributions, please refer to the repository where you obtained this script.

## Related Projects

- [custom-debian-live-creator](https://github.com/somikro/custom-debian-live-creator) - Setup an air-gapped PKI Debian-based live system

---

**Remember:** A PKI is only as secure as its weakest link. Protect your private keys, use strong passphrases, and follow security best practices.


## License

License: GPL v3
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)