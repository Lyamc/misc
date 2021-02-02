#!/bin/bash

set -e

SSLBINARY="openssl"

#Defaults
SERVER="example.com"
ORG="Company"
ORGUNIT="$ORG Admin"
CITY="Victoria"
STATE="British-Columbia"
COUNTRY="CA"
EMAIL="$USER@$SERVER"

SSLDIR="/home/$USER/ssl"
SSLFILE="$SSLDIR/$SERVER.pass"

mkdir -p "$SSLDIR"

function genuser
{
	if test -f "$SSLDIR/$USER.cnf"
		then
 	   		echo "SSL configuration found at $SSLDIR/$USER.cnf."
    	
			# Grab variables from config
			COUNTRY=$(grep "C = " $SSLDIR/$USER.cnf | sed 's/C = //g')
			STATE=$(grep "ST = " $SSLDIR/$USER.cnf | sed 's/ST = //g')
			CITY=$(grep "L = " $SSLDIR/$USER.cnf | sed 's/L = //g')
			ORG=$(grep "O = " $SSLDIR/$USER.cnf | sed 's/O = //g')
			ORGUNIT=$(grep "OU = " $SSLDIR/$USER.cnf | sed 's/OU = //g')
			SERVER=$(grep "CN = " $SSLDIR/$USER.cnf | sed 's/CN = //g')
		else
 	 		touch "$SSLDIR/$USER.cnf"
	fi

# Begins loop for configuration

	response=no
	while [[ $response =~ ^(N|n|No|no|NO)$ ]];
		do
  			response=yes
  			clear
  			sleep 0.1s
  			echo "---------------------------------------------------------"
  			echo "SSL Configuration"
  			echo "---------------------------------------------------------"
  			echo "        Country: $COUNTRY"
  			echo "          State: $STATE"
  			echo "           City: $CITY"
  			echo ""
  			echo "   Organization: $ORG"
  			echo "       Org Unit: $ORGUNIT"
  			echo ""
  			echo "         Server: $SERVER"
  			echo "      Webserver: www.$SERVER"
  			echo "     Mailserver: mail.$SERVER"
  			echo ""
  			echo "          Email: $USER@$SERVER"
  			echo "---------------------------------------------------------"
  			echo ""
  			read -r -p "Use values listed above? [Y/n] " response
				if [[ $response =~ ^(N|n|No|no|NO)$ ]]
					then
# Let User change values
  						clear
  						sleep 0.1s
						read -e -i "$COUNTRY" -p "Enter two-letter Country Code: " input
    							COUNTRY="${input:-$COUNTRY}"
						read -e -i "$STATE" -p "Enter State/Province Name: " input
    							STATE="${input:-$STATE}"
						read -e -i "$CITY" -p "Enter City Name: " input
    							CITY="${input:-$CITY}"
    							echo ""
						read -e -i "$ORG" -p "Enter Organization Name: " input
    							ORG="${input:-$ORG}"
						read -e -i "$ORGUNIT" -p "Enter Organization Unit Name: " input
    							ORGUNIT="${input:-$ORGUNIT}"
    							echo ""
						read -e -i "$SERVER" -p "Enter Hostname: " input
    							SERVER="${input:-$SERVER}"
				fi

	done

	clear
	sleep 0.1s

	echo "Saving SSL Config"
	if test -f "$SSLDIR/$USER.cnf"
		then
			:
		else
			touch "$SSLDIR/$USER.cnf"
	fi

# Write variables to config
	echo "C = $COUNTRY" 						> $SSLDIR/$USER.cnf
	echo "ST = $STATE" 						>> $SSLDIR/$USER.cnf
	echo "L = $CITY" 						>> $SSLDIR/$USER.cnf
	echo "O = $ORG" 						>> $SSLDIR/$USER.cnf
	echo "OU = $ORGUNIT" 						>> $SSLDIR/$USER.cnf
	echo "CN = $SERVER" 						>> $SSLDIR/$USER.cnf

}




function selfsign
{
sudo apt install -y libssl-dev
echo ""
SSLPASSWORD=$($SSLBINARY rand -hex 20)
echo "Generating OpenSSL Password"
echo "$SSLPASSWORD" > "$SSLFILE"
echo "Loading defaults"
cat "/etc/ssl/openssl.cnf" > "$SSLDIR/$SERVER.cnf"
echo -e "[SAN]\nsubjectAltName=DNS:$SERVER" >> "$SSLDIR/$SERVER.cnf"


$SSLBINARY \
req \
-subj "/CN=$SERVER/OU=$ORGUNIT/O=$ORG/L=$CITY/ST=$STATE/C=$COUNTRY" \
-x509 \
-newkey rsa:4096 \
-passout file:"$SSLFILE" \
-keyout "$SSLDIR/encrypted.$SERVER.key" \
-out "$SSLDIR/$SERVER.crt" \
-days 3650 \
-config "$SSLDIR/$SERVER.cnf" \
-extensions SAN \
-extensions v3_req

$SSLBINARY rsa -in "$SSLDIR/encrypted.$SERVER.key" -out "$SSLDIR/$SERVER.key" -passin file:"$SSLFILE"
}

function useselfsign
{
sudo postconf -e "smtpd_tls_cert_file = $SSLDIR/$SERVER.crt"
sudo postconf -e "smtpd_tls_key_file = $SSLDIR/$SERVER.key"
sudo postconf -e "myhostname = mail.$SERVER"
sudo systemctl restart postfix
}

function installletsencrypt
{
sudo apt install -y certbot mailutils
echo ""
sudo certbot certonly --standalone -d $SERVER -d www.$SERVER -d mail.$SERVER
}

function useletsencrypt
{
sudo postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$SERVER/fullchain.pem"
sudo postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$SERVER/privkey.pem"
sudo postconf -e "myhostname = mail.$SERVER"
sudo systemctl restart postfix
}

genuser
clear
echo "Select the type of certificate to be used."
echo ""
echo -e "1: \t Let's Encrypt Signed SSL Certificates for $SERVER"
echo ""
echo -e "2:\t Self-Signed Certificates for $SERVER"
echo ""
read -p "Enter 1 or 2: " response

case $response in

("1")
sudo apt install postfix mailutils -y
if test -f "/etc/letsencrypt/live/$SERVER/fullchain.pem"
then
echo "Generating Lets Encrypt signed key already exists, renewing."
sudo certbot renew
else
echo "Generating Lets Encrypt signed key."
installletsencrypt
fi
echo "Modifying postfix config."
useletsencrypt
echo "Done"
echo ""
;;

("2")
sudo apt install postfix -y
if test -f "$SSLDIR/encrypted.$SERVER.key"
then
echo "Self-signed key already exists, no need to regenerate."
else
echo "Generating self-signed key."
selfsign
fi
echo "Modifying postfix config."
useselfsign
echo "Done"
echo ""
;;

(*)
echo "Exiting..."
exit
;;
esac

cat /etc/postfix/main.cf | grep "smtpd_tls_cert_file\|smtpd_tls_key_file"
cat /etc/aliases | grep "$SERVER"

echo ""
echo "If $USER: $USER@$SERVER is not displayed, then add it to '"'/etc/aliases'"' or else you WILL NOT RECEIVE EMAILS."
echo "Use the command '"'mail'"' to access messages"

####END OF SCRIPT####
