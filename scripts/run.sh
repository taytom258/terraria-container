#!/bin/bash

# Set Variables
date=`date +"%Y-%m-%d-%H%M"`
serverARGS="-config /data/config/serverconfig.txt -port $SERVER_PORT -players $MAXPLAYERS -autocreate $AUTOCREATE \
-banlist /data/config/banlist.txt"
TSserverARGS="-port $SERVER_PORT -players $MAXPLAYERS -autocreate $AUTOCREATE \
-banlist /data/config/banlist.txt -worldselectpath /data/worlds -configpath /data/config/tshock \
-logpath /data/logs -additionalplugins /data/plugins -crashdir /data/logs"
updateURL=https://terraria.org/api/get/dedicated-servers-names
serverURL=https://terraria.org/api/download/pc-dedicated-server
tshockURL=https://github.com/Pryaxis/TShock/releases/download

# Check current user and adjust built-in user:group to match
if [[ "$(id -u)" = 0 ]]; then
	runAsUser=terraria
	runAsGroup=terraria

	if [[ -v PUID ]]; then
		if [[ $PUID != 0 ]]; then
			if [[ $PUID != $(id -u terraria) ]]; then
				usermod -u $PUID terraria
			fi
		else
			runAsUser=root
		fi
	fi

	if [[ -v PGID ]]; then
		if [[ $PGID != 0 ]]; then
			if [[ $PGID != $(id -g terraria) ]]; then
				groupmod -o -g "$PGID" terraria
			fi
		else
			runAsGroup=root
		fi
	fi
	
# Check what latest vanilla version is and set it as the VERSION
	HTTPCODE=$(curl -sI https://terraria.org | awk '/HTTP\/[0-9.]+/{print $2}')
	if [[ "$VERSION" == "latest" && $HTTPCODE -eq 200 ]]; then
		VERSION=$(curl -s $updateURL | grep -Po -e '\d+' | head -1)
	elif [[ $HTTPCODE -ne 200 ]]; then
		echo Terraria.org is unreachable, is it down?
		exit 2
	fi
	
	VERSION=$(echo $VERSION | sed 's/v//' | sed 's/\.//g')
	serverURL="$serverURL/terraria-server-$VERSION.zip"

# Download vanilla server and create default config file
	if [[ ! -e /opt/terraria/$VERSION.ver && "$TYPE" == "vanilla" ]]; then
		rm -rf /opt/terraria/server/*
		curl -sLo /tmp/terraria/server.zip $serverURL
		unzip -qd /tmp/terraria/ /tmp/terraria/server.zip && \
		cp -r /tmp/terraria/$VERSION/Linux/* /opt/terraria/server/ && \
		cp /tmp/terraria/$VERSION/Windows/serverconfig.txt /opt/terraria/server/serverconfig.default && \
		sed -in '/#worldpath=.*/c\worldpath=/data/worlds/' /opt/terraria/server/serverconfig.default && \
		rm -rf /tmp/* /opt/terraria/server/*.defaultn
		touch /opt/terraria/$VERSION.ver
		chmod +x /opt/terraria/server/TerrariaServer*
		mkdir -p /data/config /data/logs /data/worlds
		
		if [[ $TEST ]]; then
			echo [Test] Downloading vanilla...
			echo Version [$VERSION] from
			echo $serverURL
		fi
	fi
	
# Download TShock and create directories
	if [[ ! -e /opt/terraria/$TSVERSION.ver && "$TYPE" == "tshock" ]]; then
		if [[ "$TSVERSION" == "latest" ]]; then
			TSVERSIONexv=$(curl -s https://api.github.com/repos/Pryaxis/TShock/releases/latest | jq -r .tag_name)
			TSVERSIONex=$(echo $TSVERSIONexv | sed 's/v//')
			TSVERSION=$(echo $TSVERSIONex | sed 's/v//' | sed 's/\.//g')
		else
			TSVERSION=$(echo $TSVERSION | sed 's/v//' | sed 's/\.//g')
			TSVERSIONex=$(echo $TSVERSION | sed 's/./.&/2g')
			TSVERSIONexv="v$TSVERSIONex"
		fi
		
		VERSIONex=$(echo $VERSION | sed 's/./.&/2g')
		
		tshockURL=$tshockURL/$TSVERSIONexv/TShock-$TSVERSIONex-for-Terraria-$VERSIONex-linux-x64-Release.zip		
		mkdir -p /tmp/tshock /opt/terraria /data/config/tshock /data/plugins
		curl -sLo /tmp/tshock/tshock.zip $tshockURL
		
		if [[ ! -e /tmp/tshock/tshock.zip ]]; then
			echo TShock download failed, check version numbers to ensure compatability
			exit 4
		fi
		
		unzip -qd /tmp/tshock/ /tmp/tshock/tshock.zip
		mv /tmp/tshock/*.tar /tmp/tshock/tshock.tar
		tar -xf /tmp/tshock/tshock.tar -C /opt/terraria/server
		rm -rf /tmp/*
		
		serverARGS=$TSserverARGS
		touch /opt/terraria/$TSVERSION.ver
		
		if [[ $TEST ]]; then
			echo [Test] Downloading tshock...
			echo Version [$TSVERSION] from
			echo $tshockURL
		fi
	fi

# Checking exsistence of config and world files
	if [[ ! -f "/data/config/serverconfig.txt" && "$TYPE" == "vanilla" ]]; then
		if [[ -f "/data/serverconfig.txt" ]]; then
			mv /data/serverconfig.txt /data/config/serverconfig.txt
		else
			cp ./serverconfig.default /data/config/serverconfig.txt
		fi
	fi

	if [[ ! -f "/data/config/banlist.txt" ]]; then
		if [[ -f "/data/banlist.txt" ]]; then
			mv /data/banlist.txt /data/config/banlist.txt
		else
			touch /data/config/banlist.txt
		fi
	fi

# v1.0.0 to v1.1.0 file movements
	if ls /data/*.txt 1> /dev/null 2>&1; then
		mv /data/*.txt /data/config/
	fi

	if ls /data/*.log 1> /dev/null 2>&1; then
		mv /data/*.log /data/logs/
	fi
	
	if ls /data/*.wld 1> /dev/null 2>&1; then
		mv /data/*wld* /data/worlds/
	fi

# Giving ownership to built-in user
	chown -R ${runAsUser}:${runAsGroup} /data /opt/terraria
	chmod -R g+w /data

# Starting the server
	
	if [[ -z "$WORLD" ]]; then
			serverARGS="$serverARGS $@"
		if [[ "$TYPE" == "tshock" ]]; then
			if [[ -d /opt/terraria/server/dotnet ]]; then
				su -c "screen -mS terra -L -Logfile /data/logs/$date.sclog ./TShock.Server -x64 $serverARGS" ${runAsUser}
			else
				su -c "screen -mS terra -L -Logfile /data/logs/$date.sclog ./TShock.Installer -x64 $serverARGS" ${runAsUser}
			fi
		elif [[ "$TYPE" == "vanilla" ]]; then
			su -c "screen -mS terra -L -Logfile /data/logs/$date.sclog ./TerrariaServer -x64 $serverARGS" ${runAsUser}
		fi
	else
		if [[ -n "$WORLD" && ! -e $WORLD ]]; then
			serverARGS="$serverARGS -worldname $WORLD $@"
		else
			serverARGS="$serverARGS -world $WORLD $@"
		fi
		
		if [[ "$TYPE" == "tshock" ]]; then
			if [[ -d /opt/terraria/server/dotnet ]]; then
				su -c "screen -dmS terra -L -Logfile /data/logs/$date.sclog ./TShock.Server -x64 $serverARGS" ${runAsUser}
			else
				su -c "screen -dmS terra -L -Logfile /data/logs/$date.sclog ./TShock.Installer -x64 $serverARGS" ${runAsUser}
			fi
		elif [[ "$TYPE" == "vanilla" ]]; then
			su -c "screen -dmS terra -L -Logfile /data/logs/$date.sclog ./TerrariaServer -x64 $serverARGS" ${runAsUser}
		fi
		
		if [[ $TEST ]]; then
			echo [Test] Starting...
			echo Args [$serverARGS]
			su -c "screen -list" ${runAsUser}
		fi

# Testing if server is 'running'
		sleep $SCRDELAY
		screenTest=$(su -c "screen -list" ${runAsUser} | grep -c "\.terra")
		if [[ $screenTest -gt 0 ]]; then
			echo -e "Server started with args [$serverARGS]"
			if [[ $TEST ]]; then
				exit 0
			fi
		else
			echo -e 'Server failed to start'
			if [[ $TEST ]]; then
				cat /data/logs/server.$date.sclog
				echo [/opt/terraria]
				ls -al /opt/terraria
				echo [/opt/terraria/server]
				ls -al /opt/terraria/server
				echo [/data]
				ls -al /data
				echo [/data/config]
				ls -al /data/config
				echo [/data/logs]
				ls -al /data/logs
			fi
			exit 3
		fi
		
# Setup save on quit functionality
		trap "touch /root/sigterm" SIGTERM
		while [[ ! -e /root/sigterm ]]; do sleep 1; done
		su -c 'screen -S terra -p 0 -X stuff 'exit^M'' terraria
		echo -e 'SIGTERM Caught'
		rm -f /root/sigterm
		sleep $SIGDELAY
	fi
	exit 0

else
	echo "Setup permission not root! Please utilize ENV variables to set UID/GID."
	exit 1
fi
