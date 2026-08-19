# dist/

第三方二进制（FrankenPHP / MySQL / Redis / Python）**不提交到仓库**，由安装器 / 构建脚本按版本下载并校验哈希。

- 入口：`installer/` 下的下载脚本（M1 实现）
