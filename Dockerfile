FROM ubi8 AS builder
RUN cat /etc/redhat-release
RUN rm -f /etc/yum.repos.d/*
COPY ./tmp.repo /etc/yum.repos.d

RUN if [ $(uname -m) = "x86_64" ]; then \
      yum install -y gcc git make genisoimage xz-devel grub2 grub2-efi-x64 shim dosfstools mtools && \
      dd bs=1024 count=3200 if=/dev/zero of=esp.img && \
      mkfs.msdos -F 12 -n 'ESP_IMAGE' ./esp.img && \
      mmd -i esp.img EFI && \
      mmd -i esp.img EFI/BOOT && \
      mcopy -i esp.img -v /boot/efi/EFI/BOOT/BOOTX64.EFI ::EFI/BOOT && \
      mcopy -i esp.img -v /boot/efi/EFI/redhat/grubx64.efi ::EFI/BOOT && \
      mdir -i esp.img ::EFI/BOOT; \
    else \
      touch /esp.img; \
    fi

FROM ubi8
RUN cat /etc/redhat-release
RUN rm -f /etc/yum.repos.d/*
COPY ./tmp.repo /etc/yum.repos.d

RUN dnf update -y && \
    dnf install -y python3-gunicorn openstack-ironic-api openstack-ironic-conductor crudini \
        iproute iptables dnsmasq httpd qemu-img parted gdisk ipxe-bootimgs psmisc procps-ng \
        mariadb-server ipxe-roms-qemu genisoimage python3-ironic-prometheus-exporter \
        python3-jinja2 python3-sushy-oem-idrac && \
    dnf clean all && \
    rm -rf /var/cache/{yum,dnf}/*

COPY ./prepare-ipxe.sh /tmp
RUN chmod +x /tmp/prepare-ipxe.sh && /tmp/prepare-ipxe.sh && rm /tmp/prepare-ipxe.sh

COPY --from=builder /esp.img /httpboot/uefi_esp.img

COPY ./ironic.conf /tmp/ironic.conf
RUN crudini --merge /etc/ironic/ironic.conf < /tmp/ironic.conf && \
    rm /tmp/ironic.conf

COPY ./runironic-api.sh /bin/runironic-api
COPY ./runironic-conductor.sh /bin/runironic-conductor
COPY ./runironic-exporter.sh /bin/runironic-exporter
COPY ./rundnsmasq.sh /bin/rundnsmasq
COPY ./runhttpd.sh /bin/runhttpd
COPY ./runmariadb.sh /bin/runmariadb
COPY ./configure-ironic.sh /bin/configure-ironic.sh
COPY ./ironic-common.sh /bin/ironic-common.sh

# TODO(dtantsur): remove these 2 scripts if we decide to
# stop supporting running all 2 processes via one entry point.
COPY ./runhealthcheck.sh /bin/runhealthcheck
COPY ./runironic.sh /bin/runironic

COPY ./dnsmasq.conf.j2 /etc/dnsmasq.conf.j2
COPY ./inspector.ipxe /tmp/inspector.ipxe
COPY ./dualboot.ipxe /tmp/dualboot.ipxe

ENTRYPOINT ["/bin/runironic"]
