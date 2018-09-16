#!/bin/bash
################################################################################
# Dennis Kruemmel, 2018
#
# with content from
#   https://github.com/homebysix/auto-update-magic
#
################################################################################
#
# This script is designed to be embedded in a helper script "magic_installer_container.sh".
# base64 -i ./magic_installer.sh | pbcopy
#
################################################################################
# NAME
#   magic_installer.sh -- script for managed installation through jamf pro.
# 
# SYNOPSIS
#   ./magic_installer.sh <mountPoint> <computerName> <userName> "<processName>[;<processName>;...]" "[<appVersion>]" "[<displayname>]" "<pkgToInstall>[;<pkgToInstall>;...]" [<deadline>] [<icon>] [appVersionOld]
# 
# DESCRIPTION
#   mountPoint
#       target for installer
#       Will be automatically set from jamf pro
#       Example:
#         "/"
# 
#   computerName
#       hostname from the destination computer
#       Will be automatically set from jamf pro
#       Example:
#         "MBP2017-001"
#
#   userName
#       logged in user
#       Will be automatically set from jamf pro
#       Example:
#         "Clara.Korn"
# 
#   processName
#       process to watch. Use ; as delimiter for multiple process names
#       Example:
#         "firefox"
#         "firefox;safari$"
#
#   appVersion (Optional)
#       Version Number from the app which will be installed.
#       Example:
#         "52.7.3"
#
#   displayname (Optional)
#       Name which be used for notifications
#       Example:
#         "Firefox with CCK"
#
#   pkgToInstall
#       PKGs cached in the JAMF "Waiting Room". Use ; as delimiter for multiple Packages to install.
#       Example:
#         "MyPackage-1.0.0.pkg"
#         "MyPackage-1.0.0.pkg;MyPackageUpdate-1.1.0.pkg"
# 
#   deadline (Optional)
#       date as unix timestamp of the forced install. After this date the countdown will be ignored.
#       If the deadline is set, the forced install will be activated.
#       calculate the deadline:
#       date -j -f "%d.%m.%Y %H:%M:%S" "31.12.2018 06:00:00" +%s
#       Example:
#         "1546232400"
#
#   icon (Optional)
#       This icon will be used for the messagebox
#       Example:
#         "/Applications/Firefox.app/Contents/Resources/firefox.icns"
#
#   appVersionOld (Optional)
#       command to determine the version from the old installed app.
#       Example:
#         "defaults read /Applications/Firefox.app/Contents/Info.plist CFBundleShortVersionString"
################################################################################

logFile="/var/log/magic_installer.log"
ScriptLog() { # Re-direct logging to the log file ...
	if [[ ! -z "${logFile}" ]] && [[ ! -f "${logFile}" ]]; then
		/usr/bin/touch "${logFile}" || exit 1
	elif [[ -z "${logFile}" ]]; then
		logFile="/var/log/system.log"
		/usr/bin/touch "${logFile}" || exit 1
	fi

    exec 3>&1 4>&2          # Save standard output and standard error
    exec 1>>"${logFile}"    # Redirect standard output to logFile
    exec 2>>"${logFile}"    # Redirect standard error to logFile

    ScriptLogNOW=$(date +%Y-%m-%d\ %H:%M:%S)
    /bin/echo "[${displayname} | ${ScriptLogNOW}]  ${1}" >> ${logFile}
	exec 1>&3 2>&4
}

JAMF="/usr/local/bin/jamf"
JAMF_HELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
JAMF_ICONS="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/Resources"
MANAGEMENT_ACTION="/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action"
JAMF_CACHE="/Library/Application Support/JAMF/Waiting Room"
currentuser=$(ls -l /dev/console | cut -d " " -f 4)
skipping_counter_dir="/Library/Application Support/Scripts/magic_installer" # Edit me
[[ -d "${skipping_counter_dir}" ]] || mkdir -p "${skipping_counter_dir}"
waiting_duration=( 86400 14400 7200 1800 300 ) # 0 will deactivate the countdown
now="$(date +%s)"
identifier="com.mycompany" # Edit me

displayUserMessage () {
	MY_MESSAGE="${1}"
	[[ -z "${2}" ]] && timeout="7200" || timeout="${2}"
	[[ -z "${3}" ]] && cancel="false" || cancel="${3}"
	if
        [[ -n "${customicon}" ]] &&
        [[ -f "${customicon}" ]];
        then
		icon="${customicon}"
	elif
        [[ -f "/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns" ]];
        then
		icon="/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"
	else
		icon="${JAMF_ICONS}/Message.png"
	fi
	if [[ "${cancel}" = "false" ]]; then
		"${JAMF_HELPER}" \
			-windowType utility \
			-title "Systemupdates verfügbar" \
			-description "${MY_MESSAGE}" \
			-icon "${icon}" \
			-button1 "Installieren" \
			-defaultButton 1 \
			-timeout ${timeout} \
			-countdown
	else
		"${JAMF_HELPER}" \
			-windowType utility \
			-title "Systemupdates verfügbar" \
			-description "${MY_MESSAGE}" \
			-icon "${icon}" \
			-button1 "Installieren" \
			-button2 "Später" \
			-defaultButton 1 \
			-cancelButton 2 \
			-timeout ${timeout} \
			-countdown
	 fi

}

compareVersion (){
    /usr/bin/python - "$1" "$2" << EOF
import sys
from distutils.version import LooseVersion as LV
print LV(sys.argv[1]) >= LV(sys.argv[2])
EOF
}

if [ -n "${4}" ]; then
	appname="${4}"
else
	echo "Error: Processname not set (hint: argument #4)" 1>&2
    echo "Processname (use ; as delimiter)"
	exit 4
fi

if [ -n "${5}" ]; then
	appVersion="${5}"
else
	appVersion=""
fi

if [ -n "${6}" ]; then
	displayname="${6}"
else
	echo "Info: Displayname not set (hint: argument #6). Using Appname \"${appname}\" and appVersion \"${appVersion}\" as displayname."
	if [[ -n "${appVersion}" ]]; then
        displayname="${appname} ${appVersion}"
    else
	    displayname="${appname}"
    fi
    echo "Displayname: \"${displayname}\""
fi

if [ -n "${7}" ]; then
	pkgs="${7}"
else
	echo "Error: PKGs to install not set (hint: argument #7)" 1>&2
    echo "PKGs to install (use ; as delimiter)"
	exit 7
fi

skipping_counter="${skipping_counter_dir}/${displayname}"
touch "${skipping_counter}"

if [ -n "${8}" ]; then
	deadline="${8}"
else
	deadline="0"
fi
[[ "${deadline}" == "0" ]] && echo "deadline: not set" || echo "deadline: $(date -r ${deadline} +"%d.%m.%Y %H:%M:%S")"

if [ -n "${9}" ]; then
	customicon="${9}"
fi

if [ -n "${10}" ]; then
    if [[ -z "${11}" ]]; then
        plistKey="CFBundleShortVersionString"
    else
        plistKey="${11}"
    fi
	appVersionOld="$(defaults read "${10}" "${plistKey}" 2>/dev/null)"
fi

declare -a apparray
declare -a pkgarray
applines=$(echo "${appname}"|tr ";" "\n")
while read -r app; do
	apparray+=("$app")
done <<<"${applines}"

pkglines=$(echo "${pkgs}"|tr ";" "\n")
while read -r pkg; do
	pkgarray+=("$pkg")
done <<<"${pkglines}"

# ScriptLog "Killing old processes."
# ScriptLog "selfpid: $$"
otherpids=$( ps aux | grep "[m]agic_installer" | grep "$(echo ${appname}|sed 's/;/\\|/g')" | awk '{print $2}' | grep -v "$$" )
# ScriptLog "otherpids: $otherpids"
while read -r opid; do
    kill $opid 2>/dev/null
done <<<"${otherpids}"

installpkgs() {
    ScriptLog "Preparing Installation of ${displayname}"

    for pkg in "${pkgarray[@]}"
    do
        if [ ! -f "${JAMF_CACHE}/${pkg}" ]; then
            ScriptLog "File \"${JAMF_CACHE}/${pkg}\" doesn't exist."
            removeLaunchDaemon
            exit 1
        fi
    done

    if [[ "${loggedInUser}" = "root" ]]; then
        echo "No User logged in. Skipping notification."
    else
        ScriptLog "Management Action: Starte Installation von ${displayname}."
        "${MANAGEMENT_ACTION}" -title "Installationstatus" -message "Starte Installation von ${displayname}." &
    fi

    for pkg in "${pkgarray[@]}"
    do
        ScriptLog "Installing \"${JAMF_CACHE}/${pkg}\""
        "${JAMF}" install -package "${pkg}" -path "${JAMF_CACHE}" -target / >> /var/log/magic.log 2>&1
        exitcode=$?
        ScriptLog "Installer done with exitcode $exitcode"
        [[ "${#pkgarray[@]}" -gt 1 ]] && /bin/sleep 2
    done
    echo -n "" > "${skipping_counter}"

    if [[ "${loggedInUser}" = "root" ]]; then
        echo "No User logged in. Skipping notification."
    else
        ScriptLog "Management Action: Installation von ${displayname} erfolgreich."
        "${MANAGEMENT_ACTION}" -title "Installationstatus" -message "Installation von ${displayname} erfolgreich." &
    fi

    ScriptLog "Fertig."
}

removeLaunchDaemon() {
    ScriptLog "Removing LaunchDaemon \"${identifier}.magic_installer_${appname}.plist\""
    launchctl list "${identifier}.magic_installer_${appname}" > /dev/null 2>&1
    launchctlError=$?
    if [[ "${launchctlError}" -eq 0 ]]; then
        rm -f "/Library/LaunchDaemons/${identifier}.magic_installer_${appname}.plist"
        launchctl remove "${identifier}.magic_installer_${appname}"
    fi
}

if
    [[ -n "${appVersionOld}" ]] &&
    [[ -n "${appVersion}" ]] &&
    $(compareVersion "${appVersionOld}" "${appVersion}");
    then
        ScriptLog "Same or newer Version already installed"
        echo "Same or newer Version already installed"
        removeLaunchDaemon
        exit 10
fi

for app in "${apparray[@]}"; do
    watchedPID+=( $(pgrep -i "${app}" | grep -v "grep" | grep -v "magic_installer") )
done
echo "watchedPID: ${watchedPID[*]}"
if [[ "${watchedPID[*]/# /}" == "" ]]; then
    ScriptLog "Starting installation."
    installpkgs
    removeLaunchDaemon
else
    if [[ "${deadline}" -gt 0 ]]; then
        # ScriptLog "forced installation will be activated."
        echo "forced installation will be activated."
        norerunbefore="$(tail -n 1 "${skipping_counter}")"
        logRepeat=$(grep "${displayname}" "${logFile}" 2>/dev/null | tail -n 1 | grep -c "norerunbefore")
        [[ -z "${norerunbefore}" ]] && norerunbefore=0
        [[ "${logRepeat}" -eq 0 ]] && ScriptLog "norerunbefore: $(date -r ${norerunbefore} +"%d.%m.%Y %H:%M:%S")"
        # ScriptLog "now:           $(date -r ${now} +"%d.%m.%Y %H:%M:%S")"
        echo "now:           $(date -r ${now} +"%d.%m.%Y %H:%M:%S")"
        if
            [[ "${norerunbefore}" -le "${now}" ]];
            then
                skipping_counter_int="$(wc -l "${skipping_counter}" | awk '{print $1+1}')"
                ScriptLog "#waiting_duration[@]: ${#waiting_duration[@]}"
                ScriptLog "skipping_counter_int: $skipping_counter_int"

                if
                    [[ "${#waiting_duration[@]}" -gt "${skipping_counter_int}" ]] &&
                    (
                        [[ "${deadline}" -eq 0 ]] ||
                        [[ "${deadline}" -ge "${now}" ]]
                    );
                    then
                        timeout="${waiting_duration[$skipping_counter_int-1]}"
                        cancel="true"
                else
                        timeout="${waiting_duration[${#waiting_duration[@]}-1]}" # last array item
                        cancel="false"
                fi
                ScriptLog "timeout: $timeout"
                ScriptLog "cancel: $cancel"

                ScriptLog "Application \"${appname}\" is running..."
                ScriptLog "Display message for user \"${currentuser}\""
                displayUserMessage "Bitte beenden Sie ${displayname}, um Softwareaktualisierungen durchzuführen." "${timeout}" "${cancel}" > /dev/null
                errorcode="$?"
                if [[ "${errorcode}" -eq 0 ]]; then
                    for app in "${apparray[@]}"; do
                        ScriptLog "Quiting \"$app\" with AppleScript"
                        osascript -e "tell application \"${app}\" to quit"
                    done
                    /bin/sleep 2

                    ps ${watchedPID[*]} >/dev/null 2>&1
                    pserror=$?
                    if [[ "${pserror}" -eq 0 ]]; then
                        ScriptLog "Killing \"${displayname}\" (${watchedPID[*]})"
                        kill -9 ${watchedPID[*]} 2>/dev/null
                    fi
                else
                    echo "$(( now + timeout ))" >> "${skipping_counter}"
                    ScriptLog "Manual skipped."
                    now2="$(date +%s)"
                    timeout2=$(( timeout - ( now2 - now ) ))
                fi
        else
            now2="$(date +%s)"
            timeout2=$(( norerunbefore - now2 ))
            ScriptLog "Skipping. Next run at $(date -r ${norerunbefore} +"%d.%m.%Y %H:%M:%S")"
        fi
    else
        loggedInUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }')
        logRepeat=$(grep "${displayname}" "${logFile}" 2>/dev/null | tail -n 1 | grep -c "is logged in and app is running")
        [[ "${logRepeat}" -eq 0 ]] && ScriptLog "User \"${loggedInUser}\" is logged in and app is running. Exiting."
    fi

fi

exit 0