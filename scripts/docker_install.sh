#!/bin/bash

function install_docker() {    
    sudo modprobe overlay
    sudo docker -v 1>/dev/null 2>&1
    if [ $? -eq 0 ]
    then
        id | grep "docker" 1>/dev/null 2>&1
        if [ $? -eq 0 ]
        then
            echo "docker is OK!"
            return 1
        else
            sudo gpasswd -a $USER docker  
            sudo usermod -aG docker $USER
            sudo systemctl restart docker
            echo "please reboot the computer and run the scripts again!"
            return 2
        fi
    else
        curl https://get.docker.com | sh && sudo systemctl --now enable docker
        sudo systemctl restart docker
        sudo gpasswd -a $USER docker  
        sudo usermod -aG docker $USER
        sudo systemctl restart docker
        sudo chmod 777 /var/run/docker.sock
        echo "please reboot the computer and run the scripts again!"
        return 3
    fi

    return 0
}

install_docker
