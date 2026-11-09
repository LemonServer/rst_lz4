# 统一源码布局与迁移说明

本地工作副本、服务器仓库、GitHub 的受 Git 跟踪源码使用完全相同的相对路径与提交。
作者软件目录保留在根目录；作者硬件统一为 `hardware/`。旧本地的 `software/` 分组不再使用。

旧路径 `reproduction/extracted/home/debian/hw_artifact/rst-hardware/` 不再跟踪。
服务器本轮全量验证仍在使用该路径，因此保留其中全部文件和 build 数据作为运行兼容工作区；不移动、不删除、不覆盖。
本轮进程保留启动时的环境，后续采集本轮结果仍须使用旧 RST_HW_ROOT。
新任务默认使用顶层 `hardware/`，不会自动继承旧路径的编译缓存或全量验证检查点。
本轮结束前不要同时启动另一个全量任务，也不要清理旧路径。

`reproduction/extracted/home/debian/verilator-5.046/` 是服务器原有外部工具安装，保留且不跟踪。
以后可用 RST_VERILATOR_BIN、VERILATOR_ROOT 指定其他安装。
`5kcorrectdumps/` 是服务器原始数据集，`generated/` 是软件实验输出，均不跟踪。
本地外层 `archive/` 保存旧源码布局、传输包和历史审查文件，仅作追溯，不作为活动代码入口。

作者最初的软件说明保存在 `docs/AUTHOR_SOFTWARE_README.md`。
`reproduction/README.txt`、`env.before-full.sh`、source-file-list.json、modified-files.sha256 等是早期复现证据，路径和状态可能属于历史快照。
`hardware/evidence/` 是作者交付证据，`reproduction/` 下的对比报告是本次实验结果。
Git 作者身份只在仓库 local 配置中设置，不修改全局配置。
