import 'package:flutter_test/flutter_test.dart';
import 'package:xianbao/models/ucenter.dart';
import 'package:xianbao/models/ucenter_form.dart';
import 'package:xianbao/models/ucenter_table.dart';
import 'package:xianbao/services/ucenter_service.dart';

/// 用户中心解析层测试。夹具按线上响应的结构裁剪而来（2026-10-09 抓取），
/// 令牌、昵称、邮箱一类换成占位值。
///
/// 覆盖：首页统计片段、导航片段、layui 表单片段（含单选组/开关/多选组/禁用/隐藏）、
/// 分页表格 JSON、流水片段里的 HTML 表格、登录回包。

/// `POST …/src/views/index.php` 的统计区（四张卡片）+ 公告。
const String _indexFragment = r'''
<div class="layui-fluid" id="index_page">
  <div class="layui-row" id="tophtml">
    <div class="layui-col-sm6"><div class="layui-card">
      <div class="layui-card-header">账号级别：<span style="float: right;"><a class="biaohtml" lay-href="Vip">购买会员</a></span></div>
      <div class="layui-card-body layuiadmin-card-list">
        <p class="layuiadmin-big-font level">注册用户</p>
      </div>
    </div></div>
    <div class="layui-col-sm6"><div class="layui-card">
      <div class="layui-card-header">积分：<span style="float: right;"><a class="biaohtml" lay-href="Pay">充值</a></span></div>
      <div class="layui-card-body layuiadmin-card-list">
        <p class="layuiadmin-big-font level">668</p>
      </div>
    </div></div>
    <div class="layui-col-sm6"><div class="layui-card">
      <div class="layui-card-header">收藏文章：<span style="float: right;"><a lay-href="Collectlist">收藏管理</a></span></div>
      <div class="layui-card-body layuiadmin-card-list">
        <p class="layuiadmin-big-font level">7</p>
      </div>
    </div></div>
    <div class="layui-col-sm6"><div class="layui-card">
      <div class="layui-card-header">评论总数：</div>
      <div class="layui-card-body layuiadmin-card-list">
        <p class="layuiadmin-big-font level">0</p>
      </div>
    </div></div>
  </div>
  <div class="layui-card">
    <div class="layui-card-header">网站公告</div>
    <div class="layui-card-body layui-text gonggao"><p>会员功能使用文档：<a href="/docs/index.html">点击直达</a></p></div>
  </div>
</div>
''';

/// `POST …/src/views/Nav.php` 的顶栏用户区。
const String _navFragment = r'''
<div class="layui-header">
  <a href="javascript:;" class="nav-imsgs-iisno"><img src="https://new.xianbao.fun/zb_users/upload/mochu_us/userimg/13.png?t=92" class="nav-avatar layui-nav-img"></a>
  <ul class="layui-nav layui-layout-right">
    <li class="layui-nav-item">
      <a href="javascript:;"><div class="layui-clear usernav"><img class="nav-avatar" src="https://new.xianbao.fun/zb_users/upload/mochu_us/userimg/13.png?t=887"><div><p><span class="viple0 viple">注册用户</span>测试昵称</p><p><a lay-href="Vip">升级会员</a></p></div></div></a>
    </li>
  </ul>
</div>
''';

/// `userfilter_fun.php act=edit_html` 的表单结构（按线上 layui 表单裁剪）。
const String _ruleFormFragment = r'''
<form id="keyswords_form" class="layui-form">
  <input type="hidden" name="csrfToken" value="CSRFTOKENPLACEHOLDER" />
  <input type="hidden" name="act" value="edit_save" />
  <input type="hidden" name="id" value="" />
  <div class="layui-form-item">
    <label class="layui-form-label">筛选设置范围</label>
    <div class="layui-input-block"><input type="text" name="fanwei" value="首页" placeholder="留空=全部板块" class="layui-input"></div>
  </div>
  <div class="layui-form-item">
    <label class="layui-form-label">开关状态</label>
    <div class="layui-input-block"><input type="checkbox" name="Status" value="1" lay-skin="switch" checked></div>
  </div>
  <div class="layui-form-item">
    <label class="layui-form-label">关键词</label>
    <div class="layui-input-block"><input type="text" name="title_gjc" value="" class="layui-input"></div>
  </div>
  <div class="layui-form-item">
    <label class="layui-form-label">最低价格</label>
    <div class="layui-input-inline"><input type="text" name="Miprice" value="10" class="layui-input"></div>
  </div>
  <div class="layui-form-item">
    <label class="layui-form-label">会员专属</label>
    <div class="layui-input-block"><input type="text" name="title_pbc" value="广告" disabled class="layui-input"></div>
  </div>
</form>
''';

/// 基本设置页片段：开关 + 单选组 + 多选组 + 多行文本。
const String _settingsFragment = r'''
<div class="layui-form layui-form-pane">
  <div class="layui-form-item">
    <label class="layui-form-label">标题标红开关</label>
    <div class="layui-input-block"><input type="checkbox" name="meta_redswitch" value="1" lay-skin="switch" checked></div>
  </div>
  <div class="layui-form-item">
    <label class="layui-form-label">标题标红关键词设置</label>
    <div class="layui-input-block"><textarea name="meta_redsign" class="layui-textarea">秒杀|整点</textarea></div>
  </div>
  <div class="layui-form-item">
    <label class="layui-form-label">电脑端</label>
    <div class="layui-input-block">
      <input type="radio" name="meta_jiben_fanye_pc" value="1" title="模式一：默认" checked>
      <input type="radio" name="meta_jiben_fanye_pc" value="2" title="模式二：第二页起自动">
      <input type="radio" name="meta_jiben_fanye_pc" value="3" title="模式三：第一页起自动（停用轮询）">
    </div>
  </div>
  <div class="layui-form-item">
    <label class="layui-form-label">预设标题</label>
    <div class="layui-input-block">
      <input type="checkbox" name="moyu_yushe_cb" value="腾讯文档" title="腾讯文档" checked>
      <input type="checkbox" name="moyu_yushe_cb" value="石墨文档" title="石墨文档">
      <input type="checkbox" name="moyu_yushe_cb" value="飞书" title="飞书" checked>
    </div>
  </div>
  <div class="layui-form-item">
    <label class="layui-form-label">轮换间隔(秒)</label>
    <div class="layui-input-inline"><input type="number" name="meta_jiben_biaoti_shijian" value="30" class="layui-input"></div>
  </div>
</div>
''';

/// `json/List.php` 的一页（评论管理）。
const String _commentPageJson = r'''
{"code":"0","msg":"","count":7,"data":[
  {"Centenr":"<p>这个链接打不开</p>","Laiyuan":"<a href=\"/haodan/6614199.html\" target=\"_blank\">乐百氏矿泉水 23.9元</a>","Satus":"已通过","Posttime":"2026-10-08 12:01:11","Caozuo":"<span onclick=\"del_pinglun('88121')\">删除</span>"},
  {"Centenr":"谢谢分享","Laiyuan":"<a href=\"/weibo/1.html\">某条微博线报</a>","Satus":"审核中","Posttime":"2026-10-08 11:20:03","Caozuo":"<span onclick=\"del_pinglun('88122')\">删除</span>"}
]}
''';

/// 会话失效（网站用 1001）。
const String _needLoginJson = r'''{"code":1001,"msg":"请先登录","href":"/login.html"}''';

/// 流水账单片段（服务端渲染的表格）。
const String _liushuiFragment = r'''
<div class="layui-card">
  <div class="layui-card-header">积分流水</div>
  <div class="layui-card-body">
    <table class="layui-table"><thead><tr><th>项目</th><th>单号</th><th>数量</th><th>类型</th><th>时间</th></tr></thead>
      <tbody>
        <tr><td>每日签到</td><td>XBK20251204095043</td><td>+23</td><td>收入</td><td>2025/12/04 09:50:43</td></tr>
        <tr><td>兑换会员</td><td>XBK20251201101112</td><td>-100</td><td>支出</td><td>2025/12/01 10:11:12</td></tr>
      </tbody>
    </table>
  </div>
</div>
''';


/// 排行榜单筛选（`views/bangdanfilter.php`）：整表单页面，标签里带说明 span。
const String _bangdanFormFragment = r"""
<form id="bangdan_form" class="layui-form">
  <input type="hidden" name="act" value="edit_save" />
  <input type="hidden" name="channel" value="bangdan" />
  <input type="hidden" name="id" value="" />
  <input type="hidden" name="csrfToken" value="CSRFTOKENPLACEHOLDER" />
  <div class="layui-form-item">
    <label class="layui-form-label">启用<span class="uf-sub">关掉后本页规则不生效</span></label>
    <div class="layui-input-block"><input type="checkbox" name="Status" value="1" lay-skin="switch" checked></div>
  </div>
  <div class="layui-form-item layui-form-text">
    <label class="layui-form-label">分类关键词<span class="uf-sub">选填 · 作用于线报分类名，配置后仅展示命中的分类</span></label>
    <div class="layui-input-block"><textarea name="category_gjc" placeholder="多个词用 # 分隔"></textarea></div>
  </div>
  <div class="layui-form-item layui-form-text">
    <label class="layui-form-label">分类屏蔽词<span class="uf-sub">选填</span></label>
    <div class="layui-input-block"><textarea name="category_pbc"></textarea></div>
  </div>
  <div class="layui-form-item layui-form-text">
    <label class="layui-form-label">标题关键词<span class="uf-sub">选填</span></label>
    <div class="layui-input-block"><textarea name="title_gjc">元|羊毛</textarea></div>
  </div>
  <div class="layui-form-item layui-form-text">
    <div class="layui-input-block"><textarea name="title_pbc" placeholder="屏蔽词"></textarea></div>
  </div>
</form>
""";

/// 历史筛选数据（只读页）：标签 + 小字键名 + 值。
const String _historyFragment = r"""
<div class="layui-fluid">
  <div class="layui-form-item">
    <label class="layui-form-label xsb-form-label">旧全局屏蔽开关<br><span class="xsb-keyname">pingbi_global_switch</span></label>
    <div class="layui-input-block xsb-input-block"><input type="text" value="1" readonly></div>
  </div>
  <div class="layui-form-item">
    <label class="layui-form-label xsb-form-label">旧全局屏蔽词<br><span class="xsb-keyname">pingbi_global</span></label>
    <div class="layui-input-block xsb-input-block">抽奖#开奖</div>
  </div>
  <div class="layui-form-item">
    <label class="layui-form-label xsb-form-label">旧关注词</label>
    <div class="layui-input-block xsb-input-block"></div>
  </div>
</div>
""";

void main() {
  group('UcenterHome.parse', () {
    test('四张统计卡片与公告', () {
      final home = UcenterHome.parse(_indexFragment);
      expect(home.stats.length, 4);
      expect(home.level, '注册用户');
      expect(home.points, '668');
      expect(home.collects, '7');
      expect(home.comments, '0');
      expect(home.announcement, contains('会员功能使用文档'));
    });

    test('取不到的字段返回空串而不是抛错', () {
      final home = UcenterHome.parse('<div class="layui-fluid"></div>');
      expect(home.stats, isEmpty);
      expect(home.level, '');
      expect(home.points, '');
    });

    test('未登录时的「温馨提示」片段识别为会话过期', () {
      // 线上未登录请求 views/index.php 回来的就是这个结构。
      const guestFragment =
          '<div class="layui-fluid"><div class="layui-card"><div class="posttips">'
          '<img src="/zb_users/plugin/mochu_us/src/style/img/np.png" />'
          '<p>温馨提示：您的登陆已到期，请重新登录！</p></div></div></div>';
      expect(ucenterSessionExpired(guestFragment), isTrue);
      final home = UcenterHome.parse(guestFragment);
      expect(home.sessionExpired, isTrue);
      expect(home.stats, isEmpty);
      // 正常片段不会被误判。
      expect(ucenterSessionExpired(_indexFragment), isFalse);
    });
  });

  group('parseUcenterProfile', () {
    test('头像、昵称与等级标识', () {
      final profile = parseUcenterProfile(_navFragment);
      expect(
        profile.avatarUrl,
        'https://new.xianbao.fun/zb_users/upload/mochu_us/userimg/13.png?t=92',
      );
      expect(profile.nickname, '测试昵称');
      expect(profile.levelText, '注册用户');
      expect(profile.levelIndex, 0);
    });

    test('没有用户区时全部为空', () {
      final profile = parseUcenterProfile('<div></div>');
      expect(profile.nickname, '');
      expect(profile.levelText, '');
      expect(profile.avatarUrl, '');
    });
  });

  group('UcenterForm.parse', () {
    test('按字段类型解析，隐藏字段照带', () {
      final form = UcenterForm.parse(_ruleFormFragment);
      final byName = {for (final f in form.fields) f.name: f};

      expect(byName['csrfToken']!.kind, UcenterFieldKind.hidden);
      expect(byName['act']!.value, 'edit_save');
      expect(byName['fanwei']!.kind, UcenterFieldKind.text);
      expect(byName['fanwei']!.label, '筛选设置范围');
      expect(byName['fanwei']!.value, '首页');
      expect(byName['Status']!.kind, UcenterFieldKind.switchField);
      expect(byName['Status']!.isChecked, isTrue);
      expect(byName['Miprice']!.value, '10');
      expect(byName['title_pbc']!.disabled, isTrue);
    });

    test('回传：未勾选的开关不出现，隐藏字段保留', () {
      final form = UcenterForm.parse(_ruleFormFragment);
      final data = form.toFormData();
      expect(data['act'], 'edit_save');
      expect(data['Status'], '1');
      expect(data['fanwei'], '首页');

      final unchecked = form.withValues({'Status': '', 'fanwei': '分类页'});
      final uncheckedData = unchecked.toFormData();
      expect(uncheckedData.containsKey('Status'), isFalse);
      expect(uncheckedData['fanwei'], '分类页');
    });

    test('单选组归并成一个带选项的字段', () {
      final form = UcenterForm.parse(_settingsFragment);
      final radio = form.fields.firstWhere(
        (f) => f.name == 'meta_jiben_fanye_pc',
      );
      expect(radio.kind, UcenterFieldKind.radio);
      expect(radio.options.length, 3);
      expect(radio.options.first.label, '模式一：默认');
      expect(radio.value, '1');
      expect(radio.options[2].value, '3');
    });

    test('多选组带全部选项与已勾选项，按多值回传', () {
      final form = UcenterForm.parse(_settingsFragment);
      final group = form.fields.firstWhere((f) => f.name == 'moyu_yushe_cb');
      expect(group.isMultiCheckbox, isTrue);
      expect(group.options.length, 3);
      expect(group.selectedValues, ['腾讯文档', '飞书']);

      final data = form.withValues({
        'moyu_yushe_cb': '腾讯文档,飞书,石墨文档',
      }).toFormData();
      expect(data['moyu_yushe_cb'], ['腾讯文档', '飞书', '石墨文档']);

      final cleared = form.withValues({'moyu_yushe_cb': ''}).toFormData();
      expect(cleared.containsKey('moyu_yushe_cb'), isFalse);
    });

    test('多行文本与数字字段', () {
      final form = UcenterForm.parse(_settingsFragment);
      final textarea = form.fields.firstWhere((f) => f.name == 'meta_redsign');
      expect(textarea.kind, UcenterFieldKind.textarea);
      expect(textarea.value, '秒杀|整点');
      final number = form.fields.firstWhere(
        (f) => f.name == 'meta_jiben_biaoti_shijian',
      );
      expect(number.kind, UcenterFieldKind.number);
      expect(number.value, '30');
    });

    test('visibleFields 不含隐藏字段', () {
      final form = UcenterForm.parse(_ruleFormFragment);
      expect(
        form.visibleFields.any((f) => f.kind == UcenterFieldKind.hidden),
        isFalse,
      );
    });
  });

  group('readValues', () {
    test('按字段名取开关/单选/多选的当前值', () {
      final values = readValues(_settingsFragment, const [
        'meta_redswitch',
        'meta_redsign',
        'meta_jiben_fanye_pc',
        'meta_jiben_biaoti_shijian',
        '不存在',
      ]);
      expect(values['meta_redswitch'], '1');
      expect(values['meta_redsign'], '秒杀|整点');
      expect(values['meta_jiben_fanye_pc'], '1');
      expect(values['meta_jiben_biaoti_shijian'], '30');
      expect(values.containsKey('不存在'), isFalse);
    });
  });

  group('UcenterTablePage.fromJson', () {
    test('解析行、总数与去标签后的单元格', () {
      final page = UcenterTablePage.fromJson(_commentPageJson);
      expect(page.needLogin, isFalse);
      expect(page.total, 7);
      expect(page.rows.length, 2);
      expect(page.rows.first.cell('Centenr'), '这个链接打不开');
      expect(page.rows.first.cell('Satus'), '已通过');
      expect(
        page.rows.first.articleUrl,
        '/haodan/6614199.html',
      );
      expect(page.rows.first.actionId, '88121');
      expect(page.rows.last.actionId, '88122');
    });

    test('code 1001 = 会话失效', () {
      final page = UcenterTablePage.fromJson(_needLoginJson);
      expect(page.needLogin, isTrue);
      expect(page.message, '请先登录');
      expect(page.rows, isEmpty);
    });

    test('空响应不抛错', () {
      final page = UcenterTablePage.fromJson('');
      expect(page.rows, isEmpty);
      expect(page.total, 0);
      expect(page.needLogin, isFalse);
    });
  });

  group('parseFragmentTables', () {
    test('读表头与行，并带上卡片标题', () {
      final tables = parseFragmentTables(_liushuiFragment);
      expect(tables.length, 1);
      expect(tables.single.title, '积分流水');
      expect(tables.single.headers.first, '项目');
      expect(tables.single.rows.length, 2);
      expect(tables.single.rows.first.first, '每日签到');
      expect(tables.single.rows.last[2], '-100');
    });

    test('没有表格的片段返回空表', () {
      expect(parseFragmentTables('<div>没有表格</div>'), isEmpty);
    });
  });


  group('UcenterFilterTarget（各筛选页的接口位置）', () {
    test('常规频道带 channel，值得买是独立端点且不带 channel', () {
      final shouye = UcenterFilterTarget.shouye.params(act: 'list');
      expect(shouye['channel'], 'shouye');
      expect(shouye['act'], 'list');

      final zhidemai = UcenterFilterTarget.zhidemai.params(act: 'list');
      expect(zhidemai.containsKey('channel'), isFalse);
      expect(UcenterFilterTarget.zhidemai.endpoint, 'zhidemaifilter_fun.php');

      // 带 id / 分页时也照常拼参数。
      final withId = UcenterFilterTarget.haodan.params(
        act: 'deldata',
        id: '42',
      );
      expect(withId, {'act': 'deldata', 'channel': 'haodan', 'id': '42'});
    });
  });

  group('排行榜单筛选（整表单页）', () {
    test('解析出表单字段，标签只取直接文本（不含说明 span）', () {
      final form = UcenterForm.parse(_bangdanFormFragment);
      final byName = {for (final f in form.fields) f.name: f};
      expect(byName['Status']!.label, '启用');
      expect(byName['category_gjc']!.label, '分类关键词');
      expect(byName['category_pbc']!.label, '分类屏蔽词');
      expect(byName['title_gjc']!.label, '标题关键词');
      expect(byName['title_gjc']!.value, '元|羊毛');
      expect(byName['channel']!.value, 'bangdan');
    });

    test('没有标签的字段用占位文案兜底，而不是露出英文名', () {
      final form = UcenterForm.parse(_bangdanFormFragment);
      final titlePbc = form.fields.firstWhere((f) => f.name == 'title_pbc');
      expect(titlePbc.label, '屏蔽词');
      // 标签不会是字段名本身。
      expect(titlePbc.label, isNot('title_pbc'));
    });

    test('回传时带隐藏字段（act/channel/id），未勾选的开关不出现', () {
      final form = UcenterForm.parse(_bangdanFormFragment);
      final data = form.toFormData();
      expect(data['act'], 'edit_save');
      expect(data['channel'], 'bangdan');
      expect(data['Status'], '1');
      expect(form.withValues({'Status': ''}).toFormData().containsKey('Status'), isFalse);
    });
  });

  group('parseReadonlyFields（历史筛选数据）', () {
    test('解析标签、旧键名与值', () {
      final fields = parseReadonlyFields(_historyFragment);
      expect(fields.length, 3);
      expect(fields[0].label, '旧全局屏蔽开关');
      expect(fields[0].key, 'pingbi_global_switch');
      expect(fields[0].value, '1');
      expect(fields[1].label, '旧全局屏蔽词');
      expect(fields[1].value, '抽奖#开奖');
      // 空值条目也保留（页面显示为空），由页面过滤。
      expect(fields[2].value, '');
      expect(fields[2].isEmpty, isTrue);
    });
  });

  group('LoginResult.fromText', () {
    test('成功（服务端没有 code 1/2）', () {
      final result = LoginResult.fromText('{"code":"0","msg":"登录成功"}');
      expect(result.ok, isTrue);
      expect(result.message, '登录成功');
    });

    test('code 1 = 出错（验证码之类），把服务端消息原样带回来', () {
      final result = LoginResult.fromText('{"code":"1","msg":"验证码错误"}');
      expect(result.ok, isFalse);
      expect(result.message, '验证码错误');
    });

    test('code 2 = 需要跳转', () {
      final result = LoginResult.fromText(
        '{"code":"2","msg":"请先验证邮箱","href":"/Ucenter"}',
      );
      expect(result.ok, isFalse);
      expect(result.redirectUrl, '/Ucenter');
    });

    test('空响应/坏 JSON 不抛错', () {
      expect(LoginResult.fromText('').ok, isFalse);
      expect(LoginResult.fromText('<html>').ok, isFalse);
    });
  });
}
