import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// LaTeX→纯文本/Unicode 转换：AI 讲解偶尔会泄漏 LaTeX 命令
/// （\frac、\sqrt[n]、\text 等），渲染前清洗成学生可读的数学书写
/// （如 ½、1/2、v²、F浮=G−F示、√250、⁴√250、(1/2)m v²）。
///
/// 采用「平衡花括号解析」而不是正则硬匹配：支持**嵌套**的 \frac{\sqrt[4]{250}}{10}、
/// 带根指数的 \sqrt[4]{250}、\text/\mathrm/\number 等任意命令，
/// 未知 \xxx 命令整段删除、残余花括号清理，确保任何 LaTeX 变体都不会
/// 泄漏成 `rac{ oot 4 umber{250}}` 之类的乱码。
String texToUnicode(String input) {
  if (input.isEmpty) return input;
  var s = input;

  // 1) 移除美元标记与 \( \) \[ \] 成对括号
  s = s.replaceAll(r'$', '');
  s = s.replaceAll(r'\$', '');
  s = s.replaceAll(r'\(', '').replaceAll(r'\)', '');
  s = s.replaceAll(r'\[', '').replaceAll(r'\]', '');

  // 2) 常用操作符（先做单项替换，避免被后续命令处理误伤）
  s = s
      .replaceAll(r'\cdot', '·')
      .replaceAll(r'\times', '×')
      .replaceAll(r'\div', '÷')
      .replaceAll(r'\pm', '±')
      .replaceAll(r'\approx', '≈')
      .replaceAll(r'\rightarrow', '→')
      .replaceAll(r'\Rightarrow', '⇒')
      .replaceAll(r'\leq', '≤')
      .replaceAll(r'\geq', '≥')
      .replaceAll(r'\neq', '≠')
      .replaceAll(r'\,', ' ')
      .replaceAll(r'\!', '')
      .replaceAll(r'\;', ' ')
      .replaceAll(r'\quad', '  ')
      .replaceAll(r'\qquad', '    ')
      .replaceAll(r'\ ', ' ');

  // 3) 希腊字母与常用数学符号（\theta→θ, \circ→° 等）
  //    与上/下标命令指向符号（^\circ → \circ → °）先归一

  // 4) 统一分数命令为 \frac
  s = s.replaceAll(r'\dfrac', r'\frac').replaceAll(r'\tfrac', r'\frac');

  // 5) 平衡花括号内容提取：s[start] 必须是 '{'，返回 (闭合下标, 内部内容)
  (int, String)? brace(String str, int start) {
    if (start >= str.length || str[start] != '{') return null;
    var depth = 0;
    for (var i = start; i < str.length; i++) {
      if (str[i] == '{') {
        depth++;
      } else if (str[i] == '}') {
        depth--;
        if (depth == 0) return (i, str.substring(start + 1, i));
      }
    }
    return null;
  }

  int? skipSpaces(String str, int p) {
    while (p < str.length && (str[p] == ' ' || str[p] == '\t' || str[p] == '\n')) {
      p++;
    }
    return p < str.length ? p : null;
  }

  // 常用「单花括号参数」命令 → 直接取内部内容（去命令留内容）
  const unwrapCmds = ['text', 'textrm', 'mathrm', 'textnormal', 'mathbf', 'mathit',
      'mathsf', 'mathtt', 'mathbb', 'mathcal', 'textsf', 'operatorname', 'mbox',
      'hbox', 'number', 'unit', 'mathrm'];
  for (final cmd in unwrapCmds) {
    var guard = 0;
    while (guard++ < 10) {
      final idx = s.indexOf('\\$cmd');
      if (idx < 0) break;
      // 命令后可能是 { 或空格+{
      var p = idx + cmd.length + 1;
      p = skipSpaces(s, p) ?? -1;
      if (p < 0 || s[p] != '{') {
        // 无花括号参数：直接删命令
        s = s.replaceRange(idx, idx + cmd.length + 1, '');
        continue;
      }

      final b = brace(s, p);
      if (b == null) break;
      s = s.replaceRange(idx, b.$1 + 1, b.$2);
    }
  }

  // 5) \frac{a}{b}（支持嵌套花括号，反复处理到稳定）

  s = s.replaceAllMapped(RegExp(r'\^\\[A-Za-z]+'), (m) => m.group(0)!.substring(1));
  s = s.replaceAllMapped(RegExp(r'\_\\[A-Za-z]+'), (m) => m.group(0)!.substring(1));
  const greek = {
    'theta': 'θ', 'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ',
    'epsilon': 'ε', 'varepsilon': 'ε', 'zeta': 'ζ', 'eta': 'η',
    'mu': 'μ', 'nu': 'ν', 'xi': 'ξ', 'rho': 'ρ', 'sigma': 'σ',
    'tau': 'τ', 'phi': 'φ', 'varphi': 'φ', 'chi': 'χ',
    'psi': 'ψ', 'omega': 'ω', 'pi': 'π', 'lambda': 'λ', 'kappa': 'κ',
    'upsilon': 'υ', 'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ',
    'Lambda': 'Λ', 'Sigma': 'Σ', 'Phi': 'Φ', 'Psi': 'Ψ', 'Omega': 'Ω',
    'Xi': 'Ξ', 'Pi': 'Π', 'circ': '°', 'degree': '°', 'to': '→',
  };
  for (final e in greek.entries) {
    s = s.replaceAll('\\${e.key}', e.value);
  }
  s = s.replaceAll(r'\leftarrow', '←').replaceAll(r'\rightarrow', '→')
      .replaceAll(r'\infty', '∞').replaceAll(r'\partial', '∂')
      .replaceAll(r'\propto', '∝').replaceAll(r'\sim', '~')
      .replaceAll(r'\emptyset', '∅').replaceAll(r'\forall', '∀')
      .replaceAll(r'\exists', '∃').replaceAll(r'\nabla', '∇')
      .replaceAll(r'\perp', '⊥').replaceAll(r'\parallel', '∥')
      .replaceAll(r'\angle', '∠').replaceAll(r'\cdots', '…')
      .replaceAll(r'\ldots', '…').replaceAll(r'\dots', '…')
      .replaceAll(r'\ast', '*').replaceAll(r'\prime', '′')
      .replaceAll(r'\notin', '∉').replaceAll(r'\in', '∈')
      .replaceAll(r'\subset', '⊂').replaceAll(r'\subseteq', '⊆')
      .replaceAll(r'\supset', '⊃').replaceAll(r'\supseteq', '⊇')
      .replaceAll(r'\cup', '∪').replaceAll(r'\cap', '∩')
      .replaceAll(r'\mid', '|').replaceAll(r'\because', '∵')
      .replaceAll(r'\therefore', '∴');
  s = s.replaceAllMapped(
    RegExp(r'\\(ln|log|sin|cos|tan|cot|sec|csc|arcsin|arccos|arctan|sinh|cosh|tanh|max|min|lim|det|gcd|exp)\b'),
    (match) => match.group(1)!,
  );
  // \bar{X} → X̄、\hat{X} → X̂
  s = s.replaceAllMapped(RegExp(r'\\bar\{([^{}]*)\}'), (m) => '${m.group(1)}\u0304');
  s = s.replaceAllMapped(RegExp(r'\\hat\{([^{}]*)\}'), (m) => '${m.group(1)}\u0302');
  const fracMap = {
    '1/2': '½', '1/3': '⅓', '2/3': '⅔', '1/4': '¼', '3/4': '¾',
    '1/8': '⅛', '3/8': '⅜', '5/8': '⅝', '7/8': '⅞',
  };
  var guard = 0;
  while (guard++ < 12) {
    final idx = s.indexOf(r'\frac');
    if (idx < 0) break;
    var p = idx + 5;
    p = skipSpaces(s, p) ?? -1;
    if (p < 0 || s[p] != '{') break;
    final num = brace(s, p);
    if (num == null) break;
    var p2 = num.$1 + 1;
    p2 = skipSpaces(s, p2) ?? -1;
    if (p2 < 0 || s[p2] != '{') break;
    final den = brace(s, p2);
    if (den == null) break;
    final n = num.$2.trim(), d = den.$2.trim();
    final rep = fracMap['$n/$d'] ?? (n.isEmpty || d.isEmpty ? '' : '($n)/($d)');
    s = s.replaceRange(idx, den.$1 + 1, rep);
  }

  // 6) \sqrt[N]{x} 与 \sqrt{x}（支持根指数）
  const sup = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵',
    '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹', '+': '⁺', '-': '⁻', 'n': 'ⁿ',
  };
  guard = 0;
  while (guard++ < 12) {
    final idx = s.indexOf(r'\sqrt');
    if (idx < 0) break;
    var p = idx + 5;
    // 可选 [N] 根指数
    String rootIdx = '';
    if (p < s.length && s[p] == '[') {
      final close = s.indexOf(']', p);
      if (close > p) {
        rootIdx = s.substring(p + 1, close).trim();
        p = close + 1;
      } else {
        break; // 缺闭合 ]，放弃该处
      }
    }
    p = skipSpaces(s, p) ?? -1;
    if (p < 0 || s[p] != '{') break;
    final b = brace(s, p);
    if (b == null) break;
    final inner = b.$2.trim();
    final innerTxt = inner.isEmpty
        ? ''
        : (inner.length == 1 ? inner : '($inner)');
    final rep = rootIdx.isEmpty
        ? '√$innerTxt'
        : '${rootIdx.split('').map((c) => sup[c] ?? c).join()}√$innerTxt';
    s = s.replaceRange(idx, b.$1 + 1, rep);
  }

  // 7) 上标 / 下标（^{...} 与 ^x / _{...} 与 _x）
  const sub = {
    '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅',
    '6': '₆', '7': '₇', '8': '₈', '9': '₉', 'i': 'ᵢ', 'j': 'ⱼ',
    'm': 'ₘ', 'n': 'ₙ', '+': '₊', '-': '₋',
  };
  // 单个上/下标字符：有 Unicode 字形用字形（²₁ₘ），否则直接拼接去符号
  // （m_A → mA、E_p → Ep、v^a → va），绝不残留 _ 或 ^ 怪异符号
  String supGlyph(String g) => g.split('').map((c) => sup[c] ?? c).join();
  // 多字符下标：用专用角标标记 ~MN~（StyledMarkdown 注册 sub 语法渲染为
  // 真角标：缩小+下沉），避免出现"TMN"把角标当正文的歧义表达。
  // 注意：不用花括号（清洗器第8步会清除 {}），直接波浪线包裹。
  String subMultiGlyph(String g) {
    // 全部字符都有单字符下标字形时逐字符映射（T_{mn} → Tₘₙ）
    final allGlyph = g.split('').every((c) => sub.containsKey(c));
    if (allGlyph && g.isNotEmpty) return g.split('').map((c) => sub[c]!).join();
    return '~$g~';
  }
  // 嵌套指数（如 e^{a^2-b}）用平衡花括号提取，避免只处理一层后留下 `^`。
  guard = 0;
  while (guard++ < 12) {
    final idx = s.indexOf('^{');
    if (idx < 0) break;
    final b = brace(s, idx + 1);
    if (b == null) break;
    final inner = b.$2.trim();
    if (inner.isEmpty) {
      s = s.replaceRange(idx, b.$1 + 1, '');
      continue;
    }
    final expanded = inner.contains(RegExp(r'[\\^{}]'))
        ? texToUnicode(inner)
        : inner;
    final allGlyph = expanded.split('').every((c) => sup.containsKey(c));
    final rep = allGlyph
        ? expanded.split('').map((c) => sup[c]!).join()
        : '^($expanded)';
    s = s.replaceRange(idx, b.$1 + 1, rep);
  }
  s = s.replaceAllMapped(RegExp(r'\_\{([^{}]*)\}'), (m) {
    final g = m.group(1)!;
    return g.isEmpty ? '' : subMultiGlyph(g);
  });
  s = s.replaceAllMapped(RegExp(r'\^([0-9n+A-Za-z])'), (m) => supGlyph(m.group(1)!));
  // 多字符无花括号下标（T_MN）先处理：整体括起表角标语义，避免拼成"TMN"
  s = s.replaceAllMapped(RegExp(r'_([A-Za-z]{2,})'), (m) => subMultiGlyph(m.group(1)!));
  s = s.replaceAllMapped(RegExp(r'_([0-9ijmnA-Za-z])'), (m) {
    final g = m.group(1)!;
    return sub[g] ?? g;
  });

  // 8) 移除成对括号命令与残余反斜杠命令，清理残余花括号
  s = s.replaceAll(r'\left', '').replaceAll(r'\right', '');
  s = s.replaceAllMapped(RegExp(r'\\[a-zA-Z]+'), (_) => '');
  s = s.replaceAll('{', '').replaceAll('}', '');

  // 9) 清理多余空格（多个空格 → 一个）与孤立标点
  s = s.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  return s.trim();
}

/// 角标自定义行内语法：`~MN~` → `<sub>MN</sub>` 元素，
/// 由 [SubscriptBuilder] 渲染为缩小+下沉的真角标（T~MN~ → T 带 MN 角标）。
class SubscriptSyntax extends md.InlineSyntax {
  SubscriptSyntax() : super(r'~([A-Za-z0-9]+)~');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('sub', match[1]!);
    parser.addNode(el);
    return true;
  }
}

/// 把 `<sub>` 元素渲染为真角标（缩小 + 下沉基线）。
class SubscriptBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final base = parentStyle ?? preferredStyle ?? const TextStyle();
    return Text(
      element.textContent,
      style: base.copyWith(
        fontSize: (base.fontSize ?? 14) * 0.68,
        height: 1,
      ),
      textScaler: TextScaler.noScaling,
      textAlign: TextAlign.start,
      overflow: TextOverflow.visible,
    );
  }
}

/// 统一富文本讲解组件：对 AI 输出先做 LaTeX→Unicode 清洗，再 Markdown 渲染。
/// 支持真角标（T~MN~ 缩小下沉）+ 保留重点颜色标记（**橙色加粗**）、斜体、
/// 代码、标题、列表等全部既有样式。
class StyledMarkdown extends StatelessWidget {
  final String data;
  final bool selectable;
  final double fontSize;

  const StyledMarkdown({
    super.key,
    required this.data,
    this.selectable = true,
    this.fontSize = 14,
  });

  static MarkdownStyleSheet styleSheet(BuildContext context, {double fontSize = 14}) {
    const ink = Color(0xFF1D1D1F);
    const strong = Color(0xFFB45309);
    const accent = Color(0xFF007AFF);
    const codeBg = Color(0xFFF7EFDA);
    const codeFg = Color(0xFF92400E);
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    return base.copyWith(
      p: TextStyle(fontSize: fontSize, height: 1.55, color: ink),
      h1: TextStyle(fontSize: fontSize + 5, fontWeight: FontWeight.w800, color: ink, height: 1.4),
      h2: TextStyle(fontSize: fontSize + 3, fontWeight: FontWeight.w700, color: ink, height: 1.4),
      h3: TextStyle(fontSize: fontSize + 1, fontWeight: FontWeight.w700, color: accent, height: 1.4),
      h4: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: ink, height: 1.4),
      strong: const TextStyle(fontWeight: FontWeight.w700, color: strong),
      em: const TextStyle(fontStyle: FontStyle.italic, color: ink),
      listBullet: TextStyle(fontSize: fontSize, height: 1.5, color: accent),
      listIndent: 20,
      blockquote: TextStyle(fontSize: fontSize, height: 1.5, color: const Color(0xFF6E6E73), fontStyle: FontStyle.italic),
      code: TextStyle(
        fontSize: fontSize,
        fontFamily: 'monospace',
        color: codeFg,
        backgroundColor: codeBg,
        fontWeight: FontWeight.w500,
      ),
      codeblockDecoration: BoxDecoration(color: codeBg, borderRadius: BorderRadius.circular(8)),
      codeblockPadding: const EdgeInsets.all(10),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E5EA), width: 0.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: texToUnicode(data),
      selectable: selectable,
      styleSheet: styleSheet(context, fontSize: fontSize),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [SubscriptSyntax()],
      builders: {
        'sub': SubscriptBuilder(),
      },
    );
  }
}