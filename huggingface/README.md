# Hermes Agent on Hugging Face Spaces

这套文件用于把 Hermes Agent 部署到 **Hugging Face Docker Space**，并把所有运行数据持久化到挂载的 `/data`。

## 目录说明

- `Dockerfile`：基于官方 `nousresearch/hermes-agent` 镜像的 HF Space 定制镜像
- `entrypoint.sh`：首启引导脚本，自动初始化 `/data` 并启动 `hermes gateway run`
- `config.space.yaml`：首次启动复制到 `/data/config.yaml` 的默认配置
- `.env.space.example`：首次启动复制到 `/data/.env` 的说明模板

## 设计目标

- 无需交互式 `hermes setup`
- Space 重启后自动从 `/data` 恢复状态
- 通过 Hermes 内置 API Server 对外提供 HTTP 接口
- 兼容 Hugging Face Space 的 `PORT` 环境变量
- 在构建期显式创建运行用户 `hermes`，避免基础镜像差异导致启动阶段降权失败

## 持久化数据

容器启动后会把下面这些内容放到 `/data`：

- `/data/config.yaml`
- `/data/.env`
- `/data/SOUL.md`
- `/data/state.db`
- `/data/logs/`
- `/data/memories/`
- `/data/skills/`
- `/data/sessions/`
- `/data/home/`

因此只要 HF Space 的 Storage 挂载到 `/data`，重启后这些数据都会保留。

## 推荐的 HF Space 配置

### 1. Space 类型

使用 **Docker Space**。

### 2. Persistent Storage

- Mount path: `/data`
- Access: `Read & Write`

### 3. 必需 Secrets / Variables

至少配置以下两项：

- `API_SERVER_KEY`：必须是真实强随机值；当 API 绑定到 `0.0.0.0` 时，没有它 Hermes 会拒绝启动
- 至少一组可用于主模型的自定义接口凭据和地址

如果你只使用 **自定义 OpenAI-compatible 接口**，推荐配置：

```env
ACTIVE_CUSTOM_MODEL=primary                                        # 当前激活哪套模型：primary 或 secondary
CUSTOM_OPENAI_BASE_URL=https://your-openai-compatible-endpoint/v1  # 主模型接口地址；要求兼容 OpenAI Chat Completions
OPENAI_BASE_URL=https://your-openai-compatible-endpoint/v1         # 主模型可选别名；若你更习惯 OpenAI 风格变量名，也可用它代替 CUSTOM_OPENAI_BASE_URL
HERMES_MODEL=Qwen/qwen-max-latest                                  # 主模型名；会同步写入 model.default
OPENAI_API_KEY=your-api-key                                        # 主模型接口认证密钥；Hermes 对 custom endpoint 默认读取这个变量
ANTHROPIC_API_KEY=your-api-key                                     # 如果你的平台要求使用这个变量名，也可以同时配置；entrypoint 会兜底映射到 OPENAI_API_KEY
ANTHROPIC_APILKEY=your-api-key                                     # 兼容你当前上游使用的这个变量名；entrypoint 也会兜底映射到 OPENAI_API_KEY
```

如果你还要同时保留第二套自定义模型，可以继续配置：

```env
SECONDARY_CUSTOM_OPENAI_BASE_URL=https://your-second-endpoint/v1   # 第二套模型接口地址
SECONDARY_OPENAI_BASE_URL=https://your-second-endpoint/v1          # 第二套模型可选别名
SECONDARY_HERMES_MODEL=deepseek-expert-reasoner-search            # 第二套模型名
SECONDARY_OPENAI_API_KEY=your-second-api-key                      # 第二套模型接口认证密钥
SECONDARY_ANTHROPIC_API_KEY=your-second-api-key                   # 第二套模型若使用这个变量名，也可配置
SECONDARY_ANTHROPIC_APILKEY=your-second-api-key                   # 第二套模型兼容别名
```

可选项：

```env
HERMES_INFERENCE_PROVIDER=custom                                   # 可选；有 CUSTOM_OPENAI_BASE_URL / OPENAI_BASE_URL 时通常会自动切到 custom
API_SERVER_MODEL_NAME=Hermes-Agent                                 # /v1/models 中展示的模型名称
API_SERVER_CORS_ORIGINS=https://your-frontend.example.com          # 允许跨域访问的来源
HERMES_HOME=/data                                                  # Hermes 持久化目录，HF Storage 建议固定为 /data
```

说明：

- 这套 HF 部署文件现在默认按“自定义 OpenAI-compatible 接口”来组织
- 当 `ACTIVE_CUSTOM_MODEL=primary` 时，使用主模型变量；当 `ACTIVE_CUSTOM_MODEL=secondary` 时，使用第二套模型变量
- 启动脚本会把当前激活模型同步写入 `model.provider`、`model.base_url`、`model.default`
- 对于 custom endpoint，Hermes 默认使用 `OPENAI_API_KEY` 做认证
- 如果你只有 `ANTHROPIC_API_KEY` 或 `ANTHROPIC_APILKEY`，当前 HF 启动脚本会在 `OPENAI_API_KEY` 为空时自动复用它
- 第二套模型同理，优先使用 `SECONDARY_OPENAI_API_KEY`，否则回落到 `SECONDARY_ANTHROPIC_API_KEY` / `SECONDARY_ANTHROPIC_APILKEY`
- 你的上游接口需要兼容 OpenAI Chat Completions
- 渠道内现在额外支持 `/model primary` 和 `/model secondary`，可直接把当前会话切到这两套预定义 custom endpoint 之一

## 默认启动行为

`entrypoint.sh` 会自动：

1. 设置 `HERMES_HOME=/data`
2. 创建 Hermes 所需目录结构
3. 首次启动时复制模板文件到 `/data`
4. 同步内置 skills
5. 设置：
   - `API_SERVER_ENABLED=true`
   - `API_SERVER_HOST=0.0.0.0`
   - `API_SERVER_PORT=${PORT:-7860}`
6. 执行 `hermes gateway run`

另外，HF 专用 `entrypoint.sh` 在容器以 root 启动时会优先使用 `gosu` 降权；如果基础镜像里没有 `gosu`，则会自动回退到 `runuser` 或 `su`，避免因为缺少单个二进制而直接启动失败。

你可以把大部分部署参数放到 HF Space 的环境变量中，包括：

- 自定义模型接口地址：`CUSTOM_OPENAI_BASE_URL` 或 `OPENAI_BASE_URL`
- 模型名：`HERMES_MODEL`
- 自定义接口认证密钥：`OPENAI_API_KEY` / `ANTHROPIC_API_KEY` / `ANTHROPIC_APILKEY`
- API 服务配置：`API_SERVER_*`
- 渠道配置：例如 `WEIXIN_*`

其中 Weixin（个人微信）渠道在项目里就是通过环境变量装配到 gateway 配置中的，相关逻辑见 [gateway/config.py:1048-1087](../gateway/config.py#L1048-L1087)。

此外，这个 HF 专用 `entrypoint.sh` 已经增加了 **Weixin 首次引导逻辑**：

- 如果设置了 `WEIXIN_ENABLED=true`
- 并且还没有 `WEIXIN_ACCOUNT_ID` / `WEIXIN_TOKEN`
- 启动时就会自动进入二维码扫码登录流程
- 二维码链接和扫码状态会输出到 Space 日志中
- 扫码成功后，凭据会自动写入 `/data/.env`
- 之后再次重启，会直接复用持久化凭据并进入正常网关模式

## 暴露的接口

启动成功后可以访问：

- `/health`
- `/v1/health`
- `/v1/models`
- `/v1/chat/completions`
- `/v1/responses`

## Weixin（个人微信）渠道配置

Weixin 对应的是 **个人微信**，不是企业微信 WeCom。相关文档在：

- [website/docs/user-guide/messaging/weixin.md](../website/docs/user-guide/messaging/weixin.md)

在 Hermes 里，Weixin 可以通过环境变量直接启用；gateway 会读取这些变量并装配平台配置：

- `WEIXIN_ACCOUNT_ID`
- `WEIXIN_TOKEN`
- `WEIXIN_BASE_URL`
- `WEIXIN_CDN_BASE_URL`
- `WEIXIN_DM_POLICY`
- `WEIXIN_GROUP_POLICY`
- `WEIXIN_ALLOWED_USERS`
- `WEIXIN_GROUP_ALLOWED_USERS`
- `WEIXIN_HOME_CHANNEL`
- `WEIXIN_HOME_CHANNEL_NAME`

对应代码：

- [gateway/config.py:1048-1087](../gateway/config.py#L1048-L1087)

### 推荐的最小 Weixin 环境变量

如果你已经有微信凭据，可以直接这样配：

```env
WEIXIN_ENABLED=true                     # 启用 Weixin 渠道
WEIXIN_ACCOUNT_ID=your-account-id       # 微信 iLink Bot account_id
WEIXIN_TOKEN=your-token                 # 微信 iLink Bot token
WEIXIN_DM_POLICY=open                   # 私聊策略：open 表示允许私聊
WEIXIN_GROUP_POLICY=disabled            # 群聊策略：disabled 表示默认不响应群消息
```

如果你还没有微信凭据，希望容器启动时自动进入二维码登录引导，则这样配：

```env
WEIXIN_ENABLED=true                     # 启用 Weixin 渠道
WEIXIN_AUTO_QR_LOGIN=true               # 缺少凭据时自动进入二维码扫码登录流程
WEIXIN_QR_TIMEOUT_SECONDS=480           # 二维码登录等待超时时间，单位秒
WEIXIN_AUTO_SET_HOME_CHANNEL=true       # 扫码成功后自动把返回的 user_id 设为 home channel
WEIXIN_DM_POLICY=open                   # 私聊策略：open 表示允许私聊
WEIXIN_GROUP_POLICY=disabled            # 群聊策略：disabled 表示默认不响应群消息
```

### 如果你要做白名单控制

```env
WEIXIN_ACCOUNT_ID=your-account-id       # 微信 iLink Bot account_id
WEIXIN_TOKEN=your-token                 # 微信 iLink Bot token
WEIXIN_DM_POLICY=allowlist              # 私聊策略：仅允许白名单用户私聊
WEIXIN_ALLOWED_USERS=user_id_1,user_id_2          # 私聊白名单用户 ID，逗号分隔
WEIXIN_GROUP_POLICY=allowlist           # 群聊策略：仅允许白名单群响应
WEIXIN_GROUP_ALLOWED_USERS=group_id_1,group_id_2  # 群聊白名单群 ID，逗号分隔
```

### 关于首次扫码登录

项目标准文档仍然推荐通过 `hermes gateway setup` 完成二维码登录，参考：

- [website/docs/user-guide/messaging/weixin.md:31-53](../website/docs/user-guide/messaging/weixin.md#L31-L53)
- [gateway/platforms/weixin.py:924-1043](../gateway/platforms/weixin.py#L924-L1043)

但在这个 HF 部署方案里，`entrypoint.sh` 已经把这个流程前置到了容器启动阶段：

1. 如果设置了 `WEIXIN_ENABLED=true`
2. 且当前还没有 `WEIXIN_ACCOUNT_ID` / `WEIXIN_TOKEN`
3. 就会在启动日志中打印二维码链接/二维码状态
4. 用户扫码确认后，容器会把返回的 `WEIXIN_ACCOUNT_ID`、`WEIXIN_TOKEN`、`WEIXIN_BASE_URL` 持久化到 `/data/.env`
5. 之后再启动网关时，就会直接使用已持久化的微信凭据

这意味着在 HF Space 里，你可以把“首次扫码登录”作为启动流程的一部分，而不是必须先在本地完成。

## 本地验证示例

```bash
docker build -f huggingface/Dockerfile -t hermes-hf-space "F:/APK/hermes-agent"

docker run --rm -p 7860:7860 \
  -e PORT=7860 \
  -e API_SERVER_KEY=replace-with-a-real-secret \
  -e CUSTOM_OPENAI_BASE_URL=https://your-openai-compatible-endpoint/v1 \
  -e HERMES_MODEL=Qwen/qwen-max-latest \
  -e ANTHROPIC_APILKEY=replace-with-your-model-key \
  -v /absolute/path/to/local-data:/data \
  hermes-hf-space
```

验证：

```bash
curl -H "Authorization: Bearer replace-with-a-real-secret" http://localhost:7860/health
curl -H "Authorization: Bearer replace-with-a-real-secret" http://localhost:7860/v1/models
```

## 复制到 HF Space 仓库的方式

如果你的 HF Space 是单独仓库，推荐保留下面这个目录结构：

```text
.
├─ Dockerfile                 # 由 huggingface/Dockerfile 复制或重命名而来
└─ huggingface/
   ├─ entrypoint.sh
   ├─ config.space.yaml
   ├─ .env.space.example
   └─ README.md
```

注意：当前 `Dockerfile` 里的 `COPY` 路径依赖 `huggingface/` 子目录存在，所以如果你把它用于独立的 HF Space 仓库，应该把 `huggingface/Dockerfile` 复制到仓库根目录作为 `Dockerfile`，同时保留其余文件在 `huggingface/` 子目录下。

如果你直接基于当前仓库做构建，也可以从仓库根目录执行：

```bash
docker build -f huggingface/Dockerfile .
```
