#!/usr/bin/env python3
"""Configures a fresh new-api instance for the Transclase relay.

Creates the admin account, a DeepSeek channel that renames the models to the
`transclase-*` aliases, and one client token. Idempotent: re-running it does not
duplicate anything.

Usage:
    python3 provision.py [--base http://127.0.0.1:3000]
"""

import argparse
import json
import os
import pathlib
import sqlite3
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
ENV = ROOT / ".env"


def load_env():
    values = {}
    if ENV.exists():
        for line in ENV.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    defaults = {
        "ADMIN_USERNAME": "root",
        "ALIAS_CHAT": "transclase-chat",
        "ALIAS_REASONER": "transclase-reasoner",
        "UPSTREAM_CHAT": "deepseek-chat",
        "UPSTREAM_REASONER": "deepseek-reasoner",
    }
    for key, fallback in defaults.items():
        if not values.get(key):
            values[key] = os.environ.get(key) or fallback
    values.setdefault("ADMIN_PASSWORD", "")
    values.setdefault("DEEPSEEK_KEY", "")
    return values


class API:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.token = None

    def call(self, path, body=None, method="GET"):
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(
            f"{self.base}{path}", data=data, method=method,
            headers={"Content-Type": "application/json"},
        )
        if self.token:
            request.add_header("Authorization", f"Bearer {self.token}")
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode() or "{}")
        except urllib.error.HTTPError as error:
            raw = error.read().decode("utf-8", "replace")
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                return {"success": False, "message": f"HTTP {error.code}: {raw[:120]}"}

    def login(self, username, password):
        reply = self.call("/api/user/login", {"username": username, "password": password}, "POST")
        token = (reply.get("data") or {}).get("access_token")
        if not token:
            return False, reply.get("message", "login failed")
        self.token = token
        return True, ""


def promote_admin(db_path):
    """new-api leaves the first account at role=1; root is 100."""
    if not db_path.exists():
        return False, "database not found"
    try:
        with sqlite3.connect(db_path) as db:
            db.execute("UPDATE users SET role=100 WHERE id=1")
            db.commit()
        return True, ""
    except sqlite3.Error as error:
        return False, str(error)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:3000")
    parser.add_argument("--db", default=str(ROOT / "data" / "one-api.db"))
    args = parser.parse_args()

    env = load_env()
    if not env.get("DEEPSEEK_KEY"):
        sys.exit("缺少 DEEPSEEK_KEY：请在 .env 里填写上游密钥")

    api = API(args.base)

    # 1. 注册（首个账号）——已存在则忽略
    api.call("/api/user/register", {
        "username": env["ADMIN_USERNAME"],
        "password": env["ADMIN_PASSWORD"],
    }, "POST")

    # 2. 提升为管理员（新装实例默认 role=1）
    ok, error = promote_admin(pathlib.Path(args.db))
    if not ok:
        print(f"⚠️  无法自动提升管理员权限：{error}")
        print("   请手动执行：sqlite3 data/one-api.db \"UPDATE users SET role=100 WHERE id=1;\"")

    # 3. 登录
    ok, error = api.login(env["ADMIN_USERNAME"], env["ADMIN_PASSWORD"])
    if not ok:
        sys.exit(f"登录失败：{error}")

    me = api.call("/api/user/self").get("data") or {}
    if me.get("role") != 100:
        sys.exit("当前账号仍不是管理员（role≠100），请先执行上面的 sqlite 命令再重跑")

    # 4. 渠道（已存在就跳过）
    channels = (api.call("/api/channel/?p=1&page_size=100").get("data") or {}).get("items") or []
    existing = [c for c in channels if (c.get("channel") or c).get("name") == "DeepSeek 上游"]
    if existing:
        print("渠道已存在，跳过创建")
    else:
        alias_chat, alias_reasoner = env["ALIAS_CHAT"], env["ALIAS_REASONER"]
        upstream_chat, upstream_reasoner = env["UPSTREAM_CHAT"], env["UPSTREAM_REASONER"]
        reply = api.call("/api/channel/", {
            "mode": "single",
            "channel": {
                "name": "DeepSeek 上游",
                "type": 8,
                "key": env["DEEPSEEK_KEY"],
                # 这个版本的 new-api 不拼路径，必须给完整端点
                "base_url": "https://api.deepseek.com/v1/chat/completions",
                "models": f"{alias_chat},{alias_reasoner}",
                "model_mapping": json.dumps({
                    alias_chat: upstream_chat,
                    alias_reasoner: upstream_reasoner,
                }),
                "group": "default",
                "groups": ["default"],
                "status": 1,
                "priority": 0,
                "weight": 0,
                "auto_ban": 0,
            },
        }, "POST")
        print("创建渠道：", "成功" if reply.get("success") else reply.get("message"))

    # 5. 自用模式（跳过按模型计价）
    api.call("/api/option/", {"key": "SelfUseModeEnabled", "value": "true"}, "PUT")

    # 6. 客户端令牌
    tokens = (api.call("/api/token/?p=1&page_size=100").get("data") or {}).get("items") or []
    if any(t.get("name") == "transclase-client" for t in tokens):
        print("令牌已存在，未重复创建（如需新密钥请到后台重新生成）")
    else:
        reply = api.call("/api/token/", {
            "name": "transclase-client",
            "remain_quota": 0,
            "unlimited_quota": True,
            "expired_time": -1,
            "model_limits_enabled": False,
            "model_limits": "",
            "allow_ips": "",
        }, "POST")
        print("创建令牌：", "成功" if reply.get("success") else reply.get("message"))

    # 7. 读出完整 key（后台接口只返回掩码）
    db_path = pathlib.Path(args.db)
    if db_path.exists():
        try:
            with sqlite3.connect(db_path) as db:
                row = db.execute(
                    "SELECT key FROM tokens WHERE name='transclase-client' ORDER BY id DESC LIMIT 1"
                ).fetchone()
            if row:
                print()
                print("客户端令牌（只显示这一次，请保存）：")
                print(f"  sk-{row[0]}")
                print()
                print(f"  地址：{args.base}/v1")
                print(f"  模型：{env['ALIAS_CHAT']} / {env['ALIAS_REASONER']}")
        except sqlite3.Error as error:
            print(f"读取令牌失败：{error}，请到后台「令牌」页复制")


if __name__ == "__main__":
    main()
