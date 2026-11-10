# RST 本科毕设复现工程

本地、服务器和 GitHub 使用同一个 Git 源码布局。硬件代码来自作者 Debian 镜像，已经提取，无需启动虚拟机阅读或仿真。

| 路径 | 内容与来源 |
| --- | --- |
| `MemComp/` | 作者软件压缩基线 |
| `ablation/` | 作者分阶段消融实现 |
| `rst_figures/`、`regenerate_figures.sh` | 作者软件实验统计和绘图 |
| `hardware/` | 从作者虚拟机提取的硬件工程与完整 C++ 参考 |
| `reproduction/` | 本次复现的运行脚本、修正记录和紧凑报告 |
| `docs/` | 工程说明和作者原始软件说明 |

## 阅读入口

- 完整算法：`hardware/third_party/cram_cpp/cram_impl.cpp`。
- 当前 LARGE RTL：`hardware/experimental/frozen_large/m4_experimental_runtime_filelist.f`。
- 作者仿真入口：`hardware/tools/run_rst_verify.py`。
- 全量验证驱动：`reproduction/rtl88/run_full.py`；后台运行管理：`run_durable.py`。
- 已完成的软件复现报告：`reproduction/完整复现对比.txt`。
- 作者附带的结果：`hardware/evidence/`，须与本次测量区分。

## 环境与运行

需要 Linux/WSL、C++ 编译工具、Python 依赖与匹配的 Verilator。原始数据集和工具安装不放入 Git。
配置好环境后从工程根目录执行 `bash reproduction/run_native.sh verify`；软件全量含重算阶段 V 使用 `bash reproduction/run_native.sh full-stage-v`。
`reproduction/env.sh` 默认使用顶层 `hardware/`，允许显式覆盖工具和数据路径。
`bootvm.sh`、`install.sh`、`vm_bootstrap.sh` 和 `sync_to_vm.sh` 为作者保留的历史 VM 辅助脚本，当前服务器复现不调用它们。

## 源码与输出边界

不跟踪虚拟机、数据集、工具分发包、编译产物、仿真波形、缓存和运行日志。
`hardware/**/compressor/generated/*.sv` 是必要 RTL 源码，必须跟踪。
本地 `generated/` 保存软件复现实验输出，属于忽略的运行数据。
2026-11-10 已完成 RTL 全量验收：88/88 数据集、435461 页、6967376 个延迟用例通过。
验收脚本核对了全部输入 SHA256、逐页解压记录、原始延迟用例及重算统计。
结果见 `reproduction/rtl88/RTL全量对比.txt`；逐数据集验收证据见 `acceptance.json`。
本次是 Verilator RTL 功能与周期统计复现；与论文正文性能并不完全一致，不能据此宣称门级、频率、面积或功耗复现通过。
详细路径迁移与本轮运行兼容说明见 `SOURCE_LAYOUT.md`。
