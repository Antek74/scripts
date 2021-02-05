#!/bin/bash
# PROVISIONING DHCPD statike by Ante K. 2014.
# V1.0 - 22.01.2014.
# V1.1 - 24.01.2014. - (manje je verbose na stdout-u)
# V1.2 - 27.01.2014. - (work folder, jos manje verbose)
# V1.3 - 27.01.2014. - (provjera unesenog agent IDa)
# V1.4 - 03.02.2014. - (bug fix - $DHCPD -t -cf !)
# V2.0 - 07.02.2014. - (zbog t-com dslam-a - promijeni IP gw, dodatne provjere)
# V2.1 - 11.02.2014. - (new ficur - pocisti lease file ako je bila spojena oprema)
# V2.2 - 05.03.2014. - (promjena provjere unosa passworda)
# V2.3 - 28.04.2014. - (promjena mail servera)
# V2.4 - 06.08.2014. - (kozmetika oko lock file-a - prikazi tko je pokrenuo provisioning)
# V2.5 - 07.08.2014. - (ignoriraj lock file istog usera)
# V3.0 - 03.05.2016. - (dodao VDSL BSA)
# V3.0.1 - 10.05.2016. - (bugfix)


trap ctrl_c INT

# AKO je TEST, komentiraj ROOT i WORK folder, LEASES, STOP daemona, slanje emaila

# env
#ROOT_FOLDER=/home/ante/skripte
ROOT_FOLDER=/etc/dhcpd-include
#WORK_FOLDER=/home/ante/skripte/work
WORK_FOLDER=/etc/dhcpd-include/work
#LEASES=/home/ante/skripte/dhcpd.leases
LEASES=/var/lib/dhcp/dhcpd.leases
ERRFILE=$WORK_FOLDER/.static-dhcp-err-file
CONF=$ROOT_FOLDER/bsa-voice.conf
DHCPD=/usr/sbin/dhcpd
DATE=$(date +%d.%m.%Y)
LOCKFILE=$WORK_FOLDER/.bsa-voice.conf.lock
LOG=$WORK_FOLDER/.bsa-voice.conf.log
SUDO=/usr/bin/sudo
# [root@host2]/etc/dhcpd-include# chmod 663 .

## rutine
# racunanje IPa
dec2ip () {
    local ipa dec=$@
    for e in {3..0}
    do
        ((octet = dec / (256 ** e) ))
        ((dec -= octet * 256 ** e))
        #ipa+=$delim$octet
        ipa="$ipa$delim$octet"
        delim=.
    done
    printf '%s\n' "$ipa"
}

ip2dec () {
    local a b c d ipb=$@
    IFS=. read -r a b c d <<< "$ipb"
    printf '%d\n' "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
}

ctrl_c() {
        echo -e "** Trapped CTRL-C\\nClearing lock file"; $SUDO /bin/rm $LOCKFILE; exit 1
}

available_ip() {
	local PROTO=$1
	local GRAD=$2
	# nadji sve trenutno zauzete adrese i stavi ih u polje
	IFS=$'\r\n' GPIPSF=($(grep "$PROTO.*\_$GRAD\_" $CONF | grep allow | sed s'/;.*/;/' | awk '{print $4}'))
	#echo "GPIPS je echo ${GPIPSF[@]}"
	#exit
	local IPNEXT=""
	for gpip in "${GPIPSF[@]}"; do
                        gpip=$(echo $gpip | sed 's/;//')
                        NEXTIP=$(dec2ip $(expr `ip2dec $gpip` + 1))
                        GREP=$(echo ${GPIPSF[@]} | grep "$NEXTIP;")
                        if [ "$GREP" == "" ] ; then
                                if [ "$IPNEXT" == "" -o `ip2dec $NEXTIP` -lt `ip2dec $IPNEXT` ] ; then
                                        IPNEXT="$NEXTIP"
                                fi
                        fi
        done
	echo "$IPNEXT"
	unset IFS
}

clean_leases() {
	local OPT=$1

	IFS=$'\r\n' START=($(grep -B 10 -n "$OPT" $LEASES | grep lease | cut -d"-" -f1))
	if [ ${#START[@]} -eq 0 ] ; then echo "ERR"; exit 1; fi
	# 
	IFS=$'\r\n' END=($(grep -A 3 -n "$OPT" $LEASES | grep "\-\}" | cut -d"-" -f1))

	for (( i = 0 ; i < ${#START[@]} ; i++ )); do
        	if [ $i -eq 0 ] ; then
	        RANGE="${START[$i]},${END[$i]}d"
	        else
	        RANGE="$RANGE;${START[$i]},${END[$i]}d"
	        fi
	done
	#vraca RANGE redova u lease fileu koje treba pobrisati (sed format)	
	echo "$RANGE"
}


#clear sudo
$SUDO -k
echo "Skripta koristi sudoers, unesi ssh password za pristup 10.60.60.50"
$SUDO echo "OK" 2 > /dev/null
if [ $? -ne 0 ] ; then echo "krivi password, obrati se na rnd@obfuscatedomain.hr za promjenu passworda"; exit 1; fi

#ERROR_ON_LAST_PROV=$(cat $ERRFILE)
if [ -e $ERRFILE ] ; then echo >&2 "prosli provisioning nije prosao - zovi upomoc" | tee -a $LOG; exit 1; fi
if [ -e $LOCKFILE ] ; then 
	#provjeri da li je lock file kreirao isti user
	LOCKER=`cat $LOCKFILE`
	if [ "$LOCKER" == "$LOGNAME" ] ; then
		read -r -p "izgleda kao da si paralelno ili prije pokrenuo provisioning, da li da nastavim? [y/N] : " response
		if [ "$response" != "y" ] ; then echo "Neuspjesan provisioning"; exit 1
		else
		# pobij sve ostale pokrenute provisioninge od istog usera
		pgrep dhcp-static | grep -v $$ | xargs kill
		fi
	else
		echo >&2 "trenutno je pokrenut provisioning od strane $LOCKER - pokusajte kasnije" | tee -a $LOG; exit 1 
	fi
fi
#$SUDO /bin/touch $LOCKFILE
$SUDO echo "$LOGNAME" > $LOCKFILE
if [[ $? -ne 0 ]] ; then printf "greska pri kreiranju .lock file-a "; echo "$LOGNAME" | tee $ERRFILE; exit 1; fi
if [ -e $LOG ] ; then $SUDO /bin/touch $LOG;
        if [ $? -ne 0 ] ; then echo -n "ne mogu kreirati LOG file\\nAborting"; exit 1; fi
fi




#### unos podataka

echo "upute za koristenje nalaze se ovdje: http://wiki/doku.php/mreze/usluge/siptrunk-bsa"

read -r -p "Shifra usluge (7-ero znamenkasti broj) : " SU
#SU=1231231
if [ ${#SU} -ne 7 ] ; then echo "Aborting"; $SUDO /bin/rm $LOCKFILE; exit 1; else echo "OK"; fi
#provjeri ima li te SU vec
CLASS=$(grep -A 2 $SU $CONF |  grep -B 2 '^class' | tail -1 | cut -d"\"" -f2)
if [ "$CLASS" != "" ] ; then 
	read -r -p "Shifra vec postoji ($CLASS), promijeniti IP adresu? [y/N] : " response
	if [ "$response" != "y" ] ; then 
		echo "Neuspjesan provisioning"; $SUDO /bin/rm $LOCKFILE; exit 1
	else
		# promijeni IP adresu za vec iskonfiguriranu SU
		PROTO=$(echo "$CLASS" | cut -d "_" -f1); echo "PROTO je $PROTO"
		GRAD=$(echo "$CLASS" | cut -d"_" -f3); echo "GRAD je $GRAD"
		CLASSIP=$(grep $CLASS $CONF | grep allow | sed s'/;.*//' | awk '{print $4}')
		echo "mijenjam IP: $CLASSIP postojecoj SU: $SU"
		IPNEXT=$(available_ip $PROTO $GRAD)
		OPT=$(grep $CLASS $CONF | grep class | cut -d"\"" -f4)
		echo "OPT je $OPT"
		#echo "IPNEXT za $CLASS je $IPNEXT"
		#provjera da li je na tom OPT-u vec nesto spojeno:
        	grep "$OPT" $LEASES > /dev/null
        	if [ $? -eq 0 ] ; then echo "vec postoji lease za taj agent ID"
                	echo -e "NE SMIJE SE SPAJATI OPREMA NA MODEM PRIJE PROVISIONINGA STATICKE ADRESE\\nhttp://wiki/doku.php/mreze/usluge/siptrunk-bsa"
                	read -r -p "Jesi li siguran da je na terenu otspojena sva oprema s LAN portova modema? [y/N] : " response
               		if [ "$response" != "y" ] ; then
                        	echo "Ponovi provisioning kada field iskopca opremu"; $SUDO /bin/rm $LOCKFILE; exit 1
                	else
                        	# pocisti lease file nakon sto stopiras dhcpd daemon
				echo "pocistit cu lease"
                        	LEASES_CLEAN="1"
                	fi
        	fi
	
	fi
else	#NOVA USLUGA, procitaj vrijednosti
	echo "Nova usluga"
	read -r -p "Protokol [H323/SIP] : " PROTO
	#PROTO="H323"
	if [ "$PROTO" = "H323" -o "$PROTO" = "SIP" ] ; then echo "OK"; else echo "Aborting"; $SUDO /bin/rm $LOCKFILE; exit 1; fi
	read -r -p "Regija [ZG/RI/OS/ST/VZ] : " GRAD
	#GRAD="ZG"
	if [ "$GRAD" = "ZG" -o "$GRAD" = "RI" -o "$GRAD" = "ST" -o "$GRAD" = "OS" -o "$GRAD" = "VZ" ] ; then echo "OK"; else echo "Aborting"; $SUDO /bin/rm $LOCKFILE; exit 1; fi
	if [ "$GRAD" = "VZ" -a "$PROTO" = "H323" ] ; then echo "U VZ SAMO SIP!"; echo "Aborting"; $SUDO /bin/rm $LOCKFILE; exit 1; fi
	read -r -p "Puni naziv korisnika [Ime firme d.o.o.] : " KOR
	#KOR="Firma ABC d.o.o."
	KORCLEAN="`echo "${KOR}" | tr -cd '[:alnum:] [:space:] [:punct:]'`"
	if [[ ! $KORCLEAN == $KOR ]] ; then echo -e "dozvoljeni znakovi A-Za-z0-9.&-_ \\nAborting"; $SUDO /bin/rm $LOCKFILE; exit 1; fi
	read -r -p "Adresa korisnika [Ulica, Grad]: " ADR
	#ADR="Ilica 1, Zagreb"
	ADRCLEAN="`echo "${ADR}" | tr -cd '[:alnum:] [:space:] [:punct:]'`"
	if [[ ! $ADRCLEAN == $ADR ]] ; then echo -e "dozvoljeni znakovi A-Za-z0-9.&-_ \\nAborting"; $SUDO /bin/rm $LOCKFILE; exit 1; fi
	read -r -p "puni agent ID (napr. dslam atm 0/1/0/4:0.50 ili dslam eth 0/1/0/4:3998) : " OPT
	#OPT="dslam atm 0/1/0/4:0.50"
	OPTCLEAN="`echo "${OPT}" | tr -cd '[:alnum:] [:space:] [:punct:]'`"
	if [[ ! $OPTCLEAN == $OPT ]] ; then echo -e "dozvoljeni znakovi A-Za-z0-9.&-_ \\nAborting"; $SUDO /bin/rm $LOCKFILE; exit 1; fi
	#provjera OPTa
	if [ ! "`echo "$OPTCLEAN" | sed s'/.*://'`" == "0.50"  ]; then
		if [ ! "`echo "$OPTCLEAN" | sed s'/.*://'`" == "3998"  ]; then 
		echo -e "neispravan agent ID\\nAborting"; $SUDO /bin/rm $LOCKFILE; exit 1
		fi
	fi
	#provjera da li je na tom OPT-u vec neka fiksna IP
	grep "$OPT" $CONF > /dev/null
	if [ $? -eq 0 ] ; then echo "vec postoji statika na tom agent IDu"; $SUDO /bin/rm $LOCKFILE; exit 1; fi
	#provjera da li je na tom OPT-u vec nesto spojeno:
	echo "provjera da li je na $OPT vec nesto spojeno"
	grep "$OPT" $LEASES > /dev/null
	if [ $? -eq 0 ] ; then echo "vec postoji lease za taj agent ID"
		echo -e "NE SMIJE SE SPAJATI OPREMA NA MODEM PRIJE PROVISIONINGA STATICKE ADRESE\\nhttp://wiki/doku.php/mreze/usluge/siptrunk-bsa"
		read -r -p "Jesi li siguran da je na terenu otspojena sva oprema s LAN portova modema? [y/N] : " response
  		if [ "$response" != "y" ] ; then
                	echo "Ponovi provisioning kada field iskopca opremu"; $SUDO /bin/rm $LOCKFILE; exit 1
		else
			# pocisti lease file nakon sto stopiras dhcpd daemon
			LEASES_CLEAN=1
		fi
	fi
fi


######## POSAO
#kreiram radni conf file
WORKING="$WORK_FOLDER/bsa-voice.working.`date +%Y%m%d%H%M%S`"
$SUDO cp $CONF $WORKING


if [ "$CLASS" == "" ] ; then # nova USLUGA
	# izvuci zadnji class za GRAD i PROTOKOL
	ZC=$(grep "$PROTO.*\_$GRAD\_" $CONF | tail -1 | cut -d"\"" -f2)
	# za ZC izvuci IP
	IPZC=$(grep "allow.*$ZC" $CONF | grep allow | awk '{print $4}' | sed s'/.$//')
	# izracunaj sljedecu slobodnu IP za IPZC
	# 
	IPNEXT=$(available_ip $PROTO $GRAD)
	#echo "$IPNEXT"
	# izracunaj sljedecu slobodnu classu
	#NC=$(echo $ZC | perl -pe 's/(\d+)/ $1+1 /ge') # ruzno :)
	#NC="$(echo ${ZC:0:-4}$(printf %04d $(expr ${ZC: -4} + 1)))" # ne radi na bash3
	NC="$(echo ${ZC%_**}_$(printf %04d $(expr ${ZC:0-4} + 1)))"
	#dodajem novu classu 
	sed -i -e "/class.*$ZC/ a\\\n# $KOR, $ADR # SU: $SU # $LOGNAME $DATE\\nclass \"$NC\" { match if option agent.circuit-id = \"$OPT\"; lease limit 1; }" $WORKING
	if [[ $? -ne 0 ]] ; then echo "greska pri sedanju u $WORKING"; echo "$LOGNAME" > $ERRFILE; $SUDO /bin/rm $LOCKFILE; exit 1; fi
	#dodajem novi static lease
	sed -i -e "/allow.*$ZC/ a\\\tpool { range $IPNEXT\; allow members of \"$NC\"\; }" $WORKING
	if [[ $? -ne 0 ]] ; then echo "greska pri sedanju u $WORKING"; echo "$LOGNAME" > $ERRFILE; $SUDO /bin/rm $LOCKFILE; exit 1; fi
	#dodajem novi deny members
	sed -i -e "/deny.*$ZC/ a\\\t\\tdeny members of \"$NC\"\;" $WORKING
	if [[ $? -ne 0 ]] ; then echo "greska pri sedanju u $WORKING"; echo "$LOGNAME" > $ERRFILE; $SUDO /bin/rm $LOCKFILE; exit 1; fi
else
	# PROMJENA IP
	sed  -i -e "s/$CLASSIP/$IPNEXT/" $WORKING
	if [[ $? -ne 0 ]] ; then echo "greska pri sedanju u $WORKING"; echo "$LOGNAME" > $ERRFILE; $SUDO /bin/rm $LOCKFILE; exit 1; fi
fi

# WORKING CONFA GOTOVA, NAPRAVI PROVJERE, BACKUP I RESTART DAEMONA

printf "OK, radim provjeru promjene (PRICEKAJ trenutak)... \n$DHCPD -t -cf $WORKING \n\n"
$DHCPD -t -cf $WORKING 2> /dev/null
if [[ $? -ne 0 ]] ; then printf "greska pri provjeri nove konfe $WORKING - neuspjesan provisioning - zovi upomoc"; echo "$LOGNAME" | tee $ERRFILE; $SUDO /bin/rm $LOCKFILE; exit 1; fi
echo -e "$DATE USER: $LOGNAME je iskreirao uredan $WORKING sa parametrima:\\n$PROTO - $GRAD - $SU - $KOR - $ADR - $OPT" >> $LOG

#echo "backupiram $CONF" 
BACKUP=$CONF.backup.`date +%Y%m%d%H%M%S`
$SUDO /bin/cp $CONF $BACKUP
if [[ $? -ne 0 ]] ; then printf "greska pri backupiranju confe u $BACKUP - neuspjesan provisioning - zovi upomoc";  echo "$LOGNAME" > $ERRFILE; exit 1; fi
echo "doing cp $CONF $BACKUP" >> $LOG


#<<"COMMENT"
echo "doing /etc/init.d/dhcpd stop"
$SUDO /etc/init.d/dhcpd stop 
# error handling:
if [[ $? -ne 0 ]] ; then echo -e "$DATE USER: $LOGNAME greska pri stopiranju dhcpd daemona - zovi upomoc" | tee -a $LOG
	echo "$LOGNAME" > $ERRFILE; $SUDO /bin/rm $LOCKFILE; exit 1; 
fi

# DHCPD down OK
echo "doing cp $WORKING $CONF" | tee -a $LOG
$SUDO /bin/cp $WORKING $CONF
# error handling:
if [[ $? -ne 0 ]] ; then echo "greska pri kopiranju $WORKING u $CONF, pokusavam pokrenuti dhcpd sa starom konfom" | tee -a $LOG
	$SUDO /etc/init.d/dhcpd start
	if [[ $? -ne 0 ]] ; then echo -e "PANIC - DHCPD down - call DC dezurni" | tee -a $LOG; echo "$LOGNAME" > $ERRFILE; exit 1; fi
	exit 1 
fi

# pocisti leases file ako treba
if [ "$LEASES_CLEAN" == "1" ] ; then 
	echo "LEASES_CLEAN je $LEASES_CLEAN. Pocisti..."
	LEASESBACKUP=$LEASES.backup.`date +%Y%m%d%H%M%S`
	echo "doing cp $LEASES $LEASESBACKUP" | tee -a $LOG
	$SUDO /bin/cp $LEASES $LEASESBACKUP
	# error handling:
	if [[ $? -ne 0 ]] ; then echo "greska pri bekapiranju $LEASES u $LEASESBACKUP - neuspjesan provisioning - zovi upomoc";  echo "$LOGNAME" > $ERRFILE; exit 1; fi
	RANGEDELETE=$(clean_leases "$OPT")
	echo "RANGEDELETE je $RANGEDELETE."
	#echo "$SUDO /bin/sed -i.bak.`date +%Y%m%d%H%M%S` -e '$RANGEDELETE' $LEASES" | tee -a $LOG
	echo "$SUDO /bin/sed -i -e \"$RANGEDELETE\" $LEASES"
	$SUDO /bin/sed -i -e "$RANGEDELETE" $LEASES
	#error handling:
	if [[ $? -ne 0 ]] ; then echo "greska pri ciscenju lease filea - neuspjesan provisioning - zovi upomoc" | tee -a $LOG; echo "$LOGNAME" > $ERRFILE; exit 1; fi	
	echo "Pocistio lease file"	
	#$SUDO /bin/rm $LOCKFILE; exit 1
fi

# novi conf file kreiran, startam DHCPD
echo "Please wait...(startam server)"
$SUDO /etc/init.d/dhcpd start
# error handling:
if [[ $? -ne 0 ]] ; then echo -e "$DATE USER: $LOGNAME neuspjesno dizanje dhcpda sa novom konfom" | tee -a $LOG 
	echo "Pokusavam vratiti backup i dici DHCPD" | tee -a $LOG
	$SUDO /bin/cp $BACKUP $CONF
	$SUDO /etc/init.d/dhcpd start
	if [[ $? -ne 0 ]] ; then echo -e "PANIC - DHCPD down - call DC dezurni" | tee -a $LOG; echo "$LOGNAME" > $ERRFILE
	echo -e "$LOGNAME je skrsio DHCPD server ( $LEASESBACKUP $BACKUP )" | /usr/bin/sendEmail -s maily.obfuscatedomain.local -u DHCPd_down  -t rnd@obfuscatedomain.hr -f rnd@obfuscatedomain.hr > /dev/null
	exit 1; fi
fi

echo "Uspjesno startan DHCPD server s $WORKING konfom" | tee -a $LOG


#COMMENT

echo "Dodjeljena IP adresa $IPNEXT je aktivna!"  | tee -a $LOG; $SUDO /bin/rm $LOCKFILE
echo "#######################################################################" >> $LOG

echo -e "$LOGNAME je dodao korisnika $KOR, $ADR, $SU ($PROTO - $GRAD)\\nIP je $IPNEXT" | /usr/bin/sendEmail -s maily.obfuscatedomain.local -u Nova_statika_na_DHCPu  -t rnd@obfuscatedomain.hr -f rnd@obfuscatedomain.hr > /dev/null
