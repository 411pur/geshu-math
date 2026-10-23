/// AI 输出 JSON 的容错解析。
///
/// 数学讲解要求模型用 LaTeX 书写公式，而 LaTeX 的反斜杠命令（`\frac`、
/// `\sqrt`、`\theta`…）在 JSON 字符串里属于**非法转义**：模型若忘了写成
/// `\\frac`，`jsonDecode` 会直接抛错，整段讲解就退化成原始文本。
/// 这里在解析前把「非法反斜杠」补成合法转义，合法转义（`\\`、`\"`、
/// `\n`、`\uXXXX` 等）原样保留。
library;

import 'dart:convert';

/// 已知的 LaTeX 命令（用于区分 `\f`+`rac` 是 LaTeX 还是“换页符 + rac”）。
const Set<String> _texCommands = {
  'frac', 'dfrac', 'tfrac', 'sqrt', 'root', 'sum', 'prod', 'int', 'oint',
  'lim', 'log', 'ln', 'lg', 'sin', 'cos', 'tan', 'cot', 'sec', 'csc',
  'arcsin', 'arccos', 'arctan', 'sinh', 'cosh', 'tanh',
  'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'varepsilon', 'zeta', 'eta',
  'theta', 'vartheta', 'iota', 'kappa', 'lambda', 'mu', 'nu', 'xi', 'pi',
  'varpi', 'rho', 'varrho', 'sigma', 'varsigma', 'tau', 'upsilon', 'phi',
  'varphi', 'chi', 'psi', 'omega', 'Gamma', 'Delta', 'Theta', 'Lambda',
  'Xi', 'Pi', 'Sigma', 'Phi', 'Psi', 'Omega',
  'cdot', 'times', 'div', 'pm', 'mp', 'ast', 'star', 'circ', 'bullet',
  'leq', 'le', 'geq', 'ge', 'neq', 'ne', 'approx', 'equiv', 'sim', 'simeq',
  'cong', 'propto', 'll', 'gg', 'subset', 'subseteq', 'supset', 'supseteq',
  'in', 'notin', 'ni', 'cup', 'cap', 'setminus', 'emptyset', 'varnothing',
  'forall', 'exists', 'nexists', 'neg', 'land', 'lor', 'implies', 'iff',
  'rightarrow', 'leftarrow', 'leftrightarrow', 'Rightarrow', 'Leftarrow',
  'Leftrightarrow', 'to', 'mapsto', 'uparrow', 'downarrow', 'infty',
  'partial', 'nabla', 'angle', 'perp', 'parallel', 'triangle', 'square',
  'odot', 'oplus', 'otimes', 'prime', 'degree', 'degreec',
  'overline', 'underline', 'underbrace', 'overbrace', 'vec', 'hat', 'bar',
  'tilde', 'dot', 'ddot', 'widehat', 'widetilde', 'overrightarrow',
  'text', 'textrm', 'textbf', 'textit', 'mathrm', 'mathbf', 'mathit',
  'mathsf', 'mathtt', 'mathcal', 'mathbb', 'operatorname', 'mbox',
  'left', 'right', 'big', 'Big', 'bigg', 'Bigg',
  'quad', 'qquad', 'hspace', 'vspace', 'begin', 'end', 'displaystyle',
  'cdotp', 'ldots', 'cdots', 'vdots', 'ddots', 'dots',
  'because', 'therefore', 'approxeq', 'leqslant', 'geqslant',
  'lbrace', 'rbrace', 'langle', 'rangle', 'lfloor', 'rfloor', 'lceil',
  'rceil', 'vert', 'Vert', 'mid', 'nmid',
  'arc', 'triangleq', 'overset', 'underset', 'stackrel', 'binom',
};

/// 去掉模型偶尔多写的 Markdown 代码围栏。
String stripJsonFences(String raw) {
  var text = raw.trim();
  if (!text.startsWith('```')) return text;
  final firstBreak = text.indexOf('\n');
  if (firstBreak < 0) return text;
  text = text.substring(firstBreak + 1);
  final lastFence = text.lastIndexOf('```');
  if (lastFence >= 0) text = text.substring(0, lastFence);
  return text.trim();
}

bool _isTexCommandAt(String source, int start) {
  for (final command in _texCommands) {
    if (source.startsWith(command, start)) {
      final after = start + command.length;
      if (after >= source.length) return true;
      final ch = source[after];
      final isLetter = RegExp(r'[A-Za-z]').hasMatch(ch);
      if (!isLetter) return true;
    }
  }
  return false;
}

/// `source[i]` 是反斜杠；判断它是否是合法的 JSON 转义。
bool _isValidJsonEscape(String source, int i) {
  if (i + 1 >= source.length) return false;
  final next = source[i + 1];
  if (next == '"' || next == r'\' || next == '/') return true;
  if (next == 'u') {
    if (i + 6 > source.length) return false;
    return RegExp(r'^[0-9a-fA-F]{4}$')
        .hasMatch(source.substring(i + 2, i + 6));
  }
  if ('bfnrt'.contains(next)) {
    // `\frac`、`\theta`、`\rho`、`\beta`、`\nu` 形式上像合法转义的前缀，
    // 但后面跟的是完整 LaTeX 命令名，必须按 LaTeX 处理。
    return !_isTexCommandAt(source, i + 1);
  }
  return false;
}

/// 把 JSON 字符串中非法的反斜杠补成 `\\`，已合法转义的原样保留。
String repairJsonBackslashes(String raw) {
  final out = StringBuffer();
  var i = 0;
  while (i < raw.length) {
    final ch = raw[i];
    if (ch != r'\') {
      out.write(ch);
      i++;
      continue;
    }
    if (i + 1 < raw.length && raw[i + 1] == r'\') {
      out.write(r'\\');
      i += 2;
      continue;
    }
    if (_isValidJsonEscape(raw, i)) {
      out.write(r'\');
      i++;
      continue;
    }
    out.write(r'\\');
    i++;
  }
  return out.toString();
}

/// 宽松解析模型返回的 JSON；两次都失败时返回 null（调用方自行兜底）。
Object? decodeAiJson(String raw) {
  final text = stripJsonFences(raw);
  // 必须先修复再解析：`\f`、`\t`、`\b`、`\r`、`\n` 在 JSON 里都是**合法**
  // 转义，直接 jsonDecode 会把 `\frac` 吃成「换页符 + rac」——解析不报错，
  // 但公式被悄悄改坏。所以统一先按 LaTeX 规则修复一次。
  try {
    return jsonDecode(repairJsonBackslashes(text));
  } catch (_) {
    // 修复后仍失败（例如结构本身不合法），再退回原文尝试一次
  }
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

/// 只接受 JSON 对象的场景（绝大多数提示词契约都是对象）。
Map<String, dynamic>? decodeAiJsonObject(String raw) {
  final decoded = decodeAiJson(raw);
  return decoded is Map<String, dynamic> ? decoded : null;
}
