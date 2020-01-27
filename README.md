# cuckoo-kvm
Files to make a Cuckoo sandbox VM using KVM. This project assumes you have your own sandbox installation medium (Windows 7).

|File|Use|
|----|---|
|cuckoo-install.sh|This script automates the installation of Cuckoo dependencies, sets up a VM, and copies systemd unit files for Cuckoo|
|Windows7Sandbox.xml|An XML definition for a KVM domain. You should modify this to suit your environment/requirements|
|cuckoo\*.service|systemd unit files for the various Cuckoo services|

# Using these files
First, you should view and edit the Windows7Sandbox.xml file. A KVM domain (Virtual Machine) will be created based off of this file. Tags you may want to review:
* memory
* disk -> source
* graphics -> vnc port

Next, review cuckoo-install.sh. This script will install software, create a VM, and start cuckoo services. Check the variables towards the topand make sure the URLs and paths line up to what you want.

Use cuckoo-install.sh to install dependencies and Cuckoo. The script will define a sandbox VM based off the provided XML file, and pause so that you have time to configure the sandbox. See [the documentation](https://cuckoo.sh/docs/installation/guest/index.html).
