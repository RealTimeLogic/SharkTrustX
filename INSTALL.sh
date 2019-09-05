
export XUID=`id -u`
if [ "$XUID" != "0" ]; then
    echo "$0 must be run as root"
    echo "Example: sudo $0"
    abort
fi

export BACME=$PWD

#Remove unwanted packages
apt remove apache2.* postfix rpcbind

echo "Installing required packages"
apt-get -y install nano bind9 dnsutils bind9utils

#install Mako
clear
echo "You will now install the Mako Server."
echo "DO NOT SELECT THE LETS ENCRYPT PLUGIN!"
read -p "Press any key to continue."
cd /tmp/
rm * 2>/dev/null
wget http://makoserver.net/install/brokerX86/install.sh;
chmod +x install.sh;
./install.sh

if ! [ -d "/home/mako/www" ]; then
    echo "Oops, something failed!!"
    exit 1
fi

echo "Stopping mako server and removing SMQ broker's www directory"
/etc/init.d/mako.sh stop
rm -rf /home/mako/www
echo "Copying $BACME/www to /home/mako/"
cp -r $BACME/www /home/mako/

echo "Replacing /etc/init.d/mako.sh"
cp $BACME/mako.sh /etc/init.d/mako.sh
chmod +x /etc/init.d/mako.sh

/etc/init.d/bind9 start

cd /home/mako
read -p "Press any key to edit mako.conf using the nano editor."
nano mako.conf
