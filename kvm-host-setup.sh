# Functions

valid_ip()
{
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

cdr2mask ()
{
   # Number of args to shift, 255..255, first non-255 byte, zeroes
   set -- $(( 5 - ($1 / 8) )) 255 255 255 255 $(( (255 << (8 - ($1 % 8))) & 255 )) 0 0 0
   [ $1 -gt 1 ] && shift $1 || shift
   #echo ${1-0}.${2-0}.${3-0}.${4-0}
   netmask=${1-0}.${2-0}.${3-0}.${4-0}
}

read -e -p "Do you want to start KVM host Installation(y/n) " response
if [[ $response != y ]]; then
	exit
	else
	break
fi

# External Network

while true; do
	read -e -p "Enter External IP for host/gateway (eg. 172.24.19.1): " external
	external=${external:-172.24.19.1} # default 172.24.19.1
#echo $external_prefix
	valid_ip $external
	case "$?" in
	     0)
		break;;
	     *)
		echo "Enter Valid IP: "
		;;
	esac
done        

read -e -p "Enter Prefix (eg. 24): " external_prefix
external_prefix=${external_prefix:-24}
cdr2mask $external_prefix
external_netmask=$netmask

sed -e "s/XXXX/$external/; s/YYYY/$external_netmask/" ./master-xmls/master-external.xml > ./external.xml

while true; do
	read -e -p "Enter External IP for undercloud (eg. 172.24.19.5): " undercloud
	undercloud=${undercloud:-172.24.19.5} # default 172.24.19.5
	valid_ip $undercloud
        case "$?" in
             0)
                break;;
             *)
                echo "Enter Valid IP: "
                ;;
        esac
done

read -e -p "Enter Prefix (eg. 24): " undercloud_prefix
undercloud_prefix=${udercloud_prefix:-24}
cdr2mask $undercloud_prefix
undercloud_netmask=$netmask


sed -e "s/XXXX/$undercloud/; s/YYYY/$undercloud_netmask/; s/ZZZZ/$external/" ./master-network/master-ifcfg-eth0 > ./ifcfg-eth0
# Provisioning Network
while true; do
	read -e -p "Enter Provision IP (eg. 172.24.20.254): " provision
	provision=${provision:-172.24.20.254} # default 172.24.20.254
echo $provision
	valid_ip $provision
        case "$?" in
             0)
                break;;
             *)
                echo "Enter Valid IP: "
                ;;
        esac
done

read -e -p "Enter Prefix (eg. 24): " provision_prefix
provision_prefix=${provision_prefix:-24}
cdr2mask $provision_prefix
provision_netmask=$netmask
sed -e "s/XXXX/$provision/; s/YYYY/$provision_netmask/" ./master-xmls/master-provision.xml > ./provision.xml

while true; do
	read -e -p "Enter Repository IP (eg. 10.30.3.60): " repo
	repo=${repo:-10.30.3.60}
	valid_ip $repo
	        case "$?" in
             0)
                break;;
             *)
                echo "Enter Valid IP: "
                ;;
        esac
done


# controller and Compute VMS input
while true; do
	read -e -p "Number of Controllers (eg. 1): " controllers
	controllers=${controllers:-1} # default
	case "$controllers" in
        0)
            echo "Error, Openstack needs at least one Controller"
            ;;
	[0-9]*)
            break;;

        *)
            echo "Error, please enter a valid number: "
            ;;
    esac
done

while true; do
        read -e -p "Number of Computes (eg. 1): " computes
        computes=${computes:-1} # default
        case "$computes" in
        0)
            echo "Error, Openstack needs at least one Controller"
            ;;
        [0-9]*)
            break;;

        *)
            echo "Error, please enter a valid number: "
            ;;
    esac
done




array=(qemu-kvm qemu-img virt-manager libvirt libvirt-python libvirt-client virt-install virt-viewer bridge-utils libguestfs-tools bind bind-chroot bind-utils ntp httpd httpd-tools tigervnc-server xorg-x11-fonts-Type1)


echo "Packages Needed to be Installed"
echo "  "
echo "${array[@]}"
read -e -r -p "Do you wish to continue [y/n] " response
case "$response" in
    [nN]*)
        exit
        ;;
esac
echo "----------------------------------------"
echo "**** Checking Packages ****"
#yum clean all
#yum update

for pkg in "${array[@]}"
do
pkg="$pkg"


    # grep -ir $pkg /var/cache/yum/ > /dev/null
    yum list $pkg > /dev/null
    # yum search $pkg>/dev/null  
    a=$?
    echo "- $? - $a -"
    if [ $a -eq 0 ]
            then
                    echo "* $pkg * installed or available to be installed"
                    yum  -y install $pkg
            else
                    echo "* $pkg not found or unknown error."
                    echo "* need $pkg to continue"
                    exit
    fi
done

systemctl start libvirtd.service
sleep 3

# Building Network for EX210 Training
virsh net-destroy default
virsh net-destroy external
virsh net-destroy provision
virsh net-undefine external
virsh net-undefine provision

virsh net-define ./external.xml
virsh net-autostart external
virsh net-start external

virsh net-define ./provision.xml
virsh net-autostart provision
virsh net-start provision

sysctl -w net.ipv4.ip_forward=1

# Setting Up undercloud 
virsh destroy undercloud
virsh undefine undercloud
echo $controllers
echo $computes
for i in `seq 1 $controllers`; do virsh destroy controller$controllers; virsh undefine controller$controllers; done
for i in `seq 1 $computes`; do virsh destroy compute$computes; virsh undefine compute$computes; done


ROOTPASSWORD=Root1234
STACKPASSWORD=stack

export LIBGUESTFS_BACKEND=direct
rm -f undercloud.qcow2
qemu-img create -f qcow2 undercloud.qcow2 100G
virt-resize --expand /dev/sda1 rhel-server-7.4-x86_64-kvm.qcow2 undercloud.qcow2
virt-customize  -a undercloud.qcow2 \
  --run-command 'xfs_growfs /' \
  --root-password password:$ROOTPASSWORD \
  --hostname undercloud.osp10.demo \
  --run-command 'useradd stack' \
  --password stack:password:$STACKPASSWORD \
  --run-command 'echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack' \
  --chmod 0440:/etc/sudoers.d/stack \
  --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
  --run-command 'systemctl enable sshd' \
  --run-command 'sudo subscription-manager register --user smasud@salientglobaltech.com --password Nixon123' \
  --run-command 'yum remove -y cloud-init NetworkManager' \
  --copy-in resolv.conf:/etc \
  --copy-in ifcfg-eth0:/etc/sysconfig/network-scripts \
  --copy-in undercloud.conf:/home/stack \
  --copy-in undercloud.tar:/home/stack \
  --run-command 'chown stack:stack /home/stack/undercloud.conf' \
  --run-command 'echo "$undercloud undercloud.osp10.demo undercloud" | tee -a /etc/hosts' \
  --run-command 'echo "$repo repos.osp10.demo repos" | tee -a /etc/hosts' \
  --selinux-relabel
sudo cp undercloud.qcow2 /var/lib/libvirt/images/undercloud.qcow2

virt-install --name undercloud \
  --disk /var/lib/libvirt/images/undercloud.qcow2 \
  --vcpus=4 \
  --ram=16348 \
  --network network=external,model=virtio \
  --network network=provision,model=virtio \
  --virt-type kvm \
  --import \
  --events on_poweroff=preserve \
  --os-variant rhel7 \
  --graphics vnc \
  --serial pty \
  --noautoconsole \
  --console pty,target_type=virtio


# creating controllers and compute VMS

for i in `seq 1 $controllers`; do qemu-img create -f qcow2 -o preallocation=metadata /var/lib/libvirt/images/controller$i.qcow2 60G; done
for i in `seq 1 $controllers`; do virt-install --ram 8192 --vcpus 4 --os-variant rhel7 --disk path=/var/lib/libvirt/images/controller$i.qcow2,device=disk,bus=virtio,format=qcow2 --noautoconsole --vnc --network network:provision --network network:external --network network:external --name controller$i --cpu Westmere,+vmx --dry-run --print-xml > /tmp/controller$i.xml; virsh define --file /tmp/controller$i.xml; done

for i in `seq 1 $computes`; do qemu-img create -f qcow2 -o preallocation=metadata /var/lib/libvirt/images/compute$i.qcow2 60G; done
for i in `seq 1 $computes`; do virt-install --ram 4096 --vcpus 4 --os-variant rhel7 --disk path=/var/lib/libvirt/images/compute$i.qcow2,device=disk,bus=virtio,format=qcow2 --noautoconsole --vnc --network network:provision --network network:external --network network:external --name compute$i --cpu Westmere,+vmx --dry-run --print-xml > /tmp/compute$i.xml; virsh define --file /tmp/compute$i.xml; done

