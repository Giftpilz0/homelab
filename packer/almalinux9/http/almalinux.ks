url --url="https://repo.almalinux.org/almalinux/9/BaseOS/x86_64/os/"
repo --name="AppStream" --baseurl="https://repo.almalinux.org/almalinux/9/AppStream/x86_64/os/"
repo --name="Extras" --baseurl="https://repo.almalinux.org/almalinux/9/extras/x86_64/os/"

text
eula --agreed
firstboot --disable
reboot

lang de_DE.UTF-8
keyboard de
timezone Europe/Berlin

network --device eth0 --bootproto=dhcp
firewall --enabled --service=ssh
services --enabled=sshd
selinux --enforcing

bootloader --location=mbr --driveorder=sda

zerombr
ignoredisk --only-use=sda
clearpart --all --initlabel --disklabel=gpt

part /boot/efi --fstype=efi --size=600
part btrfs.01 --size=4096 --grow

btrfs none --data=0 --metadata=1 --label=btrfs_root btrfs.01
btrfs / --subvol --name=root LABEL=btrfs_root
btrfs /boot --subvol --name=boot LABEL=btrfs_root
btrfs /home --subvol --name=home LABEL=btrfs_root

rootpw --plaintext packer

%packages
@minimal-environment
cloud-utils-growpart
qemu-guest-agent
cloud-init
tar
%end

%post --erroronfail
echo "PermitRootLogin yes" > /etc/ssh/sshd_config.d/allow-root-ssh.conf
dnf clean all
%end
