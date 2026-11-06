# 邯郸学院空闲教室接口实证（2026-11-06）

## 本次真实会话证据

项目所有者在官方页面自行登录。学生菜单实际提供：

`clickMenu('N2155','/cdjy/cdjy_cxKxcdlb.html','查询空闲教室',...)`

完整页面使用 `?gnmkdm=N2155&layout=default`。省略layout会返回局部HTML，缺少jQuery依赖，不能据此认定模块不可用。登录状态在本次研究中曾跳回登录页；重新认证后成功取得表单、实际查询和JSON响应。不复制认证会话到代码、日志或GitHub。

已读取学校部署脚本 `/js/comp/jwglxt/pkgl/cdjy/kxcdlb.js`，重点检查 `queryFunc`、`hqjcList`、`loadSchedule`，并通过已认证会话验证以下只读接口。客户端采用已实测成功的GET，官方页面查询脚本也存在POST调用；不调用预约、申请、导出或修改接口。

| 接口（均为 /cdjy/ 前缀） | 实测用途与响应 |
| --- | --- |
| cdjy_cxKxcdlb.html?gnmkdm=N2155&layout=default | select#dm_cx学期、select#xqh_id校区；当前学期2026-3；7个校区 |
| cdjy_cxXqjc.html | xnm/xqm/xqh_id；lhList的JXLDM/JXLMC；jcList的JCMC/SJD，共13节 |
| cdjy_cxQtlb.html | xnm/xqm/xqh_id/flag=0；dqzcxq校历、nxqzcList周次 |
| cdjy_cxDateInforma.html | xnm/xqm/zcd/xqj；日期字符串数组，用于校验日期与教学周一致 |
| cdjy_cxKxcdlb.html?doType=query | xnm/xqm/xqh_id/lh/jyfs=0/zcd/xqj/jcd及queryModel分页；items、totalCount、totalPage |
| cdjy_cxAtyycdSchedule.html | xnm/xqm/xqh_id/rq/cdmc/cdjylx/sfbhkc；jcList、scheduleList全天安排 |

周次和节次使用位掩码：单个第n周/节为2^(n-1)，选中起止节次的位值相加。星期1至7。不能从其他学校照搬楼号、校区ID或日期。

实测：2026-11-06对应学校第8周星期五，`zcd=128,xqj=5`日期接口明确返回该日期。教室模块本学期第一教学周周一为2026-09-14、开放至2027-01-24；与原个人课表默认周历不同，不修改用户原学期。

选择主校区、第8周星期五、第1–2节，学校页面显示838条空闲场地记录（包含体育场所，并不全是可自习教室）；已核对JSON分页字段。A101全天接口包含第6/7节占用，同时相同条件的空闲接口排除A101。这里只记录必要的结构与核对结论，不保存完整学校响应和课程/人员内容。

## 全天占用语义

学校脚本按 jcList[].jcm 定位 `rs_<位值>`。存在非空文本表示占用，缺少该rs字段在学校自己的loadSchedule渲染中表示该节空闲。这是已验证的稀疏占用映射，不等同于“任意缺字段都空闲”：本实现要求房间ID明确匹配、节次位值完整对应、日期经过学校校验。缺少节次映射标记未知；没有找到教室、接口失败或数据结构异常时不产生全天空闲结果。占用原文可能包含课程/人员信息，仅导出占用状态，不导出原文。

## 开源参考范围

实际阅读了：

- 3beuml/ZZUPocket：RoomRepository.kt、RoomModels.kt、RoomProbe.kt。借鉴进程内短缓存、条件完整作为缓存键、标注数据时刻的设计。其当前教务为另一套接口，未复用端点或认证方式。
- drfccv/ZFJW-backend：zfjw/api/classroom.py及学校配置。对照位掩码、分页与选项加载，但以邯郸实际部署脚本和真实返回为准；没有复制其跳过TLS校验、原始请求日志等实现。

## 验证边界

学校接口已在云端本人认证会话中实测，并已将同一契约编写为APK内固定只读适配器。浏览器会话不是手机WebView会话，不能把网页实测冒充新APK真机通过。新APK首次查询、不同设备/账号、更多校区学期仍需真机验证。iOS/PWA未新增学校直连支持。
