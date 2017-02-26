# Ubuntu 16.04 Server + Custom Kernel 4.9.12 + Docker 1.12

This script setup a fresh Ubuntu 16.04 server (Linode Image) with Custom Kernel
compiled specially for Docker. It was hassle because you need special
kernel modules to have a valid Docker installation.

### Check your Kernel

To check the needed kernel modules run:

```
wget -q https://raw.githubusercontent.com/docker/docker/master/contrib/check-config.sh -O - | bash
```

### Create Stackscript in Linode

[Create stackscript](https://www.linode.com/docs/platform/stackscripts) with Ubuntu 16.04 LTS & this script:

```
#!/bin/bash

#<UDF name="hostname" label="The hostname for the new Linode.">
# HOSTNAME=
#<UDF name="fqdn" label="The new Linode's Fully Qualified Domain Name">
# FQDN=
#<UDF name="sudo_user" Label="User with sudo" />
# SUDO_USER=
#<UDF name="sudo_user_pass" Label="Sudo user password" />
# SUDO_USER_PASS=
#<UDF name="sudo_user_pubkey" Label="Sudo user public key" />
# SUDO_USER_PUBKEY=

set -e
set -x

wget -q https://raw.githubusercontent.com/laithshadeed/linode-stackscripts/master/setup-docker-server.sh -O - | /bin/bash
touch /tmp/provisioned-successfully
```

You could also run directly inside your server shell:

```
HOSTNAME=your_host
FQDN=your_fqdn
SUDO_USER=your_user
SUDO_USER_PASS=your_pass
SUDO_USER_PUBKEY='your_pub_key'
wget -q https://raw.githubusercontent.com/laithshadeed/linode-stackscripts/master/setup-docker-server.sh -O - | /bin/bash
```
### Create your Image

* Create 'Linode 81920' (Yes I know, it is expensive, but will we just need it for 10-15 min ~ 1 $)
Compiling the Kernal will talk long time. I suggest the following
* Set profile label: 'Ubuntu 16.04-4.9.12 Docker 1.12.3'
* Click 'Rebuild' with your Stackscript or with Ubuntu 16.04. Make sure to choose small disk size ~ 10GB
* It will take 2-3 min to setup (including Kernel compilation). Rename the Disk to 'Ubuntu 16.04-4.9.12 Docker 1.12.3'
* Go back and edit your profile. Now set 'Kernel' dropdown menu to 'Grub2'
* Save & Reboot. Now your Linode should reboot into the newly compiled kernel, 4.9.12.
* To verify. Login and run: `uname -a`. Confirm your docker is running: `ps aux | grep docker`
* Now your disk is ready. Shutdown your Linode.
* Go to your Disk. Click 'Create Image'
* Now you can resize your linode to smaller size or delete it and create new one with that new image.
* When you create new linode. You need to always choose 'Grub2' for kernel and your newly create disk or image.
* Enjoy!

Check [this page](https://www.linode.com/docs/tools-reference/custom-kernels-distros/custom-compiled-kernel-debian-ubuntu)
for some visual explanation.

### Notes

* This script is only tested with Ubuntu 16.04 + Upstream Kernel 4.9.12
  + Docker 1.12.3
* You can try different version by modifying DOCKER_VERSION &
  KERNEL_VERSION in setup-docker-server.sh
* The script do an `apt-mark hold` to freeze `linux-image-generic`, `linux-headers-generic`,
  `grub-pc`, `console-setup`, `docker-engine` versions from being upgraded.
* It is *not* designed to run many times. It assumed to be run only
  *one* time.
