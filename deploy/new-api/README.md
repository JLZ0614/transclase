# Transclase API 中转（new-api）

把 DeepSeek 包成 `transclase` 品牌的 OpenAI 兼容中转：

- 客户端看到的模型名：`transclase-chat`、`transclase-reasoner`
- 实际后端：`deepseek-chat`、`deepseek-reasoner`
- 客户端只需要一个 `sk-...` 和 `https://<你的域名>/v1`

## 目录

```
deploy/new-api/
├── docker-compose.yml   # new-api + Caddy（自动 HTTPS）
├── Caddyfile            # 反向代理与证书
├── .env.example         # 环境变量模板
├── provision.py         # 一键配置：管理员 / 渠道 / 令牌
└── README.md
```

## 前置条件

- 一台有公网 IP 的服务器（1 核 1 GB 足够）
- 一个域名，A 记录指向该服务器（`api.example.com`）
- 服务器开放 80 / 443
- 一个 DeepSeek API Key

## 部署步骤

```bash
# 1. 上传本目录到服务器
scp -r deploy/new-api root@<服务器 IP>:/opt/transclase-api
ssh root@<服务器 IP>

# 2. 准备环境变量
cd /opt/transclase-api
cp .env.example .env
vi .env            # 填 DOMAIN / ADMIN_PASSWORD / DEEPSEEK_KEY

# 3. 启动
docker compose up -d

# 4. 配置管理员、渠道和令牌
python3 provision.py
```

`provision.py` 会输出客户端使用的令牌（`sk-...`），**只显示一次**。

## 客户端怎么用

```bash
curl https://api.example.com/v1/chat/completions \
  -H "Authorization: Bearer sk-..." \
  -H "Content-Type: application/json" \
  -d '{
    "model": "transclase-chat",
    "messages": [{"role": "user", "content": "你好"}]
  }'
```

在 Transclase App 里：设置 → 翻译 → 云端 API，地址填 `https://api.example.com/v1`，模型名填 `transclase-chat`。

## 两个坑（实测）

1. **`base_url` 要填完整端点**
   这个版本的 new-api 不会自动拼接路径，请求会原样打到 `base_url`。
   所以渠道里必须写 `https://api.deepseek.com/v1/chat/completions`，而不是 `https://api.deepseek.com`。

2. **首个注册用户默认不是管理员**
   新装实例注册的账号 `role=1`，需要在数据库里提升：
   ```bash
   sqlite3 /data/one-api.db "UPDATE users SET role=100 WHERE id=1;"
   ```

## 计费

自用或内部使用可以开启「自用模式」跳过按模型计价：

```bash
curl -X PUT http://127.0.0.1:3000/api/option/ \
  -H "Authorization: Bearer <管理员 token>" \
  -H 'Content-Type: application/json' \
  -d '{"key":"SelfUseModeEnabled","value":"true"}'
```

要对外收费，则在「系统设置 → 模型定价」里为 `transclase-chat` 配置价格。

## 合规提醒

对外提供 API 属于经营行为，请确认你所在地对代理转发与生成式服务的监管要求；上游服务商的使用条款也需要遵守。
