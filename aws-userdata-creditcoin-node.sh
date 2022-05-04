#!/usr/bin/bash
# set debug mode
set -x
# output log of userdata to /var/log/user-data.log
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# The following AWS USER-DATA script is to provision a Podman CreditCoin Miner/Validator Node
# in AWS in a generic manner.  At the very least, you may want to change the DEFAULT in the
# nodename to something meaningful.  You can either paste it in the console or b64 encode it
# for CLI use.
#
# Notables
# 1. - Uses Podman rather than Docker - initial version runs as system (root)
#    subsequent version will run in systemd user context as I have tested that approach with no issues.
#    - Using root was the only way to limit CPU under a certain discount cloud vps provider...
#    (hint: add --cpus="5.45" as the first option after "podman run" to keep 8 cores under 70% - YMMV.)
#
# 2. - I deploy on RHEL so the build is geared towards dnf flavors.  Have deployed the container under
#    podman running on Ubuntu 20 & 22 with no issues.  Tweak to your needs.
#
# 3. - Installs a custom SELinux profile to accomodate the specific container requirements.
#    Udica is your friend. Don't disable SELinux!
#
# 4. - Data is stored locally at /app/ctcmn
#
# 5. - Sets node IP and node name when container starts
#
# 6. - Sets hostname to match nodename.

# update system
dnf -y upgrade --refresh

# install packages
dnf -y install bash-completion udica podman podman-docker

# install RedHat-Specific items
# dnf -y install rhc rhc-worker-playbook

# create CCMN work dir
mkdir -p /app/ctcmn

# create content for the systemd service
touch /etc/systemd/system/ctcmn-container.service
chmod 0644 /etc/systemd/system/ctcmn-container.service
chown root:root /etc/systemd/system/ctcmn-container.service

# Add Contents to service
(
cat << 'EOP'
# container-ctcmn-container.service
# Tue Apr 12 15:10:12 UTC 2022

[Unit]
Description=Podman container-ctcmn-container.service
Wants=network-online.target
After=network-online.target
RequiresMountsFor=%t/containers

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
# Freshen the variables
# Get External IP for node start
ExecStartPre=sh -c 'echo "EXTIP=$(curl -4 ipinfo.io/ip)" > /etc/bccmn.env'
# Use last 6 characters of AWS instance-ID for node naming.
ExecStartPre=sh -c 'iid=$(curl -s http://169.254.169.254/latest/meta-data/instance-id) && nid=${iid: -6} && echo "NID=$nid" >> /etc/bccmn.env'
ExecStartPre=/bin/rm -f %t/%n.ctr-id
#
# Start Container using SELinux profile, iid in node name.
# Insert your CreatedSS58address in the command below
# Used sh to source variables and call podman as systemd was giving me fits.
# Google it - the pain is real.
#
ExecStart=sh -c 'source /etc/bccmn.env && /usr/bin/podman run --security-opt label=type:ctcmn-container.process --cidfile=%t/%n.ctr-id --cgroups=no-conmon --rm --sdnotify=conmon --replace --name ctcmn-container --detach -p 30333:30333 -v /app/ccmn:/data gluwa/creditcoin:latest --validator --name ctcmn-DEFAULT-$NID --prometheus-external --telemetry-url "wss://telemetry.polkadot.io/submit/ 0" --bootnodes /dns4/bootnode.creditcoin.network/tcp/30333/p2p/12D3KooWAEgDL126EUFxFfdQKiUhmx3BJPdszQHu9PsYsLCuavhb /dns4/bootnode2.creditcoin.network/tcp/30333/p2p/12D3KooWRubm6c4bViYyvTKnSjMicC35F1jZNrzt3MKC9Hev5vbG /dns4/bootnode3.creditcoin.network/tcp/30333/p2p/12D3KooWSdzZaqoDAncrQmMUi34Nr29TayCr4xPvqcJQc5J434tZ --public-addr /dns4/$EXTIP/tcp/30333 --chain mainnet --mining-key <CreatedSS58address> --base-path /data --port 30333'
ExecStop=/usr/bin/podman stop --ignore --cidfile=%t/%n.ctr-id
ExecStopPost=/usr/bin/podman rm -f --ignore --cidfile=%t/%n.ctr-id
Type=notify
NotifyAccess=all

[Install]
WantedBy=default.target
EOP
) > /etc/systemd/system/ctcmn-container.service

# stage selinux container tweaks
(
cat << 'EOP'
(block ctcmn-container
    (blockinherit container)
    (blockinherit restricted_net_container)
    (allow process process ( capability ( chown dac_override fowner fsetid kill net_bind_service net_raw setfcap setgid setpcap setuid sys_chroot )))

    (allow process unreserved_port_t ( tcp_socket (  name_bind )))
    (allow process unreserved_port_t ( tcp_socket (  name_bind )))
    (allow process unreserved_port_t ( tcp_socket (  name_bind )))
    (allow process unreserved_port_t ( tcp_socket (  name_bind )))
    (allow process unreserved_port_t ( udp_socket (  name_bind )))
    (allow process default_t ( dir ( add_name create getattr ioctl lock open read remove_name rmdir search setattr write )))
    (allow process default_t ( file ( append create getattr ioctl lock map open read rename setattr unlink write )))
    (allow process default_t ( fifo_file ( getattr read write append ioctl lock open )))
    (allow process default_t ( sock_file ( append getattr open read write )))
)
EOP
) > /root/ctcmn-container.cil

# systemd enable ctcm-container.service
systemctl daemon-reload
systemctl enable ctcmn-container.service

# set hostname to match node
hiid=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
echo "hid=${hiid: -6}" > /tmp/hid
sh -c 'source /tmp/hid && /usr/bin/hostnamectl set-hostname ctcmn-DEFAULT-$nid'

# insert SEL mod
semodule -i /root/ctcmn-container.cil /usr/share/udica/templates/{base_container.cil,net_container.cil}

# Register with RH:
# rhc connect -a <KEY> -o <ORG>

# Cleanup
rm -f /root/ctcmn-container.cil /tmp/hid

# Relabel and Reboot to apply updates - save headaches.
touch /.autorelabel
/usr/sbin/shutdown -r now
