#!/bin/sh

set -e

echo "[INFO] MAKE SURE YOU'VE SET CNAME/A TYPE RECORDS IN YOUR DOMAIN NAME REGISTRAR"

usage() {
    echo "Usage: $0 -u <user> -p <password> -d <domain> -e <email>"
    echo ""
    echo "This script requires all four options to be set."
    echo "Options:"
    echo "  -d <domain>       Set DOMAIN"
    echo "  -e <email>        Set EMAIL"
    echo "  -h                Display this help message"
}

DOMAIN=""
EMAIL=""

while getopts "d:e:h" opt; do
    case "$opt" in
        d) DOMAIN="$OPTARG" ;;
        e) EMAIL="$OPTARG" ;;
        h) usage; exit 0 ;;
        \?) 
            echo "Error: Invalid option -$OPTARG" >&2
            usage >&2
            exit 1
            ;;
        :) 
            echo "Error: Option -$OPTARG requires an argument." >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$DOMAIN" ]; then
    echo "[ERROR] Missing required option -d (DOMAIN)." >&2
    exit 1
fi

if [ -z "$EMAIL" ]; then
    echo "[ERROR] Missing required option -e (EMAIL)." >&2
    exit 1
fi


# Check if ran with root
if [ "$(id -u)" -ne 0 ]; then
  echo "[INFO] UID: $(id -u)"
  echo "[FATAL] This script must be run with sudo or as the root user!" >&2
  exit 1
fi

# Check if running Linux distro is Ubuntu, if not, terminate the execution
if [ ! -f /etc/os-release ]; then
  echo "[ERROR] /etc/os-release not found. Cannot determine distribution." >&2
  exit 1
fi

CURRENT_DISTRO_ID=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
if [ "$CURRENT_DISTRO_ID" != "ubuntu" ] && [ "$CURRENT_DISTRO_ID" != "debian" ]; then
    echo "[ERROR] This script is only supported on Ubuntu or Debian." >&2
    exit 1
fi

# Update and Upgrade package managers repos
echo "[INFO] Updating apt-get repositories"
sudo apt-get update > /dev/null 2>&1

echo "[INFO] Upgrading apt-get repositories"
sudo apt-get upgrade -y > /dev/null 2>&1


echo "[INFO] Installing envsubst utility"
sudo apt-get install gettext-base -y > /dev/null 2>&1

# Check if Nginx is installed, if not, install it
echo "[INFO] Installing Nginx..."
sudo apt-get install -y nginx > /dev/null 2>&1

# Check if Certbot with Nginx plugin is installed, if not, install it
echo "[INFO] Installing Certbot..."
sudo apt-get install -y certbot python3-certbot-nginx > /dev/null 2>&1

# Write default config into a file
echo "[INFO] Generating Nginx configration for $DOMAIN"

NGINX_CONFIG_TEMPLATE="./nginx/nginx.conf"
CONFIG_FILE="/etc/nginx/sites-available/$DOMAIN"

TEMP_CONFIG_FILE=$(mktemp)

echo "[INFO] Running 'envsubst' on nginx configuration template"

export DOMAIN
envsubst '$DOMAIN' < "$NGINX_CONFIG_TEMPLATE" >  "$TEMP_CONFIG_FILE"
ENVSUBST_STATUS=$?

if [ "$ENVSUBST_STATUS" -ne 0 ]; then
  echo "[FATAL] envsubst failed with status $ENVSUBST_STATUS. Template file broken."
  rm "$TEMP_CONFIG_FILE"
  exit 1
fi

echo "[INFO] Writing configuration into /etc/nginx/sites-available/$DOMAIN"
sudo tee "$CONFIG_FILE" < "$TEMP_CONFIG_FILE" > /dev/null
TEE_STATUS=$?

rm "$TEMP_CONFIG_FILE"

if [ "$TEE_STATUS" -ne 0 ]; then
  echo "[FATAL] Failed to write configuration to $CONFIG_FILE. Exit code $TEE_STATUS"
  exit 1
fi

echo "[INFO] Creating a symlink to Nginx configuration"
sudo ln -sf /etc/nginx/sites-available/"$DOMAIN" /etc/nginx/sites-enabled/

# Test if Nginx configuration is OK
echo "[INFO] Testing Nginx..."
if ! nginx -t > /dev/null 2>&1; then
  echo "[FATAL] Nginx configuration file is NOT OK"
  exit 1
fi
echo "[INFO] Nginx configuration is OK"

# Reload Nginx
echo "[INFO] Reloading Nginx..."
if ! systemctl is-active --quiet nginx; then
  systemctl start nginx
else
  systemctl reload nginx
fi
echo "[INFO] Nginx successfully reloaded"

# Handle TLS via certbot-nginx
echo "[INFO] Setting up certbot via nginx"
certbot --nginx --non-interactive --agree-tos --redirect -d $DOMAIN --email $EMAIL > /dev/null 2>&1;
CERTBOT_STATUS=$?

if [ $CERTBOT_STATUS -ne 0 ]; then
  echo "[FATAL] Failed to setup certbot"
  exit 1
fi

echo "[INFO] Successfully finished setting up certbot via nginx"
