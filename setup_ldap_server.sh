#!/bin/bash
set -e

# Constants
DOMAIN="surina.xyz"
ORGANIZATION="Surina Family"
BASE_DN="dc=surina,dc=xyz"
ADMIN_PW="passw0rd"
LDAP_DIR="/etc/ldap"
CERT_DIR="/etc/ssl/ldap"
CA_KEY="$CERT_DIR/ca.key"
CA_CERT="$CERT_DIR/ca.crt"
SERVER_KEY="$CERT_DIR/server.key"
SERVER_CSR="$CERT_DIR/server.csr"
SERVER_CERT="$CERT_DIR/server.crt"
#SERVER_CERT="/etc/ssl/certs/surina.xyz.crt"

# Ensure sudo/root
if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root or with sudo"
  exit 1
fi

echo "Installing LDAP and SSL packages..."
apt update
DEBIAN_FRONTEND=noninteractive apt install -y slapd ldap-utils openssl

echo "Reconfiguring slapd with noninteractive default..."
echo "slapd slapd/no_configuration boolean false" | debconf-set-selections
dpkg-reconfigure -f noninteractive slapd

echo "Creating certificate directory..."
mkdir -p $CERT_DIR
chmod 700 $CERT_DIR

# Generate CA
if [ ! -f "$CA_KEY" ]; then
  echo "Generating CA key and cert..."
  openssl req -x509 -newkey rsa:4096 -days 3650 -nodes \
    -keyout "$CA_KEY" -out "$CA_CERT" \
    -subj "/CN=MyOrg CA/O=$ORGANIZATION/C=US"
fi

# Generate Server Cert
echo "Generating server certificate..."
openssl req -newkey rsa:4096 -nodes \
  -keyout "$SERVER_KEY" -out "$SERVER_CSR" \
  -subj "/CN=ldap.$DOMAIN/O=$ORGANIZATION/C=US"

openssl x509 -req -in "$SERVER_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" \
  -CAcreateserial -out "$SERVER_CERT" -days 3650

chown openldap:openldap "$CERT_DIR"/*
chmod 600 "$CERT_DIR"/*

echo "Updating slapd config for TLS..."
cat <<EOF | ldapmodify -Y EXTERNAL -H ldapi:///
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: $SERVER_CERT
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: $SERVER_KEY
-
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: $CA_CERT
EOF

echo "Populating initial LDAP directory..."
cat <<EOF > base.ldif
dn: $BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
o: $ORGANIZATION
dc: example

dn: cn=admin,$BASE_DN
objectClass: organizationalRole
cn: admin
description: LDAP Admin
EOF

ldapadd -x -D "cn=admin,$BASE_DN" -w $ADMIN_PW -f base.ldif

echo "✅ LDAP Server is ready with TLS support"
echo "➡ To add a new user entry with certificate:"

cat <<'EOT'
ldapadd -x -D "cn=admin,dc=surina,dc=xyz" -W <<EOF
dn: cn=Surina Family,dc=surina,dc=org
objectClass: inetOrgPerson
cn: Aaron Surina
sn: Surina
mail: aaron@surina.org
userCertificate;binary:< file:///path/to/john_doe.crt
EOF
EOT
