# Start that bridge on startup
# Comment this line out for the first test. So, in case you loose connection to your server, you can simply restart the server without creating that misconfigured bridge again.
auto vmbr200

# Nearly every name that starts with vmbr can be used.
# Define a static bridge without any parent interfaces
# Use your main ip of your proxmox instance. You can use any /32 private ip as well. This makes no difference.
iface vmbr200 inet static
    address [MAIN IP]/32
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    # Set the mtu explicitly on the bridge interface.
    # Containers will adapt the mtu.
    # VMs do not adapt the mtu by default. Either set it through the gui to 1476 or to 1 (= special meaning, aka adapt the mtu)
    mtu 1476

    # Proxmox Firewall blocks incoming traffic by default. Outgoing traffic is fine.
    # Allow incoming gre traffic
    # You could do this in the gui as well
    # Using -I (for instert instead of append) to have a higher prio as the default proxmox rules
    post-up iptables -I INPUT -s [NOEZ EXTERNAL REMOTE IP] -d [MAIN IP] -p gre -j ACCEPT

    # Create the gre tunnel.
    # You can name your tunnel nearly everything you want. gre0 is prohibited.
    # I prefer some catchy names.
    post-up ip tunnel add greNeptun mode gre local [MAIN IP] remote [NOEZ EXTERNAL REMOTE IP] ttl 255
    post-up ip link set dev greNeptun mtu 1476
    # Add the private tunnel-ip to the gre tunnel.
    # The system knows by /30 that the gateway ip is accessable through the gre tunnel
    post-up ip addr add [NOEZ INTERNAL CLIENT IP]/30 dev greNeptun
    # Start the tunnel
    post-up ip link set dev greNeptun up

    # Put incoming traffic into table 20 (repeat for every additional ip)
    post-up ip rule add to [NOEZ ADDITIONAL PUBLIC IP]/32 table 20 prio 1

    # Route incoming traffic to vmbr200 (repeat for every additional ip)
    post-up ip route add [NOEZ ADDITIONAL PUBLIC IP]/32 dev vmbr200 table 20

    # Put outgoing traffic into table 21 (repeat for every additional ip)
    post-up ip rule add from [NOEZ ADDITIONAL PUBLIC IP]/32 table 21 prio 2

    # Route everything else through the tunnel
    post-up ip route add default via [NOEZ TUNNEL GATEWAY IP] table 21

    # Allow Forwarding between these interfaces
    post-up iptables -I FORWARD -i greNeptun -o vmbr200 -j ACCEPT
    post-up iptables -I FORWARD -i vmbr200 -o vmbr200 -j ACCEPT
    post-up iptables -I FORWARD -i vmbr200 -o greNeptun -j ACCEPT

    # --- CLEAN SHUTDOWN ---

    # Disallow Forwarding
    pre-down iptables -D FORWARD -i greNeptun -o vmbr200 -j ACCEPT
    pre-down iptables -D FORWARD -i vmbr200 -o vmbr200 -j ACCEPT
    pre-down iptables -D FORWARD -i vmbr200 -o greNeptun -j ACCEPT

    # Flush Rules (you do not have do delete every rule manually)
    pre-down ip rule flush table 20
    pre-down ip rule flush table 21

    # Flush Routes (you do not have do delete every route manually)
    pre-down ip route flush table 20
    pre-down ip route flush table 21

    # Stop Tunnel
    pre-down ip link set dev greNeptun down

    # Delete GRE-Tunnel
    pre-down ip link del dev greNeptun

    # Disallow GRE-Tunnel (Deleting the rule)
    pre-down iptables -D INPUT -s [NOEZ EXTERNAL REMOTE IP] -d [MAIN IP] -p gre -j ACCEPT
