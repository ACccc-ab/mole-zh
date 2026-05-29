<div align="center">
  <h1>Mole 中文版</h1>
  <p><em>🐹 从终端清理、卸载、分析、优化和监控你的 Mac。</em></p>
</div>

> **致谢：** 本项目是 [tw93/mole](https://github.com/tw93/mole) 的中文汉化版本。所有核心功能和代码归原作者 [Tw93](https://github.com/tw93) 所有，遵循 [MIT 协议](LICENSE)。感谢原作者的优秀工作！

## 关于本项目

这是 [Mole](https://github.com/tw93/mole)（一款 macOS 终端系统维护工具）的中文本地化版本。所有用户界面文本均已翻译为中文，方便中文用户使用。

**原项目功能：** Mole 将 CleanMyMac、AppCleaner、DaisyDisk 和 iStat Menus 的功能整合在一个命令行工具中。

## 汉化预览

```
$ mo --help

 __  __       _
|  \/  | ___ | | ___
| |\/| |/ _ \| |/ _ \
| |  | | (_) | |  __/  https://github.com/tw93/mole
|_|  |_|\___/|_|\___|  深度清理和优化你的 Mac。

命令
  mo                           主菜单
  mo clean                     释放磁盘空间
  mo uninstall                 完全卸载应用
  mo optimize                  刷新缓存和服务
  mo analyze                   分析磁盘占用
  mo status                    监控系统状态
  mo purge                     清理项目构建产物
  mo installer                 查找并删除安装包
  ...
```

## 安装方法

### 替换 Homebrew 已安装版本

如果你已经通过 `brew install mole` 安装了英文版：

```bash
git clone https://github.com/ACccc-ab/mole-zh.git
cd mole-zh
make build

# 获取 Homebrew 安装路径
MOLE_VER=$(brew list --versions mole | awk '{print $2}')
MOLE_DIR="$(brew --prefix)/Cellar/mole/$MOLE_VER"

# 复制汉化文件
find "$MOLE_DIR" -type f -exec chmod u+w {} \;
cp bin/analyze-go "$MOLE_DIR/libexec/bin/analyze-go"
cp bin/status-go "$MOLE_DIR/libexec/bin/status-go"
cp -r lib/* "$MOLE_DIR/libexec/lib/"
cp bin/*.sh "$MOLE_DIR/libexec/bin/"

# 修补主脚本
cp mole "$MOLE_DIR/bin/mole"
sed -i '' "s|SCRIPT_DIR=.*|SCRIPT_DIR=\"$MOLE_DIR/libexec\"|" "$MOLE_DIR/bin/mole"
chmod +x "$MOLE_DIR/bin/mole"
```

### 从源码安装（无 Homebrew）

需要 Go 1.25+ 环境。

```bash
git clone https://github.com/ACccc-ab/mole-zh.git
cd mole-zh
make build

# 安装
sudo mkdir -p /usr/local/lib/mole
sudo cp -r lib/* /usr/local/lib/mole/
sudo cp -r bin/* /usr/local/lib/mole/
sudo cp mole /usr/local/bin/mole
sudo sed -i '' 's|SCRIPT_DIR=.*|SCRIPT_DIR="/usr/local/lib/mole"|' /usr/local/bin/mole
sudo cp mo /usr/local/bin/mo
sudo chmod +x /usr/local/bin/mole /usr/local/bin/mo
```

> **注意：** `brew upgrade mole` 会覆盖汉化版，需要重新执行安装步骤。

## 功能列表

| 命令 | 功能 |
|------|------|
| `mo` | 交互式主菜单 |
| `mo clean` | 深度清理缓存、日志、浏览器残留 |
| `mo uninstall` | 智能卸载应用并清除隐藏残留 |
| `mo optimize` | 刷新系统缓存、重建数据库 |
| `mo analyze` | 可视化磁盘空间分析 |
| `mo status` | 实时系统监控（CPU/内存/磁盘/网络） |
| `mo purge` | 清理项目构建产物（node_modules 等） |
| `mo installer` | 查找并清理安装包文件 |

所有命令支持 `--dry-run` 预览模式，操作前可安全预览。

## 致谢

- **原项目：** [tw93/mole](https://github.com/tw93/mole) - 由 [Tw93](https://github.com/tw93) 开发
- **协议：** [MIT License](LICENSE)
- 本汉化版仅翻译了用户界面文本，核心功能代码未做修改
- 如有任何问题，欢迎到原项目提交 Issue 或 PR

## License

MIT License - 与原项目保持一致。详见 [LICENSE](LICENSE)。
