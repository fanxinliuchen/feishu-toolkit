---
name: feishu-toolkit
description: |
  飞书 Open API 稳定文档工具链（Hermes 版）。

  仅保留基于 FEISHU_APP_ID + FEISHU_APP_SECRET 的稳定 Open API 路径：
  获取 tenant_access_token、解析 wiki token、读取 docx raw_content、
  以及基于 block API 的覆盖式写入。

  不包含 OAuth 回调流程，不依赖 localhost/public redirect URI 配置。
homepage: https://github.com/fanxinliuchen/feishu-doc-manager
metadata: {
  "hermes": {
    "emoji": "📄",
    "tags": ["feishu", "lark", "open-api", "docx", "wiki"]
  }
}
env:
  FEISHU_APP_ID: "Feishu app id"
  FEISHU_APP_SECRET: "Feishu app secret"
---

# 📄 feishu-toolkit（Hermes / Open API only）

这个技能只保留一条稳定路径：

1. 用 `FEISHU_APP_ID` + `FEISHU_APP_SECRET` 换取 `tenant_access_token`
2. 如输入是 wiki 链接/token，先解析为真实 `docx` 文档 token
3. 读取时使用 `raw_content`
4. 写入时使用 `docx block API`：
   - 列 blocks
   - PATCH 标题
   - DELETE 旧 children
   - POST 新 children

**不再使用 OAuth 授权链接 / 回调。**

---

## 适用场景

- 读取飞书 wiki / docx 文档内容
- 用脚本稳定覆盖一个飞书文档
- 自动生成日报、技能索引、知识库同步页
- 需要绕过 OAuth callback / redirect URI 问题

---

## 前置条件

### 环境变量

必须提供：

- `FEISHU_APP_ID`
- `FEISHU_APP_SECRET`

### 推荐权限

```json
{
  "scopes": {
    "tenant": [
      "docx:document",
      "docx:document:create",
      "docx:document:write_only",
      "wiki:wiki",
      "docs:permission.member",
      "contact:user.base:readonly"
    ]
  }
}
```

说明：
- 读文档至少需要 `docx:document`
- 创建文档需要 `docx:document:create`
- 覆盖写入需要 `docx:document:write_only`
- 解析 wiki 节点建议有 `wiki:wiki`

---

## 核心工作流

### 1) 获取 tenant token

```bash
curl -sS -X POST 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d '{
    "app_id": "'$FEISHU_APP_ID'",
    "app_secret": "'$FEISHU_APP_SECRET'"
  }'
```

成功后从返回 JSON 中取：

- `tenant_access_token`

---

### 2) 解析 wiki token 到真实 docx token

如果用户给的是链接，例如：

- `https://my.feishu.cn/wiki/LDx2wLgkwiEEmjknHOoctC8jnff`

其中 wiki token 是：

- `LDx2wLgkwiEEmjknHOoctC8jnff`

解析方式：

```bash
curl -sS 'https://open.feishu.cn/open-apis/wiki/v2/spaces/get_node?token=<WIKI_TOKEN>' \
  -H "Authorization: Bearer <TENANT_ACCESS_TOKEN>"
```

重点字段：

- `data.node.obj_type` → 通常是 `docx`
- `data.node.obj_token` → 真实文档 token
- `data.node.title` → 标题

---

### 3) 读取文档 raw content

```bash
curl -sS 'https://open.feishu.cn/open-apis/docx/v1/documents/<DOC_TOKEN>/raw_content' \
  -H "Authorization: Bearer <TENANT_ACCESS_TOKEN>"
```

返回字段：

- `data.content`

适合作为：
- 快速读取
- 回读校验
- 覆盖写入后的验证

---

## 稳定写入路径（覆盖式）

### 总原则

不要依赖 OAuth helper，也不要依赖 callback。
直接使用 docx block API 做覆盖写入。

### Step A. 列出 blocks

```bash
curl -sS 'https://open.feishu.cn/open-apis/docx/v1/documents/<DOC_ID>/blocks?page_size=500' \
  -H "Authorization: Bearer <TENANT_ACCESS_TOKEN>"
```

关键点：
- 第一项通常是根 page block
- 根 block 的 `block_id` 通常等于文档 id
- 根 block 的 `children` 数组是正文块列表

### Step B. PATCH 标题

```json
{
  "update_text": {
    "elements": [
      {"text_run": {"content": "新标题"}}
    ],
    "style": {"align": 1},
    "fields": [1]
  }
}
```

接口：

- `PATCH /open-apis/docx/v1/documents/<DOC_ID>/blocks/<ROOT_BLOCK_ID>`

已验证：
- `fields: [1]` 可用于更新标题文本
- 只传 `elements` 不够，必须同时传 `style` 和 `fields`

### Step C. 删除旧正文 children

接口：

- `DELETE /open-apis/docx/v1/documents/<DOC_ID>/blocks/<ROOT_BLOCK_ID>/children/batch_delete`

请求体：

```json
{
  "start_index": 0,
  "end_index": <child_count>
}
```

注意：
- `end_index` 实际表现为**排他上界**
- 如果有 1 个 child，要删干净，需要传 `end_index: 1`
- 不是 `child_count - 1`

### Step D. 重建正文 children

接口：

- `POST /open-apis/docx/v1/documents/<DOC_ID>/blocks/<ROOT_BLOCK_ID>/children`

请求体示例：

```json
{
  "index": 0,
  "children": [
    {
      "block_type": 2,
      "text": {
        "elements": [
          {"text_run": {"content": "第一行"}}
        ]
      }
    }
  ]
}
```

说明：
- `block_type: 2` 为普通段落块
- 每一行内容写成一个 paragraph block，最稳定
- 大文档分批写入，建议每批 50 行左右
- 可附带 `client_token` 做幂等控制

### Step E. 回读验证

再次调用：

- `GET /open-apis/docx/v1/documents/<DOC_ID>/raw_content`

确认：
- 标题正确
- 正文内容完整
- 分批写入没有漏行

---

## Python 参考实现

```python
import os, json, ssl, uuid, urllib.request, urllib.error

APP_ID = os.environ['FEISHU_APP_ID']
APP_SECRET = os.environ['FEISHU_APP_SECRET']


def req(method, url, data=None, headers=None):
    body = None if data is None else json.dumps(data, ensure_ascii=False).encode('utf-8')
    request = urllib.request.Request(url, data=body, method=method)
    final_headers = {'Content-Type': 'application/json; charset=utf-8'}
    if headers:
        final_headers.update(headers)
    for k, v in final_headers.items():
        request.add_header(k, v)
    try:
        with urllib.request.urlopen(request, context=ssl.create_default_context()) as r:
            return r.status, json.loads(r.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        payload = e.read().decode('utf-8', errors='ignore')
        try:
            return e.code, json.loads(payload)
        except Exception:
            return e.code, {'raw': payload}


_, token_resp = req('POST', 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal', {
    'app_id': APP_ID,
    'app_secret': APP_SECRET,
})
token = token_resp['tenant_access_token']
headers = {'Authorization': f'Bearer {token}'}

wiki_token = 'LDx2wLgkwiEEmjknHOoctC8jnff'
_, node = req('GET', f'https://open.feishu.cn/open-apis/wiki/v2/spaces/get_node?token={wiki_token}', headers=headers)
doc_id = node['data']['node']['obj_token']

_, blocks = req('GET', f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/blocks?page_size=500', headers=headers)
root = blocks['data']['items'][0]
root_id = root['block_id']
child_count = len(root.get('children', []))

req('PATCH', f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/blocks/{root_id}', {
    'update_text': {
        'elements': [{'text_run': {'content': '新标题'}}],
        'style': {'align': 1},
        'fields': [1]
    }
}, headers)

if child_count:
    req('DELETE', f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/blocks/{root_id}/children/batch_delete', {
        'start_index': 0,
        'end_index': child_count
    }, headers)

lines = ['第一行', '第二行', '第三行']
for i in range(0, len(lines), 50):
    chunk = lines[i:i+50]
    children = [
        {'block_type': 2, 'text': {'elements': [{'text_run': {'content': line}}]}}
        for line in chunk
    ]
    req('POST', f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/blocks/{root_id}/children?index={i}&client_token={uuid.uuid4()}', {
        'index': i,
        'children': children,
    }, headers)

_, raw = req('GET', f'https://open.feishu.cn/open-apis/docx/v1/documents/{doc_id}/raw_content', headers=headers)
print(raw['data']['content'])
```

---

## 最佳实践

- 读取：优先 `raw_content`
- wiki 链接：先解析，再读 docx
- 覆盖写入：始终按 block 流程做，不要混用不稳定 helper
- 大文档：分块写入，每批 50 行左右
- 写后：必须 `raw_content` 回读校验
- 自动化任务：把标题 patch、旧正文删除、新正文分块写入做成固定模板

---

## 已知坑

1. **不要走 OAuth callback 路径**
   - 容易踩 `redirect_uri mismatch`
   - 特别是在 localhost / 公网 IP 混用时

2. **删除 children 时 `end_index` 不是最后一个下标**
   - 实测应传 child 数量
   - 即 `[start_index, end_index)` 语义

3. **更新标题不能只传 elements**
   - 还要传 `style`
   - 还要传 `fields: [1]`

4. **长内容不要一次写太大**
   - 建议拆成 paragraph blocks 批量写入

---

## 简明触发词

当用户提到以下内容时，优先使用本技能的 Open API 稳定路径：

- “读取飞书文档”
- “读取飞书 wiki”
- “把内容写入飞书文档”
- “同步到飞书”
- “飞书文档 OAuth 有问题”
- “redirect_uri 不匹配”

---

## License

MIT
