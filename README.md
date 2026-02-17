# WeChatKeyboardSwitch

## 项目简介

微信输入法键盘滑动切换中英文越狱插件。通过简单的上滑或下滑手势，快速在中英文输入模式之间切换，无需点击地球图标，大幅提升输入效率。

## 功能特性

- **手势切换**: 支持上滑/下滑手势快速切换中英文输入模式
- **高效便捷**: 无需点击地球图标，提升输入效率
- **系统兼容**: 支持 iOS 14+ 系统
- **越狱友好**: 同时支持 `rootless` 与 `roothide`
- **轻量级**: 插件体积小，对系统性能影响微乎其微

## 本地编译

```bash
# 默认：同时构建 rootless + roothide
./scripts/build.sh

# 仅构建 rootless
./scripts/build.sh rootless

# 仅构建 roothide
./scripts/build.sh roothide
```

也可以直接用 Theos 命令：

```bash
THEOS=/path/to/theos THEOS_PACKAGE_SCHEME=rootless make clean package
THEOS=/path/to/theos THEOS_PACKAGE_SCHEME=roothide make clean package
```

### 本地稳定 rootless 编译（已验证可注入）

当设备对签名格式敏感时，优先使用下面脚本（会更新 Theos、升级 ldid，再打包 rootless arm64）：

```bash
./scripts/build-rootless-stable.sh
```

常用参数：

```bash
# 指定版本号
PACKAGE_VERSION=1.0.0-70 ./scripts/build-rootless-stable.sh

# 跳过 Theos 更新
UPDATE_THEOS=0 ./scripts/build-rootless-stable.sh

# 跳过 ldid 升级（已升级过时）
UPDATE_LDID=0 ./scripts/build-rootless-stable.sh
```

## 安装方法

### 方法1: 手动安装

1. 进入 `packages/`，选择对应方案产物（`rootless` 或 `roothide`）
2. 使用Filza文件管理器或通过SSH将deb包传输到iOS设备
3. 在终端中执行安装命令:
   ```bash
   dpkg -i com.yourname.wechatkeyboardswitch_1.0.0_*.deb
   ```
4. 重启微信输入法或重启设备使插件生效

### 方法2: 软件源安装（待添加）

后续版本将支持通过Cydia/Sileo等包管理器直接安装。

## 使用说明

1. 打开任意支持输入的应用（如微信、备忘录等）
2. 调出微信输入法键盘（WeType Keyboard）
3. 在键盘区域向上或向下滑动
4. 输入模式将自动在中英文之间切换

**提示**:
- 上滑和下滑效果相同，都会触发中英文切换
- 手势需要在键盘区域内进行
- 切换后键盘会自动更新显示当前输入模式

## 兼容性

- **iOS版本**: iOS 14 及以上
- **输入法**: 微信输入法（WeType Keyboard）
- **越狱类型**: `rootless` / `roothide`
- **架构**: ARM64

## 技术实现

本插件使用Theos框架开发，通过Method Swizzling技术Hook微信输入法的手势处理方法，在检测到上下滑动手势时调用输入模式切换API实现功能。

## 许可证

本项目采用MIT License开源协议。详见 [LICENSE](LICENSE) 文件。

## 更新日志

查看 [CHANGELOG.md](CHANGELOG.md) 了解版本更新历史。

## 问题反馈

如遇到问题或有功能建议，欢迎提交Issue。

## 免责声明

本插件仅供学习交流使用，使用本插件产生的任何问题由使用者自行承担。
