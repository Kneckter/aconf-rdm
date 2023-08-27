#!/system/bin/sh
# version 1.4.8

#Version checks
Ver55atlas="1.0"
Ver55cron="1.0"

export ANDROID_DATA=/data
export ANDROID_ROOT=/system

#Create logfile
if [ ! -e /sdcard/aconf.log ] ;then
    /system/bin/touch /sdcard/aconf.log
fi

logfile="/sdcard/aconf.log"
aconf="/data/local/tmp/atlas_config.json"
aconf_versions="/data/local/aconf_versions"
[[ -f /data/local/aconf_download ]] && aconf_download=$(/system/bin/grep url /data/local/aconf_download | awk -F "=" '{ print $NF }')
[[ -f /data/local/aconf_download ]] && aconf_user=$(/system/bin/grep authUser /data/local/aconf_download | awk -F "=" '{ print $NF }')
[[ -f /data/local/aconf_download ]] && aconf_pass=$(/system/bin/grep authPass /data/local/aconf_download | awk -F "=" '{ print $NF }')
if [[ -f /data/local/tmp/atlas_config.json ]] ;then
    origin=$(/system/bin/cat $aconf | /system/bin/tr , '\n' | /system/bin/grep -w 'deviceName' | awk -F "\"" '{ print $4 }')
else
    origin=$(/system/bin/cat /data/local/initDName)
fi

# stderr to logfile
exec 2>> $logfile

# add atlas.sh command to log
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

install_atlas(){
    # install 55atlas
    mount -o remount,rw /system
    mount -o remount,rw /system/etc/init.d > /dev/null 2>&1 || true
    until $download /system/etc/init.d/55atlas $aconf_download/55atlas || { echo "`date +%Y-%m-%d_%T` Download 55atlas failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x /system/etc/init.d/55atlas
    echo "`date +%Y-%m-%d_%T` 55atlas installed, from master" >> $logfile

    # install 55cron
    until /system/bin/curl -s -k -L --fail --show-error -o  /system/etc/init.d/55cron https://raw.githubusercontent.com/Kneckter/aconf-rdm/master/55cron || { echo "`date +%Y-%m-%d_%T` Download 55cron failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x /system/etc/init.d/55cron
    echo "`date +%Y-%m-%d_%T` 55cron installed, from master" >> $logfile

    # install cron job
    until /system/bin/curl -s -k -L --fail --show-error -o  /system/bin/ping_test.sh https://raw.githubusercontent.com/Kneckter/aconf-rdm/master/ping_test.sh || { echo "`date +%Y-%m-%d_%T` Download ping_test.sh failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x /system/bin/ping_test.sh
    mkdir /system/etc/crontabs || true
    touch /system/etc/crontabs/root
    echo "15 * * * * /system/bin/ping_test.sh" > /system/etc/crontabs/root
    crond -b

    # Remove any old MAD files
    /system/bin/rm -rf /data/local/madromlogs /system/etc/init.d/01madbootstrap /system/etc/init.d/01bootstrap /system/etc/init.d/42mad /system/etc/init.d/16mad /system/bin/update_mad.sh /storage/emulated/0/madversion /system/etc/init.d/41atlas /data/local/tmp/41atlas*.log /sdcard/eMagisk.zip /sdcard/magisk_repackage /sdcard/*gapps*

    mount -o remount,ro /system

    # get version
    aversions=$(/system/bin/grep 'atlas' $aconf_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')

    # download atlas
    /system/bin/rm -f /sdcard/Download/atlas.apk
    until $download /sdcard/Download/atlas.apk $aconf_download/PokemodAtlas-Public-$aversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/atlas.apk $aconf_download/PokemodAtlas-Public-$aversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download atlas failed, exit script" >> $logfile ; exit 1; } ;do
      sleep 2
    done

    # let us kill pogo as well and clear data
    /system/bin/am force-stop com.nianticlabs.pokemongo
    /system/bin/pm clear com.nianticlabs.pokemongo

    # Install atlas
    /system/bin/pm install -r /sdcard/Download/atlas.apk
    /system/bin/rm -f /sdcard/Download/atlas.apk
    echo "`date +%Y-%m-%d_%T` atlas installed" >> $logfile

    # Grant su access + settings
    auid="$(dumpsys package com.pokemod.atlas | /system/bin/grep userId | awk -F'=' '{print $2}')"
    magisk --sqlite "DELETE from policies WHERE package_name='com.pokemod.atlas'"
    magisk --sqlite "INSERT INTO policies (uid,package_name,policy,until,logging,notification) VALUES($auid,'com.pokemod.atlas',2,0,1,0)"
    /system/bin/pm grant com.pokemod.atlas android.permission.READ_EXTERNAL_STORAGE
    /system/bin/pm grant com.pokemod.atlas android.permission.WRITE_EXTERNAL_STORAGE
    echo "`date +%Y-%m-%d_%T` atlas granted su and settings set" >> $logfile

    # download atlas config file and adjust orgin to rgc setting
    install_config

    # check pogo version else remove+install
    downgrade_pogo

    # start atlas
    /system/bin/am startservice com.pokemod.atlas/com.pokemod.atlas.services.MappingService
    sleep 15

    # Set for reboot device
    reboot=1
}

install_config(){
    until $download /data/local/tmp/atlas_config.json $aconf_download/atlas_config.json || { echo "`date +%Y-%m-%d_%T` $download /data/local/tmp/atlas_config.json $aconf_download/atlas_config.json" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download atlas config file failed, exit script" >> $logfile ; exit 1; } ;do
      sleep 2
    done
    /system/bin/sed -i 's,dummy,'$origin',g' $aconf
    echo "`date +%Y-%m-%d_%T` atlas config installed, deviceName $origin"  >> $logfile
}

update_all(){
    pinstalled=$(dumpsys package com.nianticlabs.pokemongo | /system/bin/grep versionName | head -n1 | /system/bin/sed 's/ *versionName=//')
    pversions=$(/system/bin/grep 'pogo' $aconf_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
    ainstalled=$(dumpsys package com.pokemod.atlas | /system/bin/grep versionName | head -n1 | /system/bin/sed 's/ *versionName=//')
    aversions=$(/system/bin/grep 'atlas' $aconf_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')

    if [[ $pinstalled != $pversions ]] ;then
      echo "`date +%Y-%m-%d_%T` New pogo version detected, $pinstalled=>$pversions" >> $logfile
      /system/bin/rm -f /sdcard/Download/pogo.apk
      until $download /sdcard/Download/pogo.apk $aconf_download/pokemongo_$arch\_$pversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apk $aconf_download/pokemongo_$arch\_$pversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
      done
      # set pogo to be installed
      pogo_install="install"
    else
     pogo_install="skip"
     echo "`date +%Y-%m-%d_%T` PoGo already on correct version" >> $logfile
    fi

    if [ v$ainstalled != $aversions ] ;then
      echo "`date +%Y-%m-%d_%T` New atlas version detected, $ainstalled=>$aversions" >> $logfile
      /system/bin/rm -f /sdcard/Download/atlas.apk
      until $download /sdcard/Download/atlas.apk $aconf_download/PokemodAtlas-Public-$aversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/atlas.apk $aconf_download/PokemodAtlas-Public-$aversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download atlas failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
      done
      # set atlas to be installed
      atlas_install="install"
    else
     atlas_install="skip"
     echo "`date +%Y-%m-%d_%T` atlas already on correct version" >> $logfile
    fi

    if [ ! -z "$atlas_install" ] && [ ! -z "$pogo_install" ] ;then
      echo "`date +%Y-%m-%d_%T` All updates checked and downloaded if needed" >> $logfile
      if [ "$atlas_install" = "install" ] ;then
        echo "`date +%Y-%m-%d_%T` Updating atlas" >> $logfile
        # install atlas
        /system/bin/pm install -r /sdcard/Download/atlas.apk || { echo "`date +%Y-%m-%d_%T` Install atlas failed, downgrade perhaps? Exit script" >> $logfile ; exit 1; }
        /system/bin/rm -f /sdcard/Download/atlas.apk
        reboot=1
      fi
      if [ "$pogo_install" = "install" ] ;then
        echo "`date +%Y-%m-%d_%T` Updating pogo" >> $logfile
        # install pogo
        /system/bin/pm install -r /sdcard/Download/pogo.apk || { echo "`date +%Y-%m-%d_%T` Install pogo failed, downgrade perhaps? Exit script" >> $logfile ; exit 1; }
        /system/bin/rm -f /sdcard/Download/pogo.apk
        reboot=1
      fi
      if [ "$atlas_install" != "install" ] && [ "$pogo_install" != "install" ] ; then
        echo "`date +%Y-%m-%d_%T` Updates checked, nothing to install" >> $logfile
        am force-stop com.pokemod.atlas
        am startservice com.pokemod.atlas/com.pokemod.atlas.services.MappingService
        echo "`date +%Y-%m-%d_%T` Started Atlas" >> $logfile
      fi
    fi
}

downgrade_pogo(){
    pinstalled=$(dumpsys package com.nianticlabs.pokemongo | /system/bin/grep versionName | head -n1 | /system/bin/sed 's/ *versionName=//')
    pversions=$(/system/bin/grep 'pogo' $aconf_versions | /system/bin/grep -v '_' | awk -F "=" '{ print $NF }')
    if [[ $pinstalled != $pversions ]] ;then
      until $download /sdcard/Download/pogo.apk $aconf_download/pokemongo_$arch\_$pversions.apk || { echo "`date +%Y-%m-%d_%T` $download /sdcard/Download/pogo.apk $aconf_download/pokemongo_$arch\_$pversions.apk" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download pogo failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
      done
      /system/bin/pm uninstall com.nianticlabs.pokemongo
      /system/bin/pm install -r /sdcard/Download/pogo.apk
      /system/bin/rm -f /sdcard/Download/pogo.apk
      echo "`date +%Y-%m-%d_%T` PoGo removed and installed, now $pversions" >> $logfile
    else
      echo "`date +%Y-%m-%d_%T` pogo version correct, proceed" >> $logfile
    fi
}

send_logs(){
if [[ -z $webhook ]] ;then
  echo "`date +%Y-%m-%d_%T` No webhook set in job" >> $logfile
else
  # aconf log
  curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"aconf log sender\", \"content\": \"aconf.log for $origin\"}" -F "file1=@$logfile" $webhook &>/dev/null
  # monitor log
  [[ -f /sdcard/atlas_monitor.log ]] && curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"aconf log sender\", \"content\": \"atlas_monitor.log for $origin\"}" -F "file1=@/sdcard/atlas_monitor.log" $webhook &>/dev/null
  # atlas log
  cp /data/local/tmp/atlas.log /sdcard/atlas.log
  curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"aconf log sender\", \"content\": \"atlas.log for $origin\"}" -F "file1=@/sdcard/atlas.log" $webhook &>/dev/null
  /system/bin/rm /sdcard/atlas.log
  #logcat
  logcat -d > /sdcard/logcat.txt
  curl -S -k -L --fail --show-error -F "payload_json={\"username\": \"aconf log sender\", \"content\": \"logcat.txt for $origin\"}" -F "file1=@/sdcard/logcat.txt" $webhook &>/dev/null
  /system/bin/rm -f /sdcard/logcat.txt
  echo "`date +%Y-%m-%d_%T` Sending logs to discord" >> $logfile
fi
}

########## Execution

#wait on internet
until ping -c1 8.8.8.8 >/dev/null 2>/dev/null || ping -c1 1.1.1.1 >/dev/null 2>/dev/null; do
    sleep 10
done
echo "`date +%Y-%m-%d_%T` Internet connection available" >> $logfile


#download latest atlas.sh
if [[ $(basename $0) != "atlas_new.sh" ]] ;then
    mount -o remount,rw /system
    oldsh=$(head -2 /system/bin/atlas.sh | /system/bin/grep '# version' | awk '{ print $NF }')
    until /system/bin/curl -s -k -L --fail --show-error -o /system/bin/atlas_new.sh https://raw.githubusercontent.com/Kneckter/aconf-rdm/master/atlas.sh || { echo "`date +%Y-%m-%d_%T` Download atlas.sh failed, exit script" >> $logfile ; exit 1; } ;do
        sleep 2
    done
    chmod +x /system/bin/atlas_new.sh
    newsh=$(head -2 /system/bin/atlas_new.sh | /system/bin/grep '# version' | awk '{ print $NF }')
    if [[ $oldsh != $newsh ]] ;then
        echo "`date +%Y-%m-%d_%T` atlas.sh $oldsh=>$newsh, restarting script" >> $logfile
        cp /system/bin/atlas_new.sh /system/bin/atlas.sh
        mount -o remount,ro /system
        /system/bin/atlas_new.sh $@
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
until $download $aconf_versions $aconf_download/versions || { echo "`date +%Y-%m-%d_%T` $download $aconf_versions $aconf_download/versions" >> $logfile ; echo "`date +%Y-%m-%d_%T` Download atlas versions file failed, exit script" >> $logfile ; exit 1; } ;do
    sleep 2
done
dos2unix $aconf_versions
echo "`date +%Y-%m-%d_%T` Downloaded latest versions file"  >> $logfile

#update 55atlas if needed
if [[ $(basename $0) = "atlas_new.sh" ]] ;then
    old55=$(head -2 /system/etc/init.d/55atlas | /system/bin/grep '# version' | awk '{ print $NF }')
    if [ $Ver55atlas != $old55 ] ;then
        mount -o remount,rw /system
        until /system/bin/curl -s -k -L --fail --show-error -o /system/etc/init.d/55atlas https://raw.githubusercontent.com/Kneckter/aconf-rdm/master/55atlas || { echo "`date +%Y-%m-%d_%T` Download 55atlas failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
        done
        chmod +x /system/etc/init.d/55atlas
        mount -o remount,ro /system
        new55=$(head -2 /system/etc/init.d/55atlas | /system/bin/grep '# version' | awk '{ print $NF }')
        echo "`date +%Y-%m-%d_%T` 55atlas $old55=>$new55" >> $logfile
    fi
fi

#update 55cron if needed
if [[ $(basename $0) = "atlas_new.sh" ]] ;then
    old55=$(head -2 /system/etc/init.d/55cron || echo "# version 0.0" | /system/bin/grep '# version' | awk '{ print $NF }')
    if [ $Ver55cron != $old55 ] ;then
        mount -o remount,rw /system
        # install 55cron
        until /system/bin/curl -s -k -L --fail --show-error -o  /system/etc/init.d/55cron https://raw.githubusercontent.com/Kneckter/aconf-rdm/master/55cron || { echo "`date +%Y-%m-%d_%T` Download 55cron failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
        done
        chmod +x /system/etc/init.d/55cron
        echo "`date +%Y-%m-%d_%T` 55cron installed, from master" >> $logfile

        # install cron job
        until /system/bin/curl -s -k -L --fail --show-error -o  /system/bin/ping_test.sh https://raw.githubusercontent.com/Kneckter/aconf-rdm/master/ping_test.sh || { echo "`date +%Y-%m-%d_%T` Download ping_test.sh failed, exit script" >> $logfile ; exit 1; } ;do
            sleep 2
        done
        chmod +x /system/bin/ping_test.sh
        mkdir /system/etc/crontabs || true
        touch /system/etc/crontabs/root
        echo "15 * * * * /system/bin/ping_test.sh" > /system/etc/crontabs/root
        crond -b
        mount -o remount,ro /system
        new55=$(head -2 /system/etc/init.d/55cron | /system/bin/grep '# version' | awk '{ print $NF }')
        echo "`date +%Y-%m-%d_%T` 55cron $old55=>$new55" >> $logfile
    fi
fi

# prevent aconf causing reboot loop. Add bypass ??
if [ $(/system/bin/cat /sdcard/aconf.log | /system/bin/grep `date +%Y-%m-%d` | /system/bin/grep rebooted | wc -l) -gt 20 ] ;then
    echo "`date +%Y-%m-%d_%T` Device rebooted over 20 times today, atlas.sh signing out, see you tomorrow"  >> $logfile
    exit 1
fi

# set hostname = origin, wait till next reboot for it to take effect
if [[ $origin != "" ]] ;then
    if [ $(/system/bin/cat /system/build.prop | /system/bin/grep net.hostname | wc -l) = 0 ]; then
        mount -o remount,rw /system
        echo "`date +%Y-%m-%d_%T` No hostname set, setting it to $origin" >> $logfile
        echo "net.hostname=$origin" >> /system/build.prop
        mount -o remount,ro /system
    else
        hostname=$(/system/bin/grep net.hostname /system/build.prop | awk 'BEGIN { FS = "=" } ; { print $2 }')
        if [[ $hostname != $origin ]] ;then
            mount -o remount,rw /system
            echo "`date +%Y-%m-%d_%T` Changing hostname, from $hostname to $origin" >> $logfile
            /system/bin/sed -i -e "s/^net.hostname=.*/net.hostname=$origin/g" /system/build.prop
            mount -o remount,ro /system
        fi
    fi
fi

# check atlas config file exists
if [[ -d /data/data/com.pokemod.atlas ]] && [[ ! -s $aconf ]] ;then
    install_config
    am force-stop com.pokemod.atlas
    am startservice com.pokemod.atlas/com.pokemod.atlas.services.MappingService
fi

for i in "$@" ;do
    case "$i" in
        -ia) install_atlas ;;
        -ic) install_config ;;
        -ua) update_all ;;
        -dp) downgrade_pogo;;
        -sl) send_logs;;
    esac
done


(( $reboot )) && reboot_device
exit
