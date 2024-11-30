#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意: 请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "目前暂不支持你的VPS的操作系统！" && exit 1

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

archAffix(){
    case "$(uname -m)" in
        x86_64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        * ) red "不支持的CPU架构!" && exit 1 ;;
    esac
}

realip(){
    ip=$(curl -s4m8 ip.sb -k) || ip=$(curl -s6m8 ip.sb -k)
}

check_ip(){
    warpv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warpv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ $warpv4 =~ on|plus || $warpv6 =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        systemctl stop warp-go >/dev/null 2>&1
        realip
        systemctl start warp-go >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
    else
        realip
    fi
}

tuic_cert(){

        cert_path="/root/bing/cert.crt"
        key_path="/root/bing/private.key"
        domain="www.bing.com"

        mkdir /root/bing && cd /root/bing

        openssl ecparam -genkey -name prime256v1 -out private.key
        openssl req -new -x509 -days 36500 -key private.key -out cert.crt -subj "/CN=www.bing.com"
}

tuic_port(){
    read -p "设置 tuic 端口 [1-65535]（回车则随机分配端口）：" port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
            read -p "设置 tuic 端口 [1-65535]（回车则随机分配端口）：" port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done
    yellow "将在 tuic 节点使用的端口是：$port"
}




inst_tuv5(){
    if [[ $(tuic -v) == "0.8.5" ]]; then
        red "检测到已安装 Tuic V4，请先卸载再安装 Tuic V5！"
        exit 1
    fi

    check_ip

    if [[ ! ${SYSTEM} == "CentOS" ]]; then
        ${PACKAGE_UPDATE}
    fi
    ${PACKAGE_INSTALL} wget curl sudo

    wget https://gitlab.com/Misaka-blog/tuic-script/-/raw/main/files/tuic-server-latest-linux-$(archAffix) -O /usr/local/bin/tuic
    if [[ -f "/usr/local/bin/tuic" ]]; then
        chmod +x /usr/local/bin/tuic
    else
        red "Tuic V5 内核安装失败！"
        exit 1
    fi

    tuic_cert
    tuic_port

    read -p "设置 tuic UUID（回车跳过为随机 UUID）：" uuid
    [[ -z $uuid ]] && uuid=$(cat /proc/sys/kernel/random/uuid)
    yellow "使用在 tuic 节点的 UUID 为：$uuid"

    read -p "设置 tuic 密码（回车跳过为随机字符）：" passwd
    [[ -z $passwd ]] && passwd=$(date +%s%N | md5sum | cut -c 1-8)
    yellow "使用在 tuic 节点的密码为：$passwd"

    green "正在配置 Tuic..."
    if [[ $domain == "www.bing.com" ]]; then
        finaldomain=$ip
        snidomain=$domain
    else
        finaldomain=$domain
        snidomain=$domain
    fi

    mkdir /etc/tuic >/dev/null 2>&1
    cat << EOF > /etc/tuic/tuic.json
{
    "server": "[::]:$port",
    "users": {
        "$uuid": "$passwd"
    },
    "certificate": "$cert_path",
    "private_key": "$key_path",
    "congestion_control": "bbr",
    "alpn": ["h3"],
    "log_level": "warn"
}
EOF

    mkdir /root/tuic >/dev/null 2>&1
    cat << EOF > /root/tuic/tuic-client.json
{
    "relay": {
        "server": "$finaldomain:$port",
        "uuid": "$uuid",
        "password": "$passwd",
        "ip": "$ip",
        "congestion_control": "bbr",
        "alpn": ["h3"]
    },
    "local": {
        "server": "127.0.0.1:6080"
    },
    "log_level": "warn"
}
EOF
    cat << EOF > /root/tuic/tuic.txt
Sagernet、Nekobox 与 小火箭 配置说明（以下6项必填）：
{
    服务器地址：$finaldomain
    服务器端口：$port
    UUID: $uuid
    密码：$passwd
    SNI: $snidomain
    ALPN：h3
    UDP 转发：开启
    UDP 转发模式：QUIC
    拥塞控制：bbr
    跳过服务器证书验证：开启
}
EOF

    url="tuic://$uuid:$passwd@$finaldomain:$port?congestion_control=bbr&udp_relay_mode=quic&alpn=h3#tuicv5-misaka"
    echo ${url} > /root/tuic/url.txt

    systemctl daemon-reload
    systemctl enable tuic
    systemctl start tuic
    
    if [[ -n $(systemctl status tuic 2>/dev/null | grep -w active) && -f '/etc/tuic/tuic.json' ]]; then
        green "tuic 服务启动成功"
    else
        red "tuic 服务启动失败，请运行 systemctl status tuic 查看服务状态并反馈，脚本退出" && exit 1
    fi

    showconf
}

unst_tuv5(){
    systemctl stop tuic
    systemctl disable tuic
    rm -f /etc/systemd/system/tuic.service /root/tuic.sh
    rm -rf /usr/local/bin/tuic /etc/tuic /root/tuic
    
    green "Tuic V5 已彻底卸载完成！"
}

starttuic(){
    systemctl start tuic
    systemctl enable tuic >/dev/null 2>&1
}

stoptuic(){
    systemctl stop tuic
    systemctl disable tuic >/dev/null 2>&1
}

tuicswitch(){
    yellow "请选择你需要的操作："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} 启动 Tuic"
    echo -e " ${GREEN}2.${PLAIN} 关闭 Tuic"
    echo -e " ${GREEN}3.${PLAIN} 重启 Tuic"
    echo ""
    read -rp "请输入选项 [0-3]: " switchInput
    case $switchInput in
        1 ) starttuic ;;
        2 ) stoptuic ;;
        3 ) stoptuic && starttuic ;;
        * ) exit 1 ;;
    esac
}

changeport(){
    if [[ $(tuic -v) == "0.8.5" ]]; then
        oldport=$(cat /etc/tuic/tuic.json 2>/dev/null | sed -n 2p | awk '{print $2}'| tr -d ',')

        read -p "设置 tuic 端口 [1-65535]（回车则随机分配端口）：" port
        [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)

        until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
            if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
                echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
                read -p "设置 tuic 端口 [1-65535]（回车则随机分配端口）：" port
                [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
            fi
        done

        sed -i "2s/$oldport/$port/g" /etc/tuic/tuic.json
        sed -i "4s/$oldport/$port/g" /root/tuic/tuic-client.json
        sed -i "4s/$oldport/$port/g" /root/tuic/tuic.txt
        sed -i "19s/$oldport/$port/g" /root/tuic/clash-meta.yaml
        sed -i "s/$oldport/$port/g" /root/tuic/url.txt

        stoptuic && starttuic

        green "Tuic V4 节点端口已成功修改为：$port"
        yellow "请手动更新客户端配置文件以使用节点"
        showconf
    else
        oldport=$(cat /etc/tuic/tuic.json 2>/dev/null | sed -n 2p | awk '{print $2}' | tr -d ',' | awk -F ":" '{print $4}' | tr -d '"')
    
        read -p "设置 tuic 端口[1-65535]（回车则随机分配端口）：" port
        [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)

        until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
            if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
                echo -e "${RED} $port ${PLAIN} 端口已经被其他程序占用，请更换端口重试！"
                read -p "设置 tuic 端口[1-65535]（回车则随机分配端口）：" port
                [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
            fi
        done

        sed -i "2s/$oldport/$port/g" /etc/tuic/tuic.json
        sed -i "3s/$oldport/$port/g" /root/tuic/tuic-client.json
        sed -i "4s/$oldport/$port/g" /root/tuic/tuic.txt
        sed -i "19s/$oldport/$port/g" /root/tuic/clash-meta.yaml

        stoptuic && starttuic

        green "Tuic 节点端口已成功修改为：$port"
        yellow "请手动更新客户端配置文件以使用节点"
        showconf
    fi
}

changetoken(){
    oldtoken=$(cat /etc/tuic/tuic.json 2>/dev/null | sed -n 3p | awk '{print $2}' | tr -d ',[]"')

    read -p "设置tuic Token（回车跳过为随机字符）：" token
    [[ -z $token ]] && token=$(date +%s%N | md5sum | cut -c 1-8)

    sed -i "3s/$oldtoken/$token/g" /etc/tuic/tuic.json
    sed -i "5s/$oldtoken/$token/g" /root/tuic/tuic-client.json
    sed -i "5s/$oldtoken/$token/g" /root/tuic/tuic.txt
    sed -i "21s/$oldtoken/$token/g" /root/tuic/clash-meta.yaml
    sed -i "s/$oldtoken/$token/g" /root/tuic/url.txt

    stoptuic && starttuic

    green "Tuic 节点 Token 已成功修改为：$token"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

changeuuid(){
    olduuid=$(cat /etc/tuic/tuic.json 2>/dev/null | sed -n 4p | awk '{print $1}' | tr -d ':"')

    read -p "设置 tuic UUID（回车跳过为随机 UUID）：" uuid
    [[ -z $uuid ]] && uuid=$(cat /proc/sys/kernel/random/uuid)

    sed -i "3s/$olduuid/$uuid/g" /etc/tuic/tuic.json
    sed -i "4s/$olduuid/$uuid/g" /root/tuic/tuic-client.json
    sed -i "5s/$olduuid/$uuid/g" /root/tuic/tuic.txt
    sed -i "21s/$olduuid/$uuid/g" /root/tuic/clash-meta.yaml

    stoptuic && starttuic

    green "Tuic 节点 UUID 已成功修改为：$uuid"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

changepasswd(){
    oldpasswd=$(cat /etc/tuic/tuic.json 2>/dev/null | sed -n 4p | awk '{print $2}' | tr -d '"')

    read -p "设置 tuic 密码（回车跳过为随机字符）：" passwd
    [[ -z $passwd ]] && passwd=$(date +%s%N | md5sum | cut -c 1-8)

    sed -i "3s/$oldpasswd/$passwd/g" /etc/tuic/tuic.json
    sed -i "5s/$oldpasswd/$passwd/g" /root/tuic/tuic-client.json
    sed -i "6s/$oldpasswd/$passwd/g" /root/tuic/tuic.txt
    sed -i "22s/$oldpasswd/$passwd/g" /root/tuic/clash-meta.yaml

    stoptuic && starttuic

    green "Tuic 节点密码已成功修改为：$passwd"
    yellow "请手动更新客户端配置文件以使用节点"
    showconf
}

changeconf(){
    if [[ $(tuic -v) == "0.8.5" ]]; then
        green "Tuic V4 配置变更选择如下:"
        echo -e " ${GREEN}1.${PLAIN} 修改端口"
        echo -e " ${GREEN}2.${PLAIN} 修改Token"
        echo ""
        read -p " 请选择操作[1-2]：" confAnswer
        case $confAnswer in
            1 ) changeport ;;
            2 ) changetoken ;;
            * ) exit 1 ;;
        esac
    else
        green "Tuic V5 配置变更选择如下:"
        echo -e " ${GREEN}1.${PLAIN} 修改端口"
        echo -e " ${GREEN}2.${PLAIN} 修改 UUID"
        echo -e " ${GREEN}3.${PLAIN} 修改密码"
        echo ""
        read -p " 请选择操作 [1-3]：" confAnswer
        case $confAnswer in
            1 ) changeport ;;
            2 ) changeuuid ;;
            3 ) changepasswd ;;
            * ) exit 1 ;;
        esac
    fi
}

showconf(){
    yellow "客户端配置文件 tuic-client.json 内容如下，并保存到 /root/tuic/tuic-client.json"
    red "$(cat /root/tuic/tuic-client.json)"
    yellow "Clash Meta 客户端配置文件已保存到 /root/tuic/clash-meta.yaml"
    yellow "Tuic 节点配置明文如下，并保存到 /root/tuic/tuic.txt"
    red "$(cat /root/tuic/tuic.txt)"
    yellow "Tuic 节点链接如下，并保存到 /root/tuic/url.txt"
    red "$(cat /root/tuic/url.txt)"
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#                    ${RED}Tuic 一键安装脚本${PLAIN}                      #"
    echo "#############################################################"
    echo ""
    echo " -------------"
    echo -e " ${GREEN}1.${PLAIN} 安装 Tuic V5"
    echo -e " ${GREEN}2.${PLAIN} ${RED}卸载 Tuic V5${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} 关闭、启动、重启 Tuic"
    echo -e " ${GREEN}4.${PLAIN} 修改 Tuic 配置"
    echo -e " ${GREEN}5.${PLAIN} 显示 Tuic 配置文件"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请输入选项 [0-5]: " menuInput
    case $menuInput in

        1 ) inst_tuv5 ;;
        2 ) unst_tuv5 ;;
        3 ) tuicswitch ;;
        4 ) changeconf ;;
        5 ) showconf ;;
        * ) exit 1 ;;
    esac
}

menu