# Windows Server 2022 部署

这套部署方式不依赖 Cloudflare D1/R2：

- Next.js 作为 Node 服务运行
- SQLite 保存文章、分类、设置
- 本地磁盘保存上传图片和附件

## 1. 安装环境

在服务器安装：

- Git
- Node.js 24 LTS 或 Node.js 22 LTS

确认：

```powershell
node --version
npm --version
git --version
```

## 2. 拉取代码

```powershell
cd C:\
git clone https://github.com/axin3356/xuanmu-blog.git
cd C:\xuanmu-blog
```

## 3. 配置环境变量

```powershell
Copy-Item env.server.example .env.local
notepad .env.local
```

至少修改：

```env
NEXT_PUBLIC_SITE_URL=http://your-server-ip:3000
ADMIN_PASSWORD=你的后台密码
ADMIN_TOKEN_SALT=一串长随机字符
AI_CONFIG_ENCRYPTION_SECRET=另一串长随机字符
LOCAL_DB_PATH=C:\xuanmu-blog\data\xuanmu-blog.sqlite
LOCAL_UPLOAD_DIR=C:\xuanmu-blog\uploads
```

有域名后，把 `NEXT_PUBLIC_SITE_URL` 改成正式域名。

## 4. 构建并启动

```powershell
npm install
npm run build
npm install -g pm2
pm2 start npm --name xuanmu-blog -- start
pm2 save
```

访问：

```text
http://your-server-ip:3000
http://your-server-ip:3000/admin
```

## 5. 开放端口

如果服务器防火墙未开放 3000：

```powershell
New-NetFirewallRule -DisplayName "Xuanmu Blog 3000" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow
```

正式使用建议用 Nginx 或 IIS 反向代理到 `127.0.0.1:3000`，再绑定域名和 HTTPS。

## 6. 数据位置

默认建议：

```text
C:\xuanmu-blog\data\xuanmu-blog.sqlite
C:\xuanmu-blog\uploads
```

这两个目录必须定期备份。它们就是你的博客数据和图片资产。
