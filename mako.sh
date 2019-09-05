#!/bin/sh

### BEGIN INIT INFO
# Provides:             mako
# Required-Start:       $remote_fs
# Required-Stop:        $remote_fs
# Default-Start:        2 3 4 5
# Default-Stop:         0 6
# Short-Description:    Mako Server daemon script
### END INIT INFO
#
# description: Mako Server
# processname: mako

start() {
    echo "Starting Mako Server"
    export HOME=/home/mako
    cd /home/mako
    ulimit -n 200000
    echo "File (socket) descriptor limit:"
    ulimit -n
    /bin/mako -d
    RETVAL=$?
    return $RETVAL
}


stop() {
    start-stop-daemon -K -x /bin/mako
    return 0
}

case "$1" in
    start)
        start
        ;;

    boot)
        start
        ;;

    stop)
        stop
        ;;

    restart)
        stop
        sleep 1
        start
        ;;

  *)
        echo "Usage: /etc/init.d/mako.sh {start|stop|restart}"
        exit 1
esac

exit 0
