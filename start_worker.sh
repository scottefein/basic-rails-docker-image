#!/bin/bash
#
# This is script to start any amount of workers
# of different types in Docker containers.
#
###########################################

function usage {
    cat << EOF
Usage:
$0 -w <worker_type> -r <repository> [-c <count>] [-p <private_port>] [-s] [-S] [R] [D]

    -c Count of workers (1 by default)
    -D Delete all containers of specifid worker
    -p Private port of a container which should be bind on host machine. It is used for web worker only (3000 by default)
    -r Docker repository name. Note: Tag of the image should be the same as worker name (clock, rescue, etc)
    -R Reload container with a new code base: stop -> delete -> run.
    -S Shutdown all containers.
    -s Stop all containers of specified worker.
    -w Type of worker (i.e. worker name: web, clock, rescue, etc)

Example 1 - starts 3 web processes containers:
    $0 -w web -c 3 -p 3000 -r ubuntu

Example 2 - starts 1 clock process container:
    $0 -w clock -r ubuntu

EOF
    exit 2
}

function check_args {
# Check variables
    if [ -z $WORKER ]; then
        echo -e "\e[31mWorker type is missed! Aborting...\e[0m"
        usage
    fi
    if [ -z $COUNT ]; then
        echo "Number of processes is set to 1 by default."
        COUNT=1
    fi
    if [[ $WORKER == 'web' && -z $PORT_PRIVATE ]]; then
        echo "Private port is missed. Set 3000 by default."
        PORT_PRIVATE=3000
    fi
    if [ -z $REPOSITORY ]; then
        echo -e "\e[31mRepository is missed! Aborting...\e[0m"
        usage
    fi
}

function stop_all {
# Stop all running containers
    echo "You're about to stop all running containers."
    echo "Are you sure this is exactly what you want? [Y/n]"
    read approve
    if [ $approve != 'Y' ]; then
        echo 'Nothing stopped.'
        exit 1
    fi
    echo 'Stopping containers:'
    for cont in `docker ps | grep -v CONTAINER | cut -d' ' -f1`; do
        # Remove port from LB in case container is web process
        name=`docker ps | grep $cont | awk {'print $14'}`
        lb_del $name

        monit_del $cont
        echo `docker kill $cont`
    done
    echo -e "[31m Containers are not erased so you can start them manually. [0m"
    echo 'Done'
}

function stop_container {
# Stop containers of specified type and remove them
# Arg1 is worker type
    echo "Stopping $1 containers:"
    for cont in `docker ps | grep $1 | grep -v CONTAINER | cut -d' ' -f1`; do
        # Remove port from LB in case container is web process
        name=`docker ps | grep $cont | awk {'print $14'}`
        lb_del $name

        monit_del $cont
        echo `docker kill $cont`
    done
    echo -e "\e[31mContainers are not erased so you can start them manually.\e[0m"
    echo 'Done'
}

function lb_add {
# Adds backend into LB config. Send port as an argument!
# Arg1 is worker type
    echo "Adding port to LB config: /etc/nginx/nginx.conf"
    sed -i "/upstream application / a server localhost:$1;" /etc/nginx/nginx.conf
    /etc/init.d/nginx restart
}

function lb_del {
# Removes backend from LB config. Send port as an argument!
# Arg1 is web worker name which contains port
    port=${1//web_process/}
    #port=$(echo $1 | sed 's/.*\([a-z]\)//')
    echo $port
    echo "Deleting port $port from LB config..."
    sed -i "/$port/ d" /etc/nginx/nginx.conf
    /etc/init.d/nginx restart
}

function monit_add {
# Adds container to Monit config
# Arg1 is worker type, Arg2 is container ID
    w_type=$1
    cont_id=$2
    echo "Adding container to Monit config..."
    echo -e "check process $cont_id matching \"$cont_id\"\n start = \"/usr/bin/docker start $cont_id\"\n stop = \"/usr/bin/docker stop $cont_id\"\n" >> /etc/monit/monitrc
    /etc/init.d/monit restart
}

function monit_del {
# Removes container from Monit config
# Arg1 is container ID
    echo "Deleting container from Monit config..."
    sed -i "/$1/ d" /etc/monit/monitrc
    sed -i "/start $1/ d" /etc/monit/monitrc
    sed -i "/stop $1/ d" /etc/monit/monitrc
    /etc/init.d/monit restart
}

function start_web {
# Starts web worker and bind port to a host machine
# Arg1 is worker type
    last_used_port=`cat /etc/nginx/nginx.conf | grep localhost | cut -d':' -f2 | cut -d';' -f1| sort | tail -1`
    exist_workers=`docker ps | grep $1 | wc -l`
    to_start=$(expr $COUNT - $exist_workers)
    if [ $to_start > 0 ]; then
        echo "Need to start $to_start workers"
        for n in $(seq 1 $to_start); do
	        used_port=$(expr $last_used_port + $n)
            cont_id=`docker run -d -name web_process$used_port -p $used_port:$PORT_PRIVATE $REPOSITORY:$1`
            if [ -z $cont_id ]; then
                echo "Aborting..."
                exit 1
            fi
            echo "$cont_id Started"
            lb_add $used_port
            monit_add $1 $cont_id
        done
    else
        echo "No need to start more containers"
    fi
}

function start_worker {
# Start worker by argument
# Arg1 is worker type
    exist_workers=`docker ps | grep $1 | wc -l`
    to_start=$(expr $COUNT - $exist_workers)
    if [ $to_start > 0 ]; then
        echo "Need to start $to_start workers"
        for n in $(seq 1 $to_start); do
            num=$(expr $exist_workers + $n)
            cont_id=`docker run -d -name $1$num $REPOSITORY:$1`
            if [ -z $cont_id ]; then
                echo "Aborting..."
                exit 1
            fi
            echo "$cont_id Started"
            monit_add $1 $cont_id
        done
    else
        echo "No need to start more containers"
    fi
}

function run_container {
# run specified number of instances of some process
    echo "Required $COUNT number(s) of $WORKER process..."
    case $WORKER in
        web)
            start_web web;;
        clock | worker | resque )
            start_worker $WORKER ;;
        *)
            echo -e "\e[31mERROR:Unknown type of worker: $WORKER\e[0m"
            exit 1
            ;; 
    esac
}

function erase_container {
# Removes container from disk
# Arg1 is container ID
    echo "Removing container from system"
    echo `docker rm $1`
}

function del_container {
# Remove all containers of specified worker
# Arg1 is worker type
    echo "You're about to delete $1 container(s)."
    echo "Do you really want to proceed? [Y/n]"
    read approve
    if [ $approve != 'Y' ]; then
        echo 'Operation aborted.'
        exit 1
    fi
    # Check if container is running
    for name in `docker ps -a | grep $1 | grep -v CONTAINER | awk {'print $14'}`; do
        echo "$name is still running. You need to stop it first! Aborting..."
        exit 1
    done

    for cont in `docker ps -a | grep $1 | grep -v CONTAINER | cut -d' ' -f1`; do
        erase_container $cont
    done
    echo 'Done'
}

######## MAIN ################
while getopts "hsSRDw:c:p:r:" OPTION; do
    case $OPTION in
        w)  WORKER=$OPTARG ;;  # Type of process to start (e.g. web, resque, worker, etc)
        c)  COUNT=$OPTARG ;;  # Number of workers to run
        p)  PORT_PRIVATE=$OPTARG ;;  # Port which is listening at container.
        r)  REPOSITORY=$OPTARG ;;  # Repository of a containers
        R)  check_args
            echo -e "Reloading $WORKER containers...\n"
            stop_container $WORKER
            yes 'Y' | del_container $WORKER
            run_container
            exit 0
            ;;
        S)  stop_all ;; 
        s)  if [ -z $WORKER ]; then
                echo -e "\e[31mWorker type is missed! Aborting...\e[0m"
                exit 1
            else
                stop_container $WORKER
                exit 0
            fi
            ;;
        D)  if [ -z $WORKER ]; then
                echo -e "\e[31mWorker type is missed! Aborting...\e[0m"
                exit 1
            else
                del_container $WORKER
                exit 0
            fi
            ;;
        h | ?)  usage ;;
    esac
done

check_args
run_container

exit 0
