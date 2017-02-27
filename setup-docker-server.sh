#!/bin/bash
# This script setup a fresh Ubuntu 16.04 server with Custom Kernel compiled specially for Docker

set -e -o pipefail
set -x

DOCKER_VERSION=1.12.3-0~xenial
KERNEL_VERSION=4.9.12

function system_primary_ip {
  # returns the primary IP assigned to eth0
  echo $(/sbin/ifconfig eth0 | awk '/inet / { print $2 }' | sed 's/addr://')
}

function system_set_hostname {
  # $1 - The hostname to define
  HOSTNAME="$1"

  if [ ! -n "$HOSTNAME" ]; then
    echo "Hostname undefined"
    return 1;
  fi

  echo "$HOSTNAME" > /etc/hostname
  hostname -F /etc/hostname
}

function system_add_host_entry {
  IPADDR="$1"
  FQDN="$2"
  HOSTNAME="$3"

  if [ -z "$IPADDR" -o -z "$FQDN" -o -z "$HOSTNAME" ]; then
    echo "IP address and/or FQDN Undefined and/or HOSTNAME Undefined"
    return 1;
  fi

  echo $IPADDR $FQDN $HOSTNAME >> /etc/hosts
}


function user_add_sudo {
  USERNAME="$1"
  USERPASS="$2"

  if [ ! -n "$USERNAME" ] || [ ! -n "$USERPASS" ]; then
    echo "No new username and/or password entered"
    return 1;
  fi

  adduser $USERNAME --disabled-password --gecos ""
  echo "$USERNAME:$USERPASS" | chpasswd
  usermod -aG sudo $USERNAME
}

function user_add_pubkey {
  USERNAME="$1"
  USERPUBKEY="$2"

  if [ ! -n "$USERNAME" ] || [ ! -n "$USERPUBKEY" ]; then
    echo "Must provide a username and the location of a pubkey"
    return 1;
  fi

  if [ "$USERNAME" == "root" ]; then
    mkdir /root/.ssh
    echo "$USERPUBKEY" >> /root/.ssh/authorized_keys
    return 1;
  fi

  mkdir -p /home/$USERNAME/.ssh
  echo "$USERPUBKEY" >> /home/$USERNAME/.ssh/authorized_keys
  chown -R "$USERNAME":"$USERNAME" /home/$USERNAME/.ssh
}

function ssh_disable_root {
  sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
}

function postfix_install_loopback_only {
  # Installs postfix and configure to listen only on the local interface. Also
  # allows for local mail delivery

  echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
  echo "postfix postfix/mailname string localhost" | debconf-set-selections
  echo "postfix postfix/destinations string localhost.localdomain, localhost" | debconf-set-selections
  apt-get -y install postfix
  /usr/sbin/postconf -e "inet_interfaces = loopback-only"
}

# Linode ipv6 is superslow
sysctl -w net.ipv6.conf.eth0.disable_ipv6=1

# Because we are going re-compile the kernel, we will deny starting any services after installing
# it until reboot, at the of this script we will remove this policy
cat > /usr/sbin/policy-rc.d <<EOF
#!/bin/sh
exit 101
EOF
chmod a+x /usr/sbin/policy-rc.d

# Set timezone
timedatectl set-timezone Europe/Amsterdam
dpkg-reconfigure -f noninteractive tzdata

# Add Docker repo
curl -fsSL https://apt.dockerproject.org/gpg | apt-key add -
apt-get update
apt-get install -y software-properties-common build-essential libssl-dev bc htop
add-apt-repository "deb https://apt.dockerproject.org/repo/ ubuntu-$(lsb_release -cs) main"

# Compile Custom Kernel to enable Docker features required by docker check-config.sh
wget -q https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${KERNEL_VERSION}.tar.xz
tar -xf linux-${KERNEL_VERSION}.tar.xz
cd linux-${KERNEL_VERSION}
zcat /proc/config.gz > .config

# Append the missing configs
URL='https://raw.githubusercontent.com/docker/docker/master/contrib/check-config.sh'
wget -q "${URL}" -O - | /bin/bash | grep missing | grep -oP 'CONFIG_[^:]+' | sed -e "s/\x1B\[m/=y/" >> .config

mkdir -p /lib/modules/${KERNEL_VERSION}

make oldconfig
make --jobs=$(nproc) bzImage
make --jobs=$(nproc) modules
make --jobs=$(nproc)
make --jobs=$(nproc) install
make --jobs=$(nproc) modules_install

cd ../
rm -rf linux-${KERNEL_VERSION}*

update-grub

# Freeze kernel because we are compiling it
apt-mark hold linux-image-generic linux-headers-generic grub-pc

# Freeze this package to avoid answering question. TODO: Check ucf
apt-mark hold console-setup

# Update & Install packages
apt-get update
DEBIAN_FRONTEND=noninteractive
apt-get -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" dist-upgrade
apt-get -y -o DPkg::options::="--force-confdef" -o DPkg::options::="--force-confold" --no-install-recommends install \
  git vim tmux docker-engine=${DOCKER_VERSION}
postfix_install_loopback_only

# Freeze Docker as well
apt-mark hold docker-engine

# Configure Docker FileSystem
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/overlay2.conf <<EOF
[Service]
ExecStart= 
ExecStart=/usr/bin/dockerd -H fd:// --storage-driver=overlay2
EOF

# Set hostname
IPADDR=$(system_primary_ip)
system_set_hostname $HOSTNAME
system_add_host_entry $IPADDR $FQDN $HOSTNAME

# Add sudo users
user_add_sudo $SUDO_USER "${SUDO_USER_PASS}"
user_add_pubkey $SUDO_USER "${SUDO_USER_PUBKEY}"
ssh_disable_root

# Add users to docker group
usermod -aG docker $(whoami)
usermod -aG docker $SUDO_USER

# tmux stuff
cat > ~/.tmux.conf <<EOF
set-window-option -g mode-keys vi
set-option -g history-limit 5000
EOF
cp ~/.tmux.conf /home/$SUDO_USER

# Cleanup deny policy, to allow services to start after reboot
rm /usr/sbin/policy-rc.d
