#!/bin/bash
# filename:		cpu_check.sh
#
#    Copyright (c) 2013 - 2018 Andreas Schmidhuber
#    All rights reserved.
#
#    Redistribution and use in source and binary forms, with or without
#    modification, are permitted provided that the following conditions are met:
#
#    1. Redistributions of source code must retain the above copyright notice, this
#       list of conditions and the following disclaimer.
#    2. Redistributions in binary form must reproduce the above copyright notice,
#       this list of conditions and the following disclaimer in the documentation
#       and/or other materials provided with the distribution.
#
#    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
#    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
#    ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#    ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# author:		Andreas Schmidhuber
# purpose:		retrive CPU temperature infos for eGUI in file: cpu_check.log
# usage:		cpu_check.sh
# version:	date:		description:
#	0.5.1   2018.08.23	F: beep on ERROR was only working if email notification was enabled
#	0.5		2017.06.15	N: introduced Telegram as new notification service
#   0.4     2016.09.25  N: create messages for index.php
#   0.3     2016.08.21  F: if [ "${TEMPERATURE}" != "" ]; then => avoid false alarms on rpi
#   0.2     2015.11.24  N: beep on ERROR
#   0.1     2015.11.23  initial version for Extended GUI 
#------------- initialize variables ------------
cd `dirname $0`
. CONFIG
REPORT_FILE="${PREFIX}cpu_check.log"
CTRL_FILE="${PREFIX}cpu_check"
HYSTERESIS=${CPU_TEMP_HYSTERESIS}            # avoid repetitive alarms if temperature changes for some degrees
#-----------------------------------------------

# compares arg1 and arg2, returns: "0" on arg1 less, "1" on arg1 equal, "2" on arg1 greater than arg2
COMPARE ()
{ local RESULT=`echo | awk -v n1=$1 -v n2=$2 '{if (n1<n2) print("0"); else if (n1==n2) print("1"); else print("2");}'`; return $RESULT; }

# subtract floating point numbers $1 minus $2, return result directly
SUB ()
{ echo $1 $2 | awk '{print ($1) - ($2)}'; }

# $1 = severity level (WARNING|ERROR), $2 = whole output message
REPORT ()
{
	if [ ! -e ${CTRL_FILE}_${1}.lock ]; then 
#        CONVERSION=`echo -e "${@}" | awk '{gsub("°C", "degreeC"); print}'`     # v0.6.3: no longer needed, script must be UTF-8 w/o BOM !!!
        NOTIFY "$1 $2"
        echo `date +"$DT_STR"` "$1 $2" >> ${PREFIX}system_error.msg    # create system error message for index.php
        if [ $TELEGRAM_NOTIFICATIONS -eq 1 ] && [ $EMAIL_CPU_TEMP_ENABLED -eq 1 ]; then     # call Telegram if enabled
            TELEGRAM "$1 $2"
        fi
        if [ $RUN_BEEP -gt 0 ]; then                                    # call beep when enabled and ERROR condition set
            $SYSTEM_SCRIPT_DIR/beep CPU_ERROR &
        fi
		echo "Host: $HOST" > ${CTRL_FILE}_${1}.lock
		echo "\n$2" >> ${CTRL_FILE}_${1}.lock
        if [ $EMAIL_NOTIFICATIONS -eq 1 ] && [ $EMAIL_CPU_TEMP_ENABLED -eq 1 ] && [ -e ${CTRL_FILE}_ERROR.lock ]; then 
            $SYSTEM_SCRIPT_DIR/email.sh "$EMAIL_TO" "N4F-CPU" ${CTRL_FILE}_ERROR.lock; 
        fi
	fi
}

GET_TEMPERATURE ()
{
    x=0;
    OUTPUT="";
	while [ $x -lt $CPU_NUMBER ]
	do
        TEMPERATURE=`sysctl -q -n dev.cpu.${x}.temperature | awk '{gsub("C", ""); print}'`
        if [ "${TEMPERATURE}" != "" ]; then
#echo 1 "CPU${x} actual temp ${TEMPERATURE}, warning temp ${CPU_TEMP_WARNING} minus $HYSTERESIS = `SUB ${CPU_TEMP_WARNING} $HYSTERESIS`"
            COMPARE ${TEMPERATURE} ${CPU_TEMP_SEVERE}                               # test if temperature is >= CPU_TEMP_SEVERE
            if [ $? -ge 1 ]; then 
                MSG_TEMP="<font color='red'>${TEMPERATURE}&nbsp;&deg;C</font>"
                REPORT ERROR "CPU reached critical temperature threshold ${CPU_TEMP_SEVERE} °C, temperature is ${TEMPERATURE} °C!"
#echo 2 "$TEMPERATURE ${TEMPERATURE}"
            else 
                COMPARE ${TEMPERATURE} ${CPU_TEMP_WARNING}                          # test if temperature is >= CPU_TEMP_WARNING
                if [ $? -ge 1 ]; then 
                    MSG_TEMP="<font color='orange'>${TEMPERATURE}&nbsp;&deg;C</font>"
                    REPORT WARNING "CPU reached warning temperature threshold ${CPU_TEMP_WARNING} °C, temperature is ${TEMPERATURE} °C!"
#echo 3 "$TEMPERATURE ${TEMPERATURE}"
                else 
                    COMPARE ${TEMPERATURE} `SUB ${CPU_TEMP_WARNING} $HYSTERESIS`    # test if temperature is < CPU_TEMP_WARNING - $HYSTERESIS °C !
                    if [ $? -eq 0 ]; then 
                        if [ -e "${CTRL_FILE}_ERROR.lock" ]; then rm "${CTRL_FILE}_ERROR.lock"; fi
                        if [ -e "${CTRL_FILE}_WARNING.lock" ]; then rm "${CTRL_FILE}_WARNING.lock"; fi
#echo 9 "actual temp ${TEMPERATURE}, warning temp ${CPU_TEMP_WARNING} minus $HYSTERESIS = `SUB ${CPU_TEMP_WARNING} $HYSTERESIS`, files will be deleted"                
                    fi
                    MSG_TEMP="<font color='blue'>${TEMPERATURE}&nbsp;&deg;C</font>"
                fi
            fi
            if [ "$OUTPUT" == "" ]; then OUTPUT="${MSG_TEMP}";
            else OUTPUT="${OUTPUT}&nbsp;&nbsp;${MSG_TEMP}"; fi
        fi
		x=$((x+1));
	done
}

GET_TEMPERATURE
echo "${OUTPUT}" > "${REPORT_FILE}"                                     # output temperature(s) to file for index.php
