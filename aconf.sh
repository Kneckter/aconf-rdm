#!/system/bin/sh
# version 1.6.2

#Version checks
Ver55aconf="1.0"
Ver55cron="1.0"

export ANDROID_DATA=/data
export ANDROID_ROOT=/system

#Create logfile
if [ ! -e /sdcard/aconf.log ] ;then
    /system/bin/touch /sdcard/aconf.log
fi

logfile="/sdcard/aconf.log"
aconf="/data/local/tmp/config.json"
aconf_versions="/data/local/aconf_versions"
[[ -f /data/local/aconf_download ]] && aconf_download=$(/system/bin/grep url /data/local/aconf_download | awk -F "=" '{ print $NF }')
[[ -f /data/local/aconf_download ]] && aconf_user=$(/system/bin/grep authUser /data/local/aconf_download | awk -F "=" '{ print $NF }')
[[ -f /data/local/aconf_download ]] && aconf_pass=$(/system/bin/grep authPass /data/local/aconf_download | awk -F "=" '{ print $NF }')
if [[ -f /data/local/tmp/config.json ]] ;then
    origin=$(/system/bin/cat $aconf | /system/bin/tr , '\n' | /system/bin/grep -w 'device_name' | awk -F "\"" '{ print $4 }')
else
    origin=$(/system/bin/cat /data/local/initDName)
fi

# stderr to logfile
exec 2>> $logfile

# add aconf.sh command to log
echo "" >> $logfile
echo "`date +%Y-%m-%d_%T` ## Executing $(basename $0) $@" >> $logfile


########## Functions

reboot_device(){
    echo "`date +%Y-%m-%d_%T` Reboot device" >> $logfile
    sleep 60
    /system/bin/reboot
}

case "$(uname -m)" in
    aarch64) arch="arm64-v8a";;
    armv8l)  arch="armeabi-v7a";;
esac

install_mitm(){
    # install 55aconf
    until $download /system/etc/init.d/55aconf $aconf_download/55aconf || { echo "`date +%Y-%m-%d_%T` Download 55aconf failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x /system/etc/init.d/55aconf
    echo "`date +%Y-%m-%d_%T` 55aconf installed, from egg" >> $logfile

    # install 55cron
    until /system/bin/curl -s -k -L --fail --show-error -o  /system/etc/init.d/55cron https://raw.githubusercontent.com/Kneckter/aconf-rdm/eggs/55cron || { echo "`date +%Y-%m-%d_%T` Download 55cron failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x /system/etc/init.d/55cron
    echo "`date +%Y-%m-%d_%T` 55cron installed, from egg" >> $logfile

    # install cron job
    until /system/bin/curl -s -k -L --fail --show-error -o  /system/bin/ping_test.sh https://raw.githubusercontent.com/Kneckter/aconf-rdm/eggs/ping_test.sh || { echo "`date +%Y-%m-%d_%T` Download ping_test.sh failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x /system/bin/ping_test.sh
    mkdir /system/etc/crontabs || true
    touch /system/etc/crontabs/root
    echo "15 * * * * /system/bin/ping_test.sh" > /system/etc/crontabs/root
    crond -b

    # get version
    aversions=$(/system/bin/grep 'mitm' $aconf_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')

    # download mitm
    /system/bin/rm -f /sdcard/Download/mitm.apk
    until $download /sdcard/Download/mitm.apk $aconf_download/com.exeggcute.launcher_$aversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/mitm.apk $aconf_download/com.exeggcute.launcher_$aversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download mitm failed, exit script" >> $logfile ; exit 1; } ;do
      sleep 2
    done

    # let us kill pogo as well and clear data
    /system/bin/am force-stop com.nianticlabs.pokemongo
    /system/bin/pm clear com.nianticlabs.pokemongo

    # Install mitm
    settings put global package_verifier_user_consent -1
    /system/bin/pm install -r /sdcard/Download/mitm.apk
    /system/bin/rm -f /sdcard/Download/mitm.apk
    echo "`date +%Y-%m-%d_%T` mitm installed" >> $logfile

    # Grant su access + settings
    auid="$(dumpsys package com.gocheats.launcher | /system/bin/grep userId | awk -F'=' '{print $2}')"
    magisk --sqlite "DELETE from policies WHERE package_name='com.gocheats.launcher'"
    magisk --sqlite "INSERT INTO policies (uid,package_name,policy,until,logging,notification) VALUES($auid,'com.gocheats.launcher',2,0,1,0)"
    /system/bin/pm grant com.gocheats.launcher android.permission.READ_EXTERNAL_STORAGE
    /system/bin/pm grant com.gocheats.launcher android.permission.WRITE_EXTERNAL_STORAGE
    echo "`date +%Y-%m-%d_%T` mitm granted su and settings set" >> $logfile

    # download mitm config file and adjust orgin to rgc setting
    install_config

    # start mitm
    /system/bin/monkey -p com.gocheats.launcher 1
    sleep 15

    # Set for reboot device
    reboot=1
}

install_config(){
    until $download /data/local/tmp/config.json $aconf_download/exeggcute_config.json || { echo "`date +%Y-%m-%d_%T` $download /data/local/tmp/config.json $aconf_download/exeggcute_config.json" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download mitm config file failed, exit script" >> $logfile ; exit 1; } ;do
      sleep 2
    done
    /system/bin/sed -i 's,dummy,'$origin',g' $aconf
    echo "`date +%Y-%m-%d_%T` mitm config installed, deviceName $origin"  >> $logfile
}

update_all(){
    pinstalled=$(dumpsys package com.nianticlabs.pokemongo | /system/bin/grep versionName | head -n1 | /system/bin/sed 's/ *versionName=//')
    pversions=$(/system/bin/grep 'pogo' $aconf_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
    ainstalled=$(dumpsys package com.gocheats.launcher | /system/bin/grep versionName | head -n1 | /system/bin/sed 's/ *versionName=//')
    aversions=$(/system/bin/grep 'mitm' $aconf_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')

    if [[ $pinstalled != $pversions ]] ;then
      echo "`date +%Y-%m-%d_%T` New pogo version detected, $pinstalled=>$pversions" >> $logfile
      /system/bin/rm -f /sdcard/Download/pogo.apk
      until /system/bin/curl -s -k -L --fail --show-error -o /sdcard/Download/pogo.apk https://mirror.unownhash.com/apks/com.nianticlabs.pokemongo_$arch\_$pversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apk https://mirror.unownhash.com/apks/com.nianticlabs.pokemongo_$arch\_$pversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
      done
      # set pogo to be installed
      pogo_install="install"
    else
     pogo_install="skip"
     echo "`date +%Y-%m-%d_%T` PoGo already on correct version" >> $logfile
    fi

    if [ v$ainstalled != $aversions ] ;then
      echo "`date +%Y-%m-%d_%T` New mitm version detected, $ainstalled=>$aversions" >> $logfile
      /system/bin/rm -f /sdcard/Download/mitm.apk
      until $download /sdcard/Download/mitm.apk $aconf_download/com.exeggcute.launcher_$aversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/mitm.apk $aconf_download/com.exeggcute.launcher_$aversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download mitm failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
      done
      # set mitm to be installed
      mitm_install="install"
    else
     mitm_install="skip"
     echo "`date +%Y-%m-%d_%T` mitm already on correct version" >> $logfile
    fi

    if [ ! -z "$mitm_install" ] && [ ! -z "$pogo_install" ] ;then
      echo "`date +%Y-%m-%d_%T` All updates checked and downloaded if needed" >> $logfile
      settings put global package_verifier_user_consent -1
      if [ "$mitm_install" = "install" ] ;then
        echo "`date +%Y-%m-%d_%T` Updating mitm" >> $logfile
        # install mitm
        /system/bin/pm install -r /sdcard/Download/mitm.apk || { echo "`date +%Y-%m-%d_%T` Install mitm failed, downgrade perhaps? Exit script" >> $logfile ; exit 1; }
        /system/bin/rm -f /sdcard/Download/mitm.apk
        reboot=1
      fi
      if [ "$pogo_install" = "install" ] ;then
        echo "`date +%Y-%m-%d_%T` Updating pogo" >> $logfile
        # install pogo
        /system/bin/pm install -r /sdcard/Download/pogo.apk || { echo "`date +%Y-%m-%d_%T` Install pogo failed, downgrade perhaps? Exit script" >> $logfile ; exit 1; }
        /system/bin/rm -f /sdcard/Download/pogo.apk
        reboot=1
      fi
      if [ "$mitm_install" != "install" ] && [ "$pogo_install" != "install" ] ; then
        echo "`date +%Y-%m-%d_%T` Updates checked, nothing to install" >> $logfile
        /system/bin/am force-stop com.gocheats.launcher
        /system/bin/monkey -p com.gocheats.launcher 1
        echo "`date +%Y-%m-%d_%T` Started mitm" >> $logfile
      fi
    fi
}

########## Execution

#wait on internet
until ping -c1 8.8.8.8 >/dev/null 2>/dev/null || ping -c1 1.1.1.1 >/dev/null 2>/dev/null; do
    sleep 10
done
echo "`date +%Y-%m-%d_%T` Internet connection available" >> $logfile


#download latest aconf.sh
if [[ $(basename $0) != "aconf_new.sh" ]] ;then
    oldsh=$(head -2 /system/bin/aconf.sh | /system/bin/grep '# version' | awk '{ print $NF }')
    until /system/bin/curl -s -k -L --fail --show-error -o /system/bin/aconf_new.sh https://raw.githubusercontent.com/Kneckter/aconf-rdm/eggs/aconf.sh || { echo "`date +%Y-%m-%d_%T` Download aconf.sh failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x /system/bin/aconf_new.sh
    newsh=$(head -2 /system/bin/aconf_new.sh | /system/bin/grep '# version' | awk '{ print $NF }')
    if [[ $oldsh != $newsh ]] ;then
        echo "`date +%Y-%m-%d_%T` aconf.sh $oldsh=>$newsh, restarting script" >> $logfile
        cp /system/bin/aconf_new.sh /system/bin/aconf.sh
        /system/bin/aconf_new.sh $@
        exit 1
    fi
fi

# verify download credential file and set download
if [[ ! -f /data/local/aconf_download ]] ;then
    echo "`date +%Y-%m-%d_%T` File /data/local/aconf_download not found, exit script" >> $logfile && exit 1
else
    if [[ $aconf_user == "" ]] ;then
        download="/system/bin/curl -s -k -L --fail --show-error -o"
    else
        download="/system/bin/curl -s -k -L --fail --show-error --user $aconf_user:$aconf_pass -o"
    fi
fi

# download latest version file
until $download $aconf_versions $aconf_download/aconf_versions || { echo "`date +%Y-%m-%d_%T` $download $aconf_versions $aconf_download/aconf_versions" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download aconf versions file failed, exit script" >> $logfile ; exit 1; } ;do
    sleep 2
done
dos2unix $aconf_versions
echo "`date +%Y-%m-%d_%T` Downloaded latest aconf_versions file"  >> $logfile

#update 55aconf if needed
if [[ $(basename $0) = "aconf_new.sh" ]] ;then
    old55=$(head -2 /system/etc/init.d/55aconf | /system/bin/grep '# version' | awk '{ print $NF }')
    if [ $Ver55aconf != $old55 ] ;then
        until /system/bin/curl -s -k -L --fail --show-error -o /system/etc/init.d/55aconf https://raw.githubusercontent.com/Kneckter/aconf-rdm/eggs/55aconf || { echo "`date +%Y-%m-%d_%T` Download 55aconf failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
        done
        chmod +x /system/etc/init.d/55aconf
        new55=$(head -2 /system/etc/init.d/55aconf | /system/bin/grep '# version' | awk '{ print $NF }')
        echo "`date +%Y-%m-%d_%T` 55aconf $old55=>$new55" >> $logfile
    fi
fi

#update 55cron if needed
if [[ $(basename $0) = "aconf_new.sh" ]] ;then
    old55=$(head -2 /system/etc/init.d/55cron || echo "# version 0.0" | /system/bin/grep '# version' | awk '{ print $NF }')
    if [ $Ver55cron != $old55 ] ;then
        # install 55cron
        until /system/bin/curl -s -k -L --fail --show-error -o  /system/etc/init.d/55cron https://raw.githubusercontent.com/Kneckter/aconf-rdm/eggs/55cron || { echo "`date +%Y-%m-%d_%T` Download 55cron failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
        done
        chmod +x /system/etc/init.d/55cron
        echo "`date +%Y-%m-%d_%T` 55cron installed, from egg" >> $logfile

        # install cron job
        until /system/bin/curl -s -k -L --fail --show-error -o  /system/bin/ping_test.sh https://raw.githubusercontent.com/Kneckter/aconf-rdm/eggs/ping_test.sh || { echo "`date +%Y-%m-%d_%T` Download ping_test.sh failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
        done
        chmod +x /system/bin/ping_test.sh
        mkdir /system/etc/crontabs || true
        touch /system/etc/crontabs/root
        echo "15 * * * * /system/bin/ping_test.sh" > /system/etc/crontabs/root
        crond -b
        new55=$(head -2 /system/etc/init.d/55cron | /system/bin/grep '# version' | awk '{ print $NF }')
        echo "`date +%Y-%m-%d_%T` 55cron $old55=>$new55" >> $logfile
    fi
fi

# prevent aconf causing reboot loop. Add bypass ??
if [ $(/system/bin/cat /sdcard/aconf.log | /system/bin/grep `date +%Y-%m-%d` | /system/bin/grep rebooted | wc -l) -gt 20 ] ;then
    echo "`date +%Y-%m-%d_%T` Device rebooted over 20 times today, aconf.sh signing out, see you tomorrow"  >> $logfile
    exit 1
fi

# set hostname = origin, wait till next reboot for it to take effect
if [[ $origin != "" ]] ;then
    if [ $(/system/bin/cat /system/build.prop | /system/bin/grep net.hostname | wc -l) = 0 ]; then
        echo "`date +%Y-%m-%d_%T` No hostname set, setting it to $origin" >> $logfile
        echo "net.hostname=$origin" >> /system/build.prop
    else
        hostname=$(/system/bin/grep net.hostname /system/build.prop | awk 'BEGIN { FS = "=" } ; { print $2 }')
        if [[ $hostname != $origin ]] ;then
            echo "`date +%Y-%m-%d_%T` Changing hostname, from $hostname to $origin" >> $logfile
            /system/bin/sed -i -e "s/^net.hostname=.*/net.hostname=$origin/g" /system/build.prop
        fi
    fi
fi

# check mitm config file exists
if [[ -d /data/data/com.gocheats.launcher ]] && [[ ! -s $aconf ]] ;then
    install_config
    /system/bin/am force-stop com.gocheats.launcher
    /system/bin/monkey -p com.gocheats.launcher 1
fi

for i in "$@" ;do
    case "$i" in
        -ia) install_mitm ;;
        -ic) install_config ;;
        -ua) update_all ;;
    esac
done

(( $reboot )) && reboot_device
exit
