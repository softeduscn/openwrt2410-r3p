#!/bin/bash

NAME=sysmonitor
APP_PATH=/usr/share/$NAME
SYSLOG='/var/log/sysmonitor.log'
device='mi-router-3-pro'
[ ! -f /tmp/sysmonitor.pid ] && echo 0 >/tmp/sysmonitor.pid

uci_get_by_name() {
	local ret=$(uci get $1.$2.$3 2>/dev/null)
	echo ${ret:=$4}
}

uci_get_by_type() {
	local ret=$(uci get $1.@$2[0].$3 2>/dev/null)
	echo ${ret:=$4}
}

uci_set_by_name() {
	uci set $1.$2.$3=$4 2>/dev/null
	uci commit $1
}

uci_set_by_type() {
	uci set $1.@$2[0].$3=$4 2>/dev/null
	uci commit $1
}

echolog() {
	local d="$(date "+%Y-%m-%d %H:%M:%S")"
	echo -e "$d: $*" >>$SYSLOG
#	number=$(cat $SYSLOG|wc -l)
#	[ $number -gt 25 ] && sed -i '1,10d' $SYSLOG
}

echoddns() {
	[ $(uci_get_by_name $NAME $NAME ddnslog 0) == 0 ] && return
	local d="$(date "+%Y-%m-%d %H:%M:%S")"
	echo -e "$d: $*" >>$SYSLOG
#	number=$(cat $SYSLOG|wc -l)
#	[ $number -gt 25 ] && sed -i '1,10d' $SYSLOG
}

ping_url() {
	for i in $( seq 1 2 ); do
		status=$(ping -c 1 -W 1 $1 | grep -o 'time=[0-9]*.*' | awk -F '=' '{print$2}'|cut -d ' ' -f 1)
		[  "$status" == "" ] && status=0
		[ "$status" != 0 ] && break
	done
	 [ "$status" != 0 ] && status=1
	echo $status
}

test_url() {
	local url=$1
	local try=1
	[ -n "$2" ] && try=$2
	local timeout=2
	[ -n "$3" ] && timeout=$3
	local extra_params=$4
	curl --help all | grep "\-\-retry-all-errors" > /dev/null
	[ $? == 0 ] && extra_params="--retry-all-errors ${extra_params}"
	status=$(/usr/bin/curl -I -o /dev/null -skL $extra_params --connect-timeout ${timeout} --retry ${try} -w %{http_code} "$url")
	case "$status" in
		404|204|\
		200)
			status=200
		;;
		*)
			status=0
		;;
	esac
	echo $status
}

curl_url() {
	for i in $( seq 1 2 ); do
		result=$(curl -s --connect-timeout 1 $1|grep google|wc -l)
		[ "$result" != 0 ] && break
	done
	echo $result
}

setdelay_offon() {
	enabled=0
	[ -n "$2" ] && enabled=1		
	prog_num=$(cat /etc/config/sysmonitor|grep prog_list|wc -l)
	num=0
	while (($num<$prog_num))
	do
		program=$(uci_get_by_name $NAME @prog_list[$num] program)
		if [ "$program" == $1 ]; then
			uci_set_by_name $NAME @prog_list[$num] enabled $enabled
			uci commit $NAME
			break
		fi
		num=$((num+1))
	done
}

getdelay() {
	prog_num=$(cat /etc/config/sysmonitor|grep prog_list|wc -l)
	num=0
	status=-1
	while (($num<$prog_num))
	do
		program=$(uci_get_by_name $NAME @prog_list[$num] program)
		if [ "$program" == $1 ]; then
			status=$(uci_get_by_name $NAME @prog_list[$num] $2)
			break
		fi
		num=$((num+1))
	done
echo $status
}

get_delay() {
	prog_num=$(cat /etc/config/sysmonitor|grep prog_list|wc -l)
	num=0
	status=-1
	while (($num<$prog_num))
	do
		program=$(uci_get_by_name $NAME @prog_list[$num] program)
		path=$(uci_get_by_name $NAME @prog_list[$num] path "/usr/share/sysmonitor/sysapp.sh")
		cycle=$(uci_get_by_name $NAME @prog_list[$num] cycle 5)
		enabled=$(uci_get_by_name $NAME @prog_list[$num] enabled 0)
		if [ "$program" == $1 ]; then
			status=$enabled$cycle'='$path' '$program
			break
		fi
		num=$((num+1))
	done
echo $status
}

delay_prog() {
	status=$(get_delay $1)
	if [ "$status" != "" ]; then
		enabled=${status:0:1}
		status=${status:1}
		program=$(echo $status|cut -d' ' -f2)
		if [ -n "$2" ]; then
			status=$2'='$(echo $status|cut -d'=' -f2-)
			setdelay_offon $program 1
			echo $status >> /tmp/delay.sign
		else
			[ "$enabled" == 1 ] && echo $status >> /tmp/delay.sign
		fi	
	fi
}

chk_prog() {
prog_num=$(cat /etc/config/sysmonitor|grep prog_list|wc -l)
num=0
while (($num<$prog_num))
do
	program=$(uci_get_by_name $NAME @prog_list[$num] program)
	path=$(uci_get_by_name $NAME @prog_list[$num] path "/usr/share/sysmonitor/sysapp.sh")
	enabled=$(uci_get_by_name $NAME @prog_list[$num] enabled 0)
	status=$(cat /tmp/delay.list|grep $program|wc -l)
	if [ "$status" == 0 ]; then
		cycle=$(uci_get_by_name $NAME @prog_list[$num] cycle 200)
		enabled=$(uci_get_by_name $NAME @prog_list[$num] enabled 0)
		[ "$enabled" == 1 ] && echo $cycle'='$path' '$program >> /tmp/delay.sign
	else	
		[ "$enabled" == 0 ] && sed -i "/$program/d" /tmp/delay.list
	fi
	num=$((num+1))
done
}

chk_vpn() {
	status=0
	if [ "$(uci_get_by_name $NAME $NAME vpntype 0)" == 'VPN' ]; then
		file='/tmp/regvpn'
		vpnip=$(uci_get_by_name $NAME $NAME vpnip)
		vpn=$(cat $file|grep $vpnip)
		status=$(ping_url $vpnip)
		if [ "$status" == 0 ]; then
			vpn1=$(echo $vpn|sed "s|-1-|-0-|g")
			vpn1='0'${vpn1:1}
			sed -i "s|$vpn|$vpn1|g" $file
			touch /tmp/chkvpn.skip
			touch /tmp/sysmonitor
		else
			if [ "$(uci get network.wan.gateway)" == $vpnip ]; then
				status=$(ping_url www.google.com)
				if [ "$status" == 0 ]; then
					echo '2-next_vpn'|netcat -nc $vpnip 55556
					vpn1=$(echo $vpn|sed "s|-1-|-0-|g")
				else
					vpn1=$(echo $vpn|sed "s|-0-|-1-|g")
				fi
				sed -i "s|$vpn|$vpn1|g" $file
			fi
		fi
	fi
#	echo $status
}

firstrun() {
	sysdir='/etc/sysmonitor'
	mv $sysdir/fs.lua /usr/lib/lua/luci
	destdir=''
	mvdir $sysdir $destdir
	[ ! -f /etc/crontabs/root ] && touch /etc/crontabs/root
	[ ! -n "$(pgrep -f cron)" ] && /etc/init.d/cron start
	[ ! -n "$(pgrep -f ttyd)" ] && /usr/bin/ttyd -6 /bin/login &
	if [ -f /etc/init.d/mosdns ]; then
	dns=$(uci_get_by_name $NAME $NAME dns 'NULL')
	case $dns in
	SmartDNS)
		uci set mosdns.config.enabled=0
		uci commit mosdns
		;;
	MosDNS)
		uci set smartdns.@smartdns[0].enabled=0
		uci commit smartdns
		;;
	*)
		uci set smartdns.@smartdns[0].enabled=0
		uci commit smartdns
		uci set mosdns.config.enabled=0
		uci commit mosdns
		;;
	esac
	fi
	ntpd -n -q -p ntp.aliyun.com
	touch /www/ip6.html
	touch /tmp/vpns
	getip
	setdns
#	default dns=SmartDNS in selvpn
	selvpn
	#modify opkg source
	sed -i 's_downloads.openwrt.org_mirrors.cloud.tencent.com/openwrt_' /etc/opkg/distfeeds.conf
	sed -i "s/-SNAPSHOT/.10/g" /etc/opkg/distfeeds.conf
	[ "$(pgrep -f sysmonitor.sh|wc -l)" == 0 ] && $APP_PATH/monitor.sh
	touch /tmp/firstrun
#	echo "15=touch /tmp/firstrun" >> /tmp/delay.sign
}

mvdir() {
	cd $1
	home=$(pwd)
	mydir=$(ls)
	for i in $mydir
	do
	if [ -d $i ]; then
		myhome=$(pwd)
		cd $i
		mvdir=$(ls)
		mvdir $myhome/$i $2/$i
		cd $myhome
	else
		mv $i $2
	fi
	done
}

ipsec_users() {
	if [ -f "/usr/sbin/ipsec" ]; then
		users=$(/usr/sbin/ipsec status|grep xauth|grep ESTABLISHED|wc -l)
		usersl2tp=$(top -bn1|grep options.xl2tpd|grep -v grep|wc -l)
		let "users=users+usersl2tp"
		[ "$users" == 0 ] && users='None'
	else
		users='None'
	fi
	echo $users
}

pptp_users() {
	if [ -f "/usr/sbin/pppd" ]; then
		users=$(top -bn1|grep options.pptpd|grep -v grep|wc -l)
#		let users=users-1
		[ "$users" == 0 ] && users='None'
	else
		users='None'
	fi
	echo $users
}

wg_users() {
file='/var/log/wg_users'
/usr/bin/wg >$file
m=$(sed -n '/peer/=' $file | sort -r -n )
k=$(cat $file|wc -l)
let "k=k+1"
s=$k
for n in $m
do 
	let "k=s-n"
	if [ $k -le 3 ] ;then 
		let "s=s-1"
		tmp='sed -i '$n,$s'd '$file
		$tmp
	else
		let "i=n+3"
		tmp='sed -n '$i'p '$file
		tmp=$($tmp|cut -d' ' -f6)
		[ "$tmp" == "day," ] && tmp="days,"
		[ "$tmp" == "hour," ] && tmp="hours,"
		[ "$tmp" == "minute," ] && tmp="minutes,"
		case $tmp in
		days,)
			let "s=s-1"
			tmp='sed -i '$n,$s'd '$file
			$tmp
			;;
		hours,)
			let "s=s-1"
			tmp='sed -i '$n,$s'd '$file
			$tmp
			;;
		minutes,)
			tmp='sed -n '$i'p '$file
			tmp=$($tmp|cut -d' ' -f5)
			if [ $tmp -ge 3 ] ;then
				let "s=s-1"
				tmp='sed -i '$n,$s'd '$file
				$tmp
			fi
			;;
		esac
	fi
	s=$n
done
#users=$(cat $file|sed "/GWLcAE1Of.*$/d"|sed "/bmXOC.*$/d"|grep peer|wc -l)
users=$(cat $file|grep peer|wc -l)
#[ "$users" == 0 ] && users='None'
echo $users
}

wg() {
	if [ "$(uci_get_by_name $NAME $NAME wgenable 0)" == 0 ]; then
		if [ "$(ifconfig |grep wg[0-9] |cut -c3-3|wc -l)" != 0 ]; then
			wg_name=$(ifconfig |grep wg[0-9] |cut -c1-3)
			for x in $wg_name; do
			    ifdown $x &
			done
		fi
	else
		if [ "$(ifconfig |grep wg[0-9] |cut -c3-3|wc -l)" != 3 ]; then
			wg=$(ifconfig |grep wg[0-9] |cut -c1-3)
			wg_name="wg1 wg2 wg3"
			for x in $wg_name; do
				[ "$(echo $wg|grep $x|wc -l)" == 0 ] && ifup $x
			done
		fi
	fi
	wg=$(ifconfig |grep wg[0-9] |cut -c1-3)
	echo $wg
}

getip() {
	ifname=$(uci get network.wan.device)
	ip=$(ip -o -4 addr list $ifname| cut -d ' ' -f7|cut -d'/' -f1)
	echo $ip >/www/ip.html
	echo $ip
}

getip6() {
	ifname=$(uci get network.wan.device)
	ip=$(ip -o -6 addr list $ifname | cut -d ' ' -f7 | cut -d'/' -f1 |head -n1)
	echo $ip >/www/ip6.html
	echo $ip
}

gethost() {
	if [ -n "$1" ]; then
		vpn=$1		
	else
		vpn=$(uci_get_by_name $NAME $NAME vpnip '192.168.1.1')
	fi
	host=$(nslookup $vpn|grep name|cut -d'=' -f2|cut -d' ' -f2|cut -d'.' -f1)
	[ ! -n "$host" ] && host=$vpn
	echo $host
}

setdns() {
	tmp=0
	if [ "$(sed -n '/list dnslist/=' /etc/config/sysmonitor)" == '' ];then
		tmp=1
		uci del network.wan.dns
		dnslist=$(uci get network.wan.gateway)
		uci add_list network.wan.dns=$dnslist
		[ "$(uci_get_by_name $NAME $NAME syslog)" == 1 ] && echolog "WAN-DNS "$dnslist
	else
		dnslist=$(uci_get_by_name $NAME $NAME dnslist '192.168.1.1')
		if [ "$dnslist" != "$(uci get network.wan.dns)" ]; then
			tmp=1
			[ "$(uci_get_by_name $NAME $NAME syslog)" == 1 ] && echolog "WAN-DNS "$dnslist
			uci del network.wan.dns
			for n in $dnslist
			do
				uci add_list network.wan.dns=$n
			done
		fi
	fi
	if [ "$tmp" == 1 ]; then
		uci commit network
		ifup wan
		ifup wan6
		/etc/init.d/odhcpd restart
	fi
}

stopdl() {
	sed -i '/Download Firmware/,$d' $SYSLOG
	[ -f /tmp/$NAME.log.tmp ] && cp /tmp/$NAME.log.tmp $SYSLOG
	[ -f /tmp/$NAME.log.tmp ] && rm /tmp/$NAME.log.tmp
	[ -f /tmp/sysupgrade ] && rm /tmp/sysupgrade
	dl=$(pgrep -f MI-R3P)
	[ -n "$dl" ] && kill $dl
	firmware=$(uci_get_by_name $NAME $NAME firmware)
	tmp=$(echo $firmware|cut -d'/' -f 9)
	[ -f /tmp/upload/$tmp ] && rm /tmp/upload/$tmp
}

firmware() {
	[ ! -d "/tmp/upload" ] && mkdir /tmp/upload
	cd /tmp/upload
	stopdl
	[ ! -f /tmp/$NAME.log.tmp ] && cp $SYSLOG /tmp/$NAME.log.tmp
	firmware=$(uci_get_by_name $NAME $NAME firmware)
	[ "$1" != '' ] && firmware=$1
	echolog "Download Firmware:"$tmp"..."
	echolog "If download slowly,please use vpn!!!"
	echo '------------------------------------------------------------------------------------------------------' >> $SYSLOG
	echolog ""
	wget  --no-check-certificate -c $firmware -O $tmp >> $SYSLOG 2>&1
	if [ $? == 0 ]; then
		sed -i '/Download Firmware/a\ ' $SYSLOG
		sed -i '/Download Firmware/a\********************************************* ' $SYSLOG
		sed -i '/Download Firmware/a\****** Download Firmware is OK.Please Upgrade '$tmp $SYSLOG
		sed -i '/Download Firmware/a\ ' $SYSLOG
	else
		[ -f /tmp/upload/$tmp ] && rm /tmp/upload/$tmp
		sed -i '/Download Firmware/,$d' $SYSLOG
		echolog "Download Firmware is error! please use vpn & try again."
		echo '------------------------------------------------------------------------------------------------------' >> $SYSLOG
	fi
}

sysupgrade() {
	file=$(ls /tmp/upload|grep $device)
	if [ -n "$file" ]; then
		if [ "$1" == "-c" ]; then
			echo 'Upgrade Firmware (keep config)' > $SYSLOG
		else
			echo 'Upgrade Firmware' > $SYSLOG
		fi
		echo '------------------------------------------------------------------------------------------------------' >> $SYSLOG
		sysupgrade='sysupgrade '$1' /tmp/upload/'$file
		echo $sysupgrade >> $SYSLOG
		touch /tmp/sysupgrade
		echo '5='$sysupgrade >> /tmp/delay.sign
	else
		sed -i '/Download Firmware/,$d' $SYSLOG
		echolog "Download Firmware"
		echolog "No sysupgrade file? Please upload $device sysupgrade file or download."
		echo '------------------------------------------------------------------------------------------------------' >> $SYSLOG
	fi
}

agh() {
file1="/etc/AdGuardHome.yaml"
if [ -f $file1 ]; then
	status='Stopped'
	[ -n "$(pgrep -f AdGuardHome)" ] && status='Running'
	num1=$(sed -n '/upstream_dns:/=' $file1)
	let num1=num1+1
	tmp='sed -n '$num1'p '$file1
	adguardhome=$($tmp)
	echo $status$adguardhome
else
	echo ""
fi
}

ad_del() {
	file1="/etc/AdGuardHome.yaml"
	num1=$(sed -n '/upstream_dns:/=' $file1)
	num2=$(sed -n '/upstream_dns_file:/=' $file1)
	let num1=num1+1
	let num2=num2-1
	tmp='sed -i '$num1','$num2'd '$file1
	[ $num1 -le $num2 ] && $tmp
}

setddns() {
	[ ! -f "/etc/init.d/ddns" ] && exit
	if [ "$(uci_get_by_name $NAME $NAME ddns 1)" == 1 ];  then
		/etc/init.d/ddns enable
		if [ ! -n "$(pgrep -f dynamic_dns)" ]; then
			/etc/init.d/ddns start
		fi
	else
		/etc/init.d/ddns disable
		/etc/init.d/ddns stop
	fi
}

service_ddns() {
	if [ ! -n "$(pgrep -f dynamic_dns)" ]; then
		uci set sysmonitor.sysmonitor.ddns=1
	else
		uci set sysmonitor.sysmonitor.ddns=0
	fi
	uci commit sysmonitor
	service_dns
}

smartdns() {
	uci set smartdns.@smartdns[0].enabled='1'
	uci set smartdns.@smartdns[0].seconddns_enabled='0'
	uci set smartdns.@smartdns[0].auto_set_dnsmasq='1'
	uci set smartdns.@smartdns[0].port='6053'
	uci commit smartdns
	smartdns_conf='/etc/smartdns/custom.conf'
	uci set sysmonitor.sysmonitor.dns='SmartDNS'
	uci commit sysmonitor
	/etc/init.d/smartdns stop
	if [ "$(uci_get_by_name $NAME $NAME vpntype 'VPN')" == "VPN" ]; then
		cp /etc/sysmonitor/custom-vpn.conf $smartdns_conf
		vpnip=$(uci_get_by_name $NAME $NAME vpnip '192.168.1.1')
		sed -i '/server-tcp/d' $smartdns_conf
		echo 'server-tcp '$vpnip >> $smartdns_conf
	else
		cp /etc/sysmonitor/custom-novpn.conf $smartdns_conf
	fi
	/etc/init.d/smartdns start
}

mosdns() {
	if [ "$(uci_get_by_name $NAME $NAME vpntype 'VPN')" == "VPN" ]; then
		uci set sysmonitor.sysmonitor.dns='MosDNS'
		uci commit sysmonitor
		uci set mosdns.config.enabled='1'
		uci commit mosdns
		reload 'mosdns'
	else
		uci set mosdns.config.enabled='0'
		uci commit mosdns
		mosdns_stop
	fi
}

smartdns_stop() {
	[ -n "$(pgrep -f smartdns)" ] && /etc/init.d/smartdns stop 2>/dev/null
	uci set smartdns.@smartdns[0].enabled='0'
	uci commit smartdns
	uci set dhcp.@dnsmasq[0].noresolv=0
	uci set dhcp.@dnsmasq[0].server=''
	uci set dhcp.@dnsmasq[0].port=''
	uci commit dhcp
	/etc/init.d/dnsmasq reload
}

mosdns_stop() {
	if [ -n "$(pgrep -f mosdns)" ]; then
		uci set mosdns.config.enabled='0'
		uci commit mosdns
		/etc/init.d/mosdns stop 2>/dev/null
	fi
	if [ "$(uci get dhcp.@dnsmasq[0].noresolv)" == 1 ]; then
		uci set dhcp.@dnsmasq[0].noresolv=0
		uci set dhcp.@dnsmasq[0].server=''
		uci set dhcp.@dnsmasq[0].port=''
		uci commit dhcp
		/etc/init.d/dnsmasq reload
	fi
}

reload() {
	action=1
	para="reload"
	case $1 in
	smartdns)
		[ ! -n "$(pgrep -f smartdns)" ] && para="start"
		uci set mosdns.config.enabled='1'
		uci commit mosdns
		;;
	mosdns)
		[ ! -n "$(pgrep -f mosdns)" ] && para="start"
		uci set mosdns.config.enabled='1'
		uci commit mosdns
		;;
	*)
		action=0
		;;
	esac
	if [ $action == 1 ]; then
		/etc/init.d/$1 $para &
	fi
}

service_setdns() {
	uci set sysmonitor.sysmonitor.dns=$1
	uci set sysmonitor.sysmonitor.vpntype="NULL"
	uci commit sysmonitor
	case $1 in
	SmartDNS)
		uci set smartdns.@smartdns[0].enabled=1
		uci commit smartdns
		;;
	MosDNS)
		uci set mosdns.config.enabled=1
		uci commit mosdns
		;;
	esac
	service_dns
}

service_dns() {
	dns=$(uci_get_by_name $NAME $NAME dns 'NULL')
	case $dns in
	SmartDNS)
		[ -f /etc/init.d/mosdns ] && mosdns_stop
		smartdns
		;;
	MosDNS)
		[ -f /etc/init.d/smartdns ] && smartdns_stop
		mosdns
		;;
	*)
		[ -f /etc/init.d/mosdns ] && mosdns_stop
		[ -f /etc/init.d/smartdns ] && smartdns_stop
		;;
	esac
}

selvpn() {
	vpn=$(uci_get_by_name $NAME $NAME vpntype 'VPN')
	case $vpn in
	VPN)
		uci set sysmonitor.sysmonitor.dns='SmartDNS'
		uci set sysmonitor.sysmonitor.enable='1'
		uci commit sysmonitor
#		[ -n "$(pgrep -f mwan3)" ] && /etc/init.d/mwan3 stop
		;;
	*)
		uci set sysmonitor.sysmonitor.dns='SmartDNS'
		uci commit sysmonitor
#		[ -n "$(pgrep -f mwan3)" ] && /etc/init.d/mwan3 stop
		;;
	esac
	touch /tmp/sysmonitor
}

update_chnlist() {
	if [ ! -n "$(pgrep -f update_chnlist.sh)" ]; then
		sh /etc/ipset-rules/update_chnlist.sh &
	fi
}

sel_vpn() {
	uci set sysmonitor.sysmonitor.vpntype="VPN"
	uci set sysmonitor.sysmonitor.dns="NULL"
	uci commit sysmonitor
	touch /tmp/sysmonitor
}

close_vpn() {
	uci set sysmonitor.sysmonitor.vpntype="NULL"
	uci set sysmonitor.sysmonitor.dns='SmartDNS'
	uci commit sysmonitor
	touch /tmp/sysmonitor
}

mosdns_set_vpnip() {
	uci set mosdns.config.enabled='1'
	uci commit mosdns
	mosdns_conf='/etc/mosdns/config_custom.yaml'
	m=$(sed -n '/vpn_address/=' $mosdns_conf)
	m=$((m+1))
	sed -i $m's/addr:.*/addr: "tcp:\/\/'$1'"/' $mosdns_conf
	reload 'mosdns'
}

setvpnip() {
	if [ -n "$1" ]; then
		uci set sysmonitor.sysmonitor.vpnip=$1
		uci set sysmonitor.sysmonitor.vpntype='VPN'
		uci set sysmonitor.sysmonitor.dns='SmartDNS'
		uci commit sysmonitor
		touch /tmp/sysmonitor
	fi
}

sysbutton() {
case $1 in
prog)
	#button='<input type="button" class="button1" value="Show/Hiden" id="app" onclick="fun()" />'
	prog_num=$(cat /etc/config/sysmonitor|grep prog_list|wc -l)
	num=0
	while (($num<$prog_num))
	do
		program=$(uci get sysmonitor.@prog_list[$num].program)
		name=$(uci get sysmonitor.@prog_list[$num].name)
		button=$button' <button class=button1><a href="sysmenu?sys='$program'&sys1=&redir=prog">'$name'</a></button>'
		num=$((num+1))
	done
	;;
prog_list)
	button='<B>'
	while read i
	do
		color='MediumAquamarine'
		timeid=$(echo $i|cut -d'=' -f1)
		[ "$timeid" -le 30 ] && color='MediumSeaGreen '
		[ "$timeid" -le 15 ] && color='Green '
		[ "$(echo $i|cut -d' ' -f2)" != 'chkprog' ] && button=$button' <font color='$color'>'$i'</font><BR>'
	done < /tmp/delay.list
	button=$button'</B>'
	;;
vpn_list)
	button='<button class=button1 title="Close VPN"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=CloseVPN&sys1=&redir=host">CloseVPN</a></button>'
	button=$button' <button class="button1" title="Update VPN connection"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=UpdateVPN&sys1=&redir=host">UpdateVPN</a></button><BR><BR>'
	gateway=$(uci get network.wan.gateway)
	while read i
	do
		ip=$(echo ${i:1}|cut -d'-' -f1)
		status=$(echo $i|cut -d'-' -f3)
		host=$(echo $i|cut -d'-' -f2)
		color='MediumSeaGreen'
		[ "$gateway" == $ip ] && color=green
		[ "$status" == 0 ] && color='red'
		button=$button'<button class="button1" title="Goto '$host' setting"><a href="http://'$host'" target="_blank">Goto ->'$host'</a></button> '
		button=$button'<B><font color='$color'>'
		button=$button$(echo ${i:1}|cut -d'-' -f1)' '$(echo $i|cut -d'-' -f4-)'</font></B>'
		[ "$color" == 'MediumSeaGreen' ] && button=$button' <button class="button1" title="Select '$host' for VPN service"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=selVPN&sys1='$ip'&redir=host">Sel->'$host'</a></button>'
		button=$button'<BR>'
	done < /tmp/regvpn
	;;
buttontitle)
	button=''
	redir='ddns'
	[ "$(uci_get_by_name $NAME $NAME ddnslog 0)" == 1 ] && redir='log'
#	button='<button class="button1"><a href="/cgi-bin/luci/admin/services/ttyd" target="_blank">Terminal</a></button>'
	vpntype=$(uci_get_by_name $NAME $NAME vpntype 'NULL')
	dns=$(uci_get_by_name $NAME $NAME dns 'NULL')
	if [ "$dns" != "NULL" ]; then
		[ "$vpntype" != "VPN" ] && button=$button' <button class=button4 title="Close DNS"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=close_dns&sys1=&redir=settings">Close-DNS</a></button>'
		button=$button' <button class=button4 title="Restart DNS"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=restartdns&sys1=&redir=system">Restart-DNS</a></button>'
	fi
	;;
button)
	button=''
	if [ -f /etc/init.d/ddns ]; then
		if [ ! -n "$(pgrep -f dynamic_dns)" ]; then
			button=$button'<button class=button2><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=ddns&sys1=&redir=settings">DDNS</a></button>'
		else
			button=$button'<button class=button1><a href="/cgi-bin/luci/admin/services/ddns" target="_blank">DDNS</a></button>'
		fi
	fi
#	button=$button' <button class="button1"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=CHNlist&sys1=&redir=settings">CHNlist Update</a></button>'
	#if [ $(uci_get_by_name $NAME $NAME vpntype 0) == 'NULL' ]; then
	dns=$(uci_get_by_name $NAME $NAME dns 'NULL')
	if [ -f /etc/init.d/smartdns ]; then
		if [ "$(uci_get_by_name $NAME $NAME dns 'SmartDNS')" == 'SmartDNS' ]; then
			if [ ! -n "$(pgrep -f smartdns)" ]; then
				button=$button' <button class=button2 title="SmartDNS is not ready...,Restart"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=smartdns&sys1=&redir=settings">SmartDNS</a></button>'
			else
				button=$button' <button class=button1 title="Goto SmartDNS setting"><a href="/cgi-bin/luci/admin/services/smartdns" target="_blank">SmartDNS</a></button>'
			fi
		else
			if [ "$(uci_get_by_name $NAME $NAME vpntype 'NULL')" == 'NULL' ]; then
				button=$button' <button class=button3 title="Start SmartDNS"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=smartdns&sys1=&redir=settings">SmartDNS</a></button>'
			else
				button=$button' <button class=button3 title="Start SmartDNS"><a href="/cgi-bin/luci/admin/services/smartdns" target="_blank">SmartDNS</a></button>'
			fi
		fi
	fi
#	if [ -f /etc/init.d/mosdns ]; then
#		if [ "$(uci_get_by_name $NAME $NAME dns 'MosDNS')" == 'MosDNS' ]; then
#			if [ ! -n "$(pgrep -f mosdns)" ]; then
#				button=$button' <button class=button2 title="MosDNS is not ready...,Restart"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=mosdns&sys1=&redir=settings">MosDNS</a></button>'
#			else
#				button=$button' <button class=button1 "Goto MosDNS setting"><a href="/cgi-bin/luci/admin/services/mosdns" target="_blank">MosDNS</a></button>'
#			fi
#		else
#			if [ "$(uci_get_by_name $NAME $NAME vpntype 'NULL')" == 'NULL' ]; then
#				button=$button' <button class=button3 title="Start MosDNS"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=mosdns&sys1=&redir=settings">MosDNS</a></button>'
#			else
#				button=$button' <button class=button3 title="Start MosDNS"><a href="/cgi-bin/luci/admin/services/mosdns" target="_blank">MosDNS</a></button>'
#			fi
#		fi
#	fi
	#fi
	;;
lan)
	button='<font color=6699cc>lan: <a title="GOTO network setting" href="/cgi-bin/luci/admin/network/network" target="_blank">'$(uci get network.lan.ipaddr)'</a></font><font color=9699cc> dns:'$(uci get network.lan.dns)'</font>'
	;;
wantitle)
	button=''
#	gateway=$(uci get network.wan.gateway)
#	vpn=$(uci_get_by_name $NAME $NAME vpnip '192.168.1.1')
#	if [ "$vpn" == $gateway ]; then
#		button='<button class=button1 title="Close VPN"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=CloseVPN&sys1=&redir=settings">CloseVPN</a></button>'
#	fi
	;;
wan)
	ip=$(cat /www/ip.html)
	gateway=$(uci get network.wan.gateway)
	vpnip=$(uci_get_by_name $NAME $NAME vpnip '192.168.1.1')
	button='<font color=6699cc>wan: '$ip' </font><font color=9699cc>['$(cat /www/ip6.html)']</font><br>'
	if [ "$vpnip" == $gateway ]; then
		button=$button'<font color=6699cc>gateway:'$(uci get network.wan.gateway)'</font><font color=9699cc> dns:'$(uci get network.wan.dns)'</font>'
		host=$(gethost)
		name=$(cat /tmp/regvpn|grep $vpnip|cut -d'-' -f2)
		vpn=$(cat /tmp/regvpn|grep $vpnip|cut -d'-' -f3-)
		vpn=${vpn:2}
		button=$button'<BR><font color=green>'$name'-'$vpn'</font>'
		button=$button' <button class=button4 title="Close VPN"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=CloseVPN&sys1=&redir=settings">CloseVPN</a></button>'
	else
		button=$button'<font color=6699cc>gateway:'$(uci get network.wan.gateway)' </font><font color=9699cc>dns:'$(uci get network.wan.dns)'</font>'
	fi
	;;
vpnstitle)
	button='<button class="button1" title="Update VPN connection"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=UpdateVPN&sys1=&redir=settings">UpdateVPN</a></button>'
	;;
vpns)
	button=''
	vpnip=$(uci_get_by_name $NAME $NAME vpnip '192.168.1.1')
	gateway=$(uci get network.wan.gateway)
	while read i
	do
		num=${i:0:1}
		if [ "$num" != 0 ]; then
			ip=$(echo ${i:1}|cut -d'-' -f1)
			host=$(echo ${i:1}|cut -d'-' -f2)
			name=$(echo ${i:1}|cut -d'-' -f3-)
			sign=${name:0:1}
			name=${name:2}
			color='MediumSeaGreen'
			[ "$sign" == 0 ] && color='red'
			button=$button'<button class="button1" title="Goto '$host' setting"><a href="http://'$host'" target="_blank">Goto ->'$host'</a></button> '
			if [ "$gateway" == $ip ]; then
				color='green'			
				button=$button'<font color='$color'>'$ip'-'$host'-'$name'</font>'
				button=$button'<BR>'
			else
				button=$button'<font color='$color'>'$ip'-'$host'-'$name'</font> '
				button=$button'<button class="button1" title="Select '$host' for VPN service"><a href="/cgi-bin/luci/admin/sys/sysmonitor/sysmenu?sys=selVPN&sys1='$ip'&redir=settings">Sel->'$host'</a></button><BR>'
			fi
		fi
	done < /tmp/regvpn
	;;
	wg_title)
		button=''
		;;
	wg_state)
		wguser=$(wg_users)
		if [ "$wguser" == 0 ]; then
			button=''
		else
			button='<a href="/cgi-bin/luci/admin/sys/sysmonitor/wgusers">Wireguard online users: </a><font color=green>'$wguser'</font>'
		fi
		;;
esac
echo $button > /dev/null 2>&1
echo $button
}

sysmenu() {
	case $1 in
	stopdl)
		stopdl
		;;
	firmware)
		firmware
		;;
	sysupgrade)
		sysupgrade $2
		;;
	ddns)
		/etc/init.d/ddns start &
		;;
	close_dns)
		uci set sysmonitor.sysmonitor.dns='NULL'
		uci commit sysmonitor
		service_dns
		;;
	restartdns)
		service_dns
		;;
	smartdns)
		service_setdns SmartDNS
		;;
	mosdns)
		service_setdns MosDNS
		;;
	CHNlist)
		update_chnlist
		;;
	OpenVPN)
		sel_vpn
		;;
	ShowProg)
		file='/usr/lib/lua/luci/view/sysmonitor/prog.htm'
		status=$(cat $file|grep block|wc -l)
		if [ "$status" == 1 ]; then
			sed -i s/block/none/g $file
		else
			sed -i s/none/block/g $file
		fi
		;;
	UpdateVPN)
		updatevpn
		;;
	UpdateHOST)
		reg_vpn
		;;
	CloseVPN)
		close_vpn
		;;
	selVPN)
		setvpnip $2
		;;
	*)
		prog=$(uci_get_by_name $NAME $NAME prog)
		delay_prog $1 $prog
		;;
	esac
}

reg_vpn() {
	num=$(cat /etc/config/dhcp|grep "config domain"|wc -l)
	if [ "$num" != 0 ]; then
		while (($num>0))
		do
			num=$((num-1))
			uci del dhcp.@domain[$num]
		done
	fi
	host_num=$(cat /etc/config/sysmonitor|grep host_list|wc -l)
	num=0
	while (($num<$host_num))
	do
		hostname=$(uci get sysmonitor.@host_list[$num].hostname)
		hostip=$(uci get sysmonitor.@host_list[$num].hostip)
		dhcp=$(uci add dhcp domain)
		uci set dhcp.$dhcp.name=$hostname
		uci set dhcp.$dhcp.ip=$hostip
		num=$((num+1))
	done
	uci del sysmonitor.sysmonitor.vpn
	while read i
	do
		num=${i:0:1}
		if [ "$num" != 0 ]; then
			let num=num-1
			sed  -i  "s|$i|$num${i:1}|g" /tmp/regvpn
			ip=$(echo ${i:1}|cut -d'-' -f1)
			name=$(echo ${i:1}|cut -d'-' -f2)
			uci add_list sysmonitor.sysmonitor.vpn=$ip
			dhcp=$(uci add dhcp domain) 
			uci set dhcp.$dhcp.name=$name
			uci set dhcp.$dhcp.ip=$ip
		else
			sed -i "/$i/d" /tmp/regvpn
		fi
	done < /tmp/regvpn
	[ "$(uci_get_by_name $NAME $NAME syslog)" == 1 ] && echolog "VPN list is updated."
	uci commit dhcp
	uci commit sysmonitor
	/etc/init.d/odhcpd restart
	/etc/init.d/dnsmasq reload
}

updatehost() {
	vpnlist=$(uci_get_by_name $NAME $NAME vpn '192.168.1.1')
	vpnip=$(uci_get_by_name $NAME $NAME vpnip)
	file='/tmp/regvpn'
	for i in $vpnlist
	do
		status=$(ping_url $i)
		if [ "$status" == 0 ]; then
			vpn=$(cat $file|grep $i)
			if [ ${vpn:0:1} == 0 ]; then
				touch /tmp/regvpn.sign
			else
				vpn1=$(echo $vpn|sed "s|-1-|-0-|g")
				vpn1='0'${vpn1:1}
				sed -i "s|$vpn|$vpn1|g" $file
				if [ "$vpnip" == $i ]; then
					touch /tmp/chkvpn.skip
					touch /tmp/sysmonitor
				fi
			fi
		fi
	done
}

updatevpn() {
	vpnlist=$(uci_get_by_name $NAME $NAME vpn '192.168.1.1')
	file='/tmp/regvpn'
	vpnupdate=0
	for i in $vpnlist
	do
		status=$(ping_url $i)
		if [ "$status" == 0 ]; then
			vpn=$(cat $file|grep $i)
			vpn1=$(echo $vpn|sed "s|-1-|-0-|g")
			vpn1='0'${vpn1:1}
			sed -i "s|$vpn|$vpn1|g" $file
			vpnupdate=1
		else
			echo '2-next_vpn'|netcat -nc $i 55556
		fi
	done
	touch /tmp/updatevpn
	if [ "$vpnupdate" == 1 ]; then
		touch /tmp/chkvpn.skip
		touch /tmp/sysmonitor
	fi
}

reg_ddns() {
	[ $(uci_get_by_name $NAME $NAME ddns 0) == 0 ] && exit
	[ -f /tmp/update_ddns ] && exit
	touch /tmp/update_ddns
	echoddns 'Update DDNS'
	echoddns '-------------------'
	ddns_num=$(cat /etc/config/sysmonitor|grep ddns_list|wc -l)
	num=0
	ipv4=$(curl -s http://members.3322.org/dyndns/getip)
	while (($num<$ddns_num))
	do
		iptype=$(uci get sysmonitor.@ddns_list[$num].iptype)
		hostname=$(uci get sysmonitor.@ddns_list[$num].hostname)
		url=$(uci get sysmonitor.@ddns_list[$num].url)
		username=$(uci get sysmonitor.@ddns_list[$num].username)
		password=$(uci get sysmonitor.@ddns_list[$num].password)
		if [ "$iptype" == 'ip6' ]; then
			getip=$(uci get sysmonitor.@ddns_list[$num].getip)
			ddns_ip='ipv6='$($getip)
		else
			ddns_ip='ipv4='$ipv4
		fi
		ddns_url='curl  -s  --connect-timeout 1 '$url'?hostname='$hostname'&my'$ddns_ip'&username='$username'&password='$password
		ddns_status=$($ddns_url)
		echoddns $hostname'='$ddns_status
		num=$((num+1))
	done
	echoddns '-------------------'
	rm /tmp/update_ddns
#	echo "90=$APP_PATH/sysapp.sh getddnsip" >> /tmp/delay.sign
}

getddnsip() {
	ddns_num=$(cat /etc/config/sysmonitor|grep ddns_list|wc -l)
	num=0
	while (($num<$ddns_num))
	do
		iptype=$(uci get sysmonitor.@ddns_list[$num].iptype)
		hostname=$(uci get sysmonitor.@ddns_list[$num].hostname)
		if [ "$iptype" == 'ip6' ]; then
			ipaddr=$(host 'ip6.'$hostname|grep IPv6|cut -d' ' -f5)
		else
			ipaddr=$(host $hostname|grep 'has address'|cut -d' ' -f4)
		fi
		uci set sysmonitor.@ddns_list[$num].ipaddr=$ipaddr
		num=$((num+1))
	done
	uci commit sysmonitor
}

arg1=$1
shift
case $arg1 in
reg_ddns)
	reg_ddns
	delay_prog reg_ddns
	;;
sysmenu)
	sysmenu $1 $2
	;;
sysbutton)
	sysbutton $1
	;;
chkvpn)
	chk_vpn
	delay_prog chkvpn
	;;
updatehost)
	updatehost
	delay_prog updatehost
	;;
updatevpn)
	updatevpn
	;;
getddnsip)
	getddnsip
	delay_prog getddnsip
	;;
firstrun)
	firstrun
	;;
close_vpn)
	close_vpn
	;;
setvpnip)
	setvpnip $1
	;;
setdns)
	setdns
	;;
getip)
	getip
	;;
getip6)
	getip6
	;;
gethost)
	gethost $1
	;;
ipsec)
	ipsec_users
	;;
pptp)
	pptp_users
	;;
wg)
	wg_users
	;;
reg_vpn)
	reg_vpn
	;;
regvpn)
	touch=0
	[ ! -f /tmp/regvpn ] && touch /tmp/regvpn
	file='/tmp/regvpn'
	name=$(echo $2|cut -d'=' -f2)
	regvpn=$1'-'$name
	cat $file | grep $regvpn >/dev/null
	[ ! $? -eq 0 ] && touch=1
	sed -i /$name/d $file
	echo '3'$1'-'$name >> $file
	sed -i '/^\s*$/d' $file
	echo "VPNHOST is registerd. IP="$1" Name="$name
	[ "$touch" == 1 ] && touch /tmp/regvpn.sign
	;;
sel_vpn)
	sel_vpn
	;;
service_dns)
	service_dns
	;;
service_smartdns)
	service_setdns SmartDNS
	;;
service_mosdns)
	service_setdns MosDNS
	;;
reload_dns)
	dns=$(uci get sysmonitor.sysmonitor.dns|tr A-Z a-z)
	[ ! $dns == "null" ] && service_dns
	;;
setddns)
	setddns
	;;
vpn)
	vpn
	;;
selvpn)
	selvpn $1
	;;
update_chnlist)
	update_chnlist
	;;
service_ddns)
	service_ddns
	;;
agh)
	agh
	;;
logup)
	status=$(cat $SYSLOG|grep "Download Firmware"|wc -l)
#	if [ "$status" == 0 ]; then
#		status=$(cat $SYSLOG|grep "Upgrade Firmware"|wc -l)
#	fi
	file="/usr/lib/lua/luci/view/sysmonitor/log.htm"
	sed -i "/cbi-button/d" $file
	redir='log'
	if [ ! -f /tmp/sysupgrade ]; then
	if [ "$status" != 0 ]; then
		sed -i "/user_fieldset/a\\\t<input class='cbi-button cbi-input-apply' type='button' onclick=location.href='sysmenu?sys=sysupgrade&sys1=-n&redir="$redir"' value='<%:Upgrade%>' />" $file
		sed -i "/user_fieldset/a\\\t<input class='cbi-button cbi-input-apply' type='button' onclick=location.href='sysmenu?sys=sysupgrade&sys1=-c&redir="$redir"' value='<%:Keeps%>' />" $file
		sed -i "/user_fieldset/a\\\t<input class='cbi-button cbi-input-apply' type='button' onclick=location.href='sysmenu?sys=stopdl&sys1=&redir="$redir"' value='<%:Stop%>' />" $file
		sed -i "/user_fieldset/a\\\t<input class='cbi-button cbi-input-apply' type='button' onclick=location.href='sysmenu?sys=firmware&sys1=&redir="$redir"' value='<%:Download%>' />" $file
#		sed -i "/user_fieldset/a\\\t<input class='cbi-button cbi-input-apply' type='button' onclick=location.href='sysmenu?sys=update&sys1=&redir="$redir"' value='<%:Upload%>' />" $file
	else
		sed -i "/user_fieldset/a\\\t<input class='cbi-button cbi-input-apply' type='button' onclick=location.href='sysmenu?sys=firmware&sys1=&redir="$redir"' value='<%:Download Firmware%>' />" $file
		sed -i "/user_fieldset/a\\\t<input class='cbi-button cbi-input-apply' type='button' onclick='clearlog()' name='clean log' value='<%:Clear logs%>' />" $file
	fi
	fi
	;;
chk_vpn)
	chk_vpn
	;;
killtmp)
	tmp=$(pgrep -f firstrun)
	[ -n "$tmp" ] && kill $tmp
	;;
chkprog)
	chk_prog
	chkprog=$(uci_get_by_name $NAME $NAME chkprog 60)
	echo $chkprog'='$APP_PATH'/sysapp.sh chkprog' >> /tmp/delay.sign
	;;
getdelay)
	getdelay $1 $2
	;;
*)
	echo "No <"$arg1"> function!"
	;;
esac
exit
