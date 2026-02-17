# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-12-14

### Added
- 初始版本发布
- 支持上滑手势切换中英文输入模式
- 支持下滑手势切换中英文输入模式
- 兼容iOS 13+系统
- 支持无根越狱环境（Rootless Jailbreak）
- 实现基于Method Swizzling的手势拦截机制
- 集成微信输入法输入模式切换API
- 完整的测试覆盖（功能测试、兼容性测试、性能测试）

### Technical Details
- 使用Theos框架构建
- Hook WBCommonPanelView的手势处理方法
- 调用WBKeyboardInputModeController实现模式切换
- 支持ARM64架构

### Known Issues
- 无

## [Unreleased]

### Planned Features
- 添加配置选项（手势灵敏度、切换方向等）
- 支持更多输入法
- 添加Cydia/Sileo软件源
- 优化手势识别算法
