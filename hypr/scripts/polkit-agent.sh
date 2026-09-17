#!/bin/bash
# Start the first available polkit authentication agent.
#
# The agent's package (and therefore binary path) differs per distro:
# polkit-gnome is absent on Fedora and dropped in Debian 13, where mate-polkit
# or lxpolkit provide the agent instead. Launch whichever exists, so privileged
# prompts keep working on every family.
for a in \
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
    /usr/libexec/polkit-gnome-authentication-agent-1 \
    /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 \
    /usr/libexec/polkit-mate-authentication-agent-1 \
    /usr/lib/x86_64-linux-gnu/polkit-mate/polkit-mate-authentication-agent-1 \
    /usr/bin/lxpolkit \
    /usr/bin/mate-polkit; do
    [ -x "$a" ] && exec "$a"
done
echo "polkit-agent: no authentication agent found (install polkit-gnome or mate-polkit)" >&2
exit 1
