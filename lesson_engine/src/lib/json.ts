export function extractJsonObject(text: string): unknown {
  const trimmed = text.trim();
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fenced?.[1]?.trim() || trimmed;
  const start = candidate.indexOf('{');
  const end = candidate.lastIndexOf('}');

  if (start < 0 || end <= start) {
    throw new Error('模型响应中没有找到 JSON 对象');
  }

  const body = candidate.slice(start, end + 1);
  const normalized = normalizeJsonText(body);
  try {
    return JSON.parse(normalized);
  } catch (error) {
    // 国产模型还常在字符串里再写一对未转义的英文双引号（例如 图形"rod-a"不够长），
    // 或者在字符串里直接换行，JSON.parse 立刻报 "Expected ',' or ']'" 这类看不出原因的错误。
    // 先试一次宽松修复；修不好就把原始错误抛回去（保留原有报错路径，不掩盖真问题）。
    const repaired = repairLooseJson(normalized);
    if (repaired !== normalized) {
      try {
        return JSON.parse(repaired);
      } catch {
        /* 修复也没救回来：抛原始错误 */
      }
    }
    throw error;
  }
}

/**
 * 宽松 JSON 修复：只处理两类最常见的"写法污染"，其余原样保留。
 *
 * 1. 字符串内部出现未转义的英文双引号：判断依据是"这个引号后面不是 JSON 分隔符"
 *    （`, : } ]` 或文本结束）。是分隔符就当成正常收尾，否则转义成 \"。
 * 2. 字符串内部出现裸换行 / 制表符：转义成 \n \t。
 *
 * 只在 JSON.parse 已经失败后才调用，所以不会把本来合法的 JSON 改坏。
 */
export function repairLooseJson(text: string): string {
  let out = '';
  let inString = false;
  let escaped = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];

    if (!inString) {
      if (char === '"') inString = true;
      out += char;
      continue;
    }

    if (escaped) {
      out += char;
      escaped = false;
      continue;
    }
    if (char === '\\') {
      out += char;
      escaped = true;
      continue;
    }
    if (char === '\n') { out += '\\n'; continue; }
    if (char === '\r') { out += '\\r'; continue; }
    if (char === '\t') { out += '\\t'; continue; }
    if (char === '"') {
      // 往后看第一个非空白字符：是分隔符说明这是真正的字符串结尾，否则是正文里的引号
      let lookahead = index + 1;
      while (lookahead < text.length && /\s/.test(text[lookahead])) lookahead += 1;
      const next = text[lookahead];
      if (next === undefined || ',:}]{['.includes(next)) {
        inString = false;
        out += char;
      } else {
        out += '\\"';
      }
      continue;
    }
    out += char;
  }
  return out;
}

/**
 * 模型（尤其国产大模型）生成中文 JSON 时经常混入全角标点：
 * "key"："value"、{"a"："b"} 里出现 “ ” ： ，等，导致 JSON.parse 失败。
 * 只在键值分隔的上下文中做替换，避免误伤字符串值内部的中文内容。
 */
export function normalizeJsonText(raw: string): string {
  let s = raw;
  // 1) 全角引号 → 半角：JSON 里引号只承担键/值包裹，全角必然非法
  s = s.replaceAll('\u201c', '"').replaceAll('\u201d', '"');
  // 2) 中文冒号 → 半角（键值分隔）：只替换不在字符串值内部的冒号——
  //    用"引号对计数"判定当前位置是否处于未闭合字符串中。
  //    简化实现：把形式 `"..."：` 的键值分隔冒号替换为 `:`；
  //    这种形态在合法 JSON 中只会出现在键与值之间，字符串值内部的
  //    中文冒号前没有紧邻的闭合引号，不会被误伤。
  s = s.replace(/"\s*：/g, '":');
  // 3) 中文逗号 → 半角：只在整个"上一个值结束 → 下一个值开始"的位置替换。
  //    左边必须是字符串/对象/数组收尾或字面量收尾（false/true/null/数字），
  //    右边必须是一个新值的开头——只判左边会把 `false，` 这种漏掉（实测就卡在这里），
  //    只判右边又会误伤字符串值内部的中文顿号。
  s = s.replace(
    /(["}\]0-9]|\btrue|\bfalse|\bnull)[\s]*，[\s]*(?=["{\[\-0-9]|\btrue|\bfalse|\bnull)/g,
    '$1,'
  );
  return s;
}

export function safeJsonForScript(value: unknown): string {
  return JSON.stringify(value)
    .replaceAll('<', '\\u003c')
    .replaceAll('>', '\\u003e')
    .replaceAll('&', '\\u0026')
    .replaceAll('\u2028', '\\u2028')
    .replaceAll('\u2029', '\\u2029');
}

export function summarizeJsonError(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}
