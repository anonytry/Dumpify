#！/bin/sh

opcust=`ls /dev/block/by-name/opcust 2>/dev/null | tr -d "\r" ||true`

if [ "$opcust" == "/dev/block/by-name/opcust" ];then
    echo "exist"
else
    echo "non-exist"
fi
