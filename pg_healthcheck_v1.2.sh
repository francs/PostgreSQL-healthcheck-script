#!/bin/bash

# 程序名称：pg_healthcheck.sh ; 版本: 1.2
# 功能：PostgreSQL　数据库健康检查脚本;
# 使用: ./pg_healthcheck.sh, 执行成功后生成报告文件 pg_healthcheck.report ，同时注意以下：
# 1 此程序目前版本仅能在数据库主机上执行;
# 2 此程序需要数据库超级权限;
# 3 此程序需要使用数据库环境变量如$PGDATA,$PGPORT等;
# 4 此程序需要用到pg_stat_statements组件，执行前请核实 pg_stat_statements 是否安装。
# 5 目前仅支持 Linux 平台; 数据库版本: 目前仅支持 9.0, 9.1, 9.2, 9.3, 暂不支持其它版本;
# 6 此程序执行需要占用一定资源，建议在数据库空闲时段执行。    

# Author : Francs
# Email: francs3@163.com
# BLog: http://francs3.blog.163.com/

# Load env
. ~/.bash_profile

# 判断是否已经在运行健康检查脚本
if [ -f pg_healthcheck.pid ]; then
  echo "The program pg_healthcheck.sh is running now !"
  exit 0
fi

# 判断 pg 是否存活
if [ ! -f $PGDATA/postmaster.pid ]; then
  echo "PostgreSQL 服务没启动，请确认！"
  exit 0
fi

# 设置变量
base_url=" -h 127.0.0.1 -d postgres -U postgres "
db_version=`psql ${base_url} -At -c "select version();" | awk '{print $1,$2}'`
db_big_version=`echo ${db_version} | awk '{print $2}' | awk -F "." '{print $1"."$2}'`
report_file=pg_healthcheck.report

# 创建报告文件
if [ -f ${report_file} ]; then
   rm -f ${report_file}
fi

touch ${report_file}

# 检查 pg 版本
if [ ${db_big_version} != '9.0' ] && [ ${db_big_version} != '9.1' ] && [ ${db_big_version} != '9.2' ] && [ ${db_big_version} != '9.3' ]; then
 echo -e "WARNING: 目前仅支持 9.0, 9.1, 9.2, 9.3, 暂不支持其它版本。"
 exit 1
fi


# 检查 pg_stat_statements extension 是否安装
if [ ${db_big_version} == '9.0' ]; then
  pg_stat_statements=`psql ${base_url} -At -c "select 1 where exists (select viewname from pg_views where viewname='pg_stat_statements');"`
  echo "pg_stat_statements: ${pg_stat_statements}"
  if [ -z ${pg_stat_statements} ]; then
     echo "pg_stat_statements 模块没装，执行前请安装。"
     exit 1
  fi
else
  pg_stat_statements=`psql ${base_url} -At -c "select 1 where exists (select extname from pg_extension where extname='pg_stat_statements');"`
   if [ -z ${pg_stat_statements} ]; then
      echo "pg_stat_statements 模块没装，执行前请安装。"
      exit 1
   fi
fi

# 创建脚本运行标记文件
touch pg_healthcheck.pid

echo -e "###############################    PostgreSQL 数据库巡检报告    #####################################" | tee -a ${report_file}

# 一 数据库基本信息
echo -e "一 数据库基本信息" | tee -a ${report_file}
echo -e "内核版本：`uname -r`" | tee -a ${report_file}

echo -e "数据库版本：${db_version}" | tee -a ${report_file}
echo -e "\n数据库编译配置信息:" | tee -a ${report_file}
pg_config | tee -a ${report_file}


# 二 数据库配置
echo -e "\n\n二 数据库配置" | tee -a ${report_file}
echo -e "--2.1 postgresql.conf" | tee -a ${report_file}
echo -e "md5值:` md5sum $PGDATA/postgresql.conf`" | tee -a ${report_file}
echo -e "\n非默认值:" | tee -a ${report_file}
grep "^[a-z]" $PGDATA/postgresql.conf | tee -a ${report_file}

echo -e "\n--2.2 pg_hba.conf" | tee -a ${report_file}
echo -e "md5值:` md5sum $PGDATA/pg_hba.conf`" | tee -a ${report_file}
echo -e "\n非默认值:" | tee -a ${report_file}
grep "^[a-z]" $PGDATA/pg_hba.conf | tee -a ${report_file}

echo -e "\n--2.3 recovery.conf" | tee -a ${report_file}
if [ -f "$PGDATA/recovery.conf" ] || [ -f "$PGDATA/recovery.done" ]; then
   echo -e "md5值:` md5sum $PGDATA/recovery.*`" | tee -a ${report_file}
   echo -e "\n非默认值:" | tee -a ${report_file}
   grep "^[a-z]" $PGDATA/recovery.* | tee -a ${report_file}
 else
   echo -e "WARNING: recovery.conf/recovery.done 恢复配置文件不存在。" | tee -a ${report_file}
fi


# 三 上次巡检以来csvlog 中的错误分类和次数
echo -e "\n\n三 最近一个月 csvlog 日志中的错误分类和次数(如果日志量大，这步执行时间会较长。)" | tee -a ${report_file}
log_directory=`psql ${base_url} -At -c "select case when setting='pg_log' then '$PGDATA/pg_log' else setting end from pg_settings where name='log_directory';"`
# 日志分析仅支持 csv 日志格式,当前策略仅分析一月前的日志
#awk -F "," '{print $12" "$13}' ${log_directory}/postgresql-`date +%Y`-`date +%m`*.csv |grep -E "WARNING|ERROR|FATAL|PANIC"|sort|uniq -c|sort -rn
find ${log_directory}/. -name "*.csv" -ctime  -30 -exec awk -F "," '{print $12" "$13}' '{}' \; | grep -E "WARNING|ERROR|FATAL|PANIC"|sort|uniq -c|sort -rn | tee -a ${report_file}


# 四 定时任务
echo -e "\n\n四 定时任务" | tee -a ${report_file}
crontab -l | tee -a ${report_file}


# 五 数据库对像信息
echo -e "\n\n五 数据库对像信息" | tee -a ${report_file}

get_db_object_info(){
psql ${base_url} <<EOF
\echo '\n--5.1 表空间信息'
\db

\echo '\n--5.2 数据库信息'

SELECT
    datname ,
    a.rolname ,
    pg_encoding_to_char(encoding) ,
    datcollate ,
    datctype ,
    pg_size_pretty(pg_database_size(datname))
FROM
    pg_database d ,
    pg_authid a
WHERE
    d.datdba = a.oid
    AND datname NOT IN ('template0' ,'template1' ,'postgres' )
ORDER BY
    pg_database_size(datname) DESC;

\echo '\n--5.3 用户/角色信息'
\du
\q  
EOF
}

get_db_object_info | tee -a ${report_file}

# 六 自上次巡检以来的TOP 10 SQL
echo -e "\n\n六 自上次巡检以来的TOP 10 SQL" | tee -a ${report_file}

echo -e "--6.1 CPU耗时TOP 10" | tee -a ${report_file}
echo -e "SQL:select t1.datname, t2.query, t2.calls, t2.total_time, t2.total_time/t2.calls "单次调用cpu耗时" from pg_database t1, pg_stat_statements t2 where t1.oid=t2.dbid order by t2.total_time desc limit 10;\n" | tee -a ${report_file}

psql ${base_url} -xt -c "select t1.datname, t2.query, t2.calls, t2.total_time, t2.total_time/t2.calls "单次调用cpu耗时" from pg_database t1, pg_stat_statements t2 where t1.oid=t2.dbid order by t2.total_time desc limit 10" | sed /--/g | tee -a ${report_file}

echo -e "--6.2 调用次数TOP10" | tee -a ${report_file}
echo -e "SQL:select t1.datname, t2.query, t2.calls, t2.total_time, t2.total_time/t2.calls "单次调用cpu耗时" from pg_database t1, pg_stat_statements t2 where t1.oid=t2.dbid order by t2.calls desc limit 10;\n" | tee -a ${report_file}
psql ${base_url} -xt -c "select t1.datname, t2.query, t2.calls, t2.total_time, t2.total_time/t2.calls "单次调用cpu耗时" from pg_database t1, pg_stat_statements t2 where t1.oid=t2.dbid order by t2.calls desc limit 10;" | sed /--/g | tee -a ${report_file}

echo -e "--6.3 单次耗时TOP 10" | tee -a ${report_file}
echo -e "SQL: select t1.datname, t2.query, t2.calls, t2.total_time, t2.total_time/t2.calls "单次调用cpu耗时" from pg_database t1, pg_stat_statements t2 where t1.oid=t2.dbid order by t2.total_time/t2.calls desc limit 10;" | tee -a ${report_file}

psql ${base_url} -xt -c "select t1.datname, t2.query, t2.calls, t2.total_time, t2.total_time/t2.calls "单次调用cpu耗时" from pg_database t1, pg_stat_statements t2 where t1.oid=t2.dbid order by t2.total_time/t2.calls desc limit 10;" | sed /--/g | tee -a ${report_file}

# 七数据库运行状态巡检
echo -e "\n\n七 数据库运行状态巡检" | tee -a ${report_file}
echo -e "--7.1 连接数" | tee -a ${report_file}
psql ${base_url} -c "select s.setting "可用连接数",a.used_session "已使用连接数" ,s.setting::bigint - a.used_session "剩余连接数" from pg_settings s, (select count(*) as used_session from pg_stat_activity) a   where s.name='max_connections';" | tee -a ${report_file}

echo -e "\n--7.2 年龄大于10亿的数据库" | tee -a ${report_file} 
psql ${base_url} -c "select datname,age(datfrozenxid) from pg_database where age(datfrozenxid)>1000000000 order by 2 desc;" | tee -a ${report_file}


# 多库检查模块 
# 多库检查函数
muti_db_check()
{
 for sql_flag in "sql1" "sql2" "sql3" "sql4" "sql5" "sql6" "sql7"
 do
    eval remark="$"${sql_flag}_comment
    eval health_sql="$"${sql_flag}
    echo -e "\n\n########### ${remark} ###############" 
    echo -e "${sql_flag}: ${health_sql}"

   for db_name in `psql -h 127.0.0.1 -At -c "select datname from pg_database where datname not in ('template0','template1','postgres') order by 1;"`
     do
      # 数据库连接串
      db_url="-h 127.0.0.1 -d ${db_name} -U postgres"

      echo -e "##### 数据库 ${db_name} "
      # 取指标
      psql ${db_url} -c "${health_sql}"
     done
   done
  return 0
}

# 多库检查模块：各指标SQL
 #sql1: 查询大于10GB的表以及年龄 (所有库)
  sql1="select relname,age(relfrozenxid),pg_relation_size(oid)/1024/1024/1024.0 "表大小GB" from pg_class where relkind='r' and pg_relation_size(oid)/1024/1024/1024.0 > 10 order by 3 desc;"
  sql1_comment="sql1: 查询大于10GB的表以及年龄"
  
 #sql2: 索引数超过4的表 (所有库)
  sql2="select t2.nspname, t1.relname, t3.idx_cnt from pg_class t1, pg_namespace t2, (select indrelid,count(*) idx_cnt from pg_index group by 1 having count(*)>4) t3 where t1.oid=t3.indrelid and t1.relnamespace=t2.oid order by t3.idx_cnt desc;"
  sql2_comment="sql2: 索引数超过4的表"
  
 #sql3: 上次巡检以来未使用或使用较少的索引 (所有库)
  sql3="select t2.schemaname,t2.relname,t2.indexrelname,t2.idx_scan,t2.idx_tup_read,t2.idx_tup_fetch,pg_relation_size(indexrelid) from pg_stat_all_tables t1,pg_stat_all_indexes t2 where t1.relid=t2.relid and t2.idx_scan<1000 and t2.schemaname not in ('pg_toast','pg_catalog') and indexrelid not in (select conindid from pg_constraint where contype in ('p','u')) and pg_relation_size(indexrelid)>6553600 order by pg_relation_size(indexrelid) desc;"
  sql3_comment="sql3: 上次巡检以来未使用或使用较少的索引"
  
 #sql4 检查垃圾数据
  sql4="select schemaname,relname,n_live_tup,n_dead_tup from pg_stat_all_tables where n_live_tup>0 and n_dead_tup/n_live_tup>0.2 and schemaname not in ('pg_toast','pg_catalog');"
  sql4_comment="sql4: 检查垃圾数据"

 #sql4 膨胀检查 
 sql4="select * from 
(
SELECT
  current_database() AS db, schemaname, tablename, reltuples::bigint AS tups, relpages::bigint AS pages, otta,
  ROUND(CASE WHEN otta=0 OR sml.relpages=0 OR sml.relpages=otta THEN 0.0 ELSE sml.relpages/otta::numeric END,1) AS tbloat,
  CASE WHEN relpages < otta THEN 0 ELSE relpages::bigint - otta END AS wastedpages,
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::bigint END AS wastedbytes,
  CASE WHEN relpages < otta THEN '0 bytes'::text ELSE (bs*(relpages-otta))::bigint || ' bytes' END AS wastedsize,
  iname, ituples::bigint AS itups, ipages::bigint AS ipages, iotta,
  ROUND(CASE WHEN iotta=0 OR ipages=0 OR ipages=iotta THEN 0.0 ELSE ipages/iotta::numeric END,1) AS ibloat,
  CASE WHEN ipages < iotta THEN 0 ELSE ipages::bigint - iotta END AS wastedipages,
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  CASE WHEN ipages < iotta THEN '0 bytes' ELSE (bs*(ipages-iotta))::bigint || ' bytes' END AS wastedisize,
  CASE WHEN relpages < otta THEN
    CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta::bigint) END
    ELSE CASE WHEN ipages < iotta THEN bs*(relpages-otta::bigint)
      ELSE bs*(relpages-otta::bigint + ipages-iotta::bigint) END
  END AS totalwastedbytes
FROM (
  SELECT
    nn.nspname AS schemaname,
    cc.relname AS tablename,
    COALESCE(cc.reltuples,0) AS reltuples,
    COALESCE(cc.relpages,0) AS relpages,
    COALESCE(bs,0) AS bs,
    COALESCE(CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)),0) AS otta,
    COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta -- very rough approximation, assumes all cols
  FROM
     pg_class cc
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname <> 'information_schema'
  LEFT JOIN
  (
    SELECT
      ma,bs,foo.nspname,foo.relname,
      (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
      (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        ns.nspname, tbl.relname, hdr, ma, bs,
        SUM((1-coalesce(null_frac,0))*coalesce(avg_width, 2048)) AS datawidth,
        MAX(coalesce(null_frac,0)) AS maxfracsum,
        hdr+(
          SELECT 1+count(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = ns.nspname AND s2.tablename = tbl.relname
        ) AS nullhdr
      FROM pg_attribute att 
      JOIN pg_class tbl ON att.attrelid = tbl.oid
      JOIN pg_namespace ns ON ns.oid = tbl.relnamespace 
      LEFT JOIN pg_stats s ON s.schemaname=ns.nspname
      AND s.tablename = tbl.relname
      AND s.inherited=false
      AND s.attname=att.attname,
      (
        SELECT
          (SELECT current_setting('block_size')::numeric) AS bs,
            CASE WHEN SUBSTRING(SPLIT_PART(v, ' ', 2) FROM '#"[0-9]+.[0-9]+#"%' for '#')
              IN ('8.0','8.1','8.2') THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ 'mingw32' OR v ~ '64-bit' THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      WHERE att.attnum > 0 AND tbl.relkind='r'
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  ON cc.relname = rs.relname AND nn.nspname = rs.nspname
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml ORDER BY totalwastedbytes DESC
) t where totalwastedbytes/1024/1024 > 1024;
" 
 sql4_comment="sql4: 膨胀检查"

 #sql5 检查垃圾数据
 sql5="select schemaname,relname,n_live_tup,n_dead_tup from pg_stat_all_tables where n_live_tup>0 and n_dead_tup/n_live_tup>0.2 and schemaname not in ('pg_toast','pg_catalog');" 
 sql5_comment="sql5: 检查垃圾数据"


# sql6:检查序列是否正常
 sql6="do language plpgsql \$\$
declare
  v_seq name; 
  v_max int8 := 0; 
  v_last int8 := 0;
begin
  for v_seq in 
    select quote_ident(t2.nspname) || '.' || quote_ident(t1.relname) from pg_class t1, pg_namespace t2 where t1.relnamespace=t2.oid and relkind='S' 
  loop
    execute 'select max_value,last_value from '||v_seq into v_max, v_last; 
    if v_max-v_last<500000000 then 
      raise notice 'Warning seq % last % max %', v_seq, v_last, v_max ; 
    -- else
    --   raise notice 'Normal seq % last % max %', v_seq, v_last, v_max ; 
    end if;
  end loop;
end;
\$\$;"
sql6_comment="sql6: 检查序列是否正常"

$
sql7="SELECT
    nspname ,
    relname ,
    COUNT(*) AS partition_num
FROM
    pg_class c ,
    pg_namespace n ,
    pg_inherits i
WHERE
    c.oid = i.inhparent
    AND c.relnamespace = n.oid
    AND c.relhassubclass
    AND c.relkind = 'r'
GROUP BY 1,2 ORDER BY partition_num DESC;"
sql7_comment="sql7: 检查分区表"


# 执行多库检查函数
echo -e "\n\n--7.3 多库检查" | tee -a ${report_file}
muti_db_check | tee -a ${report_file}

# 回滚比例
echo -e "\n\n--7.4 回滚比例" | tee -a ${report_file}
echo "SQL: select datname,xact_rollback::numeric/(case when xact_commit > 0 then xact_commit else 1 end + xact_rollback) rollback_ratio, blks_hit::numeric/(case when blks_read>0 then blks_read else 1 end + blks_hit) hit_ratio from pg_stat_database; | tee -a ${report_file}
"
psql ${base_url} -c "select datname,xact_rollback::numeric/(case when xact_commit > 0 then xact_commit else 1 end + xact_rollback) rollback_ratio, blks_hit::numeric/(case when blks_read>0 then blks_read else 1 end + blks_hit) hit_ratio from pg_stat_database;" | tee -a ${report_file}

# 长事务
echo -e "\n\n--7.5 长事务" | tee -a ${report_file}

if [ ${db_big_version} == '9.0' ] || [ ${db_big_version} == '9.1' ]; then
   psql ${base_url} -xt -c "select usename,datname,waiting,xact_start,current_query from pg_stat_activity where now()-xact_start>interval '5 sec' and current_query !~ '^COPY' order by xact_start;" | tee -a ${report_file}
else  
   psql ${base_url} -xt -c "select usename,datname,state,waiting,xact_start,query from pg_stat_activity where now()-xact_start>interval '5 sec' and query !~ '^COPY' and state<>'idle' order by xact_start;" | tee -a ${report_file}
fi

# 删除运行标记文件
sleep 3
rm -f pg_healthcheck.pid

echo -e "\n数据库健康检查报告 pg_healthcheck.report 已生成。"
