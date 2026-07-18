FROM archlinux:latest

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm \
        bash \
        fzf \
        git \
        sudo \
        curl \
        figlet \
        gawk \
        sed \
        grep \
        coreutils \
        which \
        util-linux \
        pacman-contrib \
        && \
    pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/*

WORKDIR /opt/hyprtk-on-arch

COPY docker/dry-run.sh /usr/local/bin/dry-run
RUN chmod +x /usr/local/bin/dry-run

ENTRYPOINT ["/usr/local/bin/dry-run"]
