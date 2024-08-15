#!/bin/bash

# 设置版本号
current_version=20240815001

update_script() {
    # 指定URL
    update_url="https://raw.githubusercontent.com/breaddog100/ore/main/ore.sh"
    file_name=$(basename "$update_url")

    # 下载脚本文件
    tmp=$(date +%s)
    timeout 10s curl -s -o "$HOME/$tmp" -H "Cache-Control: no-cache" "$update_url?$tmp"
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "命令超时"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        echo "下载失败"
        return 1
    fi

    # 检查是否有新版本可用
    latest_version=$(grep -oP 'current_version=([0-9]+)' $HOME/$tmp | sed -n 's/.*=//p')

    if [[ "$latest_version" -gt "$current_version" ]]; then
        clear
        echo ""
        # 提示需要更新脚本
        printf "\033[31m脚本有新版本可用！当前版本：%s，最新版本：%s\033[0m\n" "$current_version" "$latest_version"
        echo "正在更新..."
        sleep 3
        mv $HOME/$tmp $HOME/$file_name
        chmod +x $HOME/$file_name
        exec "$HOME/$file_name"
    else
        # 脚本是最新的
        rm -f $tmp
    fi

}

# 安装MySQL数据库
function mysql_install(){

	# 检查Docker是否已安装
	if [ -x "$(command -v docker)" ]; then
	    echo "Docker is already installed."
	else
	    echo "Docker is not installed. Installing Docker..."
	    # 更新apt包索引
	    sudo apt-get update
	    # 安装包以允许apt通过HTTPS使用仓库
	    sudo apt-get install -y \
	        apt-transport-https \
	        ca-certificates \
	        curl \
	        software-properties-common
	    # 添加Docker的官方GPG密钥
	    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	    # 设置稳定仓库
	    sudo add-apt-repository \
	        "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
	        $(lsb_release -cs) \
	        stable"
	    # 再次更新apt包索引
	    sudo apt-get update -y
	    # 安装最新版本的Docker CE
	    sudo apt-get install -y docker-ce
	    # 输出Docker的版本号来验证安装
	    docker --version
	fi

	sudo docker search mysql
	sudo docker pull mysql:8.0
	sudo docker run -p 3307:3306 --name mysql -e MYSQL_ROOT_PASSWORD=$1 -d mysql:8.0
	sudo apt install mysql-client-core-8.0

}

# 安装基础环境
function basic_env(){
	# 更新软件包
	sudo apt update && sudo apt upgrade -y
	sudo apt install -y curl build-essential jq git libssl-dev pkg-config screen pkg-config libmysqlclient-dev mysql-server
	
	# 安装 Rust 和 Cargo
	echo "正在安装 Rust 和 Cargo..."
	curl https://sh.rustup.rs -sSf | sh -s -- -y
	source $HOME/.cargo/env
	
	# 安装 Solana CLI
	echo "正在安装 Solana CLI..."
	sh -c "$(curl -sSfL https://release.solana.com/v1.18.4/install)"
	
	# 检查 solana-keygen 是否在 PATH 中
	if ! command -v solana-keygen &> /dev/null; then
	    echo "将 Solana CLI 添加到 PATH"
	    export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
	    export PATH="$HOME/.cargo/bin:$PATH"
		echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> ~/.bashrc
		source ~/.bashrc
	fi
}


# 部署节点
function install_node() {
	
	basic_env

	# 安装 Ore CLI
	echo "正在安装 Ore CLI..."
	cargo install ore-cli
	
	# 检查并将Solana的路径添加到 .bashrc，如果它还没有被添加
	grep -qxF 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> ~/.bashrc
	
	# 检查并将Cargo的路径添加到 .bashrc，如果它还没有被添加
	grep -qxF 'export PATH="$HOME/.cargo/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
	
	# 使改动生效
	source ~/.bashrc
	echo "完成部署"
}

# 开始挖矿
function start_mining() {
	source ~/.bashrc
	
	# 提示用户输入RPC配置地址
	read -p "RPC 地址(默认https://api.mainnet-beta.solana.com): "  rpc_address
	# 有效RPC检测
	if [[ -z "$rpc_address" ]]; then
	  echo "RPC地址不能为空。"
	  exit 1
	fi

	# 用户输入要生成的钱包配置文件数量
	read -p "钱包数量: " count
	
	# 用户输入gas费用
	read -p "设置gas费用 (默认为1，建议50万以上): " priority_fee
	priority_fee=${priority_fee:-1}
	
	# 用户输入线程数
	read -p "挖矿线程数 (默认为 4): " threads
	threads=${threads:-4}
	
	# 基础会话名
	session_base_name="ore"
	
	# 启动命令模板，使用变量替代rpc地址、gas费用和线程数
	start_command_template="while true; do ore --rpc $rpc_address --keypair ~/.config/solana/idX.json --priority-fee $priority_fee mine --cores $threads; echo '异常退出，正在重启' >&2; sleep 1; done"

	# 确保.solana目录存在
	mkdir -p ~/.config/solana
	
	# 循环创建配置文件和启动挖矿进程
	for (( i=1; i<=count; i++ ))
	do
	    # 提示用户输入私钥
	    echo "为id${i}.json输入私钥 (格式为包含64个数字的JSON数组):"
	    read -p "私钥: " private_key
	
	    # 生成配置文件路径
	    config_file=~/.config/solana/id${i}.json
	
	    # 直接将私钥写入配置文件
	    echo $private_key > $config_file
	
	    # 检查配置文件是否成功创建
	    if [ ! -f $config_file ]; then
	        echo "创建id${i}.json失败，请检查私钥是否正确并重试。"
	        exit 1
	    fi
	
	    # 生成会话名
	    session_name="${session_base_name}_${i}"
	
	    # 替换启动命令中的配置文件名、RPC地址、gas费用和线程数
	    start_command=${start_command_template//idX/id${i}}
	
	    # 打印开始信息
	    echo "开始挖矿，会话名称为 $session_name ..."
	
	    # 使用 screen 在后台启动挖矿进程
	    screen -dmS "$session_name" bash -c "$start_command"
	
	    # 打印挖矿进程启动信息
	    echo "挖矿进程已在名为 $session_name 的 screen 会话中后台启动。"
	    echo "使用 'screen -r $session_name' 命令重新连接到此会话。"
	done
}

# 查看奖励
function check_multiple() {
	source ~/.bashrc
	echo -n "RPC地址（例如 https://api.mainnet-beta.solana.com）: "
	read rpc_address
	
	# 有效RPC检测
	if [[ -z "$rpc_address" ]]; then
	  echo "RPC地址不能为空。"
	  exit 1
	fi

	echo -n "请输入起始和结束编号，中间用空格分隔（比如10个钱包地址，输入1 10）: "
	read -a range
	
	# 获取起始和结束编号
	start=${range[0]}
	end=${range[1]}
	
	# 执行循环
	for i in $(seq $start $end); do
	  ore --rpc $rpc_address --keypair ~/.config/solana/id$i.json --priority-fee 1 rewards
	done

}

# 领取奖励
function cliam_multiple() {
	source ~/.bashrc
	echo -n "请输入RPC地址（例如：https://api.mainnet-beta.solana.com）: "
	read rpc_address
	
	# 有效RPC检测
	if [[ -z "$rpc_address" ]]; then
	  echo "RPC地址不能为空。"
	  exit 1
	fi
	
	# 提示用户输入gas费用
	echo -n "请输入gas费用（例如：50000）: "
	read priority_fee
	
	# 确认用户输入的是有效的数字
	if ! [[ "$priority_fee" =~ ^[0-9]+$ ]]; then
	  echo "gas费用必须是一个整数。"
	  exit 1
	fi
	
	# 提示用户同时输入起始和结束编号
	echo -n "请输入起始和结束编号，中间用空格分隔比如跑了10个钱包地址，输入1 10即可: "
	read -a range
	
	# 获取起始和结束编号
	start=${range[0]}
	end=${range[1]}
	
	# 无限循环
	while true; do
	  # 执行循环
	  for i in $(seq $start $end); do
	    echo "钱包 $i ， RPC：$rpc_address ， GAS： $priority_fee"
	    ore --rpc $rpc_address --keypair ~/.config/solana/id$i.json --priority-fee $priority_fee claim
	    
	    done
	  echo "成功领取 $start to $end."
	done

}

# 停止挖矿
function stop_mining(){
	screen -ls | grep 'ore' | cut -d. -f1 | awk '{print $1}' | xargs -I {} screen -S {} -X quit
}

# 查看日志
function check_logs() {
    screen -r ore
}

# 本机算力
function benchmark() {
	source ~/.bashrc
	read -p "线程数 : " threads
	ore benchmark --cores "$threads"
}

# 部署集群服务端
function install_server(){
	read -p "请输入RPC: " rpc_address
	# 有效RPC检测
	if [[ -z "$rpc_address" ]]; then
	  echo "RPC地址不能为空。"
	  exit 1
	fi

	read -p "请输入服务端密码: " passwd_server
	read -p "请输入钱包秘钥: " private_key
	# 有效秘钥检测
	if [[ -z "$private_key" ]]; then
	  echo "秘钥不能为空。"
	  exit 1
	fi

	read -p "请输入gas(默认2000): " priority_fee
	priority_fee=${priority_fee:-2000}

	mysql_install $passwd_server
	basic_env

	cd $HOME
	git clone https://github.com/Kriptikz/ore-hq-server
	cd $HOME/ore-hq-server

	# 初始化数据库
	echo "初始化 ore 数据库..."
	# 获取当前日期，格式为YYYYMMDD
	current_date=$(date +"%Y%m%d")

	# 重命名现有的 ore 数据库为 ore_当前日期
	echo "检查是否存在 ore 数据库..."
	database_exists=$(mysql -h 127.0.0.1 -P 3307 -u root -p$passwd_server -e "SHOW DATABASES LIKE 'ore';" | grep "ore")

	if [ "$database_exists" ]; then
		echo "备份现有ore数据库 ore_$current_date..."
		mysql -h 127.0.0.1 -P 3307 -u root -proot -e "RENAME DATABASE ore TO ore_$current_date;"
	fi

	mysql -h 127.0.0.1 -P 3307 -u root -p$passwd_server -e "CREATE DATABASE IF NOT EXISTS ore;"

	for sql_file in $(find "$(pwd)" -name "down.sql")
	do
		echo "正在执行: $sql_file"
		mysql -h 127.0.0.1 -P 3307 -u root -p$passwd_server ore < "$sql_file"
	done

	for sql_file in $(find "$(pwd)" -name "up.sql")
	do
		echo "正在执行: $sql_file"
		mysql -h 127.0.0.1 -P 3307 -u root -p$passwd_server ore < "$sql_file"
	done

	# 生成配置文件路径
	config_file=$HOME/ore-hq-server/id.json
	# 直接将私钥写入配置文件
	echo $private_key > $config_file

	echo "WALLET_PATH = $HOME/ore-hq-server/id.json
RPC_WS_URL = $rpc_address
PASSWORD = $passwd_server
DATABASE_URL = mysql://root:$passwd_server@127.0.0.1:3307/ore " > $HOME/ore-hq-server/.env

	# 回溯版本
	#git reset --hard a0e1d6c80ea9d17a83c9dc198a5cdba87d325e91
	git reset --hard 24b4130a461a7d0dee2a1e54e718c419e69aaa1d
	cargo build --release

	export WALLET_PATH=$HOME/ore-hq-server/id.json
	cd $HOME/ore-hq-server/target/release
	screen -dmS ore-hq-server ./ore-hq-server --priority-fee $priority_fee

	# 获取公网 IP 地址
	public_ip=$(curl -s ifconfig.me)

	printf "\033[31m集群服务端已启动，公网IP为：%s\033[0m\n" "$public_ip"

}

# 查看服务端日志
function server_log(){
	echo ""
	printf "\033[31m请同时按键盘Ctrl + a + d 退出\033[0m\n"
	sleep 3
	screen -r ore-hq-server
}

# 停止服务端
function stop_server(){
	echo "正在终止服务端..."
	screen -S ore-hq-server -X quit
	echo "服务端已终止..."
}

# 启动服务端
function start_server(){
	read -p "请输入gas(默认2000): " priority_fee
	priority_fee=${priority_fee:-2000}

	export WALLET_PATH=$HOME/ore-hq-server/id.json
	cd $HOME/ore-hq-server/target/release
	screen -dmS ore-hq-server ./ore-hq-server --priority-fee $priority_fee

	# 获取公网 IP 地址
	public_ip=$(curl -s ifconfig.me)

	printf "\033[31m集群服务端已启动，公网IP为：%s\033[0m\n" "$public_ip"
}

# 停止客户端
function stop_client(){
	echo "正在终止客户端..."
	screen -S ore-hq-client -X quit
	echo "客户端已终止..."
}

# 启动客户端
function start_client(){
	read -p "请输入集群服务端IP: " server_ip
	# 有效IP检测
	if [[ -z "$server_ip" ]]; then
	  echo "IP地址不能为空。"
	  exit 1
	fi

	read -p "请输入挖矿线程数: " threads
	# 有效threads检测
	if [[ -z "$threads" ]]; then
	  echo "threads不能为空。"
	  exit 1
	fi

	# 配置文件路径
	config_file=$HOME/ore-hq-client/id.json
	cd $HOME/ore-hq-client/target/release
	screen -dmS ore-hq-client ./ore-hq-client --url ws://$server_ip:3000 --keypair $config_file -u mine
}

# 部署集群客户端
function install_client(){
	read -p "请输入集群服务端IP: " server_ip
	# 有效IP检测
	if [[ -z "$server_ip" ]]; then
	  echo "IP地址不能为空。"
	  exit 1
	fi

	read -p "请输入挖矿线程数: " threads
	# 有效threads检测
	if [[ -z "$threads" ]]; then
	  echo "threads不能为空。"
	  exit 1
	fi

	read -p "请输入钱包秘钥: " private_key
	# 有效秘钥检测
	if [[ -z "$private_key" ]]; then
	  echo "秘钥不能为空。"
	  exit 1
	fi

	basic_env

	cd $HOME
	git clone https://github.com/Kriptikz/ore-hq-client
	cd $HOME/ore-hq-client

	# 生成配置文件路径
	config_file=$HOME/ore-hq-client/id.json
	# 直接将私钥写入配置文件
	echo $private_key > $config_file

	cargo build --release
	cd $HOME/ore-hq-client/target/release
	./ore-hq-client --url ws://$server_ip:3000 --keypair $config_file -u signup
	screen -dmS ore-hq-client ./ore-hq-client --url ws://$server_ip:3000 --keypair $config_file -u mine

	echo "集群客户端已启动..."

}

# 查看客户端日志
function client_log(){
	echo ""
	printf "\033[31m请同时按键盘Ctrl + a + d 退出\033[0m\n"
	sleep 3
	screen -r ore-hq-client
}

# 主菜单
function main_menu() {
	while true; do
	    clear
	    echo "===============ORE一键部署脚本==============="
		echo "当前版本：$current_version"
	    echo "沟通电报群：https://t.me/lumaogogogo"
	    echo "最低配置：4C8G100G；CPU核心越多越好"
		echo "集群模式采用目前流行的中彩票模式："
		echo "1台高配机型兜底，建议算力至少4000以上"
		echo "N低配机型博彩票，建议至少4C以上，至少5台以上"
		echo "集群代码采用Kriptikz的"
		echo "git地址：https://github.com/Kriptikz"
		echo "----------SOLO方式，适合高算力机器-----------"
		echo "请选择要执行的操作:"
	    echo "1. 部署节点 install_node"
	    echo "2. 开始挖矿 start_mining"
	    echo "3. 奖励列表 check_multiple"
	    echo "4. 领取奖励 cliam_multiple"
	    echo "5. 停止挖矿 stop_mining"
	    echo "6. 查看日志 check_logs"
		echo "7. 本机算力 benchmark"
		echo "-------------集群方式，中彩票---------------"
		echo "21. 部署服务端 install_server"
		echo "22. 服务端日志 server_log"
		echo "23. 停止服务端 stop_server"
		echo "24. 启动服务端 start_server"
		echo "25. 部署客户端 install_client"
		echo "26. 客户端日志 client_log"
		echo "27. 停止客户端 stop_client"
		echo "28. 启动客户端 start_client"

	    echo "0. 退出脚本exit"
	    read -p "请输入选项: " OPTION
	
	    case $OPTION in
	    1) install_node ;;
	    2) start_mining ;;
	    3) check_multiple ;;
	    4) cliam_multiple ;;
	    5) stop_mining ;;
	    6) check_logs ;;
		7) benchmark ;;

		21) install_server ;;
		22) server_log ;;
		23) stop_server ;;
		24) start_server ;;

		25) install_client ;;
		26) client_log ;;
		27) stop_client ;;
		28) start_client ;;

	    0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
        echo "按任意键返回主菜单..."
        read -n 1
    done
}
# 检查更新
update_script

# 显示主菜单
main_menu