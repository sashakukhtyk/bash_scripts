#!/bin/bash

echo "Start of the network configuration..."

# Get the active network interface (e.g., eth0 or wlan0)
INTERFACE=$(ifconfig -a | awk '/^[a-z]/ {print $1}' | grep -v 'lo' | head -n 1)
echo "Using interface: $INTERFACE"

# If multiple interfaces are found, allow the user to choose
if [ $(ifconfig -a | awk '/^[a-z]/ {print $1}' | grep -v 'lo' | wc -l) -gt 1 ]; then
  echo "Multiple interfaces detected. Please choose one:"
  select INTERFACE in $(ifconfig -a | awk '/^[a-z]/ {print $1}' | grep -v 'lo'); do
    if [ -n "$INTERFACE" ]; then
      echo "You selected: $INTERFACE"
      break
    else
      echo "Invalid selection. Please choose a valid option."
    fi
  done
fi

# Get the IP address assigned to the active interface
IP_ADDRESS=$(ifconfig $INTERFACE | grep 'inet ' | awk '{print $2}')
echo "Current IP Address: $IP_ADDRESS"

# Get the network mask (CIDR) for the active interface
NETMASK=$(ifconfig $INTERFACE | grep 'inet ' | awk '{print $4}')
echo "Netmask: $NETMASK"

# Get the default gateway
GATEWAY=$(route -n | grep '0.0.0.0' | awk '{print $2}')
echo "Default Gateway: $GATEWAY"

# Install necessary dependencies
echo "Installing necessary dependencies..."
sudo apt-get update -y
sudo apt-get install -y net-tools iputils-ping

# Prompt user for a static IP address (optional, to avoid assigning the current IP)
read -p "Enter a static IP address (or press Enter to use current IP: $IP_ADDRESS): " STATIC_IP
STATIC_IP=${STATIC_IP:-$IP_ADDRESS}  # Use current IP if none provided

# Edit the network configuration file to use static IP (optional)
# This step assumes the use of /etc/network/interfaces 
# (modify if using other network management tools like Netplan)
echo "Configuring network settings..."
sudo bash -c "cat > /etc/network/interfaces <<EOF
# Static IP configuration for $INTERFACE
auto $INTERFACE
iface $INTERFACE inet static
    address $STATIC_IP
    netmask $NETMASK
    gateway $GATEWAY
EOF"

# Check if Netplan is used (common in newer Ubuntu versions)
if [ -d "/etc/netplan" ]; then
  echo "Netplan detected. Applying configuration..."
  sudo netplan apply
else
  # Start and enable networking service for systems using /etc/network/interfaces
  echo "Using /etc/network/interfaces for configuration. Restarting networking..."
  if systemctl list-units --type=service | grep -q 'networking.service'; then
    sudo systemctl restart networking
  elif systemctl list-units --type=service | grep -q 'NetworkManager.service'; then
    sudo systemctl restart NetworkManager
  else
    echo "No networking service found to restart. Please restart the network manually."
  fi
fi

# End of the script
echo "We are done!"
