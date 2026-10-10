import 'package:flutter/material.dart';

import '../models/ucenter_form.dart';

/// 服务端下发的表单的原生渲染（规则编辑、基本设置六页共用）。
///
/// 字段来自 [UcenterForm.parse]，按类型渲染：文本 / 多行 / 数字 / 密码 / 下拉 /
/// 单选 / 开关 / 多选组；禁用字段只读展示。编辑结果通过 [UcenterFormViewState.values]
/// 取回（多选组是逗号分隔的值）。
class UcenterFormView extends StatefulWidget {
  final UcenterForm form;

  /// 覆盖初始值（如把令牌换成当前会话的）。
  final Map<String, String>? initialValues;

  const UcenterFormView({super.key, required this.form, this.initialValues});

  @override
  State<UcenterFormView> createState() => UcenterFormViewState();
}

class UcenterFormViewState extends State<UcenterFormView> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _values = {};

  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  void initState() {
    super.initState();
    _seedValues();
  }

  @override
  void didUpdateWidget(covariant UcenterFormView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.form, widget.form)) {
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      _seedValues();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _seedValues() {
    _values.clear();
    for (final field in widget.form.fields) {
      if (field.isMultiCheckbox) {
        _values[field.name] = field.selectedValues.join(',');
      } else {
        _values[field.name] = field.value;
      }
    }
    widget.initialValues?.forEach((key, value) => _values[key] = value);
  }

  TextEditingController _controllerFor(UcenterFormField field) {
    return _controllers.putIfAbsent(
      field.name,
      () => TextEditingController(text: _values[field.name] ?? field.value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in widget.form.visibleFields) ...[
          _buildField(theme, field),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildField(ThemeData theme, UcenterFormField field) {
    final label = field.label.isEmpty ? field.name : field.label;
    if (field.disabled) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: '该项当前不可修改',
          helperStyle: theme.textTheme.bodySmall,
        ),
        child: Text(
          field.value.isEmpty ? '—' : field.value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (field.isMultiCheckbox) {
      final selected = (_values[field.name] ?? '')
          .split(',')
          .where((v) => v.isNotEmpty)
          .toSet();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in field.options)
                FilterChip(
                  label: Text(
                    option.label.isEmpty ? option.value : option.label,
                  ),
                  selected: selected.contains(option.value),
                  onSelected: (on) {
                    setState(() {
                      final next = {...selected};
                      if (on) {
                        next.add(option.value);
                      } else {
                        next.remove(option.value);
                      }
                      _values[field.name] = next.join(',');
                    });
                  },
                ),
            ],
          ),
        ],
      );
    }

    switch (field.kind) {
      case UcenterFieldKind.switchField:
      case UcenterFieldKind.checkbox:
        final checked =
            (_values[field.name] ?? '').isNotEmpty &&
            (_values[field.name] ?? '') != '0' &&
            (_values[field.name] ?? '') != 'false';
        final optionValue = field.options.isNotEmpty
            ? field.options.first.value
            : '1';
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: checked,
          onChanged: (v) =>
              setState(() => _values[field.name] = v ? optionValue : ''),
        );
      case UcenterFieldKind.radio:
        final selected = _values[field.name] ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in field.options)
                  ChoiceChip(
                    label: Text(
                      option.label.isEmpty ? option.value : option.label,
                    ),
                    selected: selected == option.value,
                    onSelected: (_) =>
                        setState(() => _values[field.name] = option.value),
                  ),
              ],
            ),
          ],
        );
      case UcenterFieldKind.dropdown:
        final selected = _values[field.name] ?? '';
        return DropdownButtonFormField<String>(
          initialValue: field.options.any((o) => o.value == selected)
              ? selected
              : null,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final option in field.options)
              DropdownMenuItem(
                value: option.value,
                child: Text(
                  option.label.isEmpty ? option.value : option.label,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _values[field.name] = v ?? ''),
        );
      case UcenterFieldKind.textarea:
        return TextField(
          controller: _controllerFor(field),
          maxLines: 5,
          decoration: InputDecoration(
            labelText: label,
            hintText: field.placeholder.isEmpty ? null : field.placeholder,
            alignLabelWithHint: true,
          ),
          onChanged: (v) => _values[field.name] = v,
        );
      case UcenterFieldKind.number:
        return TextField(
          controller: _controllerFor(field),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            hintText: field.placeholder.isEmpty ? null : field.placeholder,
          ),
          onChanged: (v) => _values[field.name] = v,
        );
      case UcenterFieldKind.password:
        return TextField(
          controller: _controllerFor(field),
          obscureText: true,
          decoration: InputDecoration(
            labelText: label,
            hintText: field.placeholder.isEmpty ? null : field.placeholder,
          ),
          onChanged: (v) => _values[field.name] = v,
        );
      case UcenterFieldKind.hidden:
        return const SizedBox.shrink();
      case UcenterFieldKind.text:
        return TextField(
          controller: _controllerFor(field),
          decoration: InputDecoration(
            labelText: label,
            hintText: field.placeholder.isEmpty ? null : field.placeholder,
          ),
          onChanged: (v) => _values[field.name] = v,
        );
    }
  }
}
