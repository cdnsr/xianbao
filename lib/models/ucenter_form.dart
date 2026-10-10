import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 服务端渲染表单片段的解析与回传（用户中心的规则行编辑弹层用它）。
///
/// 规则行的编辑表单是服务端给的 HTML（`userfilter_fun.php act=edit_html`），字段
/// 由网站定义、可能随版本增减，所以这里不写死字段名：把片段解析成字段列表
/// （名称 / 标签 / 类型 / 当前值 / 选项），原生渲染后再按同样的名字回传，服务端
/// 加了新字段也能跟上。基本设置六页的字段形状固定，直接用 [readValues] 取当前值。
enum UcenterFieldKind {
  hidden,
  text,
  number,
  password,
  textarea,
  dropdown,
  radio,

  /// layui 开关（`lay-skin="switch"` 的 checkbox）。
  switchField,

  checkbox,
}

class UcenterFormOption {
  final String value;
  final String label;

  const UcenterFormOption({required this.value, required this.label});
}

class UcenterFormField {
  final String name;
  final String label;
  final UcenterFieldKind kind;

  /// 当前值：文本框是内容，开关/单勾选是 `1`，下拉/单选是选中项的值。
  /// 开关未勾选、单选未选中时为空串。
  final String value;

  final String placeholder;
  final bool disabled;
  final bool required;
  final List<UcenterFormOption> options;

  /// 多选（同名多个 checkbox）时被勾选的项；单勾选/开关为空表。
  final List<String> selectedValues;

  const UcenterFormField({
    required this.name,
    required this.label,
    required this.kind,
    this.value = '',
    this.placeholder = '',
    this.disabled = false,
    this.required = false,
    this.options = const <UcenterFormOption>[],
    this.selectedValues = const <String>[],
  });

  bool get isChecked => value == '1' || value == 'on' || value == 'true';

  /// 同名多个 checkbox（如摸鱼预设标题）：要按多选渲染、按多值回传。
  bool get isMultiCheckbox =>
      kind == UcenterFieldKind.checkbox && options.length > 1;
}

class UcenterForm {
  final List<UcenterFormField> fields;

  /// 服务端在片段里附带的提示文字（如限额说明），没有则空串。
  final String message;

  const UcenterForm({this.fields = const [], this.message = ''});

  List<UcenterFormField> get visibleFields =>
      fields.where((f) => f.kind != UcenterFieldKind.hidden).toList();

  /// 表单要回传的字段。
  ///
  /// 与浏览器提交一致：未勾选的开关/勾选框**不出现**在表单里（服务端按缺省当关），
  /// 多选组回传一组值，隐藏字段照带（服务端的 csrfToken、act、id 都在里面）。
  Map<String, dynamic> toFormData() {
    final data = <String, dynamic>{};
    for (final field in fields) {
      switch (field.kind) {
        case UcenterFieldKind.checkbox:
          if (field.isMultiCheckbox) {
            final selected = _selectedValuesOf(field);
            if (selected.isNotEmpty) data[field.name] = selected;
          } else if (field.isChecked || _selectedValuesOf(field).isNotEmpty) {
            final selected = _selectedValuesOf(field);
            data[field.name] = selected.isNotEmpty
                ? selected.first
                : (field.value.isEmpty ? '1' : field.value);
          }
        case UcenterFieldKind.switchField:
          if (field.isChecked) {
            data[field.name] = field.value.isEmpty ? '1' : field.value;
          }
        case UcenterFieldKind.hidden:
        case UcenterFieldKind.text:
        case UcenterFieldKind.number:
        case UcenterFieldKind.password:
        case UcenterFieldKind.textarea:
        case UcenterFieldKind.dropdown:
        case UcenterFieldKind.radio:
          data[field.name] = field.value;
      }
    }
    return data;
  }

  /// 勾选项：优先用编辑后的值，没有就取解析时的勾选状态。
  List<String> _selectedValuesOf(UcenterFormField field) {
    if (field.selectedValues.isNotEmpty) return field.selectedValues;
    if (field.isChecked && field.options.isNotEmpty) {
      return [field.options.first.value];
    }
    return const <String>[];
  }

  /// 用编辑后的值覆盖字段后返回新表单（提交前调用）。
  ///
  /// [values] 里多选字段用逗号分隔的多个值表示（见 `UcenterFormView`）。
  UcenterForm withValues(Map<String, String> values) {
    return UcenterForm(
      message: message,
      fields: fields
          .map(
            (field) => values.containsKey(field.name)
                ? UcenterFormField(
                    name: field.name,
                    label: field.label,
                    kind: field.kind,
                    value: values[field.name] ?? '',
                    placeholder: field.placeholder,
                    disabled: field.disabled,
                    required: field.required,
                    options: field.options,
                    selectedValues: field.isMultiCheckbox
                        ? (values[field.name] ?? '')
                              .split(',')
                              .where((v) => v.isNotEmpty)
                              .toList()
                        : field.selectedValues,
                  )
                : field,
          )
          .toList(),
    );
  }

  /// 解析一份 layui 表单片段。
  ///
  /// 同名控件会归并：一组 radio 合成一个带选项的字段；layui 给开关配的隐藏兜底
  /// 输入（`<input type="hidden" name="X">` + `<input type="checkbox" name="X">`）
  /// 只保留可见的那个，隐藏值当作未勾选时的回传值。
  factory UcenterForm.parse(String html) {
    final document = html_parser.parse(html);
    final ordered = <UcenterFormField>[];
    final indexByName = <String, int>{};

    void accept(UcenterFormField field) {
      if (field.name.isEmpty) return;
      final existingIndex = indexByName[field.name];
      if (existingIndex == null) {
        indexByName[field.name] = ordered.length;
        ordered.add(field);
        return;
      }
      final existing = ordered[existingIndex];
      if (field.kind == UcenterFieldKind.radio &&
          existing.kind == UcenterFieldKind.radio) {
        ordered[existingIndex] = UcenterFormField(
          name: existing.name,
          label: existing.label.isNotEmpty ? existing.label : field.label,
          kind: UcenterFieldKind.radio,
          value: existing.value.isNotEmpty ? existing.value : field.value,
          disabled: existing.disabled,
          options: [...existing.options, ...field.options],
        );
        return;
      }
      // 同名 checkbox 是一组多选（如摸鱼的预设标题），合并选项与勾选状态。
      if (field.kind == UcenterFieldKind.checkbox &&
          existing.kind == UcenterFieldKind.checkbox) {
        final options = [...existing.options, ...field.options];
        final selected = {
          ...existing.selectedValues,
          ...field.selectedValues,
        }.toList();
        ordered[existingIndex] = UcenterFormField(
          name: existing.name,
          label: existing.label.isNotEmpty ? existing.label : field.label,
          kind: UcenterFieldKind.checkbox,
          value: selected.isNotEmpty ? selected.first : '',
          disabled: existing.disabled,
          options: options,
          selectedValues: selected,
        );
        return;
      }
      // 隐藏兜底 vs 可见控件：可见的那个说了算。
      if (existing.kind == UcenterFieldKind.hidden &&
          field.kind != UcenterFieldKind.hidden) {
        ordered[existingIndex] = UcenterFormField(
          name: field.name,
          label: field.label.isNotEmpty ? field.label : existing.label,
          kind: field.kind,
          value: field.value,
          placeholder: field.placeholder,
          disabled: field.disabled,
          required: field.required,
          options: field.options,
        );
      }
    }

    final visited = <dom.Element>{};
    for (final item in document.querySelectorAll('.layui-form-item')) {
      final label = _labelTextOf(item);
      for (final element in item.querySelectorAll('input,textarea,select')) {
        visited.add(element);
        final field = _fieldFromElement(element, label);
        if (field != null) accept(field);
      }
    }
    // 表单项之外的字段（csrfToken / act / id 这类隐藏输入）也要带上；
    // 已经按 form-item 收过的不能再收一遍，否则同一个控件的选项会被叠加。
    for (final element in document.querySelectorAll('input,textarea,select')) {
      if (visited.contains(element)) continue;
      final field = _fieldFromElement(element, '');
      if (field != null) accept(field);
    }

    return UcenterForm(
      fields: ordered,
      message: document.querySelector('.layui-elem-quote')?.text.trim() ?? '',
    );
  }
}

/// 取表单项的标签文案。
///
/// 只取标签元素的**直接文本**：网站常把说明塞在标签里的 `<span>` 中
/// （`分类关键词<span class="uf-sub">选填 · 作用于分类名</span>`），
/// 整段 text 会把说明一起带上，标题就变得又长又乱。
/// 依次尝试 `.layui-form-label` → 任意 `label` → `legend`/`cite`。
String _labelTextOf(dom.Element item) {
  for (final selector in const [
    '.layui-form-label',
    'label',
    'legend',
    'cite',
  ]) {
    final element = item.querySelector(selector);
    if (element == null) continue;
    final text = _directText(element);
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// 元素自身文本（不含子元素的文本），用于取干净的标签。
String _directText(dom.Element element) {
  final buffer = StringBuffer();
  for (final node in element.nodes) {
    if (node.nodeType == dom.Node.TEXT_NODE) {
      buffer.write(node.text);
    }
  }
  final text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isNotEmpty) return text;
  // 标签全被包在子元素里时退一步用整段文本（并压掉多余空白）。
  return element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 字段没有标签时的兜底名：`title` / `placeholder` / 原始 name。
String _fallbackLabel(dom.Element element, String name) {
  final title = element.attributes['title']?.trim() ?? '';
  if (title.isNotEmpty) return title;
  final placeholder = element.attributes['placeholder']?.trim() ?? '';
  if (placeholder.isNotEmpty) {
    // 占位文案常常很长（说明性文字），截断到第一个分隔符/一定长度。
    final short = placeholder.split(RegExp(r'[，,。（(]')).first.trim();
    return short.isEmpty ? name : (short.length > 16 ? name : short);
  }
  return name;
}

UcenterFormField? _fieldFromElement(dom.Element element, String rawLabel) {
  final name = element.attributes['name']?.trim() ?? '';
  if (name.isEmpty) return null;
  final label = rawLabel.isNotEmpty ? rawLabel : _fallbackLabel(element, name);
  final type = (element.attributes['type'] ?? '').toLowerCase();
  final disabled = element.attributes.containsKey('disabled');
  final required = element.attributes.containsKey('required');

  if (element.localName == 'textarea') {
    return UcenterFormField(
      name: name,
      label: label,
      kind: UcenterFieldKind.textarea,
      value: element.text.trim(),
      placeholder: element.attributes['placeholder'] ?? '',
      disabled: disabled,
      required: required,
    );
  }

  if (element.localName == 'select') {
    final options = <UcenterFormOption>[];
    var selected = '';
    for (final option in element.querySelectorAll('option')) {
      final value = option.attributes['value'] ?? option.text.trim();
      options.add(
        UcenterFormOption(value: value, label: option.text.trim()),
      );
      if (option.attributes.containsKey('selected')) selected = value;
    }
    return UcenterFormField(
      name: name,
      label: label,
      kind: UcenterFieldKind.dropdown,
      value: selected,
      disabled: disabled,
      required: required,
      options: options,
    );
  }

  switch (type) {
    case 'hidden':
      return UcenterFormField(
        name: name,
        label: label,
        kind: UcenterFieldKind.hidden,
        value: element.attributes['value'] ?? '',
      );
    case 'checkbox':
      final isSwitch = (element.attributes['lay-skin'] ?? '') == 'switch';
      final optionValue = element.attributes['value']?.isNotEmpty == true
          ? element.attributes['value']!
          : '1';
      final checked = element.attributes.containsKey('checked');
      return UcenterFormField(
        name: name,
        label: label,
        kind: isSwitch
            ? UcenterFieldKind.switchField
            : UcenterFieldKind.checkbox,
        value: checked ? optionValue : '',
        disabled: disabled,
        options: [
          UcenterFormOption(
            value: optionValue,
            label: element.attributes['title'] ?? label,
          ),
        ],
        selectedValues: checked ? [optionValue] : const <String>[],
      );
    case 'radio':
      return UcenterFormField(
        name: name,
        label: label,
        kind: UcenterFieldKind.radio,
        value: element.attributes.containsKey('checked')
            ? (element.attributes['value'] ?? '')
            : '',
        disabled: disabled,
        options: [
          UcenterFormOption(
            value: element.attributes['value'] ?? '',
            label: element.attributes['title'] ?? label,
          ),
        ],
      );
    case 'number':
      return UcenterFormField(
        name: name,
        label: label,
        kind: UcenterFieldKind.number,
        value: element.attributes['value'] ?? '',
        placeholder: element.attributes['placeholder'] ?? '',
        disabled: disabled,
        required: required,
      );
    case 'password':
      return UcenterFormField(
        name: name,
        label: label,
        kind: UcenterFieldKind.password,
        value: '',
        placeholder: element.attributes['placeholder'] ?? '',
        disabled: disabled,
        required: required,
      );
    default:
      return UcenterFormField(
        name: name,
        label: label,
        kind: UcenterFieldKind.text,
        value: element.attributes['value'] ?? '',
        placeholder: element.attributes['placeholder'] ?? '',
        disabled: disabled,
        required: required,
      );
  }
}

/// 从视图片段里按字段名取当前值（基本设置六页用）。
///
/// 开关/勾选框返回 `1`（勾选）或空串；单选返回选中项的 value；文本类返回 value
/// 或正文。字段不存在时不在结果里出现。
Map<String, String> readValues(String html, Iterable<String> names) {
  final wanted = names.toSet();
  final document = html_parser.parse(html);
  final values = <String, String>{};

  for (final element in document.querySelectorAll('input,textarea,select')) {
    final name = element.attributes['name']?.trim() ?? '';
    if (name.isEmpty || !wanted.contains(name) || values.containsKey(name)) {
      continue;
    }
    final type = (element.attributes['type'] ?? '').toLowerCase();
    if (element.localName == 'textarea') {
      values[name] = element.text.trim();
    } else if (element.localName == 'select') {
      final selected = element.querySelector('option[selected]') ??
          element.querySelector('option');
      values[name] = selected?.attributes['value'] ?? selected?.text.trim() ?? '';
    } else if (type == 'checkbox') {
      values[name] = element.attributes.containsKey('checked') ? '1' : '';
    } else if (type == 'radio') {
      if (element.attributes.containsKey('checked')) {
        values[name] = element.attributes['value'] ?? '';
      }
    } else {
      values[name] = element.attributes['value'] ?? '';
    }
  }
  return values;
}

/// 只读页面上的一条「标签 + 值」（历史筛选数据这类没有表单提交的页面）。
class UcenterReadonlyField {
  /// 中文标签。
  final String label;

  /// 旧配置键（页面上的小字，如 `pingbi_global_switch`），可能为空。
  final String key;

  final String value;

  const UcenterReadonlyField({
    required this.label,
    this.key = '',
    this.value = '',
  });

  bool get isEmpty => value.isEmpty;
}

/// 解析只读页面里的「标签 + 值」列表（`views/Shaixuan_history.php`）。
///
/// 这类页面把旧配置按 `标签 + 小字键名 + 值` 铺出来，没有提交按钮也没有接口，
/// 直接解析成原生只读列表展示。
List<UcenterReadonlyField> parseReadonlyFields(String html) {
  final document = html_parser.parse(html);
  final fields = <UcenterReadonlyField>[];

  for (final item in document.querySelectorAll('.layui-form-item')) {
    final labelEl = item.querySelector('.layui-form-label');
    final label = labelEl == null ? '' : _directText(labelEl);
    final key = labelEl?.querySelector('.xsb-keyname')?.text.trim() ?? '';

    var value = '';
    final input = item.querySelector('input,textarea,select');
    if (input != null) {
      if (input.localName == 'textarea') {
        value = input.text.trim();
      } else if (input.localName == 'select') {
        value = input.querySelector('option[selected]')?.text.trim() ?? '';
      } else {
        value = input.attributes['value']?.trim() ?? '';
      }
    }
    if (value.isEmpty) {
      final block = item.querySelector('.layui-input-block') ?? item;
      value = block.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      // 标签与小字键名已经单独展示了，从值里剥掉，免得重复。
      for (final prefix in [label, key]) {
        if (prefix.isNotEmpty && value.startsWith(prefix)) {
          value = value.substring(prefix.length).trim();
        }
      }
    }

    if (label.isEmpty && key.isEmpty && value.isEmpty) continue;
    fields.add(UcenterReadonlyField(label: label, key: key, value: value));
  }
  return fields;
}
