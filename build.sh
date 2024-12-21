#!/bin/bash

set -ouex pipefail

# Image Info
OLD_PRETTY_NAME=$(bash -c 'source /usr/lib/os-release ; echo $NAME $VERSION')
MAJOR_VERSION=$(bash -c 'source /usr/lib/os-release ; echo $VERSION_ID')
IMAGE_PRETTY_NAME="Achillobator"
IMAGE_LIKE="rhel fedora"
HOME_URL="https://projectbluefin.io"
DOCUMENTATION_URL="https://docs.projectbluefin.io"
SUPPORT_URL="https://github.com/centos-workstatiom/achillobator/issues/"
BUG_SUPPORT_URL="https://github.com/centos-workstation/achillobator/issues/"
CODE_NAME="Dromaeosauridae"

IMAGE_INFO="/usr/share/ublue-os/image-info.json"
IMAGE_REF="ostree-image-signed:docker://ghcr.io/$IMAGE_VENDOR/$IMAGE_NAME"

image_flavor="main"
cat > $IMAGE_INFO <<EOF
{
  "image-name": "$IMAGE_NAME",
  "image-flavor": "$image_flavor",
  "image-vendor": "$IMAGE_VENDOR",
  "image-tag": "$MAJOR_VERSION",
  "centos-version": "$MAJOR_VERSION"
}
EOF

# OS Release File (changed in order with upstream)
sed -i "s/^NAME=.*/NAME=\"$IMAGE_PRETTY_NAME\"/" /usr/lib/os-release
sed -i "s|^VERSION_CODENAME=.*|VERSION_CODENAME=\"$CODE_NAME\"|" /usr/lib/os-release
sed -i "s/^ID=centos/ID=${IMAGE_PRETTY_NAME,}\nID_LIKE=\"${IMAGE_LIKE}\"/" /usr/lib/os-release
sed -i "s/^VARIANT_ID=.*/VARIANT_ID=$IMAGE_NAME/" /usr/lib/os-release
sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"${IMAGE_PRETTY_NAME} $MAJOR_VERSION (FROM $OLD_PRETTY_NAME)\"/" /usr/lib/os-release
sed -i "s|^HOME_URL=.*|HOME_URL=\"$HOME_URL\"|" /usr/lib/os-release
echo "DOCUMENTATION_URL=\"$DOCUMENTATION_URL\"" | tee -a /usr/lib/os-release
echo "SUPPORT_URL=\"$SUPPORT_URL\"" | tee -a /usr/lib/os-release
sed -i "s|^BUG_REPORT_URL=.*|BUG_REPORT_URL=\"$BUG_SUPPORT_URL\"|" /usr/lib/os-release
sed -i "s|^CPE_NAME=\"cpe:/o:centos:centos|CPE_NAME=\"cpe:/o:universal-blue:${IMAGE_PRETTY_NAME,}|" /usr/lib/os-release
echo "DEFAULT_HOSTNAME=\"${IMAGE_PRETTY_NAME,,}\"" | tee -a /usr/lib/os-release
sed -i "/^REDHAT_BUGZILLA_PRODUCT=/d; /^REDHAT_BUGZILLA_PRODUCT_VERSION=/d; /^REDHAT_SUPPORT_PRODUCT=/d; /^REDHAT_SUPPORT_PRODUCT_VERSION=/d" /usr/lib/os-release

if [[ -n "${SHA_HEAD_SHORT:-}" ]]; then
  echo "BUILD_ID=\"$SHA_HEAD_SHORT\"" >> /usr/lib/os-release
fi

# Fix issues caused by ID no longer being rhel??? (FIXME: check if this is necessary)
sed -i "s/^EFIDIR=.*/EFIDIR=\"rhel\"/" /usr/sbin/grub2-switch-to-blscfg

# Additions
dnf -y install \
    distrobox \
    gnome-extensions-app \
    gnome-shell-extension-appindicator \
    gnome-shell-extension-dash-to-dock \
    gnome-tweaks

# Removals
dnf -y remove \
    subscription-manager

# Repos 

dnf -y --enablerepo epel-testing install \
  gnome-shell-extension-blur-my-shell fastfetch

dnf config-manager --add-repo https://pkgs.tailscale.com/stable/centos/9/tailscale.repo
dnf config-manager --set-disabled tailscale-stable
dnf -y --enablerepo tailscale-stable install \
  tailscale

dnf config-manager --add-repo "https://repo.charm.sh/yum/"
dnf config-manager --set-disabled repo.charm.sh_yum_
echo -e "gpgcheck=1\ngpgkey=https://repo.charm.sh/yum/gpg.key" | tee -a "/etc/yum.repos.d/repo.charm.sh_yum_.repo"
dnf -y --enablerepo repo.charm.sh_yum_  install \
  glow

dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/ublue-os/staging/repo/centos-stream-${MAJOR_VERSION}/ublue-os-staging-centos-stream-${MAJOR_VERSION}.repo"
dnf config-manager --set-disabled copr:copr.fedorainfracloud.org:ublue-os:staging
dnf -y --enablerepo copr:copr.fedorainfracloud.org:ublue-os:staging install \
  gnome-shell-extension-logo-menu

dnf config-manager --add-repo "https://copr.fedorainfracloud.org/coprs/che/nerd-fonts/repo/centos-stream-${MAJOR_VERSION}/che-nerd-fonts-centos-stream-${MAJOR_VERSION}.repo"
dnf config-manager --set-disabled copr:copr.fedorainfracloud.org:che:nerd-fonts
dnf -y --enablerepo copr:copr.fedorainfracloud.org:che:nerd-fonts install \
  nerd-fonts

# UUPD while it doesnt have a COPR
UUPD_INSTALL=$(mktemp -d)
curl --retry 3 -Lo $UUPD_INSTALL/uupd.tar.gz https://github.com/ublue-os/uupd/releases/download/v0.5/uupd_Linux_x86_64.tar.gz
tar xzf $UUPD_INSTALL/uupd.tar.gz -C $UUPD_INSTALL
cp $UUPD_INSTALL/uupd /usr/bin/uupd
rm -rf $UUPD_INSTALL
tee /usr/lib/systemd/system/uupd.service <<EOF
[Unit]
Description=Universal Blue Update Oneshot Service

[Service]
Type=oneshot
ExecStart=/usr/bin/uupd --log-level debug --json --hw-check
EOF
tee /usr/lib/systemd/system/uupd.timer <<EOF
[Unit]
Description=Auto Update System Timer For Universal Blue
Wants=network-online.target

[Timer]
OnBootSec=20min
OnUnitInactiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
EOF
tee /etc/polkit-1/rules.d/uupd.rules <<EOF
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "uupd.service")
    {
        return polkit.Result.YES;
    }
})
EOF

# Convince the installer we are in CI
touch /.dockerenv

# Workarounds
mkdir -p /var/home
mkdir -p /var/roothome

# Homebrew
curl --retry 3 -Lo /tmp/brew-install https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
chmod +x /tmp/brew-install
/tmp/brew-install
tar --zstd -cvf /usr/share/homebrew.tar.zst /home/linuxbrew/.linuxbrew

rm -f /.dockerenv

# Services
systemctl enable dconf-update.service
# Forcefully enable brew setup since the preset doesnt seem to work?
systemctl enable brew-setup.service
systemctl disable mcelog.service
systemctl enable tailscaled.service
systemctl enable uupd.timer
systemctl disable bootc-fetch-apply-updates.timer bootc-fetch-apply-updates.service
