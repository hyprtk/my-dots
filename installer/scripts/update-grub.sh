#!/bin/bash
#
# by hyprtk (Kori Tk) (2026)
# ----------------------------------------------------- 

sudo sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
echo " Enable OS-Prober"

sudo grub-mkconfig -o /boot/grub/grub.cfg

sudo sed -i 's/GRUB_DISABLE_OS_PROBER=false/#GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
echo " Disable OS-Prober"