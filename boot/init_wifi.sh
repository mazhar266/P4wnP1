#!/bin/sh
#
# provides WiFi functionality for Pi Zero W (equipped with WiFI module)

# check for wifi capability
function check_wifi()
{
	if $wdir/wifi/check_wifi.sh; then WIFI=true; else WIFI=false; fi
}

function generate_dnsmasq_wifi_conf()
{
	cat <<- EOF > /tmp/dnsmasq_wifi.conf
		bind-interfaces
		port=0
		interface=wlan0
		listen-address=$WIFI_ACCESSPOINT_IP
		dhcp-range=$WIFI_ACCESSPOINT_DHCP_RANGE,$WIFI_ACCESSPOINT_NETMASK,5m

		# router
		#dhcp-option=3,$WIFI_ACCESSPOINT_IP

		# DNS
		#dhcp-option=6,$WIFI_ACCESSPOINT_IP

		# NETBIOS NS
		#dhcp-option=44,$WIFI_ACCESSPOINT_IP
		#dhcp-option=45,$WIFI_ACCESSPOINT_IP

		dhcp-leasefile=/tmp/dnsmasq_wifi.leases
		dhcp-authoritative
		log-dhcp
EOF

}

function generate_hostapd_conf()
{
	cat <<- EOF > /tmp/hostapd.conf
		# This is the name of the WiFi interface we configured above
		interface=wlan0

		# Use the nl80211 driver with the brcmfmac driver
		driver=nl80211

		# This is the name of the network
		ssid=$WIFI_ACCESSPOINT_NAME

		# Use the 2.4GHz band
		hw_mode=g

		# Use channel 6
		channel=6

		# Enable 802.11n
		ieee80211n=1

		# Enable WMM
		wmm_enabled=1

		# Enable 40MHz channels with 20ns guard interval
		ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]

		# Accept all MAC addresses
		macaddr_acl=0

		# Use WPA authentication
		auth_algs=1
EOF

	if $WIFI_ACCESSPOINT_HIDE_SSID; then
	cat <<- EOF >> /tmp/hostapd.conf
		# Require clients to know the network name
		ignore_broadcast_ssid=2

EOF
	else
	cat <<- EOF >> /tmp/hostapd.conf
		# Require clients to know the network name
		ignore_broadcast_ssid=0

EOF
	fi

	cat <<- EOF >> /tmp/hostapd.conf
		# Use WPA2
		wpa=2

		# Use a pre-shared key
		wpa_key_mgmt=WPA-PSK

		# The network passphrase
		wpa_passphrase=$WIFI_ACCESSPOINT_PSK

		# Use AES, instead of TKIP
		rsn_pairwise=CCMP
EOF
}

function start_wifi_accesspoint()
{
	generate_hostapd_conf

	hostapd /tmp/hostapd.conf > /dev/null &
#	hostapd /tmp/hostapd.conf

	# configure interface
	ifconfig wlan0 $WIFI_ACCESSPOINT_IP netmask $WIFI_ACCESSPOINT_NETMASK

	# start DHCP server (second instance if USB over Etherne is in use)
	generate_dnsmasq_wifi_conf
	dnsmasq -C /tmp/dnsmasq_wifi.conf
}
function connect_to_accesspoint()
{
	#not sure how to setup dnsmasq and hostapd so this just gets run after the accesspoint was already started
	sudo ifconfig wlan0 up
	if [ $(sudo iwlist wlan0 scan | grep $EXISTING_AP_NAME) ]; then
		# check if /etc/wpa_supplicant/wpa_supplicant.conf exists
		printf "\"$EXISTING_AP_NAME\" was found\n"
		if [ $(cat /etc/wpa_supplicant/wpa_supplicant.conf | grep $EXISTING_AP_NAME) ]; then
			# only connect if its there. connect. if not open accesspoint
			printf "entry was found, connecting...\n"
			sudo wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
			sudo dhclient wlan0
			#check if IP was obtained (to lazy to implement)
		else
			printf "\nNo entry for Accesspoint \"$EXISTING_AP_NAME\" found! creating one... "
			if [ $EXISTING_AP_PSK ]; then
				$wdir/wifi/append_secure_wpa_conf.sh $EXISTING_AP_NAME $EXISTING_AP_PSK
				printf "success! retrying...\n"
				connect_to_accesspoint
			else
				printf "fail!\n PLEASE SPECIFY EXISTING_AP_PSK or use wifi/append_secure_wpa_conf.sh to generate an AP entry\n"
			fi
		fi
	else
		printf "\nNetwork \"$EXISTING_AP_NAME\" not found!\n"
	fi
}
