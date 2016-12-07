#!/bin/bash 

PWD=`pwd`
TOOL_DIR=$PORT_ROOT/tools
OTA_FROM_TARGET_FILES=$TOOL_DIR/releasetools/ota_from_target_files
TARGET_FILES_TEMPLATE_DIR=$TOOL_DIR/target_files_template

TMP_DIR=$PWD/out
TARGET_FILES_DIR=$TMP_DIR/target_files
RECOVERY_ETC_DIR=$TARGET_FILES_DIR/RECOVERY/RAMDISK/etc
STOCK=$PWD/stockrom_cm/system
META_DIR=$TARGET_FILES_DIR/META
TARGET_FILES_ZIP=$TMP_DIR/target_files.zip

OUTPUT_OTA_PACKAGE=$PWD/stockrom.zip
OUTPUT_METADATA_DIR=$PWD/metadata

FULL_OTA_PACKAGE=$2
MODE=$1

# build apkcerts.txt
function build_apkcerts {
    echo "Build apkcerts.txt"
    adb pull /data/system/packages.xml $TMP_DIR
    python $TOOL_DIR/apkcerts.py $TMP_DIR/packages.xml $TMP_DIR/apkcerts.txt
    for file in `ls $STOCK/framework/*.apk`
    do
        apk=`basename $file`
        echo "name=\"$apk\" certificate=\"build/target/product/security/platform.x509.pem\" private_key=\"build/target/product/security/platform.pk8\"" >> $TMP_DIR/apkcerts.txt
    done
    cat $TMP_DIR/apkcerts.txt | sort > $TMP_DIR/temp.txt
    mv $TMP_DIR/temp.txt $TMP_DIR/apkcerts.txt
    rm $TMP_DIR/packages.xml
}

# build filesystem_config.txt from device
function build_filesystem_config {
    echo "Run getfilesysteminfo to build filesystem_config.txt"
    if [ $ANDROID_PLATFORM -gt 19 ];then
        adb push $TOOL_DIR/target_files_template/OTA/bin/busybox /data/local/tmp/
        adb shell chmod 755 /data/local/tmp/busybox
        bash $TOOL_DIR/get_filesystem_config --info /data/local/tmp/busybox | tee $TMP_DIR/filesystem_config.txt
        if [ $? -ne 0 ];then
            echo "Get file info failed"
            exit 1
        fi
    else
        adb push $TOOL_DIR/releasetools/getfilesysteminfo /system/xbin
        adb shell chmod 0777 /system/xbin/getfilesysteminfo
        adb shell /system/xbin/getfilesysteminfo --info /system >> $TMP_DIR/filesystem_config.txt
        fs_config=`cat $TMP_DIR/filesystem_config.txt | col -b | sed -e '/getfilesysteminfo/d'`
        OLD_IFS=$IFS
        IFS=$'\n'
        for line in $fs_config
        do
            echo $line | grep -q -e "\<su\>" && continue
            echo $line | grep -q -e "\<invoke-as\>" && continue
            echo $line >> $TMP_DIR/tmp.txt
        done
        IFS=$OLD_IFS
        cat $TMP_DIR/tmp.txt | sort > $TMP_DIR/filesystem_config.txt
        rm $TMP_DIR/tmp.txt
    fi
}

# recover the device files' symlink information
function recover_symlink {
    echo "Run getfilesysteminfo and recoverylink.py to recover symlink"
    if [ $ANDROID_PLATFORM -gt 19 ];then
        bash $TOOL_DIR/get_filesystem_config --link /data/local/tmp/busybox | tee $TMP_DIR/linkinfo.txt
        if [ $? -ne 0 ];then
            echo "Get file symlink failed"
            exit 1
        fi
    else
        adb shell /system/xbin/getfilesysteminfo --link /system | sed -e '/\<su\>/d;/\<invoke-as\>/d' | sort > $TMP_DIR/linkinfo.txt
    fi
    python $TOOL_DIR/releasetools/recoverylink.py $TMP_DIR
}

# In recovery mode, extract the recovery.fstab from device
function extract_recovery_fstab {
    echo "Extract recovery.fstab from device"
    adb shell cat /etc/recovery.fstab | awk '{print $1 "\t" $2 "\t" $3}'> $TMP_DIR/recovery.fstab
}

build_apkcerts
build_filesystem_config
recover_symlink
extract_recovery_fstab
