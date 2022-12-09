---
title: 【一键启动】在 Linux 平台使用 Clash
categories:
- post
tags:
- clash
- 代理
---

# Clash
为了方便在 linux 上安装和使用 clash，本项目集成了 clash，subconverter，mmdb。支持一键部署，一键更新订阅，systemd 守护启动。

[项目地址](https://github.com/merore/merore/tree/main/clash)  
[推荐 clash 节点](https://tigr.icu/s/#/register?code=pKEQOxNd)

## 安装
```shell
curl https://raw.githubusercontent.com/merore/merore/main/clash/install.sh | sudo bash -
```

## 更新订阅
1. 编辑 `/etc/clash/calsh.env` 文件
```shell
$ cat clash.env 
#auth_user=xxx
#auth_pass=xxx
sub_url=https://xxx
```
`sub_url` 是订阅链接，`auth_user`, `auth_pass` 是 clash 身份认证，默认不开启。

2. 生成配置文件
```shell
cd /etc/clash
./update-subscribe.sh
```

## 开机自启
```shell
sudo systemctl daemon-reload
sudo systemctl enable clash
sudo systemctl start clash
```
