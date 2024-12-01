#!/bin/bash

[ -f /tmp/chkvpn.run ] && exit
[ ! -f /tmp/chkvpn.pid ] && echo 0 >/tmp/chkvpn.pid
[ "$(cat /tmp/chkvpn.pid)" != 0 ] && exit

touch /tmp/chkvpn.run
NAME=sysmonitor
APP_PATH=/usr/share/$NAME
SYSLOG='/var/log/sysmonitor.log'

echolog() {
	local d="$(date "+%Y-%m-%d %H:%M:%S")"
	echo -e "$d: $*" >>$SYSLOG
	number=$(cat $SYSLOG|wc -l)
	[ $number -gt 25 ] && sed -i '1,10d' $SYSLOG
}

uci_get_by_name() {
	local ret=$(uci get $1.$2.$3 2>/dev/null)
	echo ${ret:=$4}
}

uci_set_by_name() {
	uci set $1.$2.$3=$4 2>/dev/null
	uci commit $1
}

sys_exit() {
	#echolog "chkVPN is off."
	[ -f /tmp/chkvpn.run ] && rm -rf /tmp/chkvpn.run
	syspid=$(cat /tmp/chkvpn.pid)
	syspid=$((syspid-1))
	echo $syspid > /tmp/chkvpn.pid
	exit 0
}

chk_sign() {
	if [ -f /tmp/$1 ]; then
		rm -rf /tmp/$1
		$APP_PATH/sysapp.sh $2 &
	fi
}

run_prog() {
echo "" >/tmp/delay.sign
echo "" >/tmp/delay.list
prog_num=$(cat /etc/config/sysmonitor|grep prog_list|wc -l)
num=0
while (($num<$prog_num))
do
	program=$(uci_get_by_name $NAME @prog_list[$num] program)
	path=$(uci_get_by_name $NAME @prog_list[$num] path "/usr/share/sysmonitor/sysapp.sh")
	enabled=$(uci_get_by_name $NAME @prog_list[$num] enabled 0)
	status=$(cat /tmp/delay.list|grep $program|wc -l)
	if [ "$status" == 0 ]; then
		cycle=$(uci_get_by_name $NAME @prog_list[$num] first 100)
		enabled=$(uci_get_by_name $NAME @prog_list[$num] enabled 0)
		[ "$enabled" == 1 ] && echo $cycle'='$path' '$program >> /tmp/delay.sign
	else	
		[ "$enabled" == 0 ] && sed -i "/$program/d" /tmp/delay.list
	fi
	num=$((num+1))
done
echo '10=/usr/share/sysmonitor/sysapp.sh killtmp' >> /tmp/delay.sign
echo "20=ntpd -n -q -p ntp.aliyun.com" >> /tmp/delay.sign
echo '60='$APP_PATH'/sysapps.sh chkprog' >> /tmp/delay.list
[ -f /tmp/firstrun ] && rm /tmp/firstrun
}

update_regvpn() {
	file='/tmp/regvpn'
	touch=0
	while read i
	do
		num=${i:0:1}
		let num=num-1
		if [ "$num" -le 0 ]; then
			sed -i /${i:1}/d $file
			touch=1
		else
			sed -i "s|$i|$num${i:1}|g" $file
			vpnname=$(gethost $(echo ${i:1}|cut -d'-' -f1))
			name=$(echo ${i:1}|cut -d'-' -f2)
			[ "$name" != $vpnname ] && touch=1
		fi
	done < /tmp/regvpn
	[ "$touch" == 1 ] && touch /tmp/regvpn.sign
}

#echolog "chkVPN is on."
syspid=$(cat /tmp/chkvpn.pid)
syspid=$((syspid+1))
echo $syspid > /tmp/chkvpn.pid
chknum=0
chksys=0
regvpn_num=0
while [ "1" == "1" ]; do
	chknum=$((chknum+1))
	regvpn_num=$((regvpn_num+1))
	if [ -f /tmp/updatevpn ]; then
		rm /tmp/updatevpn
		regvpn_num=61
	fi	
	if [ "$regvpn_num" -ge 60 ]; then
		regvpn_num=0
		update_regvpn
	fi
	touch /tmp/test.chkvpn
	prog='sysmonitor'
	for i in $prog
	do
		progsh=$i'.sh'
		progpid='/tmp/'$i'.pid'
		[ "$(pgrep -f $progsh|wc -l)" == 0 ] && echo 0 > $progpid
		[ ! -f $progpid ] && echo 0 > $progpid
		arg=$(cat $progpid)
		case $arg in
			0)
				pid_arg=$(pgrep -f $progsh|wc -l)
				if [ "$pid_arg" == 0 ]; then
					chksys=0
					chknum=0	
					progrun='/tmp/'$i'.run'
					[ -f $progrun ] && rm $progrun
					[ -f $progpid ] && rm $progpid
					$APP_PATH/$progsh &	
				elif [ "$pid_arg" == 1 ]; then
					echo $pid_arg > $progpid
				else
					echolog "Sysmonitor.pid=0."
					killall $progsh
				fi
				;;
			1)
				chksys=0
				#if [ "$i" == "sysmonitor" ] && [ "$chknum" -ge 60 ]; then
				check_test=$(uci_get_by_name $NAME $NAME chktest 120)
				if [ "$chknum" -ge $chk_test ]; then
					chknum=0
					if [ ! -f /tmp/test.$i ]; then
						echolog "Sysmonitor is not work."
						killall $progsh
					else
						rm /tmp/test.$i	
					fi
				fi
				;;
			*)
				chksys=$((chksys+1))
				check_sys=$(uci_get_by_name $NAME $NAME chksys 300)
				if [ "$chksys" -ge $check_sys ]; then
					echolog "Sysmonitor is more."
					killall $progsh
					echo 0 > $progpid
					chksys=0
				fi
				;;
		esac
	done
	if [ -f /tmp/firstrun ]; then
		run_prog
	else
		[ $(cat /tmp/delay.list|grep chkprog|wc -l) == 0 ] && $APP_PATH/sysapp.sh chkprog
	fi
	if [ -f /tmp/delay.sign ]; then
		while read i
		do
			prog=$(echo $i|cut -d'=' -f2)
			[ -n $(echo $prog|cut -d' ' -f2) ] && prog=$(echo $prog|cut -d' ' -f2)
			sed -i "/$prog/d" /tmp/delay.list
			echo $i >> /tmp/delay.list
		done < /tmp/delay.sign
		rm /tmp/delay.sign
	fi
	if [ -f /tmp/delay.list ]; then
		touch /tmp/delay.tmp
		while read line
		do
   			num=$(echo $line|cut -d'=' -f1)
			prog=$(echo $line|cut -d'=' -f2-)
			if [ "$num" -gt 0 ];  then
				num=$((num-1))
				tmp=$num'='$prog
				echo $tmp >> /tmp/delay.tmp
			else
			[ "$num" == 0 ] && $prog &
			fi
		done < /tmp/delay.list
		mv /tmp/delay.tmp /tmp/delay.list	
	fi
	[ ! -n "$(pgrep -f next_vpn)" ] && [ -f /tmp/next_vpn.run ] && rm /tmp/next_vpn.run
	[ -f /etc/init.d/lighttpd ] && [ ! -n "$(pgrep -f lighttpd)" ] && {
		/etc/init.d/uhttpd stop
		echo '1-/etc/init.d/lighttpd start' >> /tmp/delay.sign
		echo '2-/etc/init.d/uhttpd start' >> /tmp/delay.sign
		}
	chk_sign regvpn.sign reg_vpn
	[ ! -f /tmp/chkvpn.run ] && sys_exit
	[ "$(cat /tmp/chkvpn.pid)" -gt 1 ] && sys_exit
	sleep 1
done
