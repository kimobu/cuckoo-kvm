#!/bin/bash

# CuckooAutoInstall for KVM systems

# Copyleft (C) 2020 Kimo Bumanglag
# Based on work by the following:
# Copyright (C) 2014-2015 David Reguera García - dreg@buguroo.com
# Copyright (C) 2015 David Francos Cuartero - dfrancos@buguroo.com
# Copyright (C) 2017-2018 Erik Van Buggenhout & Didier Stevens - NVISO

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

source /etc/os-release

# Base variables. Only change these if you know what you are doing...
SUDO="sudo"
TMPDIR=$(mktemp -d)
RELEASE=$(lsb_release -cs)
CUCKOO_USER="cuckoo"
CUCKOO_PASSWD="cuckoo"
CUSTOM_PKGS=""
ORIG_DIR=$( cd "$( dirname "${BASH_SOURCE[0]}"  )" && pwd  )
VOLATILITY_URL="http://downloads.volatilityfoundation.org/releases/2.6/volatility_2.6_lin64_standalone.zip"
YARA_REPO="https://github.com/plusvic/yara"

# Virt variables
VMNAME="Windows7Sandbox"
DISKPATH="/mnt/datastore/vm/Windows7Sandbox/disk1.qcow2"
ISOPATH="/mnt/datastore/iso/c8648303-5b5b-4aa2-b434-20885025b9ae/images/11111111-1111-1111-1111-111111111111/"
CDROM="Windows7Ultimate64.iso"
VIRTIO="virtio-win_amd64.vfd"

LOG=$(mktemp)
UPGRADE=true

declare -a packages
declare -a python2_packages
declare -a python3_packages

packages="apparmor-utils automake build-essential clamav clamav-daemon clamav-freshclam curl exiftool gdebi-core geoip-database git htop libboost-all-dev libcap2-bin libffi-dev libfreetype6-dev libfuzzy-dev libgeoip-dev libjansson-dev libjpeg-dev libjpeg8-dev liblcms2-dev libmagic-dev libmagic1 libpq-dev libssl-dev libtiff5-dev libvirt-clients libvirt-daemon libvirt-dev libwebp-dev mongodb-org-server mono-utils openjdk-11-jre-headless p7zip-full postgresql postgresql-contrib privoxy python python3 python-dev python3-dev python-m2crypto python-pil python-pip python3-pip python-setuptools python-tk python-virtualenv python3-virtualenv qemu-kvm qemu-utils ssdeep suricata swig tcl8.6-dev tcpdump tk8.6-dev tmux tor unzip upx-ucl virt-manager  wget wkhtmltopdf zlib1g-dev"

python2_packages="pip setuptools cuckoo pycrypto libvirt-python"
python3_packages="pip setuptools distorm3 yara-python==3.6.3 pycrypto"

# Pretty icons
log_icon="\e[31m✓\e[0m"
log_icon_ok="\e[32m✓\e[0m"
log_icon_nok="\e[31m✗\e[0m"

# -

print_copy(){
cat <<EO
┌─────────────────────────────────────────────────────────┐
│                CuckooAutoInstall KVM                    │
│     The foundation of this script is built by:          │
│ David Reguera García - Dreg <dreguera@buguroo.com>      │
│ David Francos Cuartero - XayOn <dfrancos@buguroo.com>   │
│ Erik Van Buggenhout - <evanbuggenhout@nviso.be>         |
│ Didier Stevens - <dstevens@nviso.be                     |
│            Buguroo Offensive Security - 2015            │
│            NVISO - 2017-2018  			  │
└─────────────────────────────────────────────────────────┘
EO
}

check_viability(){
    [[ $UID != 0 ]] && {
        type -f $SUDO || {
            echo "You're not root and you don't have $SUDO, please become root or install $SUDO before executing $0"
            exit
        }
    } || {
        SUDO=""
    }

    [[ ! -e /etc/debian_version ]] && {
        echo  "This script currently works only on debian-based (debian, ubuntu...) distros"
        exit 1
    }
}

print_help(){
    cat <<EOH
Usage: $0 [--verbose|-v] [--help|-h] [--upgrade|-u]

    --verbose   Print output to stdout instead of temp logfile
    --help      This help menu
    --upgrade   Use newer volatility, yara and jansson versions (install from source)

EOH
    exit 1
}

setopts(){
    optspec=":hvu-:"
    while getopts "$optspec" optchar; do
        case "${optchar}" in
            -)
                case "${OPTARG}" in
                    help) print_help ;;
                    upgrade) UPGRADE=true ;;
                    verbose) LOG=/dev/stdout ;;
                esac;;
            h) print_help ;;
            v) LOG=/dev/stdout;;
            u) UPGRADE=true;;
        esac
    done
}

run_and_log(){
    $1 &> ${LOG} && {
        _log_icon=$log_icon_ok
    } || {
        _log_icon=$log_icon_nok
        exit_=1
    }
    echo -e "${_log_icon} ${2}"
    [[ $exit_ ]] && { echo -e "\t -> ${_log_icon} $3";  exit; }
}

clone_repos(){
    git clone ${YARA_REPO}
    return 0
}

cdcuckoo(){
    eval cd ~${CUCKOO_USER}
    return 0
}

create_cuckoo_user(){
#    $SUDO adduser  -gecos "" ${CUCKOO_USER}
#    $SUDO echo ${CUCKOO_PASSWD} | passwd ${CUCKOO_USER} --stdin
    $SUDO adduser --disabled-login -gecos "" ${CUCKOO_USER}
    echo -e "${CUCKOO_PASSWD}\n${CUCKOO_PASSWD}" | $SUDO passwd ${CUCKOO_USER}
    $SUDO usermod -G vboxusers ${CUCKOO_USER}
    return 0
}

allow_tcpdump(){
    $SUDO /bin/bash -c 'setcap cap_net_raw,cap_net_admin=eip /usr/sbin/tcpdump' 2 &> /dev/null
    $SUDO aa-disable /usr/sbin/tcpdump
    return 0
}

build_yara(){
    cd ${TMPDIR}/yara
    ./bootstrap.sh
    $SUDO autoreconf -vi --force
    ./configure --enable-cuckoo --enable-magic
    make
    $SUDO make install
    cd yara-python/
    $SUDO python setup.py install
    cd ${TMPDIR}
    return 0
}

build_volatility(){
    wget $VOLATILITY_URL
    unzip volatility_2.6_lin64_standalone.zip
    cd volatility_2.6_lin64_standalone
    sudo mv volatility_2.6_lin64_standalone /usr/local/bin/volatility
    return 0
}

install_packages(){
    $SUDO wget -qO - https://www.mongodb.org/static/pgp/server-4.2.asc | sudo apt-key add -
    $SUDO echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu bionic/mongodb-org/4.2 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.2.list
    $SUDO apt update
    $SUDO apt install -y ${packages["${RELEASE}"]}
    $SUDO apt install -y $CUSTOM_PKGS
    $SUDO apt -y install 
    return 0
}

install_python3_packages(){
    pip install $python3_packages --upgrade
    return 0
}

install_python2_packages(){
    virtualenv cuckoo-venv
    . cuckoo-venv/bin/activate
    pip install $python2_packages --upgrade
    . cuckoo-venv/bin/deactivate
    return 0
}

run_cuckoo_community(){
    runuser -l $CUCKOO_USER -c 'cuckoo'
    runuser -l $CUCKOO_USER -c 'cuckoo community'
    return 0
}

create_virt_vm(){
	if [ ! -f $DISKPATH ]; then
		qemu-img create -f qcow2 $DISKPATH 80G
	fi
	virt-install --name="$VMNAME-test" --os-type=windows --os-variant win7 --network network=default,model=virtio --disk path=$DISKPATH-test,format=qcow2,device=disk,bus=virtio --cdrom $ISOPATH$CDROM --disk path=$ISOPATH$VIRTIO,device=floppy --graphics vnc,listen=0.0.0.0 --ram=1024 --vcpus 2 &

}


create_cuckoo_startup_scripts(){
    $SUDO rm /root/cuckoo-start.sh
    $SUDO rm /root/cuckoo-kill.sh
    $SUDO echo "#!/bin/bash" >> /root/cuckoo-start.sh
    $SUDO echo "# Cuckoo run script" >> /root/cuckoo-start.sh
    $SUDO echo "#!/bin/bash" >> /root/cuckoo-kill.sh
    $SUDO echo "# Cuckoo run script" >> /root/cuckoo-kill.sh
    $SUDO echo "killall cuckoo" >> /root/cuckoo-start.sh
    $SUDO echo "pkill -f 'cuckoo web runserver'" >> /root/cuckoo-start.sh

    $SUDO echo "vboxmanage dhcpserver modify --ifname $VIRTUALBOX_INT_NAME --disable" >> /root/cuckoo-start.sh
    $SUDO echo "vboxmanage hostonlyif ipconfig $VIRTUALBOX_INT_NAME --ip $VIRTUALBOX_INT_ADDR --netmask $VIRTUALBOX_INT_SUBNET" >> /root/cuckoo-start.sh
    $SUDO echo "iptables -A FORWARD -o $INTERNET_INT_NAME -i $VIRTUALBOX_INT_NAME -s $VIRTUALBOX_INT_NETWORK -m conntrack --ctstate NEW -j ACCEPT" >> /root/cuckoo-start.sh
    $SUDO echo "iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT" >> /root/cuckoo-start.sh
    $SUDO echo "iptables -A POSTROUTING -t nat -j MASQUERADE" >> /root/cuckoo-start.sh
    $SUDO echo "sysctl -w net.ipv4.ip_forward=1" >> /root/cuckoo-start.sh

    $SUDO echo "killall cuckoo" >> /root/cuckoo-kill.sh
    $SUDO echo "pkill -f 'cuckoo web runserver'" >> /root/cuckoo-kill.sh
    $SUDO echo "runuser -l cuckoo -c 'cuckoo' &" >> /root/cuckoo-start.sh
    $SUDO echo "runuser -l cuckoo -c 'cuckoo web runserver 0.0.0.0:8000' &" >> /root/cuckoo-start.sh
    $SUDO echo "runuser -l cuckoo -c 'cuckoo api --host 0.0.0.0 --port 8090' &" >> /root/cuckoo-start.sh
    $SUDO sed -i "/# By default this script does nothing./ { N; s/# By default this script does nothing./&\n\/root\/cuckoo-start.sh\n/ }" /etc/rc.local

    $SUDO chmod +x /root/cuckoo-start.sh
    $SUDO chmod +x /root/cuckoo-kill.sh
}

# Init.

print_copy
check_viability
setopts ${@}

# Load config

source config &>/dev/null

echo "Logging enabled on ${LOG}"

# Install packages
#run_and_log install_packages "Installing packages ${CUSTOM_PKGS} and ${packages[$RELEASE]}" "Something failed installing packages, please look at the log file"

# Create user and clone repos
# Not creating a user; ubuntu requires a non-root user already
# run_and_log create_cuckoo_user "Creating cuckoo user" "Could not create cuckoo user"
#run_and_log clone_repos "Cloning repositories" "Could not clone repos"

# Install python packages
#run_and_log install_python2_packages "Installing python2 packages: ${python_packages}" "Something failed install python packages, please look at the log file"
#run_and_log install_python3_packages "Installing python3 packages: ${python_packages}" "Something failed install python packages, please look at the log file"

# Install volatility
if [ ! -f /usr/local/bin/volatility ]; then
	run_and_log build_volatility "Installing volatility"
else
	echo "Found volality, not installing"
fi

run_and_log create_virt_vm "libvirt VM created" "failed to create the VM"
# Networking (latest, because sometimes it crashes...)
#run_and_log create_hostonly_iface "Creating hostonly interface for cuckoo"
#run_and_log allow_tcpdump "Allowing tcpdump for normal users"

# Preparing VirtualBox VM
#run_and_log import_virtualbox_vm "Importing specified VirtualBoxVM"
#run_and_log launch_virtualbox_vm "Launching imported VM"
#sleep 60
#run_and_log create_virtualbox_vm_snapshot "Creating snapshot 'Clean'"
#run_and_log poweroff_virtualbox_vm

# Configuring Cuckoo
run_and_log run_cuckoo_community "Downloading community rules"
run_and_log update_cuckoo_config "Updating Cuckoo config files"
run_and_log create_cuckoo_startup_scripts "Creating Cuckoo startup scripts"

