#!/bin/bash


#
# Assigning Variables
#

# Postal specific variables for configuration
scriptname=$(basename "$0")
postaluser="postal"
postaldir="/opt/postal"
ssldir="/opt/postal/ssl"
sslbin="openssl"
postalpass="$ssldir/password.bak"
#passgen=$($sslbin rand -hex 20)
nginxdir="/etc/nginx"
nginxwww="/var/www/html"
TIMEDATE=$(date +%Y-%m-%d_%R:%S)

ADMIN=admin
SERVER="example.com"
EMAIL="$ADMIN@$SERVER"

# Kill program upon error
set -e


# Get dependencies
function postal.depend
{
	sudo apt update
	sudo apt install -y software-properties-common ruby ruby-dev build-essential libssl-dev mariadb-server libmysqlclient-dev rabbitmq-server nodejs git nginx wget nano
	echo "Apt install complete."
	echo ""
	postalpass="$ssldir/password.bak"
	passgen=$($sslbin rand -hex 20)
	rubybin=$(gem env | grep "RUBY EXECUTABLE" | cut -d ":" -f2 | cut -d " " -f2)
	sudo setcap 'cap_net_bind_service=+ep' $rubybin
	echo "Setcapped $rubybin"
	echo "Installing bundler and procodile..."
	sudo gem install bundler procodile
	echo "Gem install complete."
	echo ""
}

function postal.showpassword
{
	sudo cat "$postalpass"
}

function postal.checkuser
{
        if test -f "$postaldir"
                then
                        echo "Postal directory found at $postaldir."
                else
                        echo "No Postal directory found at $postaldir. Creating..."
        fi
        sudo mkdir -p "$postaldir"
        echo "Checking $ssldir"
        if test -f "$ssldir"
                then
                        :
                else
                        sudo mkdir -p $ssldir
        fi
        echo "Checking postal user."
        if id "$postaluser" &>/dev/null
                then
                        echo "User $postaluser already exists."
                        echo "Updating password for $postaluser"
                        sudo usermod postal -aG sudo -m -d $postaldir -s /bin/bash
                        sudo chown $postaluser:$postaluser -R $postaldir
                        echo -e "$passgen\n$passgen" | sudo passwd $postaluser

                else
                        echo "User $postaluser not found, creating..."
                        sudo useradd -r -m -d $postaldir -s /bin/bash postal
                        echo -e "$passgen\n$passgen" | sudo passwd $postaluser
        fi
}


# Generate or update postal password
function postal.password 
{
	if test -f "$postalpass"
		then
    			echo "SSL Postal password found at $ssldir."
    			sudo chmod 700 "$postalpass"
    			passgen=$(postal.showpassword)
		else
			echo "No postal wassword found at $ssldir. Creating..."
			echo "$passgen" | sudo tee "$postalpass"
			sudo chmod 700 "$postalpass"
	fi
}


# SSL Configuration
#
# Prepare config file for reading/editing

function postal.ask
{
	response=no
	while [[ $response =~ ^(N|n|No|no|NO)$ ]];
		do
  			response=yes
  			clear
  			sleep 0.1s
  			echo "---------------------------------------------------------"
  			echo "Website Configuration"
  			echo "---------------------------------------------------------"
  			echo -e "       Hostname: $SERVER"
  			echo -e "          Email: $ADMIN@$SERVER"
  			echo "---------------------------------------------------------"
  			echo ""
  			read -r -p "Use values listed above? [Y/n] " response
				if [[ $response =~ ^(N|n|No|no|NO)$ ]]
					then
# Let User change values
  						clear
						sleep 0.1s
						read -e -i "$SERVER" -p "Enter Hostname: " input
                                                        SERVER="${input:-$SERVER}"
						echo ""
						read -e -i "$ADMIN" -p "Enter Admin Name: " input
    							ADMIN="${input:-$ADMIN}"
				fi

	done

	clear
	sleep 0.1s
}

#
function postal.mysqldb
{
	echo "Checking for mySQL DB $postaluser."
	result=$(sudo mysql -u root -s -N -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$postaluser'");
	if [ -z "$result" ]
  		then
    			echo "$postaluser DB does not exist, creating...";
    			echo 'CREATE DATABASE `'$postaluser'` CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci;' | sudo mysql -u root
  		else
    			echo "$postaluser DB already exists.";
    			echo 'SELECT table_schema '"$postaluser"', ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) "DB Size in MB" FROM information_schema.tables GROUP BY table_schema;' | sudo mysql -u root -t
    			response=yes
    			read -r -p "In order to proceed, the old DB $postaluser must be deleted. Proceed? [Y/n] " response

# Ask user if they want to use existing DB, returns FALSE if yes.
    			if [[ "$response" =~ ^(Y|y|YES|yes|Yes)?$ ]]
    				then
# Double check with user.
					response=yes
					read -r -p "Are you sure you want to DELETE the DB $postaluser? [Y/n] " response
					if [[ "$response" =~ ^(Y|y|YES|yes|Yes)?$ ]]
						then
# User wants to delete the database
# Delete database
              						echo "Deleting old DB $postaluser"
              						echo 'DROP DATABASE IF EXISTS '$postaluser';' | sudo mysql -u root
# Database creation
              						echo 'CREATE DATABASE `'$postaluser'` CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci;' | sudo mysql -u root
              						echo "Database created"
              						sudo systemctl restart mysql
              						sudo systemctl restart mariadb
            					else
              						echo "Installation cannot proceed. Exiting."
              						exit 0
          				fi
      				else
        				echo "Installation cannot proceed. Exiting."
        				exit 0
			fi
	fi
}

function postal.mysqluser
{
# Check if DB user already exists
	if [ $(echo "SELECT COUNT(*) FROM mysql.user WHERE user = '$postaluser'" | sudo mysql -u root | tail -n1) -gt 0 ]
		then
  			echo "User $postaluser exists. Updating password."
    			echo 'ALTER USER '$postaluser'@'127.0.0.1' IDENTIFIED BY "'$passgen'";' | sudo mysql -u root
    			echo "Password successfully updated."
  		else
    			echo "User $postaluser doesn't exist."
    			echo "Creating mySQL user: $postaluser"
	fi

	echo 'GRANT ALL PRIVILEGES ON `'$postaluser'-%` . * to `'$postaluser'`@`127.0.0.1`  IDENTIFIED BY "'$passgen'";' | sudo mysql -u root
	echo "GRANT ALL PRIVILEGES ON $postaluser.* TO '$postaluser'@'127.0.0.1';" | sudo mysql -u root
	echo 'FLUSH PRIVILEGES;' | sudo mysql -u root
	sudo systemctl restart mysql
        sudo systemctl restart mariadb
	echo "mySQL Configuration Completed."
# End of mySQL configuration
}


#
# RabbitMQ
function postal.rabbitmqctl
{
	echo "Checking for existing RabbitMQ config"
	sudo rabbitmqctl list_users
	response=$(sudo rabbitmqctl list_users)
	if [[ $response =~ "postal" ]]
  		then
    			echo "User $postaluser exists, continuing..."
    			echo $passgen | sudo rabbitmqctl change_password postal
  		else
    			echo "User $postaluser doesn't exist, creating..."
    			sudo rabbitmqctl add_user $postaluser $passgen
	fi
	sudo rabbitmqctl add_vhost /postal
	sudo rabbitmqctl set_permissions -p /postal $postaluser ".*" ".*" ".*"
	echo "RabbitMQ Configuration Completed."
}

#
# Application Setup
#


# Grab latest version and extract to $postaldir, check that bin is correct.
function postal.update
{
	echo "Getting latest postal application"
	sudo chown $postaluser:$postaluser -R $postaldir

	if ls "$postaldir/app" &>/dev/null
		then
			:
		else
			sudo -i -u $postaluser mkdir -p $postaldir/app
	fi
	wget https://postal.atech.media/packages/stable/latest.tgz -O - | sudo -u $postaluser tar zxpv -C $postaldir/app

	if ls "/usr/bin/postal" &>/dev/null
  		then 
  			:
  		else
      			sudo ln -s $postaldir/app/bin/postal /usr/bin/postal
	fi
}


function postal.backupconfig
{
	if ls "$postaldir/config/postal.yml" &>/dev/null
  		then
    			echo ""
    			echo "Backing up old configs"
    			sudo -i -u $postaluser cp "$postaldir/config/postal.yml" "$postaldir/config/postal_$TIMEDATE.bak"
	fi
}



function postal.generateconfig
{
	postal.backupconfig
	sudo -i -u $postaluser rm "$postaldir/config/postal.yml" || true
	echo ""
	echo "Initializing Postal Bundle..."
	cd "$postaldir/app"
	sudo bundle update --bundler
	sudo chown -R $postaluser:$postaluser "$postaldir"
	cd ~
	postal bundle $postaldir/vendor/bundle
	echo "Done"
	echo ""

	echo "Initializing Postal Config..."
	postal initialize-config
	echo "Done."
	echo ""
	echo "Modifying Postal Example Config..."
	
	# sudo -i -u $postaluser replace "127.0.0.1" "localhost" -- $postaldir/config/postal.yml
	sudo replace "username: postal" "username: $postaluser" -- $postaldir/config/postal.yml
	sudo replace "password: p0stalpassw0rd" "password: $passgen" -- $postaldir/config/postal.yml
	sudo replace "prefix: postal" "prefix: $postaluser" -- $postaldir/config/postal.yml
	sudo replace "database: postal" "database: $postaluser" -- $postaldir/config/postal.yml
	sudo replace "example.com" "$SERVER" -- $postaldir/config/postal.yml
	sudo replace "yourdomain.com" "$SERVER" -- $postaldir/config/postal.yml
	sudo chown -R $postaluser:$postaluser "$postaldir"
	echo "Done."
	echo ""
}

function postal.finishinstall
{
	echo "Initializing Postal..."
	postal initialize
	echo "Done."
	echo ""
	
	echo "Starting Postal"
	postal start
	echo "Done"
	echo ""
}
#
# nginx

function postal.nginx
{
	echo "Configuring nginx"
	sudo cp $postaldir/app/resource/nginx.cfg $nginxdir/sites-available/default
	sudo mkdir -p $nginxdir/ssl
	sudo openssl req -x509 -newkey rsa:4096 -keyout $nginxdir/ssl/postal.key -out $nginxdir/ssl/postal.cert -days 365 -nodes -subj "/C=GB/ST=Example/L=Example/O=Example/CN=example.com"
	
        sudo replace "yourdomain.com" "$SERVER" -- $nginxdir/sites-available/default
	sudo systemctl restart nginx
}


# Installs Postal
function postal.install
{
# Grab dependecies
	postal.depend
# Checks directory and user
        postal.checkuser
# Use existing password or generate new one via $passgen
	postal.password
# Gets variables from user
	postal.ask
# Checks and configures mySQL for postal
	postal.mysqldb
	postal.mysqluser
# Configures RabbitMQ
	postal.rabbitmqctl
	postal.update
	postal.generateconfig
	postal.finishinstall
	postal.nginx
#
# All done
#
	echo "---------------------------------------------------------"
	echo "Installation complete. Type \"postal make-user\" to create your first user."
	echo "Configuration is saved in $postaldir/config/postal.yml which you will need to edit later to use SMTP."
	echo "---------------------------------------------------------"
}

case $1 in
	("install" | "showpassword")
		postal.$1
	;;
	(*)
		echo ""
		echo "Usage:"
		echo "install		- Installs postal from start to finish"
		echo "showpassword	- Displays current postal password"
		echo ""
	;;
esac
