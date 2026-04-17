---
name: feishu-toolkit
description: |
  飞书文档稳定工具链（Hermes 版）。

  仅保留基于 FEISHU_APP_ID + FEISHU_APP_SECRET 的 Open API 路径：
  获取 tenant_access_token、解析 wiki token、读取 docx raw_content、
  以及基于 block API 的覆盖式写入。
homepage: https://github.com/fanxinliuchen/feishu-toolkit
metadata: {
  "hermes": {
    "emoji": "📄",
    "tags": ["feishu", "lark", "open-api", "docx", "wiki", "productivity"]
  }
}
env:
  FEISHU_APP_ID: "Defaults to FEISHU_APP_ID in Hermes .env if present; otherwise prompt user to configure it"
  FEISHU_APP_SECRET: "Defaults to FEISHU_APP_SECRET in Hermes .env if present; otherwise prompt user to configure it"
---

# 📄 feishu-toolkit

这是一个面向 Hermes 的飞书文档技能，定位是：

- **只走稳定的 Open API 路径**
- **不依赖额外授权跳转**
- **适合自动化读写 wiki / docx**

保留的能力：

1. 用 `FEISHU_APP_ID` + `FEISHU_APP_SECRET` 获取 `tenant_access_token`
2. 将 wiki token 解析为真实 `docx` 文档 token
3. 读取文档 `raw_content`
4. 用 block API 覆盖写入文档

---

## 适用场景

- 读取飞书 wiki / docx 内容
- 将结构化文本同步到飞书文档
- 自动生成日报、周报、技能索引、知识库目录页
- 需要稳定、可脚本化、可回读校验的飞书文档流程

---

## 前置条件

### 环境变量

默认行为：

- 优先读取**运行中 Hermes 进程环境变量**中的 `FEISHU_APP_ID`
- 优先读取**运行中 Hermes 进程环境变量**中的 `FEISHU_APP_SECRET`
- 如果进程环境中没有，再读取 `~/.hermes/.env`
- 如果 `~/.hermes/.env` 中也没有，再向用户明确报错

对大多数已经配置了 **Feishu gateway** 的 Hermes 环境来说，这意味着用户通常可以**无感直接使用**，不需要再次单独输入这两个值。

### 实现约定

技能应按以下顺序解析凭证：

1. 先检查运行中 Hermes 进程的环境变量：
   - `FEISHU_APP_ID`
   - `FEISHU_APP_SECRET`
2. 若进程环境中缺失，再检查 `~/.hermes/.env`
3. 若两处都缺失，则不要继续调用 Feishu Open API，而是直接向用户报错

推荐错误提示：

- `缺少 FEISHU_APP_ID`
- `缺少 FEISHU_APP_SECRET`

可扩展为更完整的提示，例如：

- `缺少 FEISHU_APP_ID：请先在 Hermes 运行环境或 ~/.hermes/.env 中配置`
- `缺少 FEISHU_APP_SECRET：请先在 Hermes 运行环境或 ~/.hermes/.env 中配置`

最少需要：

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
- 读取文档至少需要 `docx:document`
- 创建文档需要 `docx:document:create`
- 覆盖写入需要 `docx:document:write_only`
- wiki 节点解析建议启用 `wiki:wiki`

---

## 核心流程

### 1）获取 tenant token

```bash
curl -sS -X POST 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d '{
    "app_id": "'$FEISHU_APP_ID'",
    "app_secret": "'$FEISHU_APP_SECRET'"
  }'
```

成功后读取：

- `tenant_access_token`

---

### 2）解析 wiki token

如果用户给的是 wiki 链接，例如：

- `https://my.feishu.cn/wiki/LDx2wLgkwiEEmjknHOoctC8jnff`

其中 token 为：

- `LDx2wLgkwiEEmjknHOoctC8jnff`

解析方式：

```bash
curl -sS 'https://open.feishu.cn/open-apis/wiki/v2/spaces/get_node?token=<WIKI_TOKEN>' \
  -H "Authorization: Bearer <TENANT_ACCESS_TOKEN>"
```

关注字段：

- `data.node.obj_type`
- `data.node.obj_token`
- `data.node.title`

其中：
- `obj_type=docx` 表示真实对象是文档
- `obj_token` 就是后续读取 / 写入要用的文档 token

---

### 3）读取文档 raw content

```bash
curl -sS 'https://open.feishu.cn/open-apis/docx/v1/documents/<DOC_TOKEN>/raw_content' \
  -H "Authorization: Bearer <TENANT_ACCESS_TOKEN>"
```

返回中的关键字段：

- `data.content`

适合作为：
- 快速读取
- 结果展示
- 写入后的回读校验

---

## 创建文档

### 创建空白 docx 文档

接口：

- `POST /open-apis/docx/v1/documents`

最小请求体：

```json
{
  "title": "新文档标题"
}
```

如果需要创建到指定文件夹，可传：

```json
{
  "title": "新文档标题",
  "folder_token": "<FOLDER_TOKEN>"
}
```

返回中重点关注：

- `data.document.document_id`
- `data.document.revision_id`
- `data.document.title`

其中：
- `document_id` 就是后续 block 读写和 `raw_content` 读取使用的 doc token
- 创建成功后，建议立刻进入“覆盖式写入文档”流程，补上正文内容

### 创建后推荐动作

1. 记录 `document_id`
2. 若需要，立即 PATCH 根标题 block
3. 用 block API 创建正文 children
4. 最后用 `raw_content` 回读校验

### cURL 示例

```bash
curl -sS -X POST 'https://open.feishu.cn/open-apis/docx/v1/documents' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer <TENANT_ACCESS_TOKEN>" \
  -d '{
    "title": "新文档标题"
  }'
```

---

## 覆盖式写入文档

### 总原则

文档写入统一走 block API：

1. 列出现有 blocks
2. 更新标题 block
3. 删除旧正文 children
4. 分批创建新的 paragraph children
5. 再次读取 `raw_content` 校验

### A. 列出 blocks

```bash
curl -sS 'https://open.feishu.cn/open-apis/docx/v1/documents/<DOC_ID>/blocks?page_size=500' \
  -H "Authorization: Bearer <TENANT_ACCESS_TOKEN>"
```

关键点：
- 第一项通常是根 page block
- 根 block 的 `block_id` 通常等于文档 id
- 根 block 的 `children` 是正文块列表

### B. 更新标题 block

接口：

- `PATCH /open-apis/docx/v1/documents/<DOC_ID>/blocks/<ROOT_BLOCK_ID>`

请求体：

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

实测要点：
- 更新标题时不能只传 `elements`
- 还需要传 `style`
- 还需要传 `fields: [1]`

### C. 删除旧正文 children

接口：

- `DELETE /open-apis/docx/v1/documents/<DOC_ID>/blocks/<ROOT_BLOCK_ID>/children/batch_delete`

请求体：

```json
{
  "start_index": 0,
  "end_index": <child_count>
}
```

实测要点：
- `end_index` 应按**排他上界**理解
- 如果有 1 个 child，要删干净，应传 `end_index: 1`

### D. 创建新正文 children

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
- `block_type: 2` 是普通段落块
- 每一行内容写成一个 paragraph block 最稳定
- 大文档建议按 50 行左右分批写入
- 可附加 `client_token` 做幂等控制

### E. 回读校验

再次调用：

- `GET /open-apis/docx/v1/documents/<DOC_ID>/raw_content`

确认：
- 标题正确
- 正文完整
- 没有漏行或重复

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
headers = {'Authorization': f"Bearer {token_resp['tenant_access_token']}"}

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

- 读取优先用 `raw_content`
- wiki 链接先解析 token，再读取 docx
- 写入固定走 block 流程
- 大文档分批写入
- 写后必须回读校验
- 自动化任务建议把“标题更新 + 正文清空 + 正文重建 + 回读验证”做成固定模板

---

## 触发词

用户提到以下内容时，优先使用本技能：

- “读取飞书文档”
- “读取飞书 wiki”
- “把内容写进飞书文档”
- “同步到飞书”
- “飞书文档自动化”

---

## License

MIT
