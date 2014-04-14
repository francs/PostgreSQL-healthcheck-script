PostgreSQL 数据库健康检查脚本
====================

提供一个检查 PostgreSQL 数据库健康检查的 shell 脚本, 欢迎下载试用，如发现 bug 或者遇到问题，联系下面邮箱:

Email: francs3@163.com

一 Introduction
---

此脚本收集以下信息
    
- 基本信息，如操作系统内核版本，数据库版本;

- 数据库控制文件信息;

- 数据库配置信息, 如 postgresql.conf , pg_hba.conf , recovery.conf 的非默认配置参数;

- 数据库 csv 错误日志分析统计;

- 数据库基本信息,　包括数据库大小，字符编码，表空间信息，用户/角色信息;

- 数据库性能 top 10  SQL(按多维度统计);

- 数据库运行状态检查(连接数，数据库年龄，索引超过4的表，膨胀检查，垃圾数据)

- 分区表检查;

- 数据库回滚比例，长事务检查;

二 Requirements
---

- 此程序需要用到 pg_stat_statements 组件
- 程序需要使用数据库环境变量如 $PGDATA, $PGPOT 等;

三 Supported Platforms
---

- 操作系统:  目前仅支持 Linux 平台
- 数据库版本:  目前仅支持 9.0, 9.1, 9.2, 9.3,  暂不支持其它版本;

四  README
---

- 此程序目前版本仅能在数据库主机上执行;
- 此程序需要数据库超级权限;
- 此程序执行过程中需要占用一定资源，建议在数据库空闲时段执行。    

五 Usage
---

        ./pg_healthcheck.sh 

备注：执行成功后生成报告文件 pg_healthcheck.report，格式为文本。

六 About me
---

- Author: 谭峰(francs)

- Email: francs3@163.com

- BLog: http://francs3.blog.163.com/

- github:  https://github.com/francs/

- 增加一行，测试。
