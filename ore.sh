#!/bin/bash

# 设置版本号
current_version=20240805001

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

# 部署节点
function install_node() {
	
	# 更新系统和安装必要的包
	echo "更新系统软件包..."
	sudo apt update && sudo apt upgrade -y
	echo "安装必要的工具和依赖..."
	sudo apt install -y curl build-essential jq git libssl-dev pkg-config screen
	
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
	
	# 提示用户输入RPC配置地址
	read -p "RPC 地址(默认https://api.mainnet-beta.solana.com): "  rpc_address
	
	# 用户输入要生成的钱包配置文件数量
	read -p "钱包数量: " count
	
	# 用户输入优先费用
	read -p "请输入交易的优先费用 (默认为 1): " priority_fee
	priority_fee=${priority_fee:-1}
	
	# 用户输入线程数
	read -p "挖矿线程数 (默认为 4): " threads
	threads=${threads:-4}
	
	# 基础会话名
	session_base_name="ore"
	
	# 启动命令模板，使用变量替代rpc地址、优先费用和线程数
	start_command_template="while true; do ore --rpc $rpc_address --keypair ~/.config/solana/idX.json --priority-fee $priority_fee mine --threads $threads; echo '异常退出，正在重启' >&2; sleep 1; done"

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
	
	    # 替换启动命令中的配置文件名、RPC地址、优先费用和线程数
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
	# 提示用户同时输入起始和结束编号，用空格分隔
	
	# 提示用户输入RPC地址
	echo -n "请输入RPC地址（例如 https://api.mainnet-beta.solana.com）: "
	read rpc_address
	
	# 提示用户同时输入起始和结束编号，用空格分隔
	echo -n "请输入起始和结束编号，中间用空格分隔（例如，对于10个钱包地址，输入1 10）: "
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
	#!/bin/bash
	
	# 提示用户输入RPC地址
	echo -n "请输入RPC地址（例如：https://api.mainnet-beta.solana.com）: "
	read rpc_address
	
	# 确认用户输入的是有效RPC地址
	if [[ -z "$rpc_address" ]]; then
	  echo "RPC地址不能为空。"
	  exit 1
	fi
	
	# 提示用户输入优先费用
	echo -n "请输入优先费用（单位：lamports，例如：500000）: "
	read priority_fee
	
	# 确认用户输入的是有效的数字
	if ! [[ "$priority_fee" =~ ^[0-9]+$ ]]; then
	  echo "优先费用必须是一个整数。"
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
	    echo "执行钱包 $i 并且RPC $rpc_address and 以及 $priority_fee"
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

# 主菜单
function main_menu() {
	while true; do
	    clear
	    echo "===============ORE一键部署脚本==============="
		echo "当前版本：$current_version"
	    echo "沟通电报群：https://t.me/lumaogogogo"
	    echo "单号需要的资源：1C1G5G；CPU核心越多越好"
		echo "请选择要执行的操作:"
	    echo "1. 部署节点"
	    echo "2. 开始挖矿"
	    echo "3. 查看奖励"
	    echo "4. 领取奖励"
	    echo "5. 停止挖矿"
	    echo "6. 查看日志"
	    echo "0. 退出脚本exit"
	    read -p "请输入选项: " OPTION
	
	    case $OPTION in
	    1) install_node ;;
	    2) start_mining ;;
	    3) check_multiple ;;
	    4) cliam_multiple ;;
	    5) stop_mining ;;
	    6) check_logs ;;
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