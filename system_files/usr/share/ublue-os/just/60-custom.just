install-system-flatpaks:
    #!/usr/bin/env bash
    if ! flatpak remotes | grep -q flathub; then
        flatpak remote-add --system flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
    flatpak --system -y install --or-update $(curl -s https://raw.githubusercontent.com/ublue-os/bluefin/main/bluefin_flatpaks/flatpaks | tr '\n' ' ')

bluefin-cli:
    /usr/libexec/ublue-bling
