---
title: 关于自建博客的若干问题
date: 2022-11-11 10:33:09
categories:
- post
---
:::info no-icon
本站点的技术框架
- [hexo](https://hexo.io/) - 博客系统
- [shoka](https://github.com/amehime/hexo-theme-shoka) - 主题
- [vercel](https://vercel.com) - 部署
- [leancloud](https://console.leancloud.cn) - 统计和评论
- [imgurl](https://www.imgurl.org) - 图床
- [gituhb](https://github.com/merore/merore.github.io)- 源码托管

其他工具
- [https://squoosh.app/](https://squoosh.app/) - 一个图片处理工具，方便压缩图片上传图床

shoka 主题修改记录，在最初的几次提交中
[https://github.com/merore/merore.github.io/commits/main](https://github.com/merore/merore.github.io/commits/main)
:::

这篇文章不是一步一步教你如何搭建自己的博客，而是在博客搭建的基础之上，总结一下博客搭建中遇到的问题以及解决方法，能给别人一点启示和思路的的话那是极好的。我将从下面几个方面介绍。

1. 博客功能确定
2. 博客技术选型
3. 百度及 seo 问题
4. hexo 主题
5. markdown 图片处理
6. 源码敏感信息处理


## 博客功能确定
要选择博客方案，首先要明确我们需要什么样的功能，我个人将功能按重要程度从上往下进行排列，每个人侧重点不同，照搬没有意义
- 方便写作
- 及时更新
- 清晰的分类
- 良好的 seo
- 访问统计
- 页面扩展

### 方便写作
写作方式一般就两种，一是本地，二是在线，个人更喜欢在线写作，因为本人平时工作环境是 linux。对 vim， git 使用比较熟练，所以任何一种写作方式对我而言都比较方便。

### 及时更新
这是本人从简书切换到个人博客最重要的原因，简书的更新和发布有限，每次发现问题想要修改时，简书不让改，记下来以后改，又老是忘记，让本来 2 min 就可以解决的事情一拖再拖。所以为了能够及时更新，放弃使用平台，转而使用个人博客是必要的。

## 博客技术选型

### 平台 vs 自建
博客选型无非就是 平台（csdn，简书） vs 自建 （hexo，hugo，wordpress 等）。从功能上来说，使用自建的覆盖范围更广一些，但是随之而来的是运维工作和对能力要求的上升，选择自建要谨慎，这是我第三次自建个人博客，也会是最后一次。

### hexo vs hugo vs wordpress
hugo 可以看作是 hexo 的另一种实现，但主题数量太少了，美观才是虽然不是第一生产力，但也是生产力的一部分，而且前端技术也有了很大的变化，更规范，更模块化，自己定制门槛也低。至于渲染速度，因为肯定要上 CI，倒也不用太担心。
至于 wordpress，不使用的原因是不会用，没兴趣学 php。

## 百度及 seo 问题
这个问题就是部署问题，如果部署在 github page 上，百度引擎无法收录，当然也有其他绕行的办法，比如 cdn 或者多线部署，但不够简洁。在这里强烈强烈推荐 [https://vercel.com/](https://vercel.com/)，直接关联 github 仓库自动部署，站点也可以被任何引擎收录，自带 cdn，国内可访问，反正用就对了。

## hexo 主题
这个个人审美不同，我选择了 shoka， 比较喜欢首页的风格，略做了配色修改，可以在前几次提交中找到修改记录[https://github.com/merore/merore.github.io/commits/main](https://github.com/merore/merore.github.io/commits/main)

## markdown 图片处理
推荐使用 [https://squoosh.app](https://squoosh.app) 进行图像处理，然后使用 imgurl 图床保存图片

## 源码敏感信息处理
发现很多博客源码都不开源了，因为其中确实有一些敏感信息，为了保持开源，同时对信息进行脱敏处理，我使用 `脚本 + 环境变量` 的方式，在部署之前运行脚本读取环境变量填充敏感信息，这样就可以在保持开源的同时保护敏感信息。详见 [https://github.com/merore/merore.github.io/blob/main/sensitive.sh](https://github.com/merore/merore.github.io/blob/main/sensitive.sh)。同时可以在本地开发环境创建一个 `.sensitive`文件，文件内容形式为
```
ALGOLIA_APP_ID=kskwjj1djj102w
ALGOLIA_API_KEY=ksdjjje98dj201j
```
脚本会自动读取这些变量进行处理。
