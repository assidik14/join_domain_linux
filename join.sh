!/bin/bash

RESET="\033[0m"			# Normal Colour
RED="\033[0;31m" 		# Error / Issues
GREEN="\033[0;32m"		# Successful       
BOLD="\033[01;01m"    	# Highlight
WHITE="\033[1;37m"		# BOLD
YELLOW="\033[1;33m"		# Warning
PADDING="  "
DPADDING="\t\t"

#### Other Colors / Status Code

LGRAY="\033[0;37m"		# Light Gray
LRED="\033[1;31m"		# Light Red
LGREEN="\033[1;32m"		# Light GREEN
LBLUE="\033[1;34m"		# Light Blue
LPURPLE="\033[1;35m"	# Light Purple
LCYAN="\033[1;36m"		# Light Cyan
SORANGE="\033[0;33m"	# Standar Orange
SBLUE="\033[0;34m"		# Standar Blue
SPURPLE="\033[0;35m"	# Standar Purple      
SCYAN="\033[0;36m"		# Standar Cyan
DGRAY="\033[1;30m"		# Dark Gray

error_status="${LRED}ERROR${RESET}"
success_status="${LGREEN}SUCCESS${RESET}"
info_status="${YELLOW}INFO${RESET}"

SRV_HOST=$(hostname)
timestamp=$(date | cut -d ' ' -f 5,6,7)

function Banner(){
#
## Print ASCII Banner
#################################

    clear
    echo -e "

${LPURPLE} ____    ${LGREEN}Auto Join   ${LPURPLE}_     
|    \ ___ _____ ___|_|___ 
|  |  | . |     | .'| |   |
|____/|___|_|_|_|__,|_|_|_|${RESET}

"

}

function checkPriv() {
#
# Checking Privileges to running 
# Join Domain Script
#################################

  if [[ $EUID -ne 0 ]]; then
    echo -e "[${LBLUE}${timestamp}${RESET}] [${error_status}] This script need ${LRED}root${RESET} privileges to run.\n"
    exit
  else
    echo -ne "[${LBLUE}${timestamp}${RESET}] [${info_status}] Installing Dependencies Package...................."
  fi

}

function checkOS() {
#
# Installing Package Dependencies
#################################

  getOS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')

  if [[ ${getOS} == "Ubuntu" ]]; then
    $(apt-get -y install realmd libnss-sss libpam-sss sssd sssd-tools adcli samba-common-bin oddjob oddjob-mkhomedir packagekit > /dev/null)
    CHECK_PKG=$?
    if [ ${CHECK_PKG} -eq 0 ]; then
        echo -e "${LGREEN}DONE${RESET}"
    else
        echo -e "${LRED}FAILED${RESET}"
    fi
    wait
    wait
  elif [[ ${getOS} == "CentOS" ]]; then
    $(yum -yy install realmd sssd oddjob oddjob-mkhomedir adcli samba-common ntpdate ntp samba-common-tools)
    wait
  else
    echo -e "[${LBLUE}${timestamp}${RESET}] [${error_status}] This script noot support ${YELLOW}${getOS}${RESET}."
  fi

}

function configNTP() {
#
# Configuring NTP Service
#################################

  echo -ne "[${LBLUE}${timestamp}${RESET}] [${info_status}] Configuring NTP Service...................."
  sudo systemctl enable ntp >/dev/null 2>&1 && sudo systemctl stop ntp >/dev/null 2>&1 && sudo ntpdate time.windows.com >/dev/null 2>&1 && sudo systemctl start ntp >/dev/null 2>&1
  wait
  echo -e "${LGREEN}DONE${RESET}"

}

function joinRealm() {
#
# Join Domain using Realm Service
# Change Password on the Variable
# AD_PASSWD < Domain User Account
#################################

    AD_PASSWD="AD_PASSWORD"
    
    if [[ $(realm list) ]]; then
        echo -e "[${LBLUE}${timestamp}${RESET}] [${error_status}] The server already join domain"
        echo -ne "[${LBLUE}${timestamp}${RESET}] [${info_status}] Leaving old domain...................."
        realm leave $(realm list | head -n 1)

        CHECK_LEAVE=$?
        if [ ${CHECK_LEAVE} -eq 0 ]; then
            echo -e "${LGREEN}DONE${RESET}"
        else
            echo -e "${LRED}FAILED${RESET}"
        fi
        wait
        echo -ne "[${LBLUE}${timestamp}${RESET}] [${info_status}] Joining New Domain using Realm...................."
        $(echo ${AD_PASSWD} | realm join -U administrator@domain.LOCAL domain.local > /dev/null)

        CHECK_JOIN=$?
        if [ ${CHECK_JOIN} -eq 0 ]; then
            echo -e "${LGREEN}DONE${RESET}"
        else
            echo -e "${LRED}FAILED${RESET}"
        fi
        wait
    else
        echo -ne "[${LBLUE}${timestamp}${RESET}] [${info_status}] Joining Domain using Realm...................."
        $(echo ${AD_PASSWD} | realm join -U administrator@domain.LOCAL domain.local > /dev/null)

        CHECK_JOIN=$?
        if [ ${CHECK_JOIN} -eq 0 ]; then
            echo -e "${LGREEN}DONE${RESET}"
        else
            echo -e "${LRED}FAILED${RESET}"
        fi
        wait
    fi

#
# Joining AD Group via Realm
#################################

  echo -ne "[${LBLUE}${timestamp}${RESET}] [${info_status}] Applying policy for logon access...................."
  $(realm permit -g OU@domain.local)
  
  CHECK_GROUP=$?
  if [ ${CHECK_GROUP} -eq 0 ]; then
    echo -e "${LGREEN}DONE${RESET}"
  else
    echo -e "${LRED}FAILED${RESET}"
  fi
  wait

}

function setPrivileges() {
#
# Restrict user privileges on 
# CentOS7 / Ubuntu using Sudo
#################################

  echo -ne "[${LBLUE}${timestamp}${RESET}] [${info_status}] Set user privileges...................."
  $(cp /etc/sudoers /etc/sudoers.bak)
  $(echo '%OU@domain.local ALL=(ALL) ALL' >> /etc/sudoers)
  $(echo '%OU@domain.local ALL=/usr/bin/passwd [A-Z][a-z]*, !/usr/bin/passwd root' >> /etc/sudoers)
  $(echo '%OU@domain.local ALL=!/usr/bin/visudo' >> /etc/sudoers)
  echo -e "${LGREEN}DONE${RESET}"
}

function setSSSD() {
#
# Modify sssd.conf to fix a issue 
# with FQDN and enable a simple
# ACL only allowing TEKNOLOGI INFORMASI to connect
#################################

  echo -ne "[${LBLUE}${timestamp}${RESET}] [${info_status}] Setting ${YELLOW}sssd.conf${RESET} to fix FQDN and enabling ACL...................."

  $(sed -i -e 's|use_fully_qualified_names = True|#use_fully_qualified_names = True|' /etc/sssd/sssd.conf)
  $(echo | tee -a /etc/sssd/sssd.conf > /dev/null)
  $(echo access_provider = simple | tee -a /etc/sssd/sssd.conf > /dev/null)
  $(echo simple_allow_groups = OU@domain.local | sudo tee -a /etc/sssd/sssd.conf > /dev/null)
  $(systemctl restart sssd.service >/dev/null 2>&1)

  CHECK_SSSD=$?
  if [ ${CHECK_SSSD} -eq 0 ]; then
    echo -e "${LGREEN}DONE${RESET}"
  else
    echo -e "${LRED}FAILED${RESET}"
  fi
  wait

}

Banner
checkPriv
checkOS
configNTP
joinRealm
setPrivileges
setSSSD

echo -e "[${LBLUE}${timestamp}${RESET}] [${success_status}] Server ${LBLUE}${SRV_HOST}${RESET} successfully joined Active Directory Domain."
