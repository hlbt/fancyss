#!/bin/sh

# fancyss script for asuswrt/merlin based router with software center

source /koolshare/scripts/ss_base.sh
mkdir -p /tmp/upload
alias echo_date='echo 【$(TZ=UTC-8 date -R +%Y%m%d\ %X)】:'
main_url="https://raw.githubusercontent.com/hlbt/fancyss/refs/heads/main/packages"
backup_url_1="https://raw.githubusercontent.com/hlbt/fancyss/main/packages"
backup_url_2="https://cdn.jsdelivr.net/gh/hlbt/fancyss@main/packages"

# --------------------------------------
# 6.x.4708			2.6.36.4		arm
# 7.14.114.x		2.6.36.4		arm
# hnd				4.1.27			hnd hnd_v8
# axhnd 			4.1.51			hnd hnd_v8
# axhnd.675x 		4.1.52			hnd hnd_v8
# p1axhnd.675x		4.1.27			hnd hnd_v8
# 5.04axhnd.675x	4.19.183		hnd hnd_v8
# qca (RT-AX89X)	4.4.60			qca
# mtk (TX-AX6000)	5.4.182			mtk
# --------------------------------------

run(){
	env -i PATH=${PATH} "$@"
}

curl_update_fetch(){
	local remote_file="$1"
	local output_file="$2"
	local base_url=""
	for base_url in "${main_url}" "${backup_url_1}" "${backup_url_2}"; do
		echo_date "尝试地址：${base_url}/${remote_file}"
		if [ -n "${SOCKS5_OPEN}" ];then
			run /tmp/curl-update -4skf -L --connect-timeout 5 --max-time 120 --retry 3 --retry-delay 1 -x socks5h://127.0.0.1:23456 "${base_url}/${remote_file}" > "${output_file}"
		else
			run /tmp/curl-update -4skf -L --connect-timeout 5 --max-time 120 --retry 3 --retry-delay 1 "${base_url}/${remote_file}" > "${output_file}"
		fi
		if [ "$?" = "0" ];then
			main_url="${base_url}"
			return 0
		fi
	done
	return 1
}

curl_update_download_verified(){
	local remote_file="$1"
	local output_file="$2"
	local expected_md5="$3"
	local base_url=""
	local tmp_file="${output_file}.download"
	local downloaded_md5=""
	local downloaded_size=""
	rm -f "${output_file}" "${tmp_file}"
	for base_url in "${main_url}" "${backup_url_1}" "${backup_url_2}"; do
		echo_date "尝试下载：${base_url}/${remote_file}"
		rm -f "${tmp_file}"
		if [ -n "${SOCKS5_OPEN}" ];then
			run /tmp/curl-update -4kf -L --connect-timeout 5 --max-time 180 --retry 2 --retry-delay 1 -x socks5h://127.0.0.1:23456 "${base_url}/${remote_file}" --output "${tmp_file}"
		else
			run /tmp/curl-update -4kf -L --connect-timeout 5 --max-time 180 --retry 2 --retry-delay 1 "${base_url}/${remote_file}" --output "${tmp_file}"
		fi
		if [ "$?" != "0" ] || [ ! -s "${tmp_file}" ];then
			echo_date "下载失败或文件为空，切换下一个更新源..."
			rm -f "${tmp_file}"
			continue
		fi
		downloaded_size=$(ls -lh "${tmp_file}" | awk '{print $5}')
		downloaded_md5=$(md5sum "${tmp_file}" | sed 's/ /\n/g'| sed -n 1p)
		echo_date "本次下载大小：${downloaded_size}"
		echo_date "本次下载md5：${downloaded_md5}"
		echo_date "在线期望md5：${expected_md5}"
		if [ "${downloaded_md5}" = "${expected_md5}" ];then
			mv -f "${tmp_file}" "${output_file}"
			main_url="${base_url}"
			echo_date "更新包md5校验一致，使用源：${main_url}"
			return 0
		fi
		echo_date "更新包md5校验不一致，删除坏包并切换下一个更新源..."
		rm -f "${tmp_file}"
	done
	rm -f "${tmp_file}"
	return 1
}

# arm hnd hnd_v8 qca mtk
PLATFORM=$(get_pkg_arch)
PKGTYPE=$(get_pkg_type)
MD5NAME=md5_${PLATFORM}_${PKGTYPE}
PACKAGE=fancyss_${PLATFORM}_${PKGTYPE}
VERSION=version.json.js

install_fancyss(){
	echo_date "开始解压压缩包..."
	tar -zxf shadowsocks.tar.gz
	chmod a+x /tmp/shadowsocks/install.sh
	echo_date "开始安装更新文件..."
	sh /tmp/shadowsocks/install.sh
	rm -rf /tmp/shadowsocks*
}

update_ss(){
	echo_date "更新过程中请不要刷新本页面或者关闭路由等，不然可能导致问题！"
	echo_date "检查科学上网插件更新，主服务器：github（失败自动切换镜像）"
	echo_date "检测主服务器在线版本号..."
	echo_date "地址：${main_url}/${VERSION}"
	
	if [ ! -L "/tmp/curl-update" ];then
		ln -sf /koolshare/bin/curl-fancyss /tmp/curl-update
	fi

	SOCKS5_OPEN=$(netstat -nl 2>/dev/null | grep -w "23456")
	curl_update_fetch "${VERSION}" "/tmp/version.json.js"
	if [ "$?" != "0" ];then
		echo_date "没有检测到在线版本号，github及镜像访问可能有点问题！"
		echo "XU6J03M6"
		exit 1
	fi
	echo_date "在线版本源：${main_url}/${VERSION}"
	run jq --tab . /tmp/version.json.js >/dev/null 2>&1
	if [ "$?" != "0" ];then
		echo_date "在线版本号获取错误！请检测你的网络！"
		echo "XU6J03M6"
		exit
	fi
	
	fancyss_version_online=$(cat /tmp/version.json.js | run jq -r '.version')
	echo_date "检测到主服务器在线版本号：${fancyss_version_online}"
	dbus set ss_basic_version_web="${fancyss_version_online}"
	if [ "${ss_basic_version_local}" != "${fancyss_version_online}" ];then
		echo_date "主服务器在线版本号：${fancyss_version_online} 和本地版本号：${ss_basic_version_local} 不同！"
		cd /tmp
		rm -rf /tmp/${PACKAGE}.tar.gz
		fancyss_md5_online=$(cat /tmp/version.json.js | run jq -r .$MD5NAME)
		echo_date "开启下载进程，从主服务器上下载更新包..."
		echo_date "下载链接：${main_url}/${PACKAGE}.tar.gz"
		curl_update_download_verified "${PACKAGE}.tar.gz" "/tmp/${PACKAGE}.tar.gz" "${fancyss_md5_online}"
		
		if [ "$?" != "0" ];then
			rm -rf /tmp/${PACKAGE}.tar.gz
			echo_date "所有更新源均下载失败或md5校验不一致，请稍后再试！"
			echo "XU6J03M6"
			exit 1
		fi
		echo_date "${PACKAGE}.tar.gz 下载成功！"
		mv ${PACKAGE}.tar.gz shadowsocks.tar.gz
		fancyss_size_download=$(ls -lh /tmp/shadowsocks.tar.gz |awk '{print $5}')
		fancyss_md5_download=$(md5sum /tmp/shadowsocks.tar.gz | sed 's/ /\n/g'| sed -n 1p)
		echo_date "安装包大小：${fancyss_size_download}"
		echo_date "安装包md5校验值：${fancyss_md5_download}"
		echo_date "安装包在线md5：${fancyss_md5_online}"
		if [ "${fancyss_md5_download}" != "${fancyss_md5_online}" ]; then
			echo_date "更新包md5校验不一致！估计是下载的时候出了什么状况，请等待一会儿再试..."
			rm -rf /tmp/shadowsocks* >/dev/null 2>&1
		else
			echo_date "更新包md5校验一致！ 开始安装！..."
			install_fancyss
		fi
	else
		echo_date "主服务器在线版本号：${fancyss_version_online} 和本地版本号：${ss_basic_version_local} 相同！"
		echo_date "退出插件更新!"
	fi
}


case $2 in
update)
	true > /tmp/upload/ss_log.txt
	http_response "$1"
	(
		update_ss >> /tmp/upload/ss_log.txt 2>&1
		echo XU6J03M6 >> /tmp/upload/ss_log.txt
	) &
	;;
esac
