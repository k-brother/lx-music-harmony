### 下哪个包

| 文件 | 用途 |
| --- | --- |
| `*-unsigned.hap` | **推荐**。未签名包：用 DevEco Studio / AGC 配自己的证书签名后安装（调试证书只需把设备 UDID 登记进 profile） |
| `*-signed.hap` | 已用本工程发布证书签名，只能装到该 profile 里登记过的设备上 |

### 安装

```bash
# 手机开「开发者选项 → USB 调试」并连上电脑
hdc install lx-music-harmony-<版本>-unsigned.hap   # 未签名的包需先自行签名
```

也可以直接用 DevEco Studio 打开本仓库、连真机后 Run。签名与构建说明见仓库 README。
