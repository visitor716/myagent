# OA 费用报销单（武汉）WfForm 自动填写实测手册（2026-08-18 会话）

适用表单：费用报销单审批（武汉）（requestid 草稿，经典 E9 引擎 + WfForm API）。
项目侧代码：/home/zhanxp/projects/oa-fill-assistant；更多惯例见项目内
docs/agent-memory/reimbursement-form-conventions.md。

## 表单字段映射（WfForm.convertFieldNameToId 实测）

基础字段：sy=field6481(事由) sqrq=field6480(申请日期) yxzh=field6637(银行账号)
shhj=field10642(审核会计) bz=field11093(币种) sfyfp=field10660(是否有电子发票)
szgs=field6668(所属公司) sjbxr=field6636(实际报销人) zjje/clhjje=自动合计

- detail_1 = oTable0 差旅报销：lx=field6489 qzd=field6491 tj=field6789 zd=field6790
  ksrq=field6492 jsrq=field6493 fy=field6494 tzr=field10405 bz=field6495
- detail_2 补贴表；detail_3 非差旅报销；detail_4 借支核销；detail_6 研发分摊
- detail_5 = oTable4 电子发票明细：fpdm=field10403 fphm=field10402 fph=field10404

## 模板固定值与填写惯例（取自 2026-08-03 / 2026-06-21 已归档单）

- lx 类型代码：0=火车 4=住宿 5=市内交通(车站往返)
- shhj=2045(黄漪娴) bz=1(RMB) sfyfp=0 tzr 同住人=2361(汪毅德，browser 字段需 specialobj)
- yxzh="6226 2205 1911 6932"（带空格）
- 发票行固定：fpdm=001 fphm=20位号码 fph=001+号码（无发票代码填001）
- sy 格式："<客户名>客户端出差（YYYY.M.D-YYYY.M.D）"
- 差旅明细行顺序：火车逐段(lx=0) -> 滴滴/市内交通(lx=5) -> 住宿汇总行(lx=4，
  整段日期区间+总额+tzr+bz注明晚数和单价，如"住宿30晚，198元/晚"）
- lx=5 交通费行的起点/终点统一写"车站(宿舍)"（用户 2026-08-18 明确要求，
  对齐 06-21 模板惯例）——即使实际端点是具体酒店名/站名也写"车站(宿舍)"
- 金额两位小数"308.00"；日期 YYYY-MM-DD
- 12306 全电发票统一开票日（如08-18）时，文件名日期可能是开票日而非行程日；
  按衔接车次/滴滴链推断真实行程日，行内 bz 注明"发票开具日期XXXX，行程日期XX-XX"

## 填写前合规检查：跨单重复发票

填写前打开"我的请求"(listMine) 读取近月已提交/在途报销单，比对本月发票号码：
同一发票号出现在两张在途单会重复报销（财务查验发票号必命中）。
发现重叠时报告用户并让用户决定（撤旧单/剔除该行/忽略），不要自行跳过或删行。

## WSL 执行链路

1. Windows Chrome CDP 从 WSL 仅经 relay 可达（ws://172.31.112.1:39222，
   由 wsl-windows-chrome 技能的 attach 脚本维护；直连 127.0.0.1:9222 不通）。
2. 工具若硬编码 127.0.0.1:9222（如 oa-fill-assistant Python 流程），先起本地 TCP 转发：
   python3 /home/zhanxp/projects/oa-fill-assistant/scripts/cdp_local_proxy.py
   （stdlib asyncio，127.0.0.1:9222 -> 172.31.112.1:39222，后台常驻）
3. Node playwright 可用性：NODE_PATH=~/.nvm/versions/node/v20.20.2/lib/node_modules/@playwright/cli/node_modules
   （WSL 侧 pip playwright 因 PEP 668 未装，Node 路线更快）。
4. 用户给的表单 URL 带 _key 令牌是一次性的，直接 goto 会跳登录页。正确姿势：
   在已登录的 listMine 标签页里按行文本定位（创建时间戳）click 列表行，
   监听 context 'page' 事件拿新表单页（带新 sessionkey）。
5. 复用已打开的表单标签：按 URL 含 requestid=<id> 查找 context.pages()。

## 填写与保存流程（本次验证可行）

1. dry-run：填入全部字段 -> 逐字段 getFieldValue 回读比对 -> 0 失配才继续（不保存）。
2. 正式：重新幂等填写 -> 点击安全"保存"按钮 -> 等待 toast（可能捕捉不到）。
3. 落库验证以 reload 后服务器回读为准（本次单次保存全部落库，
   与旧"每段保存"建议并存：该表单引擎 addDetailRow 行在单次保存后可存活）。
4. **保存等待（2026-08-18 实测踩坑）**：点击保存后仅等 ~4s 就 reload 会中断
   还在途的保存 XHR，改动静默丢失（表单上还是旧值）。必须等保存网络空闲：
   轮询 `performance.getEntriesByType('resource')` 中 1200ms 内是否仍有
   /workflow|reqform|save/i 请求，连续 ~5s 无活动后再加 3s 缓冲，才允许 reload。
5. **reload 后水合等待**：WfForm 对象先于明细数据加载出现。reload 后立即
   getFieldValue 会拿到空行/空合计，误判为数据丢失。必须轮询
   `getDetailAllRowIndexStr('detail_1')` 直到达到预期行数（如 7）再回读。
6. 安全保存按钮匹配：normalize 去空白后 text==='保存'||'保存草稿'，
   严格排除 提交/转发/转办/移交/归档/办结；按钮实际文本是"保 存"（带空格）。
7. 绝不点击 提交/转发/转办/移交。

## 发票号码独立核验（表单 vs 资料目录）

用户会要求核对表单上的发票号与资料目录是否一致。核验必须独立重新提取，
不能拿填写来源的 OCR JSON 自查（同源数据必然一致，没有验证意义）：

1. 文本层 PDF（滴滴/住宿等数电票）：
   `pdftotext -layout <file> - | grep -oE '[0-9]{20}'`
2. 图片型 PDF（12306 火车票 PDF 只有"￥"等零星文本，页面是渲染图）：
   `pdftoppm -r 300 -png <file> /tmp/ocr_check/<base>`
   然后 `tesseract <img> - --psm 6 -l chi_sim | grep '发票号码'` —— 数字干净可读。
3. **反模式**：tesseract 加 `-c tessedit_char_whitelist=0123456789` 会把相邻
   字符粘连成大量伪 20 位数字串，无法使用；必须用 chi_sim 语言模型整行识别。
4. 顺带报告"目录有、表单无"的项（待确认资料），区分文本层可靠号码与
   OCR 读出但可能误读 1 位的号码（如 8/9 之差需人工确认）。

## Playwright CDP 技术坑

- page.evaluate 传字符串箭头函数不会自动调用、返回 undefined：必须用
  new Function('return (' + script + ')();') 包装后再 evaluate。
- 页面被表单 SPA 关闭时报 "Target page has been closed"：优先复用已有标签，
  新开标签导航失败时回退 listMine 点击法。
- 明细行单元格 mark = `${fieldId}_${rowIndex}`，rowIndex 取自
  WfForm.getDetailAllRowIndexStr(mark).split(',')。
- 加行：WfForm.addDetailRow(mark, {})，每次 ~350ms 后重读行数；
  写值：WfForm.changeFieldValue(mark, {value, specialobj:[{id,name}]}) + triggerFieldAllLinkage(mark)。
- browser 类字段（tzr/shhj）传 {value, specialobj:[{id,name}]}，
  纯 select 字段只传 {value} 即可。
- 保存成功的 toast 可能出现在 portal 层且转瞬即逝，不能作为落库依据。
